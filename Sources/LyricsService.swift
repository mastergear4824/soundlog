import Foundation

struct Lyrics: Sendable, Equatable {
    var synced: String?   // LRC (timestamped)
    var plain: String?
    /// Prefer synced (LRC) lyrics when embedding.
    var best: String? { (synced?.isEmpty == false ? synced : nil) ?? plain }
    var isEmpty: Bool { (synced?.isEmpty ?? true) && (plain?.isEmpty ?? true) }
}

/// Fetches lyrics from LRCLIB (free, no key) — returns synced (LRC) + plain lyrics.
enum LyricsService {
    static func fetch(title: String, artist: String, durationSeconds: Int?) async -> Lyrics? {
        guard var comps = URLComponents(string: "https://lrclib.net/api/search") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("SoundLog/1.0 (https://github.com/mastergear4824/soundlog)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let results = try? JSONDecoder().decode([LRCResult].self, from: data),
              !results.isEmpty else { return nil }

        // Prefer an entry that has synced lyrics and the closest duration.
        let best = results
            .sorted { a, b in
                let sa = a.syncedLyrics?.isEmpty == false, sb = b.syncedLyrics?.isEmpty == false
                if sa != sb { return sa }  // synced first
                guard let t = durationSeconds, t > 0 else { return false }
                return abs(Int(a.duration ?? 0) - t) < abs(Int(b.duration ?? 0) - t)
            }
            .first
        guard let best, (best.syncedLyrics?.isEmpty == false || best.plainLyrics?.isEmpty == false) else { return nil }
        return Lyrics(synced: best.syncedLyrics, plain: best.plainLyrics)
    }
}

private struct LRCResult: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?
    let duration: Double?
}
