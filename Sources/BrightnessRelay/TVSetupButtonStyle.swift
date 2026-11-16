import SwiftUI

/// Explicit adaptive ink and a dashed disabled outline keep small controls
/// readable and distinguishable over both ends of the solar gradient.
struct SolarUtilityButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = 7
        configuration.label
            .font(.system(size:12,weight:.semibold))
            .foregroundStyle(enabled ? DeckPaint.ink : DeckPaint.muted)
            .padding(.horizontal,9).padding(.vertical,5)
            .background {
                RoundedRectangle(cornerRadius:radius).fill(DeckPaint.button)
                if enabled && configuration.isPressed {
                    RoundedRectangle(cornerRadius:radius).fill(DeckPaint.ink.opacity(0.10))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius:radius).strokeBorder(
                    focused && enabled ? DeckPaint.ink : DeckPaint.rule,
                    style: StrokeStyle(lineWidth: focused && enabled ? 2 : 1,
                                       dash: enabled ? [] : [3,2]))
            }
            .contentShape(RoundedRectangle(cornerRadius:radius))
    }
}
