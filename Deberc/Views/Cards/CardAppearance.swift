import SwiftUI
import DebercKit

/// Рубашка карт.
enum CardBackStyle: String, CaseIterable, Codable, Identifiable {
    case burgundy, navy, emerald

    var id: String { rawValue }

    var title: String {
        switch self {
        case .burgundy: return "Бордо"
        case .navy: return "Синяя"
        case .emerald: return "Изумрудная"
        }
    }

    /// Градиент поля рубашки: сверху-слева → снизу-справа.
    var colors: (top: Color, bottom: Color) {
        switch self {
        case .burgundy:
            return (Theme.backLight, Theme.backDark)
        case .navy:
            return (Color(red: 0.10, green: 0.20, blue: 0.42), Color(red: 0.04, green: 0.09, blue: 0.22))
        case .emerald:
            return (Color(red: 0.05, green: 0.36, blue: 0.27), Color(red: 0.01, green: 0.17, blue: 0.12))
        }
    }
}

/// Общие для всех карт настройки вида. Задаются один раз выше по иерархии:
/// `.cardAppearance(fourColor: settings.fourColorDeck, largeIndex: settings.largeCards)`.
/// Параметры `CardView(fourColor:largeIndex:)` включают режим и без окружения (логическое «или»).
struct CardAppearance: Equatable {
    var fourColor = false
    var largeIndex = false
    var back: CardBackStyle = .burgundy
}

private struct CardAppearanceKey: EnvironmentKey {
    static let defaultValue = CardAppearance()
}

extension EnvironmentValues {
    var cardAppearance: CardAppearance {
        get { self[CardAppearanceKey.self] }
        set { self[CardAppearanceKey.self] = newValue }
    }
}

extension View {
    /// Вид всех карт внутри: четырёхцветная колода, крупные индексы, рубашка.
    func cardAppearance(fourColor: Bool = false, largeIndex: Bool = false,
                        back: CardBackStyle = .burgundy) -> some View {
        environment(\.cardAppearance, CardAppearance(fourColor: fourColor, largeIndex: largeIndex, back: back))
    }
}
