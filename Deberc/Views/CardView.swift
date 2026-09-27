import SwiftUI
import DebercKit

/// Карта: лицом (если передана) или рубашкой.
struct CardView: View {
    let card: Card?
    let width: CGFloat
    var dimmed = false
    var highlighted = false

    private var height: CGFloat { width * 1.45 }
    private var corner: CGFloat { width * 0.1 }

    var body: some View {
        ZStack {
            if let card {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white)
                CardFace(card: card, width: width, height: height)
            } else {
                CardBack(width: width, corner: corner)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(highlighted ? Theme.gold : Color.black.opacity(0.3), lineWidth: highlighted ? 3 : 0.8)
        )
        .overlay {
            if dimmed {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.black.opacity(0.38))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: highlighted ? 6 : 2, x: 0, y: 1)
        .accessibilityElement()
        .accessibilityLabel(card.map { "\($0.rank.name) \($0.suit.name)" } ?? "карта рубашкой")
    }
}

private struct CardFace: View {
    let card: Card
    let width: CGFloat
    let height: CGFloat

    private var color: Color { card.suit.color }
    private var isFace: Bool { card.rank == .jack || card.rank == .queen || card.rank == .king }

    var body: some View {
        ZStack {
            corner
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, width * 0.07)
                .padding(.top, width * 0.05)

            center

            corner
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, width * 0.07)
                .padding(.bottom, width * 0.05)
        }
        .foregroundStyle(color)
    }

    private var corner: some View {
        VStack(spacing: -width * 0.05) {
            Text(card.rank.symbol)
                .font(.system(size: width * (card.rank == .ten ? 0.25 : 0.30), weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(card.suit.glyph)
                .font(.system(size: width * 0.24))
        }
        .frame(width: width * 0.34)
    }

    @ViewBuilder
    private var center: some View {
        if isFace {
            VStack(spacing: 0) {
                Text(card.rank.symbol)
                    .font(.system(size: width * 0.46, weight: .heavy, design: .serif))
                Text(card.suit.glyph)
                    .font(.system(size: width * 0.30))
            }
            .padding(.vertical, width * 0.06)
            .padding(.horizontal, width * 0.1)
            .background(
                RoundedRectangle(cornerRadius: width * 0.06)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
        } else {
            Text(card.suit.glyph)
                .font(.system(size: width * (card.rank == .ace ? 0.7 : 0.55)))
        }
    }
}

private struct CardBack: View {
    let width: CGFloat
    let corner: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(colors: [Theme.backLight, Theme.backDark],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner * 0.7, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: max(1, width * 0.025))
                    .padding(width * 0.08)
            )
            .overlay(
                Text("♦\u{FE0E}")
                    .font(.system(size: width * 0.34))
                    .foregroundStyle(Color.white.opacity(0.45))
            )
    }
}
