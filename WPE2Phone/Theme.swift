import SwiftUI

/// Visual language: deep-space dark with an electric cyan→violet accent,
/// echoing Wallpaper Engine's desktop client.
enum Theme {
    static let accentA = Color(red: 0.30, green: 0.78, blue: 1.00)
    static let accentB = Color(red: 0.55, green: 0.42, blue: 1.00)
    static let background = Color(red: 0.05, green: 0.06, blue: 0.10)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentA, accentB],
                       startPoint: .leading, endPoint: .trailing)
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, Color(red: 0.09, green: 0.07, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            }
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

/// Primary call-to-action button used across the flow.
struct AccentButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accentGradient.opacity(isEnabled ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Step number badge for the onboarding cards.
struct StepBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Theme.accentGradient, in: Circle())
            .accessibilityHidden(true)
    }
}
