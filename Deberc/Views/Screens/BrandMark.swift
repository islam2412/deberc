import SwiftUI
import DebercKit

/// Заставка меню и приветствия: веер «рубашка и валет пик», как на иконке, и название.
/// Рубашка — та, что игрок выбрал в Настройках → Вид (из окружения, `cardAppearance`).
struct BrandMark: View {
    /// Крупный вариант (iPad).
    var large = false
    /// Поменьше — для приветствия и невысоких экранов.
    var compact = false
    /// Веер карт над названием. На невысоком экране меню его убирает, чтобы плитки влезли без прокрутки.
    var showsFan = true
    /// Подзаголовок «по домашним правилам».
    var showsTagline = true

    private var cardWidth: CGFloat {
        if compact { return large ? 78 : 54 }
        return large ? 100 : 66
    }

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            if showsFan {
                fan
            }
            Text("Деберц")
                .font(.system(size: titleSize, weight: .bold, design: .serif))
                .foregroundStyle(Theme.tableText)
                .shadow(color: Color.black.opacity(0.45), radius: 4, x: 0, y: 2)
                .accessibilityAddTraits(.isHeader)
            if showsTagline {
                Text(RulesText.housePhrase)
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    private var titleSize: CGFloat {
        if compact { return large ? 64 : 44 }
        return large ? 88 : 58
    }

    private var fan: some View {
        let w = cardWidth
        let h = CardView.height(forWidth: w)
        return ZStack {
            CardView(card: nil, width: w)
                .rotationEffect(.degrees(-13), anchor: .bottom)
                .offset(x: -w * 0.3)
            CardView(card: Card(.jack, .spades), width: w)
                .rotationEffect(.degrees(7), anchor: .bottom)
                .offset(x: w * 0.3, y: -h * 0.02)
        }
        .frame(width: w * 2.1, height: h * 1.08)
        .accessibilityHidden(true)
    }
}
