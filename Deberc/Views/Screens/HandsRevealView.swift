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
                    .accessibilityLabel("Обмен семёрки: \(seats.speaker(exchange.seat)) — \(Narrator.spokenCard(exchange.gave)) на \(Narrator.spokenCard(exchange.took))")
            }
            if deal.bottomCardVisible, let bottom = deal.bottomCard {
                Label("Низ колоды: \(TableText.short(bottom))", systemImage: "arrow.down.to.line")
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
                    .accessibilityLabel("Низ колоды: \(Narrator.spokenCard(bottom))")
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
        if let melds = meldText(seat) { text += ". \(Narrator.spoken(melds))" }
        return text
    }
}

/// «Взятки по порядку» после сдачи: кто зашёл, какие карты легли, кто взял и сколько в ней очков.
/// В игре видна только последняя взятка, а после байта хочется понять, где сдача ушла.
struct TricksReplayView: View {
    let deal: Deal
    let seats: SeatNames
    var tileHeight: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(deal.tricks.enumerated()), id: \.offset) { index, trick in
                row(trick, number: index + 1)
            }
        }
    }

    private func isLast(_ number: Int) -> Bool { number == deal.tricks.count }

    /// Очки за карты взятки, у последней — ещё 10.
    private func points(_ trick: Trick, number: Int) -> Int {
        guard let trump = deal.trump else { return 0 }
        return PlayRules.points(of: trick.cards, trump: trump) + (isLast(number) ? 10 : 0)
    }

    /// «взяли вы», «взяла Вера», «взял Саша».
    private func taker(_ seat: Int) -> String {
        if seat == seats.humanSeat { return "взяли вы" }
        let verb = seats.persona(seat)?.feminine == true ? "взяла" : "взял"
        return "\(verb) \(seats.speaker(seat))"
    }

    /// Строка взятки; не помещается в ширину (втроём на узком экране) — итог уходит под карты.
    private func row(_ trick: Trick, number: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                numberLabel(number)
                plays(trick)
                Spacer(minLength: 4)
                result(trick, number: number, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    numberLabel(number)
                    plays(trick)
                }
                result(trick, number: number, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(trick, number: number))
    }

    private func numberLabel(_ number: Int) -> some View {
        Text("\(number)")
            .font(.footnote.weight(.bold).monospacedDigit())
            .foregroundStyle(Theme.tableSecondaryText)
            .frame(minWidth: 18, alignment: .leading)
    }

    /// Карты в порядке хода (первая — заход), под каждой — кто её положил. Взявшая — в золотой рамке.
    private func plays(_ trick: Trick) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(trick.plays, id: \.self) { play in
                let won = play.seat == trick.winner
                VStack(spacing: 4) {
                    MiniTile(card: play.card, height: tileHeight)
                        .padding(3)
                        .overlay(
                            RoundedRectangle(cornerRadius: tileHeight * 0.22, style: .continuous)
                                .strokeBorder(Theme.gold, lineWidth: won ? 2.5 : 0))
                    Text(seats.column(play.seat))
                        .font(.caption2.weight(won ? .bold : .regular))
                        .foregroundStyle(won ? Theme.gold : Theme.tableSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: tileHeight * 1.7)
                }
            }
        }
    }

    private func result(_ trick: Trick, number: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(RuPlural.count(points(trick, number: number), "очко", "очка", "очков"))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.tableText)
            if let winner = trick.winner {
                Text(taker(winner))
                    .font(.caption)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
            if isLast(number) {
                Text("+10 за последнюю")
                    .font(.caption)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
        }
        .lineLimit(1)
    }

    /// «Взятка 3. Заход: Саша — туз червей, Вы — десятка червей. Взял Саша, 21 очко».
    private func spoken(_ trick: Trick, number: Int) -> String {
        let cards = trick.plays
            .map { "\(seats.speaker($0.seat)) — \(Narrator.spokenCard($0.card))" }
            .joined(separator: ", ")
        var text = "Взятка \(number). Заход: \(cards)."
        if let winner = trick.winner {
            let who = taker(winner)
            text += " \(who.prefix(1).uppercased() + who.dropFirst()), \(RuPlural.count(points(trick, number: number), "очко", "очка", "очков"))"
            if isLast(number) { text += " вместе с десятью за последнюю" }
        }
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
