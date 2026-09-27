import SwiftUI
import DebercKit

enum Theme {
    static let feltLight = Color(red: 0.11, green: 0.46, blue: 0.27)
    static let feltDark = Color(red: 0.03, green: 0.22, blue: 0.12)
    static let red = Color(red: 0.80, green: 0.07, blue: 0.14)
    static let black = Color(white: 0.08)
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.30)
    static let backDark = Color(red: 0.36, green: 0.04, blue: 0.09)
    static let backLight = Color(red: 0.58, green: 0.10, blue: 0.14)
}

extension Suit {
    /// Символ масти, который всегда рисуется текстом, а не эмодзи.
    var glyph: String { symbol + "\u{FE0E}" }

    var color: Color { isRed ? Theme.red : Theme.black }

    /// Цвет символа масти на тёмном фоне стола.
    var tableColor: Color { isRed ? Color(red: 1.0, green: 0.42, blue: 0.42) : .white }
}

struct FeltBackground: View {
    var body: some View {
        RadialGradient(
            colors: [Theme.feltLight, Theme.feltDark],
            center: .center, startRadius: 40, endRadius: 800)
            .ignoresSafeArea()
    }
}

/// Кнопка в стиле стола.
struct TableButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? Theme.gold : Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(prominent ? 0 : 0.35), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
