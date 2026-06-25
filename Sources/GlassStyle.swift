import SwiftUI
import AppKit

// MARK: - Native Liquid Glass (macOS 26+) with a material fallback

extension View {
    /// Apple's Liquid Glass (`glassEffect`) on macOS 26+, falling back to a frosted material
    /// card on older systems. `tintWhite` adds a white tint for a brighter, white-ish glass.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 16, tintWhite: Double = 0, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                glassStyle(tintWhite: tintWhite, interactive: interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.glassCard(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(tintWhite: Double = 0) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(glassStyle(tintWhite: tintWhite, interactive: false), in: Capsule(style: .continuous))
        } else {
            self.glassCapsule()
        }
    }
}

@available(macOS 26.0, *)
private func glassStyle(tintWhite: Double, interactive: Bool) -> Glass {
    var glass: Glass = tintWhite > 0 ? .regular.tint(.white.opacity(tintWhite)) : .regular
    if interactive { glass = glass.interactive() }
    return glass
}

// MARK: - Ambient background driven by the playing track's artwork

/// Soft, blurred colour blobs. When a track is playing, the blobs take on the dominant colours
/// of its album art (Apple Music style); otherwise a default brand aurora is shown.
struct AmbientBackground: View {
    @Environment(AppModel.self) private var model
    @State private var colors: [Color] = AmbientBackground.fallback

    static let fallback: [Color] = [.purple, .blue, .pink, .orange]

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            blob(colors[safe: 0] ?? .purple, 0.42, 470, x: -190, y: -240)
            blob(colors[safe: 1] ?? .blue,   0.30, 380, x:  175, y: -150)
            blob(colors[safe: 2] ?? .pink,   0.34, 390, x: -150, y:  240)
            blob(colors[safe: 3] ?? .orange, 0.34, 450, x:  210, y:  220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.9), value: colors)
        .task(id: model.player.current?.id) { await refresh() }
    }

    private func blob(_ color: Color, _ opacity: Double, _ size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(color.opacity(opacity)).frame(width: size, height: size).blur(radius: 110).offset(x: x, y: y)
    }

    private func refresh() async {
        guard let entry = model.player.current,
              let url = model.library.thumbnailURL(for: entry) else {
            colors = Self.fallback
            return
        }
        let extracted = await Task.detached(priority: .utility) { DominantColors.extract(from: url) }.value
        colors = (extracted?.count ?? 0) >= 4
            ? extracted!.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: 1) }
            : Self.fallback
    }
}

/// Plain brand aurora (no track dependency) for the settings sheet.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            blob(.purple, 0.34, 420, x: -170, y: -200)
            blob(.pink,   0.28, 360, x:  150, y: -120)
            blob(.orange, 0.28, 420, x:  120, y:  200)
        }
        .ignoresSafeArea().allowsHitTesting(false)
    }
    private func blob(_ c: Color, _ o: Double, _ s: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(c.opacity(o)).frame(width: s, height: s).blur(radius: 110).offset(x: x, y: y)
    }
}

struct RGB: Sendable { let r: Double; let g: Double; let b: Double }

/// Extract four quadrant-average colours from an image, lightly boosted for vividness.
enum DominantColors {
    static func extract(from url: URL) -> [RGB]? {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 4, h > 4 else { return nil }
        // YouTube thumbnails (hqdefault) are letterboxed 4:3 with black bars top/bottom.
        // Sample only the central frame so the bars don't muddy the colours.
        let insetY = h / 6, insetX = w / 12
        let x0 = insetX, x1 = w - insetX
        let y0 = insetY, y1 = h - insetY
        let mw = (x0 + x1) / 2, mh = (y0 + y1) / 2
        return [
            average(rep, x0, y0, mw, mh),
            average(rep, mw, y0, x1, mh),
            average(rep, x0, mh, mw, y1),
            average(rep, mw, mh, x1, y1),
        ]
    }

    private static func average(_ rep: NSBitmapImageRep, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> RGB {
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        let stepX = max(1, (x1 - x0) / 8), stepY = max(1, (y1 - y0) / 8)
        var x = x0
        while x < x1 {
            var y = y0
            while y < y1 {
                if let c = rep.colorAt(x: x, y: y) {
                    r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1
                }
                y += stepY
            }
            x += stepX
        }
        guard n > 0 else { return RGB(r: 0.5, g: 0.5, b: 0.5) }
        return vivid(RGB(r: r / n, g: g / n, b: b / n))
    }

    /// Boost saturation a little so muddy averages still read as colour.
    private static func vivid(_ rgb: RGB) -> RGB {
        let color = NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        guard let hsb = color.usingColorSpace(.sRGB) else { return rgb }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        hsb.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let boosted = NSColor(hue: h, saturation: min(1, s * 1.5), brightness: min(0.92, max(0.5, v)), alpha: 1)
        guard let srgb = boosted.usingColorSpace(.sRGB) else { return rgb }
        return RGB(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Material fallbacks (pre-macOS 26)

extension View {
    func glassCard(cornerRadius: CGFloat = 16, rim: Double = 0.28, shadow: Double = 0.12) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(rim * 1.7), .white.opacity(rim * 0.25)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(shadow), radius: 12, y: 5)
    }

    func glassCapsule(rim: Double = 0.30, shadow: Double = 0.10) -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(rim), lineWidth: 1))
            .shadow(color: .black.opacity(shadow), radius: 8, y: 4)
    }

    func glassBanner(tint: Color, cornerRadius: CGFloat = 12) -> some View {
        self
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}
