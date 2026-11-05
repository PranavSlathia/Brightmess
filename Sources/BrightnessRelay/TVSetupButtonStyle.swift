import SwiftUI

/// Popover-safe chrome. Automatic macOS button styles can choose a dark
/// control-text colour even though this fixed forest band requires cream.
struct TVSetupButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = 5
        let fill = enabled ? (configuration.isPressed ? 0.20 : 0.10) : 0.035
        configuration.label
            .font(.system(size:12,weight:.semibold))
            .foregroundStyle(DeckPaint.cream.opacity(enabled ? 1 : 0.72))
            .padding(.horizontal,9).padding(.vertical,5)
            .background {
                RoundedRectangle(cornerRadius:radius).fill(DeckPaint.forest)
                RoundedRectangle(cornerRadius:radius).fill(DeckPaint.cream.opacity(fill))
            }
            .overlay {
                RoundedRectangle(cornerRadius:radius).strokeBorder(
                    focused && enabled ? DeckPaint.leaf : DeckPaint.cream.opacity(enabled ? 0.55 : 0.24),
                    lineWidth: focused && enabled ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius:radius))
    }
}
