import SwiftUI
import DebercKit

/// «Карты всех игроков» после сдачи: у кого что было на руках к первому ходу
/// (после прикупа и обмена семёрки), кто сколько взял и чьи комбинации записаны.
/// Так видно, что компьютер играл своими картами, и сдачу можно разобрать.
struct HandsRevealView: View {
    let deal: Deal
    let score: DealScore
    let seats: SeatNames
    var cardWidth: CGFloat = 40

    private var order: [Int] {
        // Сначала вы, затем соперники по кругу.
        (0 ..< deal.playerCount).map { (seats.humanSeat + $0) % deal.playerCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(order, id: \.self) { seat in
                seatBlock(seat)
            }
            if let exchange = deal.sevenExchange {
                Label("Обмен семёрки: \(seats.speaker(exchange.seat)) — \(TableText.short(exchange.gave)) на \(TableText.short(exchange.took))",
                      systemImage: "arrow.left.arrow.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
            if deal.bottomCardVisible, let bottom = deal.bottomCard {
                Label("Низ колоды: \(TableText.short(bottom))", systemImage: "arrow.down.to.line")
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
            Text("Компьютер видит только свои карты и открытые на столе — здесь видно, что было у каждого.")
                .font(.footnote)
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func seatBlock(_ seat: Int) -> some View {
        let hands = deal.initialHands
        let cards = hands.indices.contains(seat) ? hands[seat].sortedForDisplay(trump: deal.trump) : []
        let tricks = score.tricksTaken.indices.contains(seat) ? score.tricksTaken[seat] : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(seats.column(seat))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.tableText)
                if deal.bidder == seat {
                    ScoreMarkBadge(text: "играет", color: Theme.gold)
                }
                Spacer(minLength: 4)
                Text(RuPlural.count(tricks, "взятка", "взятки", "взяток"))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.tableSecondaryText)
            }
            CardStrip(cards: cards, trump: deal.trump, width: cardWidth)
            if let melds = meldText(seat) {
                Text(melds)
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(seat, cards: cards, tricks: tricks))
    }

    /// Комбинации места и их судьба: записаны, не в зачёт или младше.
    private func meldText(_ seat: Int) -> String? {
        guard let decl = deal.declarations, decl.melds.indices.contains(seat) else { return nil }
        var parts: [String] = []
        let melds = decl.melds[seat]
        if !melds.isEmpty {
            let list = melds.map { Narrator.meldTitle($0, rules: deal.rules) }.joined(separator: ", ")
            if decl.meldWinner == seat {
                let written = score.meldPoints.indices.contains(seat) && score.meldPoints[seat] > 0
                parts.append(written ? "\(list) — записано" : "\(list) — не в зачёт")
            } else {
                parts.append("\(list) — младше, не пишется")
            }
        }
        if decl.bellaSeat == seat {
            let written = score.bellaPoints.indices.contains(seat) && score.bellaPoints[seat] > 0
            parts.append(written ? "бэла — записана" : "бэла — не в зачёт")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func spoken(_ seat: Int, cards: [Card], tricks: Int) -> String {
        let list = cards.map { CardView.spokenName($0) }.joined(separator: ", ")
        var text = "\(seats.column(seat)): \(list). \(RuPlural.count(tricks, "взятка", "взятки", "взяток"))"
        if let melds = meldText(seat) { text += ". \(melds)" }
        return text
    }
}

/// Карты рядом внахлёст (для итогов сдачи).
struct CardStrip: View {
    let cards: [Card]
    let trump: Suit?
    var width: CGFloat = 40

    var body: some View {
        HStack(spacing: -width * 0.36) {
            ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                CardView(card: card, width: width, isTrump: card.suit == trump,
                         showsBottomIndex: index == cards.count - 1)
            }
        }
        .accessibilityHidden(true)
    }
}
