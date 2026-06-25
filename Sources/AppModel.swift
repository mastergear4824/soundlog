import Foundation
import Observation
import AppKit

/// The single @MainActor source of truth. Coordinates tool resolution, the metadata probe,
/// the serial download queue, persistence, and all user actions.
@MainActor
@Observable
final class AppModel {
    // Input / preview
    var urlText: String = "" {
        didSet { if urlText != oldValue { scheduleProbe() } }
    }
    private(set) var input: InputState = .idle

    // Serial download queue: one active job, the rest waiting.
    private(set) var activeJob: Job?
    private(set) var jobPhase: JobPhase?
    private(set) var queue: [Job] = []
    private(set) var lastError: JobError?

    // Environment
    private(set) var missingTools: MissingTools?
    private(set) var staleHint: Bool = false

    // Settings (persisted to UserDefaults)
    var settings: AppSettings {
        didSet { persistSettings() }
    }

    let library = LibraryStore()
    let player = PlayerController()

    /// Marketing version from the bundle, shown in the UI so updates are visible.
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    @ObservationIgnored private var tools: ToolSet?
    @ObservationIgnored private var engine: DownloadEngine?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    struct JobError: Sendable, Equatable {
        var message: String
        var detail: String
    }

    init() {
        settings = AppModel.loadSettings()
    }

    var isWorking: Bool { activeJob != nil }

    /// Can the current input be saved? (Enqueuing is allowed even while a job runs.)
    var canSave: Bool {
        guard tools != nil else { return false }
        switch input {
        case .ready(_, let dup): return dup == nil
        case .playlistReady(_, let items): return playlistNewCount(items) > 0
        default: return false
        }
    }

    var readyMeta: VideoMeta? {
        if case let .ready(meta, _) = input { return meta }
        return nil
    }

    /// How many playlist entries aren't already in the library.
    func playlistNewCount(_ items: [VideoMeta]) -> Int {
        items.reduce(0) { $0 + (library.existing(videoID: $1.id) == nil ? 1 : 0) }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        library.load()
        switch await ToolLocator.resolve() {
        case .success(let t):
            tools = t
            engine = DownloadEngine(tools: t)
            missingTools = nil
        case .failure(let missing):
            missingTools = missing
        }
    }

    // MARK: - Probe (preview)

    private func scheduleProbe() {
        probeTask?.cancel()
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { input = .idle; return }
        guard YouTubeURL.looksLikeYouTube(raw), let tools else {
            input = tools == nil ? .idle : .error("올바른 링크가 아닌 것 같아요.")
            return
        }
        input = .probing
        let isPlaylist = YouTubeURL.isPlaylistURL(raw)
        probeTask = Task { [weak self] in
            // Small debounce so we don't probe on every keystroke of a paste.
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            if isPlaylist {
                await self?.runPlaylistProbe(url: raw, tools: tools)
            } else {
                await self?.runProbe(url: raw, tools: tools)
            }
        }
    }

    private func runProbe(url: String, tools: ToolSet) async {
        do {
            let meta = try await ProbeService.probe(url: url, tools: tools)
            if Task.isCancelled { return }
            let dup = library.existing(videoID: meta.id)
            input = .ready(meta, duplicate: dup)
        } catch {
            if Task.isCancelled { return }
            input = .error(error.localizedDescription)
        }
    }

    private func runPlaylistProbe(url: String, tools: ToolSet) async {
        do {
            let (title, items) = try await ProbeService.probePlaylist(url: url, tools: tools)
            if Task.isCancelled { return }
            input = .playlistReady(title: title, items: items)
        } catch {
            if Task.isCancelled { return }
            input = .error(error.localizedDescription)
        }
    }

    // MARK: - Save (serial queue)

    func save() {
        switch input {
        case .ready(let meta, let dup) where dup == nil:
            enqueue([Job(meta: meta, url: meta.webpageURL ?? YouTubeURL.canonicalURL(forID: meta.id))])
        case .playlistReady(_, let items):
            // Skip videos already in the library; enqueue the rest, preserving order.
            let jobs = items
                .filter { library.existing(videoID: $0.id) == nil }
                .map { Job(meta: $0, url: $0.webpageURL ?? YouTubeURL.canonicalURL(forID: $0.id)) }
            enqueue(jobs)
        default:
            return
        }
        // Clear the input so the field is ready for the next paste.
        urlText = ""
        input = .idle
    }

    /// Append jobs to the queue and start pumping if idle.
    private func enqueue(_ jobs: [Job]) {
        guard !jobs.isEmpty else { return }
        lastError = nil
        queue.append(contentsOf: jobs)
        pump()
    }

    /// Start the next queued job if nothing is active.
    private func pump() {
        guard activeJob == nil, !queue.isEmpty else { return }
        start(queue.removeFirst())
    }

    func cancelQueued(_ job: Job) {
        queue.removeAll { $0.id == job.id }
    }

    private func start(_ job: Job) {
        guard let engine else { return }
        activeJob = job
        jobPhase = .downloading(DownloadProgress(percent: nil, downloadedBytes: nil, totalBytes: nil,
                                                 speedBytesPerSec: nil, etaSeconds: nil))
        let settings = self.settings
        let url = job.url
        let meta = job.meta
        saveTask = Task { [weak self] in
            guard let self else { return }
            var finalPath: String?
            do {
                for try await event in await engine.download(url: url, settings: settings) {
                    switch event {
                    case .downloading(let p): self.jobPhase = .downloading(p)
                    case .postprocessing(let stage): self.jobPhase = .postprocessing(stage: stage)
                    case .finalPath(let path): finalPath = path
                    case .info: break
                    }
                }
                if let finalPath {
                    await self.finishSuccess(meta: meta, url: url, finalPath: finalPath)
                } else {
                    // Stream ended without a final path (e.g. cancelled mid-flight).
                    self.endJob()
                }
            } catch is CancellationError {
                self.endJob()
            } catch let e as DownloadError {
                self.fail(JobError(message: e.message, detail: e.detail))
            } catch {
                self.fail(JobError(message: "다운로드에 실패했습니다.", detail: error.localizedDescription))
            }
        }
    }

