import Foundation
import AVFoundation
import Observation

enum RepeatMode: Sendable, Equatable {
    case off    // play queue once, then stop
    case all    // loop the whole queue
    case one    // repeat the current track
}

/// In-app audio playback with its own play queue (separate from the library and the download
/// queue), repeat modes, and shuffle. Wraps AVAudioPlayer; publishes state for the player UI.
@MainActor
@Observable
final class PlayerController {
    private(set) var queue: [LogEntry] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var repeatMode: RepeatMode = .off
    var shuffle: Bool = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var current: LogEntry? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    var hasContent: Bool { current != nil }

    // MARK: - Building the queue

    /// Play immediately. If already queued, jump to it; otherwise insert after current.
    func playNow(_ entry: LogEntry) {
        if let i = queue.firstIndex(where: { $0.id == entry.id }) {
            currentIndex = i
        } else {
            let pos = currentIndex.map { $0 + 1 } ?? queue.count
            queue.insert(entry, at: pos)
            currentIndex = pos
        }
        loadAndPlayCurrent()
    }

    /// Queue right after the current track.
    func playNext(_ entry: LogEntry) {
        let pos = currentIndex.map { $0 + 1 } ?? queue.count
        queue.insert(entry, at: pos)
        if currentIndex == nil { currentIndex = pos; loadAndPlayCurrent() }
    }

    /// Append to the end of the queue.
    func addToQueue(_ entry: LogEntry) {
        queue.append(entry)
        if currentIndex == nil { currentIndex = queue.count - 1; loadAndPlayCurrent() }
    }

    func playFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        loadAndPlayCurrent()
    }

    func removeFromQueue(_ entry: LogEntry) {
        guard let i = queue.firstIndex(where: { $0.id == entry.id }) else { return }
        let wasCurrent = (i == currentIndex)
        queue.remove(at: i)
        if let ci = currentIndex {
            if i < ci { currentIndex = ci - 1 }
            else if wasCurrent {
                if queue.isEmpty { close() }
                else { currentIndex = min(ci, queue.count - 1); loadAndPlayCurrent() }
            }
        }
    }

    func clearQueue() {
        close()
        queue = []
    }

    // MARK: - Transport

    func togglePlayPause() {
        guard let p = player else {
            if current != nil { loadAndPlayCurrent() }
            return
        }
        if p.isPlaying { p.pause(); isPlaying = false; stopTicker() }
        else { p.play(); isPlaying = true; startTicker() }
    }

    func next() { advance(auto: false) }

    func previous() {
        // Restart the current track if we're more than 3s in.
        if currentTime > 3 { seek(to: 0); return }
        guard let ci = currentIndex, !queue.isEmpty else { return }
        let target: Int
        if shuffle { target = randomIndex(excluding: ci) ?? ci }
        else if ci > 0 { target = ci - 1 }
        else { target = (repeatMode == .all) ? queue.count - 1 : 0 }
        currentIndex = target
        loadAndPlayCurrent()
    }

    func seek(to time: Double) {
        guard let p = player else { return }
        let t = max(0, min(time, p.duration))
        p.currentTime = t
        currentTime = t
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleShuffle() { shuffle.toggle() }

    func close() {
        stopTicker()
        player?.stop()
        player = nil
        currentIndex = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    // MARK: - Internals

    private func advance(auto: Bool) {
        guard let ci = currentIndex, !queue.isEmpty else { return }
        if auto && repeatMode == .one { loadAndPlayCurrent(); return }
        let target: Int?
        if shuffle {
            target = randomIndex(excluding: ci)
        } else if ci + 1 < queue.count {
            target = ci + 1
        } else {
            target = (repeatMode == .all) ? 0 : nil
        }
        if let t = target {
            currentIndex = t
            loadAndPlayCurrent()
        } else {
            // Reached the end of the queue.
            isPlaying = false
            stopTicker()
            seek(to: 0)
        }
    }

    private func randomIndex(excluding i: Int) -> Int? {
        guard queue.count > 1 else { return queue.isEmpty ? nil : 0 }
        var r = i
        while r == i { r = Int.random(in: 0..<queue.count) }
        return r
    }

    private func loadAndPlayCurrent() {
        guard let entry = current else { return }
        guard let p = try? AVAudioPlayer(contentsOf: entry.fileURL) else {
            // File unreadable — skip to the next one.
            advance(auto: true)
            return
        }
        stopTicker()
        player?.stop()
        player = p
        duration = p.duration
        currentTime = 0
        p.prepareToPlay()
        p.play()
        isPlaying = true
        startTicker()
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.tick() else { break }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    /// Update time / detect end. Returns false to stop the ticker.
    private func tick() -> Bool {
        guard let p = player else { return false }
        currentTime = p.currentTime
        if isPlaying && !p.isPlaying {
            advance(auto: true)
            return false
        }
        return isPlaying
    }
}
