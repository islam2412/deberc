import Foundation

/// Простая, но разумная стратегия розыгрыша. Используется в моделированиях
/// (доигрывание сдачи в случайных мирах) и как основа игры «Новичка».
/// Смотрит только на свои карты и на вышедшие карты (`SimState.played`).
enum HeuristicPolicy {

    static func choose(_ s: SimState, _ ctx: SimContext) -> Int {
        let legal = s.legalMask(ctx)
        if legal & (legal &- 1) == 0 { return legal.trailingZeroBitCount }
        return s.trickCount == 0 ? lead(s, ctx, legal: legal) : follow(s, ctx, legal: legal)
    }

    // MARK: - Вспомогательное

    /// Карты, которых нет ни у меня, ни на столе (у соперников или в колоде).
    @inline(__always)
    static func outstanding(_ s: SimState) -> UInt32 {
        ~(s.played | s.hands[s.turn])
    }

    @inline(__always)
    static func highestPower(in mask: UInt32, _ ctx: SimContext) -> Int {
        var best = 0
        var m = mask
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m &- 1
            if ctx.power[id] > best { best = ctx.power[id] }
        }
        return best
    }

    /// Самая старшая оставшаяся карта своей масти.
    @inline(__always)
    static func isMaster(_ id: Int, _ s: SimState, _ ctx: SimContext) -> Bool {
        ctx.power[id] > highestPower(in: outstanding(s) & suitMask(id >> 3), ctx)
    }

    /// Самая дешёвая карта: без очков, младшая, козыри — в последнюю очередь.
    @inline(__always)
    static func cheapest(_ mask: UInt32, _ ctx: SimContext) -> Int {
        let key = CardTables.naturalKey[ctx.trump]
        var best = -1
        var bestKey = Int.max
        var m = mask
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m &- 1
            if key[id] < bestKey { bestKey = key[id]; best = id }
        }
        return best
    }

    // MARK: - Заход

    static func lead(_ s: SimState, _ ctx: SimContext, legal: UInt32) -> Int {
        let me = s.turn
        let hand = s.hands[me]
        let pts = ctx.points
        let power = ctx.power
        let myTrumps = hand & ctx.trumpBits
        let out = outstanding(s)
        let outTrumps = out & ctx.trumpBits

        // Играющий со старшим козырем выбивает козыри соперников.
        if me == ctx.bidder, myTrumps != 0, outTrumps != 0 {
            var top = -1
            var m = myTrumps
            while m != 0 {
                let id = m.trailingZeroBitCount
                m &= m &- 1
                if top < 0 || power[id] > power[top] { top = id }
            }
            if top >= 0 && isMaster(top, s, ctx) { return top }
        }

        // Забираем очки старшими картами в некозырных мастях.
        let plain = hand & ~ctx.trumpBits
        var bestMaster = -1
        var m = plain
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m &- 1
            if pts[id] >= 10 && isMaster(id, s, ctx) && (bestMaster < 0 || pts[id] > pts[bestMaster]) {
                bestMaster = id
            }
        }
        if bestMaster >= 0 { return bestMaster }

        // Иначе — мелкая карта из некозырной масти, по возможности не из-под десятки.
        if plain != 0 {
            var best = -1
            var bestKey = Int.max
            m = plain
            while m != 0 {
                let id = m.trailingZeroBitCount
                m &= m &- 1
                let suit = id >> 3
                let suitCards = hand & suitMask(suit)
                let guardsTen = (suitCards & bit(suit * 8 + Rank.ten.index)) != 0
                    && (out & bit(suit * 8 + Rank.ace.index)) != 0
                let key = pts[id] * 10 + power[id] + (guardsTen ? 40 : 0) - suitCards.nonzeroBitCount
                if key < bestKey { bestKey = key; best = id }
            }
            return best
        }

        // Остались только козыри.
        var low = -1
        m = legal
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m &- 1
            if low < 0 || power[id] < power[low] { low = id }
        }
        return low
    }

    // MARK: - Ответ на ход

    static func follow(_ s: SimState, _ ctx: SimContext, legal: UInt32) -> Int {
        let pts = ctx.points
        let power = ctx.power
        let trickPoints = s.trickPoints

        var winners: UInt32 = 0
        var m = legal
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m &- 1
            if s.beatsTrick(id, ctx) { winners |= bit(id) }
        }
        let losers = legal & ~winners
        let isLast = s.trickCount == s.n - 1

        if winners != 0 {
            let cheapestWinner = cheapest(winners, ctx)
            let isHighTrump = cheapestWinner >> 3 == ctx.trump && power[cheapestWinner] >= 6
            if isLast {
                if trickPoints == 0 && isHighTrump && losers != 0 {
                    let discard = cheapest(losers, ctx)
                    if pts[discard] == 0 { return discard }
                }
                return cheapestWinner
            }
            // Не последний: берём наверняка старшей картой, если во взятке есть что брать.
            var masterWinner = -1
            m = winners
            while m != 0 {
                let id = m.trailingZeroBitCount
                m &= m &- 1
                if isMaster(id, s, ctx) && (masterWinner < 0 || power[id] < power[masterWinner]) {
                    masterWinner = id
                }
            }
            if s.led != ctx.trump && cheapestWinner >> 3 == ctx.trump {
                // Приходится бить козырем — бьём младшим.
                return cheapestWinner
            }
            if masterWinner >= 0 && trickPoints + pts[masterWinner] >= 10 {
                return masterWinner
            }
            if losers != 0 { return cheapest(losers, ctx) }
            return cheapestWinner
        }
        return cheapest(legal, ctx)
    }
}
