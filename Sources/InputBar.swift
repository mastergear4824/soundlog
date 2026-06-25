import SwiftUI

/// The paste field at the top of the window. Glows when the clipboard/field holds a YouTube link.
struct InputBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField("URL을 붙여넣으세요  (⌘V)", text: $model.urlText)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit { if model.canSave { model.save() } }
            if case .probing = model.input {
                ProgressView().controlSize(.small)
            } else if !model.urlText.isEmpty {
                Button {
                    model.urlText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlassCapsule()
        .overlay(
            Capsule(style: .continuous).strokeBorder(glowColor, lineWidth: glowWidth)
        )
        .animation(.easeOut(duration: 0.2), value: glowWidth)
        .onAppear { focused = true }
    }

    private var hasLink: Bool { YouTubeURL.looksLikeYouTube(model.urlText) }

    private var glowColor: Color {
        switch model.input {
        case .error: return .red.opacity(0.6)
        case .ready: return .green.opacity(0.7)
        default: return hasLink ? .accentColor.opacity(0.8) : .clear
        }
    }

    private var glowWidth: CGFloat {
        if case .ready = model.input { return 2 }
        return hasLink ? 2 : 0
    }
}
