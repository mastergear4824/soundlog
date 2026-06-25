import SwiftUI

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

enum LRC {
    private static let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)

    /// Parse LRC text into time-sorted lines (supports multiple timestamps per line).
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(raw)
            let ns = s as NSString
            let matches = stamp.matches(in: s, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                lines.append(LyricLine(time: mm * 60 + ss + frac, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

/// Shows the current track's lyrics. If timestamped (LRC), highlights and auto-scrolls to the
/// active line as the song plays; tap a line to seek there. Falls back to plain text.
struct LyricsView: View {
    let entry: LogEntry
    let currentTime: Double
    let onSeek: (Double) -> Void

    @State private var lines: [LyricLine] = []

    private var activeIndex: Int? {
        guard !lines.isEmpty else { return nil }
        var idx: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= currentTime + 0.25 { idx = i } else { break }
        }
        return idx
    }

    var body: some View {
        Group {
            if !lines.isEmpty {
                synced
            } else if let plain = entry.plainLyrics, !plain.isEmpty {
                ScrollView {
                    Text(plain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "text.quote").font(.title2).foregroundStyle(.tertiary)
                    Text("가사가 없어요").font(.callout).foregroundStyle(.secondary)
                    Text("✨ 버튼으로 메타·가사를 가져오면 표시됩니다.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: entry.id) {
            lines = (entry.syncedLyrics?.isEmpty == false) ? LRC.parse(entry.syncedLyrics!) : []
        }
    }

    private var synced: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(i == activeIndex ? .title3.weight(.bold) : .body)
                            .foregroundStyle(i == activeIndex ? Color.primary : Color.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(i)
                            .contentShape(Rectangle())
                            .onTapGesture { onSeek(line.time) }
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: activeIndex) { _, new in
                guard let new else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }
}
