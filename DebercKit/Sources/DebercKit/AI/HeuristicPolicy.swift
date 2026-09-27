import Foundation

/// Простая, но разумная стратегия розыгрыша. Используется в моделированиях
/// и как «лёгкий» уровень. Смотрит только на свои карты и вышедшие карты.
enum HeuristicPolicy {

    static func choose(_ s: SimState, _ ctx: SimContext, bidder: Int) -> Int {
        let legal = s.legalMask(ctx)
        if legal.nonzeroBitCount == 1 { return legal.trailingZeroBitCount }
        return s.trickCards.isEmpty
            ? lead(s, ctx, legal: legal, bidder: bidder)
            : follow(s, ctx, legal: legal)
    }

    // MARK: - Вспомогательное

    /// Карты, которых нет ни у меня, ни на столе (у соперников или в колоде).
    private static func outstanding(_ s: SimState) -> UInt32 {
        ~(s.played | s.hands[s.turn])
    }

    private static func highestPower(in mask: UInt32, _ power: [Int]) -> Int {
        var best = 0
        for id in ids(in: mask) { best = max(best, power[id]) }
        return best
    }

    /// Самая старшая оставшаяся карта своей масти.
    private static func isMaster(_ id: Int, _ s: SimState, _ ctx: SimContext) -> Bool {
        let power = CardTables.power[ctx.trump]
        let rest = outstanding(s) & suitMask(id >> 3)
        return power[id] > highestPower(in: rest, power)
    }

    private static func cheapest(_ mask: UInt32, _ ctx: SimContext) -> Int {
        let pts = CardTables.points[ctx.trump]
        let power = CardTables.power[ctx.trump]
        var best = -1
        var bestKey = Int.max
        for id in ids(in: mask) {
            let trumpPenalty = id >> 3 == ctx.trump ? 100 : 0
            let key = trumpPenalty + pts[id] * 10 + power[id]
            if key < bestKey { bestKey = key; best = id }
        }
        return best
    }

    // MARK: - Заход

    private static func lead(_ s: SimState, _ ctx: SimContext, legal: UInt32, bidder: Int) -> Int {
        let me = s.turn
        let hand = s.hands[me]
        let pts = CardTables.points[ctx.trump]
        let power = CardTables.power[ctx.trump]
        let trumpBits = suitMask(ctx.trump)
        let myTrumps = hand & trumpBits
        let outTrumps = outstanding(s) & trumpBits

        // Играющий со старшим козырем выбивает козыри соперников.
        if me == bidder, myTrumps != 0, outTrumps != 0 {
            var top = -1
            for id in ids(in: myTrumps) where top < 0 || power[id] > power[top] { top = id }
            if top >= 0 && isMaster(top, s, ctx) { return top }
        }

        // Забираем очки старшими картами в некозырных мастях.
        let plain = hand & ~trumpBits
        var bestMaster = -1
        for id in ids(in: plain) where isMaster(id, s, ctx) && pts[id] >= 10 {
            if bestMaster < 0 || pts[id] > pts[bestMaster] { bestMaster = id }
        }
        if bestMaster >= 0 { return bestMaster }

        // Иначе — мелкая карта из некозырной масти, по возможности не из-под десятки.
        if plain != 0 {
            var best = -1
            var bestKey = Int.max
            for id in ids(in: plain) {
                let suitCards = hand & suitMask(id >> 3)
                let guardsTen = (suitCards & bit((id >> 3) * 8 + Rank.ten.index)) != 0
                    && (outstanding(s) & bit((id >> 3) * 8 + Rank.ace.index)) != 0
                let key = pts[id] * 10 + power[id] + (guardsTen ? 40 : 0) - suitCards.nonzeroBitCount
                if key < bestKey { bestKey = key; best = id }
            }
            return best
        }

        // Остались только козыри.
        var low = -1
        for id in ids(in: legal) where low < 0 || power[id] < power[low] { low = id }
        return low
    }

    // MARK: - Ответ на ход

    private static func follow(_ s: SimState, _ ctx: SimContext, legal: UInt32) -> Int {
        let pts = CardTables.points[ctx.trump]
        let power = CardTables.power[ctx.trump]
        let bestIndex = s.currentWinnerIndex(ctx)
        let best = s.trickCards[bestIndex]
        let led = s.trickCards[0] >> 3
        var trickPoints = 0
        for id in s.trickCards { trickPoints += pts[id] }

        var winners: UInt32 = 0
        for id in ids(in: legal) {
            let beats: Bool
            if id >> 3 == best >> 3 {
                beats = power[id] > power[best]
            } else {
                beats = id >> 3 == ctx.trump
            }
            if beats { winners |= bit(id) }
        }
        let losers = legal & ~winners
        let isLast = s.trickCards.count == s.n - 1

        if winners != 0 {
            let cheapestWinner = cheapest(winners, ctx)
            let isHighTrump = cheapestWinner >> 3 == ctx.trump && power[cheapestWinner] >= 6
            if isLast {
                if trickPoints == 0 && isHighTrump && losers != 0 {
                    let discard = cheapest(losers, ctx)
                    if pts[discard] == 0 { return discard }
                }
                // Берём десяткой, если туз уже вышел или его всё равно берём сейчас.
                return cheapestWinner
            }
            // Не последний: берём наверняка старшей картой, если во взятке есть что брать.
            var masterWinner = -1
            for id in ids(in: winners) where isMaster(id, s, ctx) {
                if masterWinner < 0 || power[id] < power[masterWinner] { masterWinner = id }
            }
            if led != ctx.trump && cheapestWinner >> 3 == ctx.trump {
                // Приходится бить козырем — бьём младшим.
                return cheapestWinner
            }
            if masterWinner >= 0 && (trickPoints + pts[masterWinner] >= 10) {
                return masterWinner
            }
            if losers != 0 { return cheapest(losers, ctx) }
            return cheapestWinner
        }
        return cheapest(legal, ctx)
    }
}
