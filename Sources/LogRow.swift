import SwiftUI
import AppKit

/// One row in the log: cover, title/artist, duration + relative time, hover actions,
/// drag-out to Finder, and a file-missing repair affordance.
struct LogRow: View {
    @Environment(AppModel.self) private var model
    let entry: LogEntry
    @State private var hovering = false
    @State private var coverImage: NSImage?

    private var fileMissing: Bool { !model.library.fileExists(for: entry) }

    var body: some View {
        HStack(spacing: 12) {
            cover
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .center) {
                    if hovering && !fileMissing {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .onTapGesture { if !fileMissing { model.playNow(entry) } }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if let artist = entry.artist, !artist.isEmpty {
                        Text(artist).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if fileMissing {
                        Label("파일 없음", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption)
                    }
                }
                .font(.subheadline)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if entry.durationSeconds > 0 {
                    Text(Format.duration(entry.durationSeconds)).monospacedDigit()
                }
                Text(Format.relative(entry.savedAt))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            actionButtons
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(hovering ? 0.22 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onDrag { dragProvider() }
        .contextMenu { contextMenu }
        .task(id: entry.id) { await loadCover() }
    }

    /// Load the cached thumbnail off the main thread, then hand the image to the view.
    private func loadCover() async {
        guard let url = model.library.thumbnailURL(for: entry) else { coverImage = nil; return }
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        coverImage = data.flatMap(NSImage.init(data:))
    }

    /// Always-visible row actions. The play button plays now on click; its menu adds
    /// "play next" and "add to queue".
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if fileMissing {
                iconButton("arrow.clockwise.circle", "다시 받기") { model.redownload(entry) }
            } else {
                Menu {
                    Button { model.playNow(entry) } label: { Label("바로 재생", systemImage: "play.fill") }
                    Button { model.playNext(entry) } label: { Label("다음에 재생", systemImage: "text.line.first.and.arrowtriangle.forward") }
                    Button { model.addToQueue(entry) } label: { Label("재생 목록에 추가", systemImage: "plus.circle") }
                } label: {
                    Image(systemName: "play.circle")
                } primaryAction: {
                    model.playNow(entry)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("재생 (메뉴: 다음에 재생 / 목록에 추가)")
                iconButton("folder", "Finder에서 열기") { model.reveal(entry) }
            }
        }
        .font(.title3)
        .foregroundStyle(hovering ? Color.accentColor : Color.secondary)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("바로 재생") { model.playNow(entry) }.disabled(fileMissing)
        Button("다음에 재생") { model.playNext(entry) }.disabled(fileMissing)
        Button("재생 목록에 추가") { model.addToQueue(entry) }.disabled(fileMissing)
        Divider()
        Button("Finder에서 보기") { model.reveal(entry) }.disabled(fileMissing)
        Button("원본 URL 복사") { model.copyToPasteboard(entry.sourceURL) }
        Button("yt-dlp 명령 복사") { Task { model.copyToPasteboard(await model.copyCommand(for: entry)) } }
        Divider()
        if fileMissing {
            Button("다시 받기") { model.redownload(entry) }
        }
        Button("로그에서 삭제", role: .destructive) { model.library.remove(entry) }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }

    @ViewBuilder
    private var cover: some View {
        if let coverImage {
            Image(nsImage: coverImage).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }

    private func dragProvider() -> NSItemProvider {
        // Re-check readability at drag time, not just existence at render time.
        guard !fileMissing,
              FileManager.default.isReadableFile(atPath: entry.filePath),
              let provider = NSItemProvider(contentsOf: entry.fileURL) else { return NSItemProvider() }
        return provider
    }
}
