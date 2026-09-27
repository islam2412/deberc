import SwiftUI
import DebercKit

/// Карта лицом (если передана) или рубашкой. Пропорции 1:1.45; работает от 28 до 180 pt ширины.
/// Уже 46 pt рисуется упрощённо: индекс и крупная масть.
///
/// - `dimmed` — карту сейчас нельзя сыграть: лёгкое затемнение в тон сукна.
/// - `highlighted` — выбранная карта или карта, взявшая взятку: золотая обводка и тень выше.
/// - `playable` — допустимая карта в ваш ход: мягкое золотое свечение снаружи.
/// - `isTrump` — золотая звезда под угловым индексом; VoiceOver добавляет «козырь».
/// - `fourColor`, `largeIndex` — включают режим и сами по себе, и через `.cardAppearance(...)`.
/// - `showsBottomIndex` — нижний перевёрнутый индекс; в веере руки его стоит скрывать
///   у всех карт, кроме правой: он выглядывает из-под соседней карты обрывками.
struct CardView: View {
    let card: Card?
    let width: CGFloat
    var dimmed: Bool
    var highlighted: Bool
    var isTrump: Bool
    var fourColor: Bool
    var largeIndex: Bool
    var showsBottomIndex: Bool
    var playable: Bool

    @Environment(\.cardAppearance) private var appearance
    @Environment(\.colorSchemeContrast) private var contrast

    init(card: Card?, width: CGFloat, dimmed: Bool = false, highlighted: Bool = false,
         isTrump: Bool = false, fourColor: Bool = false, largeIndex: Bool = false,
         showsBottomIndex: Bool = true, playable: Bool = false) {
        self.card = card
        self.width = width
        self.dimmed = dimmed
        self.highlighted = highlighted
        self.isTrump = isTrump
        self.fourColor = fourColor
        self.largeIndex = largeIndex
        self.showsBottomIndex = showsBottomIndex
        self.playable = playable
    }

    /// Отношение высоты карты к ширине.
    /// `nonisolated`: нужны геометрии стола и текстам вне главного актора (View — @MainActor).
    nonisolated static let aspectRatio: CGFloat = CardMetrics.aspectRatio

    /// Высота карты заданной ширины.
    nonisolated static func height(forWidth width: CGFloat) -> CGFloat { width * aspectRatio }

    /// «дама червей», «десятка бубен», «туз пик».
    nonisolated static func spokenName(_ card: Card) -> String {
        let suit: String
        switch card.suit {
        case .spades: suit = "пик"
        case .clubs: suit = "треф"
        case .diamonds: suit = "бубен"
        case .hearts: suit = "червей"
        }
        return "\(card.rank.name) \(suit)"
    }

    var body: some View {
        let metrics = CardMetrics(
            width: width,
            largeIndex: largeIndex || appearance.largeIndex,
            showsBottomIndex: showsBottomIndex,
            isTrump: isTrump && card != nil)
        let w = metrics.width
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        let increased = contrast == .increased

        ZStack {
            // Основа с тенями. Тени только у одной фигуры — дёшево даже при 30 картах на столе.
            shape
                .fill(LinearGradient(colors: [Theme.ivory, Theme.ivoryShade], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.black.opacity(0.30), radius: max(0.5, w * 0.008), x: 0, y: max(0.5, w * 0.01))
                .shadow(color: ambientShadowColor, radius: ambientShadowRadius(w),
                        x: 0, y: playable && !highlighted ? 0 : ambientShadowOffset(w))

            if let card {
                CardFaceCanvas(card: card, metrics: metrics, fourColor: fourColor || appearance.fourColor)
                    .equatable()
            } else {
                CardBackCanvas(metrics: metrics, style: appearance.back)
                    .equatable()
            }

            if dimmed {
                shape.fill(Theme.dimTint.opacity(increased ? 0.42 : 0.24))
            }

            if highlighted {
                shape.strokeBorder(Theme.gold, lineWidth: max(2, w * 0.035))
            } else if playable {
                shape.strokeBorder(Theme.gold.opacity(0.9), lineWidth: max(1.5, w * 0.02))
            } else {
                shape.strokeBorder(Color.black.opacity(increased ? 0.5 : 0.22), lineWidth: metrics.hairline)
            }
        }
        .frame(width: w, height: metrics.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var ambientShadowColor: Color {
        if highlighted { return Color.black.opacity(0.32) }
        if playable { return Theme.gold.opacity(0.6) }
        return Color.black.opacity(0.2)
    }

    private func ambientShadowRadius(_ w: CGFloat) -> CGFloat {
        if w < CardMetrics.compactWidth { return max(1, w * 0.04) }
        if highlighted { return w * 0.1 }
        if playable { return w * 0.07 }
        return w * 0.05
    }

    private func ambientShadowOffset(_ w: CGFloat) -> CGFloat {
        highlighted ? w * 0.08 : w * 0.035
    }

    private var accessibilityText: String {
        guard let card else { return "карта рубашкой" }
        return isTrump ? "\(CardView.spokenName(card)), козырь" : CardView.spokenName(card)
    }
}

#if DEBUG
struct CardView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Suit.allCases, id: \.self) { suit in
                    HStack(spacing: 8) {
                        ForEach(Rank.allCases, id: \.self) { rank in
                            CardView(card: Card(rank, suit), width: 85, isTrump: suit == .hearts)
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach([28, 36, 46, 64, 120] as [CGFloat], id: \.self) { w in
                        CardView(card: Card(.queen, .hearts), width: w)
                    }
                    CardView(card: nil, width: 64)
                }
                HStack(spacing: 8) {
                    CardView(card: Card(.ten, .diamonds), width: 85, fourColor: true, largeIndex: true)
                    CardView(card: Card(.nine, .clubs), width: 85, dimmed: true)
                    CardView(card: Card(.jack, .spades), width: 85, playable: true)
                    CardView(card: Card(.ace, .hearts), width: 85, highlighted: true)
                }
                HStack(spacing: 12) {
                    Button("Пас") {}.buttonStyle(TableButtonStyle())
                    Button("Беру") {}.buttonStyle(TableButtonStyle(prominent: true))
                    SuitBadge(suit: .hearts, size: 32)
                }
            }
            .padding()
        }
        .background(FeltBackground())
    }
}
#endif
