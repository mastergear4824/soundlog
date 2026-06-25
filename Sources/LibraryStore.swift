import Foundation
import Observation

/// Single source of truth for the saved-audio log. Owns atomic JSON persistence and the
/// thumbnail cache. @MainActor so all reads/writes are single-threaded by construction.
@MainActor
@Observable
final class LibraryStore {
    private(set) var entries: [LogEntry] = []

    /// Dedup index keyed by the resolved canonical video id. Rebuilt on load.
    @ObservationIgnored private var indexByVideoID: [String: LogEntry] = [:]

    @ObservationIgnored private let baseDir: URL
    @ObservationIgnored private let libraryURL: URL
    @ObservationIgnored private let backupURL: URL
    @ObservationIgnored private let thumbnailsDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        baseDir = appSupport.appendingPathComponent("Soundlog", isDirectory: true)
        libraryURL = baseDir.appendingPathComponent("library.json")
        backupURL = baseDir.appendingPathComponent("library.json.bak")
        thumbnailsDir = baseDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
    }

    // MARK: - Load / save

    func load() {
        let doc = readDocument(at: libraryURL) ?? readDocument(at: backupURL) ?? .empty
        // Newest first.
        entries = doc.entries.sorted { $0.savedAt > $1.savedAt }
        rebuildIndex()
    }

    private func readDocument(at url: URL) -> LibraryDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso.decode(LibraryDocument.self, from: data)
    }

    /// Crash-safe write: write a temp file, snapshot the previous good copy to .bak, then
    /// ATOMICALLY swap it in with replaceItemAt — so library.json is never absent, even if
    /// the process dies mid-write (it's always either the old or the new full document).
    private func persist() {
        let doc = LibraryDocument(schemaVersion: LibraryDocument.currentSchemaVersion, entries: entries)
        guard let data = try? JSONEncoder.pretty.encode(doc) else { return }
        let tmp = libraryURL.appendingPathExtension("tmp")
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                // Keep one backup of the last good copy (before swapping). The live file is
                // untouched until the atomic replace below, so a crash here loses nothing.
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: libraryURL, to: backupURL)
                _ = try FileManager.default.replaceItemAt(libraryURL, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: libraryURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    // MARK: - Mutations

    func add(_ entry: LogEntry) {
        entries.removeAll { $0.canonicalVideoID == entry.canonicalVideoID }
        entries.insert(entry, at: 0)
        indexByVideoID[entry.canonicalVideoID] = entry
        persist()
    }

    func remove(_ entry: LogEntry) {
        entries.removeAll { $0.id == entry.id }
        indexByVideoID[entry.canonicalVideoID] = nil
        if let name = entry.thumbnailFileName {
            try? FileManager.default.removeItem(at: thumbnailsDir.appendingPathComponent(name))
        }
        persist()
    }

    private func rebuildIndex() {
        indexByVideoID = Dictionary(entries.map { ($0.canonicalVideoID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Queries

    func existing(videoID: String) -> LogEntry? { indexByVideoID[videoID] }

    func fileExists(for entry: LogEntry) -> Bool {
        FileManager.default.fileExists(atPath: entry.filePath)
    }

    // MARK: - Thumbnails

    func thumbnailURL(for entry: LogEntry) -> URL? {
        guard let name = entry.thumbnailFileName else { return nil }
        let url = thumbnailsDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Download and cache a video's thumbnail as <id>.jpg. Uses the canonical i.ytimg jpg
    /// (reliable, always decodable) rather than yt-dlp's possibly-webp thumbnail field.
    func cacheThumbnail(videoID: String) async -> String? {
        let fileName = "\(videoID).jpg"
        let dest = thumbnailsDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) { return fileName }

        let candidates = [
            "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg",
            "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg",
        ]
        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }
            if let data = try? await URLSession.shared.data(from: url).0, data.count > 1024 {
                try? data.write(to: dest, options: .atomic)
                return fileName
            }
        }
        return nil
    }
}

// MARK: - Codec helpers

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
