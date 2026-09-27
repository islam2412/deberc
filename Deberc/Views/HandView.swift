import SwiftUI
import DebercKit

/// Карты человека веером внизу экрана.
struct HandView: View {
    let cards: [Card]
    let legal: Set<Card>
    let isActive: Bool
    let selected: Card?
    let cardWidth: CGFloat
    let onTap: (Card) -> Void

    private var cardHeight: CGFloat { cardWidth * 1.45 }
    private var lift: CGFloat { cardWidth * 0.22 }

    var body: some View {
        GeometryReader { geo in
            let count = cards.count
            let available = geo.size.width
            let spacing: CGFloat = count > 1
                ? min(cardWidth * 0.92, (available - cardWidth) / CGFloat(count - 1))
                : 0
            let total = cardWidth + spacing * CGFloat(max(count - 1, 0))
            let startX = max(0, (available - total) / 2)
            ZStack(alignment: .topLeading) {
                ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                    let isLegal = legal.contains(card)
                    let isSelected = card == selected
                    CardView(
                        card: card,
                        width: cardWidth,
                        dimmed: isActive && !isLegal,
                        highlighted: isSelected)
                        .offset(
                            x: startX + CGFloat(index) * spacing,
                            y: isSelected ? 0 : (isActive && isLegal ? lift * 0.45 : lift))
                        .onTapGesture { onTap(card) }
                        .zIndex(Double(index))
                }
            }
            .frame(width: available, height: geo.size.height, alignment: .topLeading)
        }
        .frame(height: cardHeight + lift)
        .animation(.easeOut(duration: 0.18), value: selected)
        .animation(.easeOut(duration: 0.18), value: cards)
    }
}
