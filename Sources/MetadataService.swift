import Foundation

/// Canonical track metadata fetched from a music database.
struct TrackMeta: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String?
    var year: Int?
    var genre: String?
    var artworkURL: String?
    var durationSeconds: Int?
}

/// Looks up canonical metadata via the free iTunes Search API (no key required).
enum MetadataService {
    static func search(title: String, artist: String?, durationSeconds: Int?) async -> TrackMeta? {
        let term = cleanQuery([artist, title].compactMap { $0 }.joined(separator: " "))
        guard !term.isEmpty,
              var comps = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "12"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(ITunesResponse.self, from: data) else { return nil }

        let candidates = resp.results.filter { $0.trackName != nil && $0.artistName != nil }
        guard let r = pickBest(candidates, durationSeconds: durationSeconds) else { return nil }
        return TrackMeta(
            title: r.trackName ?? title,
            artist: r.artistName ?? (artist ?? ""),
            album: r.collectionName,
            year: r.year,
            genre: r.primaryGenreName,
            artworkURL: r.artworkHigh,
            durationSeconds: r.trackTimeMillis.map { $0 / 1000 }
        )
    }

    /// Pick the result whose duration is closest to ours (within reason); else the first.
    private static func pickBest(_ results: [ITunesResult], durationSeconds: Int?) -> ITunesResult? {
        guard let target = durationSeconds, target > 0 else { return results.first }
        return results.min { a, b in
            let da = abs((a.trackTimeMillis ?? 0) / 1000 - target)
            let db = abs((b.trackTimeMillis ?? 0) / 1000 - target)
            return da < db
        }
    }

    /// Strip common YouTube-title noise so the search term is closer to the real song.
    private static func cleanQuery(_ s: String) -> String {
        var t = s
        // Remove bracketed/parenthetical chunks and quotes.
        t = t.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"['"\u{2018}\u{2019}\u{201C}\u{201D}]"#, with: " ", options: .regularExpression)
        let noise = ["official music video", "official video", "official audio", "music video",
                     "lyric video", "lyrics", "performance video", "m/v", "mv", "audio", "hd", "4k"]
        for n in noise {
            t = t.replacingOccurrences(of: n, with: " ", options: [.caseInsensitive])
        }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ITunesResponse: Decodable { let results: [ITunesResult] }

private struct ITunesResult: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let releaseDate: String?
    let primaryGenreName: String?
    let trackTimeMillis: Int?
    let artworkUrl100: String?

    var year: Int? { releaseDate.flatMap { Int($0.prefix(4)) } }
    var artworkHigh: String? { artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600") }
}
