import Foundation

/// A resolved external CLI tool: absolute path + version string.
struct ResolvedTool: Sendable, Equatable {
    var path: String
    var version: String
}

/// The pair of tools the app needs, plus the ffmpeg directory for --ffmpeg-location.
struct ToolSet: Sendable, Equatable {
    var ytDlp: ResolvedTool
    var ffmpeg: ResolvedTool
    /// Directory containing the ffmpeg binary, passed to yt-dlp via --ffmpeg-location.
    var ffmpegDir: String { (ffmpeg.path as NSString).deletingLastPathComponent }
}

/// Locates yt-dlp / ffmpeg and runs maintenance commands. A Finder-launched GUI app
/// has a stripped PATH, so we resolve absolute paths from the known Homebrew locations.
enum ToolLocator {
    /// Common install prefixes (Apple Silicon Homebrew, Intel Homebrew, MacPorts).
    static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]

    /// Writable override dir (~/Library/Application Support/Soundlog/bin) for self-updated tools.
    static var overrideDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Soundlog/bin", isDirectory: true)
    }

    /// A binary bundled inside the app (Contents/Resources/bin), if present.
    static func bundledPath(_ tool: String) -> String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("bin/\(tool)") else { return nil }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }

    /// Absolute path to a tool: self-updated override first, then the bundled copy
    /// (self-contained app), then a system install on PATH.
    static func locate(_ tool: String) -> String? {
        if let dir = overrideDir?.appendingPathComponent(tool).path,
           FileManager.default.isExecutableFile(atPath: dir) {
            return dir
        }
        if let bundled = bundledPath(tool) { return bundled }
        return searchDirs
            .map { "\($0)/\(tool)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Resolve both tools with versions, or return what's missing.
    static func resolve() async -> Result<ToolSet, MissingTools> {
        let ytPath = locate("yt-dlp")
        let ffPath = locate("ffmpeg")
        guard let ytPath, let ffPath else {
            return .failure(MissingTools(ytDlp: ytPath == nil, ffmpeg: ffPath == nil))
        }
        async let ytVer = version(ofYtDlp: ytPath)
        async let ffVer = version(ofFfmpeg: ffPath)
        let tools = ToolSet(
            ytDlp: ResolvedTool(path: ytPath, version: await ytVer),
            ffmpeg: ResolvedTool(path: ffPath, version: await ffVer)
        )
        return .success(tools)
    }

    private static func version(ofYtDlp path: String) async -> String {
        (try? await captureFirstLine(path, ["--version"])) ?? "unknown"
    }

    private static func version(ofFfmpeg path: String) async -> String {
        guard let line = try? await captureFirstLine(path, ["-version"]) else { return "unknown" }
        // "ffmpeg version 8.1.2 Copyright ..." -> "8.1.2"
        let parts = line.split(separator: " ")
        if let idx = parts.firstIndex(of: "version"), idx + 1 < parts.count {
            return String(parts[idx + 1])
        }
        return line
    }

    /// Download the latest standalone yt-dlp into the writable override dir, so the app can
    /// self-heal when the bundled copy goes stale (the bundled binary inside the .app is
    /// read-only / signed and can't replace itself).
    static func updateYtDlp() async throws {
        guard let dir = overrideDir else { throw ToolError.message("저장 위치를 찾을 수 없습니다.") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        let (tmp, _) = try await URLSession.shared.download(from: url)
        let dest = dir.appendingPathComponent("yt-dlp")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    private static func captureFirstLine(_ path: String, _ args: [String]) async throws -> String {
        for try await line in ProcessRunner.run(executable: path, arguments: args) {
            if case let .stdout(text) = line, !text.isEmpty { return text }
        }
        return ""
    }
}

struct MissingTools: Error, Sendable, Equatable {
    var ytDlp: Bool
    var ffmpeg: Bool

    var bannerMessage: String {
        (ytDlp || ffmpeg)
            ? "오디오 도구를 찾을 수 없습니다 — 앱을 다시 설치해 주세요 (또는 `brew install yt-dlp ffmpeg`)."
            : ""
    }
}

enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(m) = self { return m } else { return nil } }
}
