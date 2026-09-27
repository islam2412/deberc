import SwiftUI
import DebercKit

extension Path {
    /// Путь из команд контура (`OutlineCommand`).
    init(outline: [OutlineCommand]) {
        self.init()
        for command in outline {
            switch command {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .quad(let p, let control): addQuadCurve(to: p, control: control)
            case .curve(let p, let c1, let c2): addCurve(to: p, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }
}

/// Векторная масть — та же, что на картах. Вписывается в квадрат по центру рамки.
struct SuitShape: Shape {
    let suit: Suit

    func path(in rect: CGRect) -> Path {
        Path(outline: SuitOutline.commands(
            suit, center: CGPoint(x: rect.midX, y: rect.midY), size: min(rect.width, rect.height)))
    }
}

/// Масть настоящим цветом на светлой плашке — читается на сукне при любом зрении
/// (красный на слоновой кости 5.6:1 против 2–3:1 у красного прямо на зелёном).
/// Для индикатора козыря, «низа», табло счёта, итогов сдачи.
struct SuitBadge: View {
    let suit: Suit
    var size: CGFloat = 24
    /// nil — брать из окружения (`cardAppearance.fourColor`).
    var fourColor: Bool? = nil

    @Environment(\.cardAppearance) private var appearance

    var body: some View {
        let color = Theme.suitColor(suit, fourColor: fourColor ?? appearance.fourColor)
        SuitShape(suit: suit)
            .fill(color)
            .frame(width: size * 0.66, height: size * 0.66)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.ivory))
            .overlay(Circle().strokeBorder(Theme.goldDeep.opacity(0.75), lineWidth: max(1, size * 0.05)))
            .accessibilityElement()
            .accessibilityLabel(suit.name)
    }
}
