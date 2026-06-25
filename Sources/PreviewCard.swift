import SwiftUI

/// The pre-flight preview shown after a probe: thumbnail + title + Save, or an
/// "already saved" variant when the video id is a duplicate.
struct PreviewCard: View {
    @Environment(AppModel.self) private var model
    let meta: VideoMeta
    let duplicate: LogEntry?

    var body: some View {
        HStack(spacing: 14) {
            RemoteThumbnail(url: thumbURL)
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(meta.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let up = meta.uploader { Text(up).foregroundStyle(.secondary) }
                    if let d = meta.durationSeconds {
                        Text(Format.duration(d))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }

            Spacer(minLength: 8)

            if let duplicate {
                VStack(alignment: .trailing, spacing: 6) {
                    Label("이미 저장됨", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                    Text(Format.relative(duplicate.savedAt))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Finder에서 보기") { model.reveal(duplicate) }
                        .controlSize(.small)
                }
            } else {
                Button {
                    model.save()
                } label: {
                    Label("저장", systemImage: "arrow.down.circle.fill")
                        .font(.body.bold())
                        .frame(minWidth: 64)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14)
    }

    private var thumbURL: URL? {
        if let s = meta.thumbnailURL, let u = URL(string: s) { return u }
        return URL(string: "https://i.ytimg.com/vi/\(meta.id)/hqdefault.jpg")
    }
}

/// The active download card: live progress, stage label, and Cancel.
struct ActiveJobCard: View {
    @Environment(AppModel.self) private var model
    let meta: VideoMeta
    let phase: JobPhase

    var body: some View {
        HStack(spacing: 14) {
            RemoteThumbnail(url: URL(string: "https://i.ytimg.com/vi/\(meta.id)/hqdefault.jpg"))
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(meta.title).font(.headline).lineLimit(1)
                progressContent
            }

            Spacer(minLength: 8)

            Button(role: .cancel) { model.cancel() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("취소")
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14)
    }

    @ViewBuilder
    private var progressContent: some View {
        switch phase {
        case .downloading(let p):
            if let percent = p.percent {
                ProgressView(value: percent)
                HStack(spacing: 10) {
                    Text("\(Int(percent * 100))%").monospacedDigit().bold()
                    if let sp = p.speedBytesPerSec { Text(Format.speed(sp)) }
                    if let eta = p.etaSeconds { Text("· \(Format.eta(eta)) 남음") }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
                Text(queuedSuffix("받는 중…")).font(.caption).foregroundStyle(.secondary)
            }
        case .postprocessing(let stage):
            ProgressView().controlSize(.small)
            Text(queuedSuffix(stage)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func queuedSuffix(_ s: String) -> String {
        model.queue.count > 0 ? "\(s)  ·  대기 \(model.queue.count)" : s
    }
}

/// Preview for a playlist URL: title + count, with a "save all new" button.
struct PlaylistPreviewCard: View {
    @Environment(AppModel.self) private var model
    let title: String?
    let items: [VideoMeta]

    private var newCount: Int { model.playlistNewCount(items) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 34))
                .foregroundStyle(.purple)
                .frame(width: 68, height: 68)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.purple.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title ?? "재생목록").font(.headline).lineLimit(1)
                Text(newCount == items.count
                     ? "\(items.count)개 영상"
                     : "\(items.count)개 중 새로 \(newCount)개")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                model.save()
            } label: {
                Label("\(newCount)개 저장", systemImage: "arrow.down.circle.fill")
                    .font(.body.bold())
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .keyboardShortcut(.defaultAction)
            .disabled(newCount == 0)
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14)
    }
}

/// A queued (not-yet-started) job row in the log list.
struct QueuedRow: View {
    @Environment(AppModel.self) private var model
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            RemoteThumbnail(url: URL(string: "https://i.ytimg.com/vi/\(job.meta.id)/hqdefault.jpg"))
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.meta.title).font(.body).lineLimit(1)
                Text("대기 중").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { model.cancelQueued(job) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("대기열에서 제거")
        }
        .padding(.vertical, 4)
    }
}

/// A banner shown when a download fails, with Copy-detail and (for extractor breaks) upgrade.
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    let error: AppModel.JobError

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(error.message).font(.subheadline)
            Spacer()
            Button("상세 복사") { model.copyToPasteboard(error.detail) }
                .controlSize(.small)
            if model.staleHint {
                Button("yt-dlp 업데이트") { Task { await model.upgradeTools() } }
                    .controlSize(.small)
            }
            Button { model.dismissError() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassBanner(tint: .orange, cornerRadius: 12)
    }
}

/// Async remote image with a neutral placeholder.
struct RemoteThumbnail: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
            case .empty: Rectangle().fill(.quaternary).overlay(ProgressView().controlSize(.small))
            case .failure: Rectangle().fill(.quaternary).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            @unknown default: Rectangle().fill(.quaternary)
            }
        }
    }
}
