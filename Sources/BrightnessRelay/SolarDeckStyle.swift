import AppKit
import SwiftUI

private struct DeckOpaquePreviewKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var deckOpaquePreview: Bool {
        get { self[DeckOpaquePreviewKey.self] }
        set { self[DeckOpaquePreviewKey.self] = newValue }
    }
}

/// One native backdrop for the panel. Controls keep their own content/state;
/// this bridge only supplies behind-window vibrancy.
private struct DeckVibrancy: NSViewRepresentable {
    let withinWindow: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.blendingMode = withinWindow ? .withinWindow : .behindWindow
    }
}

struct DeckGlassPanel: View {
    var withinWindow = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.deckOpaquePreview) private var opaquePreview
    var body: some View {
        Group {
            if reduceTransparency || opaquePreview {
                DeckPaint.solarGradient
            } else {
                DeckVibrancy(withinWindow:withinWindow)
                    .overlay {
                        // The whole material is sun-coloured; the native
                        // backdrop remains visible through this chromatic veil.
                        DeckPaint.solarGradient.opacity(scheme == .dark ? 0.86 : 0.80)
                    }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct SolarKeyGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing:8) { content }
        } else { content }
    }
}

struct SolarSourceKeyStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.deckOpaquePreview) private var opaquePreview
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius:primary ? 14 : 10)
        let label = configuration.label
            .foregroundStyle(enabled ? DeckPaint.keyLabel : DeckPaint.muted)
            .contentShape(shape)
        Group {
            if #available(macOS 26.0, *), !reduceTransparency, !opaquePreview, enabled {
                label.glassEffect(.regular.tint(DeckPaint.glassTint.opacity(primary ? 0.35 : 0.22))
                    .interactive(), in:shape)
            } else {
                label.background(reduceTransparency || opaquePreview ? DeckPaint.ground : DeckPaint.button, in:shape)
                    .overlay {
                        shape.strokeBorder(contrast == .increased ? DeckPaint.ink : DeckPaint.rule,
                                           style:StrokeStyle(lineWidth:1, dash:enabled ? [] : [3,2]))
                    }
            }
        }
        .overlay { shape.fill(DeckPaint.amber.opacity(enabled && configuration.isPressed ? 0.12 : 0)) }
        .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.985 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration:0.12), value:configuration.isPressed)
    }
}
