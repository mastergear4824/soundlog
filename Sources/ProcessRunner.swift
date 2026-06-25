import Foundation

/// One line read from a child process, tagged by stream.
enum RawLine: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
}

/// A non-zero exit. Callers that need stderr collect it from the `.stderr` lines
/// they already received before this is thrown.
struct ProcessFailure: Error, Sendable {
    var status: Int32
}

/// Coordinates the two pipe-reader threads and the termination handler. It splits output
/// into lines and finishes the stream once BOTH pipes have hit EOF and the process exited.
/// Holds the process and pipes strongly so their file descriptors stay valid while draining.
private final class RunCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<RawLine, Error>.Continuation
    private var process: Process?
    private var pipes: [Pipe] = []
    private var outEOF = false, errEOF = false, exited = false, finished = false, killed = false
    private var status: Int32 = 0
    private var outBuf = Data(), errBuf = Data()

    init(_ continuation: AsyncThrowingStream<RawLine, Error>.Continuation) {
        self.continuation = continuation
    }

    func retain(process: Process, pipes: [Pipe]) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        self.pipes = pipes
    }

    func feed(_ data: Data, isStdout: Bool) {
        lock.lock(); defer { lock.unlock() }
        if isStdout { outBuf.append(data); emitLines(&outBuf, isStdout: true) }
        else { errBuf.append(data); emitLines(&errBuf, isStdout: false) }
    }

    func eof(isStdout: Bool) {
        lock.lock()
        if isStdout { outEOF = true } else { errEOF = true }
        let done = markDoneLocked()
        lock.unlock()
        if done { finishNow() }
    }

    func processExited(status: Int32) {
        lock.lock()
        self.status = status
        exited = true
        let done = markDoneLocked()
        lock.unlock()
        if done { finishNow() }
    }

    /// SIGTERM now (lets yt-dlp clean its .part files), SIGKILL after a grace period —
    /// but only if the process is still alive then.
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !killed, let p = process, p.isRunning else { return }
        killed = true
        let pid = p.processIdentifier
        p.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    private func emitLines(_ buf: inout Data, isStdout: Bool) {
        let newline = UInt8(ascii: "\n")
        while let nl = buf.firstIndex(of: newline) {
            var lineData = Data(buf[buf.startIndex..<nl])
            if lineData.last == UInt8(ascii: "\r") { lineData.removeLast() } // tolerate CRLF
            buf = Data(buf[buf.index(after: nl)...])
            if let s = String(data: lineData, encoding: .utf8) {
                continuation.yield(isStdout ? .stdout(s) : .stderr(s))
            }
        }
    }

    /// Returns true exactly once, when both pipes have EOF'd and the process has exited.
    private func markDoneLocked() -> Bool {
        guard !finished, outEOF, errEOF, exited else { return false }
        finished = true
        return true
    }

    /// Flush trailing data and finish the stream — called OUTSIDE the lock so the synchronous
    /// onTermination callback can never re-enter the (non-reentrant) lock and deadlock.
    private func finishNow() {
        lock.lock()
        let trailingOut = outBuf; let trailingErr = errBuf
        outBuf.removeAll(); errBuf.removeAll()
        let exitStatus = status
        process = nil   // break the terminationHandler retain cycle
        pipes = []
        lock.unlock()

        if !trailingOut.isEmpty, let s = String(data: trailingOut, encoding: .utf8) { continuation.yield(.stdout(s)) }
        if !trailingErr.isEmpty, let s = String(data: trailingErr, encoding: .utf8) { continuation.yield(.stderr(s)) }
        if exitStatus == 0 { continuation.finish() }
        else { continuation.finish(throwing: ProcessFailure(status: exitStatus)) }
    }
}

/// Generic async subprocess driver. Streams stdout/stderr line-by-line by draining each pipe
/// on a dedicated background thread with blocking `read()` (reliable EOF on child exit) and
/// yielding lines into an AsyncThrowingStream. Cancelling the stream terminates the child.
enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        extraEnvironment: [String: String] = [:]
    ) -> AsyncThrowingStream<RawLine, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            // A Finder-launched GUI app has a stripped PATH. Set an explicit one so yt-dlp can
            // find ffmpeg, plus a UTF-8 locale for correct title handling.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["LC_ALL"] = "en_US.UTF-8"
            for (k, v) in extraEnvironment { env[k] = v }
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let coordinator = RunCoordinator(continuation)
            coordinator.retain(process: process, pipes: [outPipe, errPipe])
            process.terminationHandler = { p in coordinator.processExited(status: p.terminationStatus) }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            // Close our copy of the write ends so the read side hits EOF when the child exits.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()

            drain(fd: outPipe.fileHandleForReading.fileDescriptor, isStdout: true, coordinator: coordinator)
            drain(fd: errPipe.fileHandleForReading.fileDescriptor, isStdout: false, coordinator: coordinator)

            // Only kill the child when the CONSUMER cancels — not on our own normal finish
            // (which also fires onTermination). cancel() locks, so calling it during our
            // under-lock finish would deadlock.
            continuation.onTermination = { reason in
                if case .cancelled = reason { coordinator.cancel() }
            }
        }
    }

    private static func drain(fd: Int32, isStdout: Bool, coordinator: RunCoordinator) {
        DispatchQueue.global(qos: .utility).async {
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &buffer, buffer.count)
                if n > 0 {
                    coordinator.feed(Data(buffer[0..<n]), isStdout: isStdout)
                } else {
                    break // 0 = EOF, negative = error
                }
            }
            coordinator.eof(isStdout: isStdout)
        }
    }
}
