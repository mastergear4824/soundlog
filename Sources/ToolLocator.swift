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

    /// Absolute path to a tool if it exists and is executable.
    static func locate(_ tool: String) -> String? {
        searchDirs
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

    /// Run `brew upgrade yt-dlp ffmpeg`. NEVER use `yt-dlp -U` on a brew-managed binary —
    /// it corrupts the self-replacing managed file.
    static func brewUpgrade() async throws {
        guard let brew = locate("brew") else {
            throw ToolError.message("Homebrew(brew)를 찾을 수 없습니다. 터미널에서 'brew upgrade yt-dlp ffmpeg'를 직접 실행하세요.")
        }
        let stream = ProcessRunner.run(executable: brew, arguments: ["upgrade", "yt-dlp", "ffmpeg"])
        for try await _ in stream { /* drain to completion */ }
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
        switch (ytDlp, ffmpeg) {
        case (true, true):  return "yt-dlp와 ffmpeg가 필요합니다 — 터미널에서 `brew install yt-dlp ffmpeg`"
        case (true, false): return "yt-dlp가 필요합니다 — 터미널에서 `brew install yt-dlp`"
        case (false, true): return "ffmpeg가 필요합니다 — 터미널에서 `brew install ffmpeg`"
        case (false, false): return ""
        }
    }
}

enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(m) = self { return m } else { return nil } }
}
