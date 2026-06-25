import Foundation

enum ProbeError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case let .failed(m) = self { return m } else { return nil } }
}

/// Fast metadata probe: `yt-dlp --dump-single-json --skip-download` for the preview + dedup id.
enum ProbeService {
    static func probe(url: String, tools: ToolSet) async throws -> VideoMeta {
        let args = ["--dump-single-json", "--skip-download", "--no-playlist", "--no-warnings", url]
        var jsonText = ""
        var stderrText = ""
        do {
            for try await line in ProcessRunner.run(executable: tools.ytDlp.path, arguments: args) {
                switch line {
                case .stdout(let s): jsonText += s
                case .stderr(let s): stderrText += s + "\n"
                }
            }
        } catch is ProcessFailure {
            throw ProbeError.failed(shortMessage(from: stderrText))
        } catch {
            throw ProbeError.failed(error.localizedDescription)
        }

        guard let data = jsonText.data(using: .utf8), !data.isEmpty else {
            throw ProbeError.failed("메타데이터를 가져오지 못했습니다.")
        }
        let info = try JSONDecoder().decode(RawInfo.self, from: data)
        return info.toMeta()
    }

    /// Probe a playlist URL flatly (fast, no per-video extraction) into its entries.
    static func probePlaylist(url: String, tools: ToolSet) async throws -> (title: String?, items: [VideoMeta]) {
        let args = ["--flat-playlist", "--dump-single-json", "--no-warnings", url]
        var jsonText = ""
        var stderrText = ""
        do {
            for try await line in ProcessRunner.run(executable: tools.ytDlp.path, arguments: args) {
                switch line {
                case .stdout(let s): jsonText += s
                case .stderr(let s): stderrText += s + "\n"
                }
            }
        } catch is ProcessFailure {
            throw ProbeError.failed(shortMessage(from: stderrText))
        } catch {
            throw ProbeError.failed(error.localizedDescription)
        }

        guard let data = jsonText.data(using: .utf8), !data.isEmpty else {
            throw ProbeError.failed("재생목록을 가져오지 못했습니다.")
        }
        let playlist = try JSONDecoder().decode(RawPlaylist.self, from: data)
        let items = (playlist.entries ?? []).compactMap { $0.toMeta() }
        guard !items.isEmpty else {
            throw ProbeError.failed("재생목록이 비어있거나 가져올 수 없습니다.")
        }
        return (playlist.title, items)
    }

    private static func shortMessage(from stderr: String) -> String {
        let lower = stderr.lowercased()
        if lower.contains("private video") { return "비공개 영상입니다." }
        if lower.contains("video unavailable") || lower.contains("removed") { return "삭제되었거나 사용할 수 없는 영상입니다." }
        if lower.contains("sign in") || lower.contains("not a bot") { return "확인이 필요한 항목입니다 (로그인/봇 확인)." }
        // Last ERROR line, else a generic message.
        let errLine = stderr.split(separator: "\n").last(where: { $0.contains("ERROR") })
        return errLine.map(String.init) ?? "메타데이터를 가져오지 못했습니다."
    }
}

/// The subset of yt-dlp's JSON we decode. Unknown keys are ignored.
private struct RawInfo: Decodable {
    let id: String
    let title: String?
    let uploader: String?
    let channel: String?
    let duration: Double?
    let thumbnail: String?
    let webpage_url: String?
    let availability: String?
    let is_live: Bool?
    let track: String?
    let artist: String?
    let album: String?
    let release_year: Int?

    func toMeta() -> VideoMeta {
        VideoMeta(
            id: id,
            title: title ?? id,
            uploader: uploader ?? channel,
            durationSeconds: duration.map { Int($0) },
            thumbnailURL: thumbnail,
            webpageURL: webpage_url ?? YouTubeURL.canonicalURL(forID: id),
            availability: availability,
            isLive: is_live ?? false,
            track: track,
            artist: artist,
            album: album,
            releaseYear: release_year
        )
    }
}

/// A flat playlist probe: title + lightweight entries.
private struct RawPlaylist: Decodable {
    let title: String?
    let entries: [RawEntry]?
}

private struct RawEntry: Decodable {
    let id: String?
    let title: String?
    let duration: Double?
    let uploader: String?
    let channel: String?

    func toMeta() -> VideoMeta? {
        guard let id else { return nil }
        return VideoMeta(
            id: id,
            title: title ?? id,
            uploader: uploader ?? channel,
            durationSeconds: duration.map { Int($0) },
            thumbnailURL: nil,
            webpageURL: YouTubeURL.canonicalURL(forID: id),
            availability: nil,
            isLive: false,
            track: nil, artist: nil, album: nil, releaseYear: nil
        )
    }
}