    private func finishSuccess(meta: VideoMeta, url: String, finalPath: String) async {
        let thumb = await library.cacheThumbnail(videoID: meta.id)
        let size = (try? FileManager.default.attributesOfItem(atPath: finalPath)[.size] as? Int64) ?? nil
        let display = Self.displayMetadata(meta: meta, settings: settings)
        let entry = LogEntry(
            canonicalVideoID: meta.id,
            sourceURL: url,
            title: display.title,
            artist: display.artist,
            album: display.album,
            year: meta.releaseYear,
            durationSeconds: meta.durationSeconds ?? 0,
            filePath: finalPath,
            fileSizeBytes: size ?? 0,
            thumbnailFileName: thumb,
            savedAt: Date(),
            ytDlpVersion: tools?.ytDlp.version ?? "unknown",
            rawTitle: meta.title
        )
        library.add(entry)
        endJob()
    }

    private func fail(_ error: JobError) {
        lastError = error
        if error.message.contains("yt-dlp") { staleHint = true }
        endJob()
    }

    /// Tear down the finished/cancelled active job and start the next one. Always called from
    /// the running task's terminal path so the queue advances exactly once.
    private func endJob() {
        jobPhase = nil
        activeJob = nil
        saveTask = nil
        pump()
    }

    /// Request cancellation of the active job. The running task unwinds and advances the queue
    /// exactly once — doing teardown synchronously here would race the unwinding task.
    func cancel() {
        saveTask?.cancel()
    }

    func dismissError() { lastError = nil }

    // MARK: - Re-download a missing/old entry

    func redownload(_ entry: LogEntry) {
        let meta = VideoMeta(id: entry.canonicalVideoID, title: entry.rawTitle, uploader: entry.artist,
                             durationSeconds: entry.durationSeconds, thumbnailURL: nil,
                             webpageURL: entry.sourceURL, availability: nil, isLive: false,
                             track: nil, artist: entry.artist, album: entry.album, releaseYear: entry.year)
        enqueue([Job(meta: meta, url: entry.sourceURL)])
    }

    // MARK: - Row actions

    /// Play this track now inside the app (separate player window).
    func playNow(_ entry: LogEntry) {
        guard library.fileExists(for: entry) else { return }
        player.playNow(entry)
    }

    /// Queue this track right after the current one.
    func playNext(_ entry: LogEntry) {
        guard library.fileExists(for: entry) else { return }
        player.playNext(entry)
    }

    /// Append this track to the end of the play queue.
    func addToQueue(_ entry: LogEntry) {
        guard library.fileExists(for: entry) else { return }
        player.addToQueue(entry)
    }

    func reveal(_ entry: LogEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.fileURL])
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func copyCommand(for entry: LogEntry) async -> String {
        guard let engine else { return "" }
        return await engine.shellCommand(url: entry.sourceURL, settings: settings)
    }

    func copyCommandForCurrentInput() async -> String? {
        guard let engine, let meta = readyMeta else { return nil }
        let url = meta.webpageURL ?? YouTubeURL.canonicalURL(forID: meta.id)
        return await engine.shellCommand(url: url, settings: settings)
    }

    // MARK: - Tool maintenance

    func upgradeTools() async {
        do {
            try await ToolLocator.brewUpgrade()
            staleHint = false
            _ = await bootstrap()
        } catch {
            lastError = JobError(message: "업그레이드에 실패했습니다.", detail: error.localizedDescription)
        }
    }

    func pickDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.destinationURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.destinationFolder = url.path
        }
    }

    // MARK: - Display metadata

    /// Derive display title/artist. Honors clean-titles: split "Artist - Title" only when it
    /// looks like music. The original is always preserved as rawTitle.
    static func displayMetadata(meta: VideoMeta, settings: AppSettings) -> (title: String, artist: String?, album: String?) {
        if let track = meta.track, let artist = meta.artist {
            return (track, artist, meta.album)
        }
        if settings.cleanTitles {
            let cleaned = stripNoise(meta.title)
            if let dash = cleaned.range(of: " - ") {
                let artist = String(cleaned[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
                let title = String(cleaned[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty, !title.isEmpty, artist.count < 60 {
                    return (title, artist, meta.album)
                }
            }
            return (cleaned, meta.artist ?? meta.uploader, meta.album)
        }
        return (meta.title, meta.artist ?? meta.uploader, meta.album)
    }

    private static func stripNoise(_ title: String) -> String {
        var t = title
        let patterns = ["(Official Video)", "(Official Music Video)", "(Official Audio)",
                        "(Lyrics)", "(Lyric Video)", "[Official Video]", "[Official Audio]",
                        "(Audio)", "[HD]", "(HD)", "(MV)", "(M/V)", "[MV]"]
        for p in patterns {
            t = t.replacingOccurrences(of: p, with: "", options: .caseInsensitive)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Settings persistence

    private static let settingsKey = "soundlog.settings.v1"

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: AppModel.settingsKey)
        }
    }
}
