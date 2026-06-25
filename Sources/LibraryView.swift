import SwiftUI
import AppKit

enum LibraryTab: Hashable { case saved, active }

/// The root view: input + preview on top, then a tabbed list of saved vs in-progress audio.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var showSettings = false
    @State private var tab: LibraryTab = .saved

    private var jobCount: Int { (model.activeJob != nil ? 1 : 0) + model.queue.count }
    private var hasJobs: Bool { jobCount > 0 }

    var body: some View {
        ZStack {
            AmbientBackground()
            NavigationStack {
                VStack(spacing: 0) {
                    topArea
                    Divider().opacity(0.4)
                    logArea
                }
                .background(Color.clear)
                // Floating mini-player hovering over the bottom of the window.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingPlayer()
                        .animation(.spring(response: 0.35, dampingFraction: 0.85),
                                   value: model.player.current?.id)
                }
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 8) {
                            Image(nsImage: NSApplication.shared.applicationIconImage)
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text("Soundlog").font(.headline.weight(.semibold))
                            Text("v\(model.appVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .help("설정")
                    }
                }
                .searchable(text: $search, placement: .toolbar, prompt: "로그 검색")
            }
        }
        .frame(minWidth: 620, minHeight: 580)
        .task { await model.bootstrap() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Top (input + preview + status)

    @ViewBuilder
    private var topArea: some View {
        VStack(spacing: 12) {
            InputBar()

            if let missing = model.missingTools {
                banner(missing.bannerMessage, system: "wrench.and.screwdriver.fill", tint: .orange)
            }

            switch model.input {
            case .ready(let meta, _):
                PreviewCard(meta: meta, duplicate: model.library.existing(videoID: meta.id))
            case .playlistReady(let title, let items):
                PlaylistPreviewCard(title: title, items: items)
            case .error(let msg) where !model.urlText.isEmpty:
                banner(msg, system: "exclamationmark.circle", tint: .red)
            default:
                EmptyView()
            }

            if let err = model.lastError {
                ErrorBanner(error: err)
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 12)
    }

    // MARK: - Tabbed log

    @ViewBuilder
    private var logArea: some View {
        if model.library.entries.isEmpty && !hasJobs {
            emptyState
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("저장됨 \(model.library.entries.count)").tag(LibraryTab.saved)
                    Text(hasJobs ? "진행 중 \(jobCount)" : "진행 중").tag(LibraryTab.active)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch tab {
                case .saved: savedList
                case .active: activeList
                }
            }
        }
    }

    @ViewBuilder
    private var savedList: some View {
        if model.library.entries.isEmpty {
            centeredHint("아직 저장한 곡이 없어요")
        } else if filtered.isEmpty {
            centeredHint("검색 결과가 없어요")
        } else {
            List {
                ForEach(filtered) { entry in
                    LogRow(entry: entry)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var activeList: some View {
        if !hasJobs {
            centeredHint("진행 중인 작업이 없어요")
        } else {
            List {
                if let job = model.activeJob, let phase = model.jobPhase {
                    ActiveJobCard(meta: job.meta, phase: phase)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                }
                ForEach(model.queue) { job in
                    QueuedRow(job: job)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func centeredHint(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("아직 저장한 오디오가 없어요")
                .font(.title3.weight(.medium))
            Text("위에 YouTube URL을 붙여넣고 저장하면 여기에 쌓입니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var filtered: [LogEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.library.entries }
        return model.library.entries.filter {
            $0.title.lowercased().contains(q)
                || ($0.artist?.lowercased().contains(q) ?? false)
                || $0.rawTitle.lowercased().contains(q)
        }
    }

    private func banner(_ text: String, system: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: system).foregroundStyle(tint)
            Text(text).font(.subheadline)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassBanner(tint: tint, cornerRadius: 12)
    }
}
