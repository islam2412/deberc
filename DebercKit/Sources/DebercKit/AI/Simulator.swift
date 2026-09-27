import Foundation

/// Быстрые таблицы очков и старшинства по номеру карты (0…31) для каждой козырной масти.
enum CardTables {
    static let points: [[Int]] = (0..<4).map { t in
        (0..<32).map { Card(id: $0).points(trump: Suit(rawValue: t)!) }
    }
    static let power: [[Int]] = (0..<4).map { t in
        (0..<32).map { Card(id: $0).power(trump: Suit(rawValue: t)!) }
    }
}

@inline(__always) func suitMask(_ suit: Int) -> UInt32 { UInt32(0xFF) << UInt32(suit * 8) }
@inline(__always) func bit(_ id: Int) -> UInt32 { UInt32(1) << UInt32(id) }

func mask(of cards: [Card]) -> UInt32 {
    cards.reduce(0) { $0 | bit($1.id) }
}

func ids(in mask: UInt32) -> [Int] {
    var result: [Int] = []
    result.reserveCapacity(mask.nonzeroBitCount)
    var m = mask
    while m != 0 {
        let i = m.trailingZeroBitCount
        result.append(i)
        m &= m - 1
    }
    return result
}

/// Сведения о сдаче, от которых зависит итоговый подсчёт.
struct SimContext {
    let rules: RuleSet
    let playerCount: Int
    let trump: Int
    let bidder: Int
    let priority: [Int]
    /// Объявления: у победителя — его последовательности, бэла — у кого она в этом мире.
    let declarations: Declarations
    let pot: Int
    let baitCounts: [Int]
    let nakedCounts: [Int]
}

/// Компактное состояние розыгрыша для моделирования.
struct SimState {
    var hands: [UInt32]
    var trickCards: [Int] = []
    var trickSeats: [Int] = []
    var turn: Int
    var cardPoints: [Int]
    var tricks: [Int]
    var played: UInt32
    var tricksLeft: Int
    var finished = false

    var n: Int { hands.count }

    /// Допустимые карты для игрока, чья очередь.
    func legalMask(_ ctx: SimContext) -> UInt32 {
        let hand = hands[turn]
        guard let first = trickCards.first else { return hand }
        let led = first >> 3
        let trumpBits = suitMask(ctx.trump)
        let power = CardTables.power[ctx.trump]
        var highestTrump = 0
        for id in trickCards where id >> 3 == ctx.trump { highestTrump = max(highestTrump, power[id]) }

        let same = hand & suitMask(led)
        if same != 0 {
            if led == ctx.trump, ctx.rules.overtrump != .never, highestTrump > 0 {
                var higher: UInt32 = 0
                for id in ids(in: same) where power[id] > highestTrump { higher |= bit(id) }
                if higher != 0 { return higher }
            }
            return same
        }
        let trumps = hand & trumpBits
        if ctx.rules.mustTrump && trumps != 0 {
            if ctx.rules.overtrump == .always, highestTrump > 0 {
                var higher: UInt32 = 0
                for id in ids(in: trumps) where power[id] > highestTrump { higher |= bit(id) }
                if higher != 0 { return higher }
            }
            return trumps
        }
        return hand
    }

    /// Индекс (во взятке) карты, которая сейчас берёт.
    func currentWinnerIndex(_ ctx: SimContext) -> Int {
        guard trickCards.count > 1 else { return 0 }
        let power = CardTables.power[ctx.trump]
        var best = 0
        for i in 1..<trickCards.count {
            let a = trickCards[i], b = trickCards[best]
            if a >> 3 == b >> 3 {
                if power[a] > power[b] { best = i }
            } else if a >> 3 == ctx.trump {
                best = i
            }
        }
        return best
    }

    mutating func play(_ id: Int, _ ctx: SimContext) {
        hands[turn] &= ~bit(id)
        played |= bit(id)
        trickCards.append(id)
        trickSeats.append(turn)
        if trickCards.count == n {
            let w = trickSeats[currentWinnerIndex(ctx)]
            let pts = CardTables.points[ctx.trump]
            var sum = 0
            for c in trickCards { sum += pts[c] }
            cardPoints[w] += sum
            tricks[w] += 1
            tricksLeft -= 1
            trickCards.removeAll(keepingCapacity: true)
            trickSeats.removeAll(keepingCapacity: true)
            turn = w
            if tricksLeft == 0 {
                cardPoints[w] += 10
                finished = true
            }
        } else {
            turn = (turn + 1) % n
        }
    }

    /// Итог сдачи: изменение счёта каждого игрока (с байтом, висячими очками и штрафами).
    func settlementChange(_ ctx: SimContext) -> [Int] {
        let s = Scoring.settle(
            cardPoints: cardPoints, tricksTaken: tricks, declarations: ctx.declarations,
            bidder: ctx.bidder, priority: ctx.priority, rules: ctx.rules, pot: ctx.pot,
            baitCounts: ctx.baitCounts, nakedCounts: ctx.nakedCounts)
        return s.change
    }

    /// Полезность для каждого игрока: своё изменение счёта минус среднее у соперников.
    func utilities(_ ctx: SimContext) -> [Double] {
        let change = settlementChange(ctx)
        let total = change.reduce(0, +)
        let others = Double(n - 1)
        return change.map { Double($0) - Double(total - $0) / others }
    }
}
