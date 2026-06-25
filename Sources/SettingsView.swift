import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("저장 위치") {
                    HStack {
                        Text(model.settings.destinationFolder)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("변경…") { model.pickDestinationFolder() }
                    }
                }

                Section("오디오") {
                    Picker("MP3 품질", selection: $model.settings.mp3Quality) {
                        Text("V0 — 최고 음질 (~256k VBR)").tag("0")
                        Text("V2 — 높음 (~190k VBR)").tag("2")
                        Text("V5 — 보통 (~130k VBR)").tag("5")
                        Text("320 kbps (CBR)").tag("320K")
                        Text("192 kbps (CBR)").tag("192K")
                        Text("128 kbps (CBR)").tag("128K")
                    }
                    Toggle("커버 아트 임베드", isOn: $model.settings.embedThumbnail)
                    Toggle("음량 정규화 (EBU R128)", isOn: $model.settings.normalizeLoudness)
                }

                Section("메타데이터") {
                    Toggle("제목 자동 정리 (Artist - Title)", isOn: $model.settings.cleanTitles)
                    Text("음악 패턴일 때만 정리하며, 원본 제목은 항상 보존됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("버전", value: "Soundlog v\(model.appVersion)")
                    Link(destination: URL(string: "https://github.com/mastergear4824/soundlog")!) {
                        Label("GitHub 저장소", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text("개인용 도구입니다. 콘텐츠 다운로드는 본인 책임 하에 사용하세요.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 460)
        .background(AuroraBackground())
    }
}
