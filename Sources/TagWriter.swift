import Foundation

enum TagError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(m) = self { return m } else { return nil } }
}

/// Rewrites an mp3's ID3 tags, cover art, and lyrics using the bundled ffmpeg (no re-encode).
/// Returns a temp file with the tagged audio; the caller moves it into place.
enum TagWriter {
    static func apply(ffmpeg: String, source: URL, meta: TrackMeta, lyrics: Lyrics?, coverData: Data?) async throws -> URL {
        let dir = source.deletingLastPathComponent()
        let out = dir.appendingPathComponent(".sl-tag-\(UUID().uuidString).mp3")

        var coverURL: URL?
        if let coverData, coverData.count > 1024 {
            let c = dir.appendingPathComponent(".sl-cover-\(UUID().uuidString).jpg")
            try? coverData.write(to: c)
            coverURL = c
        }
        defer { coverURL.map { try? FileManager.default.removeItem(at: $0) } }

        var args = ["-y", "-hide_banner", "-loglevel", "error", "-i", source.path]
        if let coverURL { args += ["-i", coverURL.path] }

        if coverURL != nil {
            args += ["-map", "0:a", "-map", "1:v"]   // audio + new cover (replaces old)
        } else {
            args += ["-map", "0"]                     // keep all streams incl. existing cover
        }
        args += ["-c", "copy", "-id3v2_version", "3"]

        args += ["-metadata", "title=\(meta.title)", "-metadata", "artist=\(meta.artist)"]
        if let album = meta.album { args += ["-metadata", "album=\(album)"] }
        if let year = meta.year { args += ["-metadata", "date=\(year)"] }
        if let genre = meta.genre { args += ["-metadata", "genre=\(genre)"] }
        if let words = lyrics?.best, !words.isEmpty { args += ["-metadata", "lyrics=\(words)"] }
        if coverURL != nil {
            args += ["-metadata:s:v", "title=Album cover", "-disposition:v:0", "attached_pic"]
        }
        args.append(out.path)

        var stderr = ""
        do {
            for try await line in ProcessRunner.run(executable: ffmpeg, arguments: args) {
                if case let .stderr(s) = line { stderr += s + "\n" }
            }
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw TagError.message(stderr.isEmpty ? "태그 기록에 실패했습니다." : stderr)
        }
        return out
    }
}
