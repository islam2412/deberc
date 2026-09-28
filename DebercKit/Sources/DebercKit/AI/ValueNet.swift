import Foundation

// MARK: - Оценка позиции втроём
//
// Мастер втроём перебирает расклады, которые могли бы быть у соперников, и для каждого своего хода
// оценивает, чем кончится сдача. Раньше он для этого доигрывал сдачу по простым правилам; сеть
// оценки позиции даёт ожидаемый итог сдачи при игре сильных соперников. Её обучают на партиях
// Мастеров (`tools/belief`): позиция с открытыми картами → чем сдача на самом деле кончилась.
// Открытые карты здесь — это расклад, который бот сам придумал, чужих карт он не видит.

/// Признаки позиции для сети оценки. Все карты известны; места — относительно игрока `me`
/// (0 — он сам, 1 — следующий, 2 — следующий за ним).
public enum ValueFeatures {
    /// На карту: у кого (3), во взятке на столе, берёт ли сейчас взятку, вышла раньше, козырь,
    /// очки, старшинство.
    public static let perCard = 9
    public static let global = 33
    public static let count = 32 * perCard + global

    static func encode(_ s: SimState, _ ctx: SimContext, me: Int) -> [Float] {
        var x = [Float](repeating: 0, count: count)
        let n = s.n
        @inline(__always) func rel(_ seat: Int) -> Int { (seat - me + n) % n }
        for c in 0..<32 {
            let b = bit(c)
            let o = c * perCard
            for seat in 0..<n where s.hands[seat] & b != 0 { x[o + rel(seat)] = 1 }
            if s.trickMask & b != 0 { x[o + 3] = 1 }
            if s.trickCount > 0 && s.winCard == c { x[o + 4] = 1 }
            if s.played & b != 0 && s.trickMask & b == 0 { x[o + 5] = 1 }
            if c >> 3 == ctx.trump { x[o + 6] = 1 }
            x[o + 7] = Float(ctx.points[c]) / 20
            x[o + 8] = Float(ctx.power[c]) / 8
        }
        var o = 32 * perCard
        func slot(_ size: Int) -> Int {
            defer { o += size }
            return o
        }
        x[slot(3) + rel(ctx.bidder)] = 1
        x[slot(3) + rel(s.turn)] = 1
        x[slot(1)] = Float(s.trickCount) / 2
        let winner = slot(3)
        if s.trickCount > 0 { x[winner + rel(s.winSeat)] = 1 }
        x[slot(1)] = min(1, Float(s.trickPoints) / 60)
        x[slot(1)] = s.trickCount > 0 && s.led == ctx.trump ? 1 : 0
        let points = slot(3), tricks = slot(3)
        for seat in 0..<n {
            x[points + rel(seat)] = min(1, Float(s.cardPoints[seat]) / 200)
            x[tricks + rel(seat)] = Float(s.tricks[seat]) / 9
        }
        x[slot(1)] = Float(s.tricksLeft) / 9
        let meld = slot(4)
        if ctx.meldWinner >= 0 {
            x[meld + rel(ctx.meldWinner)] = 1
            x[meld + 3] = min(1, Float(ctx.meldPoints) / 100)
        }
        let bella = slot(3)
        if ctx.bellaSeat >= 0 { x[bella + rel(ctx.bellaSeat)] = 1 }
        // Следующий байт или «голый» для этого игрока — со штрафом.
        let bait = slot(3), naked = slot(3)
        let rules = ctx.rules
        for seat in 0..<n {
            if rules.baitPenaltyEvery > 0 && (ctx.baitCounts[seat] + 1) % rules.baitPenaltyEvery == 0 { x[bait + rel(seat)] = 1 }
            if rules.nakedPenaltyEvery > 0 && (ctx.nakedCounts[seat] + 1) % rules.nakedPenaltyEvery == 0 { x[naked + rel(seat)] = 1 }
        }
        x[slot(1)] = min(1, Float(ctx.pot) / 200)
        precondition(o == count, "ValueFeatures: \(o) != \(count)")
        for i in x.indices where x[i] != 0 && x[i] != 1 { x[i] = (x[i] * 255).rounded() / 255 }
        return x
    }

