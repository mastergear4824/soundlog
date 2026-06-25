import Foundation

/// A download failure with a friendly message and the raw detail for "Copy error".
struct DownloadError: LocalizedError, Sendable {
    var message: String
    var detail: String
    var errorDescription: String? { message }
}

/// The result of a completed download: where the file landed.
struct DownloadResult: Sendable, Equatable {
    var finalPath: String
}

/// Builds and runs the single-invocation yt-dlp -> mp3 pipeline, streams typed progress,
/// and self-heals around the common YouTube breakages via an android_vr retry.
///
/// An `actor` so each Process is constructed and consumed in one isolation domain.
/// The app drives one download at a time (serial queue lives in AppModel).
actor DownloadEngine {
    private let tools: ToolSet

    /// US-ASCII Unit Separator (0x1F) used to delimit progress-template fields.
    private static let sep = "\u{1F}"

    init(tools: ToolSet) {
        self.tools = tools
    }

    /// Run the pipeline. Yields ProgressEvents; on success the final event is `.finalPath`.
    /// Throws `DownloadError` on unrecoverable failure (after the android_vr retry).
    func download(url: String, settings: AppSettings) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try ensureDirectory(settings.destinationURL)

                    // First attempt with the default extractor.
                    do {
                        let final = try await runAttempt(url: url, settings: settings,
                                                         androidVR: false, continuation: continuation)
                        continuation.yield(.finalPath(final))
                        continuation.finish()
                        return
                    } catch let failure as AttemptFailure {
                        guard failure.retryable else {
                            throw failure.asDownloadError
                        }
                        continuation.yield(.info("응답이 막혀 대체 클라이언트로 자동 재시도합니다…"))
                    }

                    // Retry with the android_vr client (works logged-out, no cookies/PO token).
                    let final = try await runAttempt(url: url, settings: settings,
                                                     androidVR: true, continuation: continuation)
                    continuation.yield(.finalPath(final))
                    continuation.finish()
                } catch let e as DownloadError {
                    continuation.finish(throwing: e)
                } catch let e as AttemptFailure {
                    continuation.finish(throwing: e.asDownloadError)
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: DownloadError(message: "다운로드에 실패했습니다.", detail: error.localizedDescription))
                }
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason { task.cancel() }
            }
        }
    }

    // MARK: - One attempt

    private struct AttemptFailure: Error {
        var retryable: Bool
        var message: String
        var detail: String
        var asDownloadError: DownloadError { DownloadError(message: message, detail: detail) }
    }

    private func runAttempt(
        url: String,
        settings: AppSettings,
        androidVR: Bool,
        continuation: AsyncThrowingStream<ProgressEvent, Error>.Continuation
    ) async throws -> String {
        let args = buildArguments(url: url, settings: settings, androidVR: androidVR)
        var finalPath: String?
        var stderr = ""

        do {
            for try await line in ProcessRunner.run(executable: tools.ytDlp.path, arguments: args) {
                // yt-dlp prints progress-template (__DL__/__PP__) to stderr and --print
                // (__FINAL__) to stdout, so parse markers on BOTH streams; non-marker
                // stderr is accumulated for error classification.
                switch line {
                case .stdout(let text):
                    if let event = parse(line: text) {
                        if case let .finalPath(p) = event { finalPath = p }
                        else { continuation.yield(event) }
                    }
                case .stderr(let text):
                    if let event = parse(line: text) {
                        if case let .finalPath(p) = event { finalPath = p }
                        else { continuation.yield(event) }
                    } else {
                        stderr += text + "\n"
                    }
                }
            }
        } catch is ProcessFailure {
            let (retryable, message) = classify(stderr: stderr)
            throw AttemptFailure(retryable: !androidVR && retryable, message: message, detail: stderr)
        }

        guard let finalPath else {
            throw AttemptFailure(retryable: false,
                                 message: "다운로드는 끝났지만 저장 경로를 확인하지 못했습니다.",
                                 detail: stderr)
        }
        return finalPath
    }

    // MARK: - Argument builder

    /// The exact yt-dlp argv. Public-ish helper so the UI can show "Copy command".
    func buildArguments(url: String, settings: AppSettings, androidVR: Bool) -> [String] {
        let s = Self.sep
        var args: [String] = [
            "-f", "bestaudio/best",
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", settings.mp3Quality,
            "--embed-metadata",
            "--no-playlist",
            "--no-mtime",
            "--ffmpeg-location", tools.ffmpegDir,
            "--newline", "--no-color",
            "--progress-delta", "0.25",
            "--progress-template",
            "download:__DL__\(s)%(progress.status)s\(s)%(progress.downloaded_bytes)s\(s)%(progress.total_bytes,progress.total_bytes_estimate)s\(s)%(progress.speed)s\(s)%(progress.eta)s",
            "--progress-template",
            "postprocess:__PP__\(s)%(progress.status)s\(s)%(progress.postprocessor)s",
            "--print", "after_move:__FINAL__\(s)%(filepath)s",
            "-o", "%(title).80B [%(id)s].%(ext)s",
            "-P", settings.destinationURL.path,
        ]
        if settings.embedThumbnail {
            args += ["--embed-thumbnail"]
        }
        if settings.cleanTitles {
            // Parses an "Artist - Title" title into ID3 artist/title. No-op when the
            // pattern doesn't match, so podcasts/lectures keep their original title.
            args += ["--parse-metadata", "%(title)s:%(artist)s - %(title)s"]
        }
        if settings.normalizeLoudness {
            args += ["--postprocessor-args", "ffmpeg:-af loudnorm=I=-16:TP=-1.5:LRA=11"]
        }
        if androidVR {
            args += ["--extractor-args", "youtube:player_client=android_vr"]
        }
        args.append(url)
        return args
    }

    /// argv rendered as a copy-pasteable shell command.
    func shellCommand(url: String, settings: AppSettings) -> String {
        ([tools.ytDlp.path] + buildArguments(url: url, settings: settings, androidVR: false))
            .map { token in
                token.contains(" ") || token.contains(Self.sep)
                    ? "'\(token.replacingOccurrences(of: "'", with: "'\\''"))'"
                    : token
            }
            .joined(separator: " ")
    }

    // MARK: - Output parsing

    private func parse(line: String) -> ProgressEvent? {
        guard line.contains(Self.sep) else { return nil }
        let f = line.components(separatedBy: Self.sep)
        switch f.first {
        case "__DL__":
            // [_, status, downloaded, total, speed, eta]
            let downloaded = num(f, 2).map { Int64($0) }
            let total = num(f, 3).map { Int64($0) }
            let speed = num(f, 4)
            let eta = num(f, 5).map { Int($0) }
            var percent: Double?
            if let d = downloaded, let t = total, t > 0 { percent = min(1, Double(d) / Double(t)) }
            return .downloading(DownloadProgress(
                percent: percent, downloadedBytes: downloaded, totalBytes: total,
                speedBytesPerSec: speed, etaSeconds: eta))
        case "__PP__":
            // [_, status, postprocessor]
            let pp = f.count > 2 ? f[2] : ""
            return .postprocessing(stage: stageLabel(forPostprocessor: pp))
        case "__FINAL__":
            let path = f.count > 1 ? f[1] : ""
            return path.isEmpty ? nil : .finalPath(path)
        default:
            return nil
        }
    }

    /// Parse a numeric progress field, treating yt-dlp's "NA"/"N/A"/empty as nil.
    private func num(_ fields: [String], _ idx: Int) -> Double? {
        guard idx < fields.count else { return nil }
        let raw = fields[idx].trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, raw != "NA", raw != "N/A", raw.lowercased() != "none" else { return nil }
        return Double(raw)
    }

    private func stageLabel(forPostprocessor pp: String) -> String {
        switch pp {
        case "ExtractAudio": return "변환 중"
        case "Metadata", "FFmpegMetadata": return "태그 입히는 중"
        case "EmbedThumbnail": return "커버 입히는 중"
        case "MoveFiles": return "마무리 중"
        default: return "처리 중"
        }
    }

    // MARK: - Error classification

    /// (retryable-with-androidVR, user-facing message)
    private func classify(stderr: String) -> (Bool, String) {
        let s = stderr.lowercased()
        let botSignals = ["not a bot", "sign in to confirm", "http error 403", "forcing sabr",
                          "sabr", "nsig", "unable to extract", "player response", "failed to extract"]
        if botSignals.contains(where: s.contains) {
            return (true, "스트리밍 서비스 쪽이 바뀐 것 같습니다 — yt-dlp 업데이트가 필요할 수 있어요.")
        }
        if s.contains("private video") { return (false, "비공개 영상입니다.") }
        if s.contains("video unavailable") || s.contains("has been removed") || s.contains("no longer available") {
            return (false, "삭제되었거나 사용할 수 없는 영상입니다.")
        }
        if s.contains("age") && (s.contains("confirm") || s.contains("restricted") || s.contains("inappropriate")) {
            return (false, "연령 제한 영상입니다 (브라우저 쿠키가 필요할 수 있어요).")
        }
        if s.contains("not available in your country") || s.contains("geo") {
            return (false, "지역 제한 영상입니다.")
        }
        return (false, "다운로드에 실패했습니다.")
    }

    // MARK: - Util

    private func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
