import SwiftUI

enum LRC {
    /// Strip `[..]` tags (timestamps + metadata) so LRC shows as plain readable text.
    static func stripped(_ lrc: String) -> String {
        lrc.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Displays the current track's lyrics (scrollable). No playback-synced highlighting.
struct LyricsView: View {
    let entry: LogEntry

    private var text: String? {
        if let p = entry.plainLyrics, !p.isEmpty { return p }
        if let s = entry.syncedLyrics, !s.isEmpty { return LRC.stripped(s) }
        return nil
    }

    var body: some View {
        if let text {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
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
}