    /// Признаки текущей позиции партии с открытыми картами — для данных обучения (розыгрыш втроём).
    /// `me` — с чьего места считать. nil — сейчас не розыгрыш.
    public static func encode(match: Match, perspective me: Int) -> [Float]? {
        guard let deal = match.deal, deal.phase == .playing, let trump = deal.trump, let bidder = deal.bidder else { return nil }
        let s = fullState(match: match, deal: deal, trump: trump, bidder: bidder)
        return encode(s.state, s.ctx, me: me)
    }

    static func fullState(match: Match, deal: Deal, trump: Suit, bidder: Int) -> (state: SimState, ctx: SimContext) {
        let n = deal.playerCount
        var seen = bit(deal.openCard.id)
        for t in deal.tricks + [deal.currentTrick] { seen |= mask(of: t.cards) }
        if deal.bottomCardVisible, let b = deal.bottomCard { seen |= bit(b.id) }
        var cardPoints = [Int](repeating: 0, count: n), tricks = [Int](repeating: 0, count: n)
        for t in deal.tricks {
            guard let w = t.winner else { continue }
            cardPoints[w] += PlayRules.points(of: t.cards, trump: trump)
            tricks[w] += 1
        }
        let decl = deal.declarations
        let meldWinner = decl?.meldWinner ?? -1
        let ctx = SimContext(rules: deal.rules, playerCount: n, trump: trump.rawValue, bidder: bidder,
                             priority: Deal.leadOrder(dealer: deal.dealer, bidder: bidder, playerCount: n, rules: deal.rules),
                             meldWinner: meldWinner,
                             meldPoints: meldWinner >= 0 ? decl!.meldPoints(for: meldWinner, rules: deal.rules) : 0,
                             bellaSeat: decl?.bellaSeat ?? -1, pot: match.pot,
                             baitCounts: match.baitCounts, nakedCounts: match.nakedCounts)
        let state = SimState(hands: deal.hands.map { mask(of: $0) }, turn: deal.turn, cardPoints: cardPoints, tricks: tricks,
                             played: seen, tricksLeft: deal.hands[deal.turn].count,
                             trick: deal.currentTrick.plays.map { (seat: $0.seat, card: $0.card.id) }, ctx: ctx)
        return (state, ctx)
    }

    /// Правила, при которых сеть обучалась: подсчёт очков и штрафы как в домашних правилах.
    /// При других — оценка по сети неверна, и бот доигрывает сдачу, как раньше.
    static func supports(_ r: RuleSet) -> Bool {
        let h = RuleSet.house
        return r.combosNeedTrick == h.combosNeedTrick && r.baitTransfer == h.baitTransfer
            && r.baitRecipient == h.baitRecipient && r.bidderMustBeat == h.bidderMustBeat && r.tieRule == h.tieRule
            && r.baitPenaltyEvery == h.baitPenaltyEvery && r.baitPenaltyPoints == h.baitPenaltyPoints
            && r.hangingCountsAsBait == h.hangingCountsAsBait && r.nakedPenaltyEvery == h.nakedPenaltyEvery
            && r.nakedPenaltyPoints == h.nakedPenaltyPoints && r.terzPoints == h.terzPoints
            && r.fiftyPoints == h.fiftyPoints && r.bellaPoints == h.bellaPoints && r.hundredForFive == h.hundredForFive
            && r.mustTrump == h.mustTrump && r.overtrump == h.overtrump
    }
}

/// Сеть оценки позиции втроём (веса — `value3.bin`, обучает `tools/belief/train_value.py`):
/// ожидаемый итог сдачи (полезность, как в `SimState.utility`) для каждого из трёх мест.
final class ValueNet: @unchecked Sendable {
    private let net: DenseNet
    /// Во сколько раз уменьшен итог при обучении.
    static let scale: Float = 100

    static let shared: ValueNet? = DenseNet.resource("value3").flatMap(ValueNet.init(net:))

    init?(net: DenseNet) {
        guard net.inputs == ValueFeatures.count, net.outputs == 3 else { return nil }
        self.net = net
    }

    /// Ожидаемая полезность для `me` в позиции `s`.
    func utility(_ s: SimState, _ ctx: SimContext, me: Int) -> Double {
        Double(net.forward(ValueFeatures.encode(s, ctx, me: me))[0] * ValueNet.scale)
    }
}
