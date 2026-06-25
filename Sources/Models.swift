import Foundation

// MARK: - Persisted log entry

/// One saved audio file. The permanent record that makes Soundlog a "log".
struct LogEntry: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    /// The RESOLVED yt-dlp video id (not the pasted string). The real dedup key —
    /// collapses youtu.be / watch?v= / playlist-param URL variants to one video.
    var canonicalVideoID: String
    var sourceURL: String
    var title: String
    var artist: String?
    var album: String?
    var year: Int?
    var durationSeconds: Int
    var filePath: String
    var fileSizeBytes: Int64
    var thumbnailFileName: String?
    var savedAt: Date
    var ytDlpVersion: String
    /// Original title, preserved even when clean-titles rewrites artist/title.
    var rawTitle: String
    /// Lyrics fetched during enrichment (LRCLIB). `synced` is timestamped LRC.
    var syncedLyrics: String?
    var plainLyrics: String?

    init(id: UUID = UUID(), canonicalVideoID: String, sourceURL: String, title: String,
         artist: String? = nil, album: String? = nil, year: Int? = nil,
         durationSeconds: Int, filePath: String, fileSizeBytes: Int64,
         thumbnailFileName: String? = nil, savedAt: Date, ytDlpVersion: String, rawTitle: String,
         syncedLyrics: String? = nil, plainLyrics: String? = nil) {
        self.id = id
        self.canonicalVideoID = canonicalVideoID
        self.sourceURL = sourceURL
        self.title = title
        self.artist = artist
        self.album = album
        self.year = year
        self.durationSeconds = durationSeconds
        self.filePath = filePath
        self.fileSizeBytes = fileSizeBytes
        self.thumbnailFileName = thumbnailFileName
        self.savedAt = savedAt
        self.ytDlpVersion = ytDlpVersion
        self.rawTitle = rawTitle
        self.syncedLyrics = syncedLyrics
        self.plainLyrics = plainLyrics
    }

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var hasLyrics: Bool { (syncedLyrics?.isEmpty == false) || (plainLyrics?.isEmpty == false) }
}

/// Top-level JSON document with a schema version for forward migration.
struct LibraryDocument: Codable, Sendable {
    var schemaVersion: Int
    var entries: [LogEntry]

    static let currentSchemaVersion = 1
    static let empty = LibraryDocument(schemaVersion: currentSchemaVersion, entries: [])
}

// MARK: - Settings

struct AppSettings: Codable, Sendable, Equatable {
    var destinationFolder: String
    /// LAME VBR quality: "0" = V0 (best). Remembered between runs.
    var mp3Quality: String
    var embedThumbnail: Bool
    /// Apply "Artist - Title" cleanup only on a confident music pattern.
    var cleanTitles: Bool
    /// EBU R128 loudness normalization (off by default).
    var normalizeLoudness: Bool

    static var `default`: AppSettings {
        AppSettings(
            destinationFolder: defaultDestination().path,
            mp3Quality: "0",
            embedThumbnail: true,
            cleanTitles: true,
            normalizeLoudness: false
        )
    }

    static func defaultDestination() -> URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("Soundlog", isDirectory: true)
    }

    var destinationURL: URL { URL(fileURLWithPath: destinationFolder, isDirectory: true) }
}

// MARK: - Probe result

/// Metadata from a `--dump-single-json` probe, used for the preview card + dedup.
struct VideoMeta: Sendable, Equatable {
    var id: String
    var title: String
    var uploader: String?
    var durationSeconds: Int?
    var thumbnailURL: String?
    var webpageURL: String?
    var availability: String?
    var isLive: Bool

    /// Music metadata yt-dlp sometimes returns for Topic / YT Music channels.
    var track: String?
    var artist: String?
    var album: String?
    var releaseYear: Int?
}

// MARK: - Live job state

