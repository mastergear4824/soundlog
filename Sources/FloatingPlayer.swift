import SwiftUI
import AppKit

/// A floating mini-player hovering over the bottom of the main window. The list button expands
/// the card upward to reveal the play queue; tapping it again collapses back to the mini bar.
struct FloatingPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var expanded = false

    var body: some View {
        let player = model.player
        if let entry = player.current {
            VStack(spacing: 0) {
                if expanded {
                    queuePanel(player)
                    Divider()
                }
                controlRow(entry, player)
            }
            .liquidGlass(cornerRadius: 18, tintWhite: 0.35, interactive: true)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Expanded queue (above the controls)

    private func queuePanel(_ player: PlayerController) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("비우기") { player.clearQueue() }
                    .controlSize(.small)
                    .disabled(player.queue.isEmpty)
                Text("재생 목록 · \(player.queue.count)곡").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { expanded = false }
                } label: {
                    Image(systemName: "chevron.down").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("재생 목록 접기")
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)

            if player.queue.isEmpty {
                Text("재생 목록이 비어 있어요")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, entry in
                            QueueRow(entry: entry, index: index, isCurrent: index == player.currentIndex)
                            if index < player.queue.count - 1 { Divider().padding(.leading, 40) }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    // MARK: - Compact control row

    private func controlRow(_ entry: LogEntry, _ player: PlayerController) -> some View {
        HStack(spacing: 12) {
            LocalThumb(entry: entry)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if let artist = entry.artist, !artist.isEmpty {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)

            transportToggle("shuffle", on: player.shuffle, help: "임의 재생") { player.toggleShuffle() }
            Button { player.previous() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(.plain)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 22)
            }
            .buttonStyle(.plain)
            Button { player.next() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(.plain)
            repeatToggle(player)

            Text(Format.duration(Int(player.currentTime)))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
            Slider(value: $scrubValue, in: 0...max(player.duration, 1)) { editing in
                scrubbing = editing
                if !editing { player.seek(to: scrubValue) }
            }
            .frame(minWidth: 110)
            .onChange(of: player.currentTime) { _, t in if !scrubbing { scrubValue = t } }
            .onChange(of: player.current?.id) { _, _ in scrubValue = 0 }
            Text(Format.duration(Int(player.duration)))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            // Open the queue from the compact bar. When expanded, the panel header's
            // chevron handles collapsing, so this is hidden.
            if !expanded {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { expanded = true }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("재생 목록 펼치기")
            }

            Button { player.close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("플레이어 닫기")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func transportToggle(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(on ? Color.accentColor : Color.secondary)
            .help(help)
    }

    private func repeatToggle(_ player: PlayerController) -> some View {
        Button { player.cycleRepeat() } label: {
            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
        }
        .buttonStyle(.plain)
        .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
        .help(repeatHelp(player.repeatMode))
    }

    private func repeatHelp(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: return "반복 꺼짐"
        case .all: return "재생 목록 반복"
        case .one: return "한 곡 반복"
        }
    }
}

private struct QueueRow: View {
    @Environment(AppModel.self) private var model
    let entry: LogEntry
    let index: Int
    let isCurrent: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if isCurrent && model.player.isPlaying {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint).frame(width: 16)
            } else {
                Text("\(index + 1)").font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 16)
            }
            LocalThumb(entry: entry)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).lineLimit(1).fontWeight(isCurrent ? .semibold : .regular)
                if let artist = entry.artist, !artist.isEmpty {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if hovering {
                Button { model.player.removeFromQueue(entry) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.player.playFromQueue(at: index) }
        .onHover { hovering = $0 }
    }
}

/// A locally-cached thumbnail loaded off the main thread.
struct LocalThumb: View {
    @Environment(AppModel.self) private var model
    let entry: LogEntry
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .task(id: entry.id) {
            guard let url = model.library.thumbnailURL(for: entry) else { image = nil; return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
