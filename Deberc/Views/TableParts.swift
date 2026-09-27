import SwiftUI
import DebercKit

/// Табло счёта одного игрока.
struct ScoreChip: View {
    let name: String
    let score: Int
    let isDealer: Bool
    let isBidder: Bool
    let trump: Suit?
    let isActive: Bool

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if isDealer {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.gold)
                        .accessibilityLabel("сдаёт")
                }
            }
            HStack(spacing: 4) {
                Text("\(score)")
                    .font(.headline.monospacedDigit())
                if isBidder, let trump {
                    Text(trump.glyph)
                        .font(.headline)
                        .foregroundStyle(trump.tableColor)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(isActive ? 0.45 : 0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Theme.gold : Color.clear, lineWidth: 2)
        )
    }
}

/// Реплика игрока при торговле.
struct Bubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white))
            .shadow(radius: 2)
            .transition(.scale.combined(with: .opacity))
    }
}

/// Соперник: имя, рубашки карт, реплика.
struct OpponentView: View {
    let name: String
    let cardCount: Int
    let bubble: String?
    let isThinking: Bool
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack(spacing: -cardWidth * 0.62) {
                    ForEach(0..<cardCount, id: \.self) { _ in
                        CardView(card: nil, width: cardWidth)
                    }
                }
                .frame(height: cardWidth * 1.45)
                if let bubble {
                    Bubble(text: bubble)
                        .offset(y: cardWidth * 0.55)
                }
            }
            HStack(spacing: 6) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if isThinking {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
            }
            .frame(height: 20)
        }
        .animation(.easeInOut(duration: 0.2), value: bubble)
    }
}

/// Всплывающее сообщение.
struct BannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.gold.opacity(0.6), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Колода с открытой картой под ней и нижней картой.
struct DeckView: View {
    let openCard: Card
    let bottomCard: Card?
    let showsStock: Bool
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                CardView(card: openCard, width: cardWidth)
                    .rotationEffect(.degrees(90))
                    .offset(x: cardWidth * 0.35)
                if showsStock {
                    CardView(card: nil, width: cardWidth)
                        .offset(x: -cardWidth * 0.2)
                }
            }
            .frame(width: cardWidth * 2.1, height: cardWidth * 1.45)
            if let bottomCard {
                HStack(spacing: 3) {
                    Text("низ:")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(bottomCard.rank.symbol + bottomCard.suit.glyph)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(bottomCard.suit.tableColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.3)))
            }
        }
    }
}

/// Карты текущей взятки в центре стола.
struct TrickView: View {
    let plays: [PlayedCard]
    let winner: Int?
    let playerCount: Int
    let humanSeat: Int
    let cardWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let size = min(cardWidth, h * 0.42)
            ZStack {
                ForEach(plays, id: \.card) { play in
                    let position = relativePosition(play.seat)
                    CardView(card: play.card, width: size, highlighted: winner == play.seat)
                        .rotationEffect(.degrees(position.angle))
                        .offset(x: position.x * w, y: position.y * h)
                        .transition(.asymmetric(
                            insertion: .offset(x: position.x * w * 1.6, y: position.y * h * 2.2).combined(with: .opacity),
                            removal: .opacity))
                }
            }
            .frame(width: w, height: h)
        }
    }

    /// Смещение карты игрока относительно центра стола (доли ширины и высоты).
    private func relativePosition(_ seat: Int) -> (x: CGFloat, y: CGFloat, angle: Double) {
        let relative = (seat - humanSeat + playerCount) % playerCount
        if playerCount == 2 {
            return relative == 0 ? (0, 0.2, -3) : (0, -0.2, 4)
        }
        switch relative {
        case 0: return (0, 0.2, -2)
        case 1: return (-0.2, -0.1, -8)
        default: return (0.2, -0.1, 8)
        }
    }
}