struct DownloadProgress: Sendable, Equatable {
    var percent: Double?        // 0...1, nil when totals unknown (DASH/HLS)
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var speedBytesPerSec: Double?
    var etaSeconds: Int?
}

/// Typed events the engine emits while a download runs.
enum ProgressEvent: Sendable, Equatable {
    case downloading(DownloadProgress)
    case postprocessing(stage: String)
    case finalPath(String)
    case info(String)
}

/// The phase of the one active job, surfaced to the UI.
enum JobPhase: Sendable, Equatable {
    case downloading(DownloadProgress)
    case postprocessing(stage: String)
}

/// State of the input/preview area above the log.
enum InputState: Sendable, Equatable {
    case idle
    case probing
    case ready(VideoMeta, duplicate: LogEntry?)
    case playlistReady(title: String?, items: [VideoMeta])
    case error(String)
}

/// One unit of work in the download queue (a single video, possibly from a playlist).
struct Job: Identifiable, Equatable, Sendable {
    let id: UUID
    var meta: VideoMeta
    var url: String

    init(meta: VideoMeta, url: String) {
        self.id = UUID()
        self.meta = meta
        self.url = url
    }
}

// MARK: - YouTube URL canonicalization

enum YouTubeURL {
    /// Extract the 11-char video id from any common YouTube URL form, or nil.
    static func videoID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare id pasted directly.
        if isValidID(trimmed) { return trimmed }

        guard let comps = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)") else {
            return nil
        }
        let host = (comps.host ?? "").lowercased()
        let isYouTube = host.contains("youtube.com") || host.contains("youtu.be")
        guard isYouTube else { return nil }

        // youtu.be/<id>
        if host.contains("youtu.be") {
            let id = comps.path.split(separator: "/").first.map(String.init) ?? ""
            return isValidID(id) ? id : nil
        }
        // youtube.com/watch?v=<id>
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, isValidID(v) {
            return v
        }
        // youtube.com/{shorts,embed,live,v}/<id>
        let segments = comps.path.split(separator: "/").map(String.init)
        if let idx = segments.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }),
           idx + 1 < segments.count, isValidID(segments[idx + 1]) {
            return segments[idx + 1]
        }
        return nil
    }

    /// Does the string look like a YouTube link or bare id at all?
    static func looksLikeYouTube(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.contains("youtube.com") || s.contains("youtu.be") || isValidID(s)
    }

    /// The `list=` playlist id, if present.
    static func playlistID(from raw: String) -> String? {
        guard let comps = URLComponents(string: normalized(raw)) else { return nil }
        let host = (comps.host ?? "").lowercased()
        guard host.contains("youtube.com") || host.contains("youtu.be") else { return nil }
        return comps.queryItems?.first(where: { $0.name == "list" })?.value
    }

    /// A link to expand into many entries: a `/playlist` path, or any `list=` playlist —
    /// including `watch?v=…&list=…`, so pasting a video that's part of a playlist grabs the
    /// whole list. Auto-generated radio/mix lists (`list=RD…`) are NOT real playlists, so
    /// those fall back to the single video.
    static func isPlaylistURL(_ raw: String) -> Bool {
        guard let comps = URLComponents(string: normalized(raw)) else { return false }
        let host = (comps.host ?? "").lowercased()
        guard host.contains("youtube.com") || host.contains("youtu.be") else { return false }
        if comps.path.contains("playlist") { return true }
        guard let list = comps.queryItems?.first(where: { $0.name == "list" })?.value else { return false }
        return !list.hasPrefix("RD") && !list.isEmpty
    }

    static func canonicalURL(forID id: String) -> String {
        "https://www.youtube.com/watch?v=\(id)"
    }

    private static func normalized(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("://") ? t : "https://\(t)"
    }

    private static func isValidID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

// MARK: - Formatting helpers

enum Format {
    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func speed(_ bytesPerSec: Double) -> String {
        bytes(Int64(bytesPerSec)) + "/s"
    }

    static func eta(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: date, relativeTo: now)
    }
}
