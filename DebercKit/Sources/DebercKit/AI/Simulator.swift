import Foundation

// Быстрое моделирование розыгрыша для ботов.
//
// Всё здесь работает на масках карт (UInt32, бит = номер карты 0…31) и SIMD-векторах,
// чтобы копирование состояния не выделяло память: боты разыгрывают десятки тысяч
// сдач на одно решение.

/// Быстрые таблицы очков и старшинства по номеру карты (0…31) для каждой козырной масти.
enum CardTables {
    static let points: [[Int]] = (0..<4).map { t in
        (0..<32).map { Card(id: $0).points(trump: Suit(rawValue: t)!) }
    }
    static let power: [[Int]] = (0..<4).map { t in
        (0..<32).map { Card(id: $0).power(trump: Suit(rawValue: t)!) }
    }
    /// Козыри старше заданного старшинства: `trumpAbove[trump][p]` — маска козырей с power > p.
    static let trumpAbove: [[UInt32]] = (0..<4).map { t in
        (0...8).map { p in
            var m: UInt32 = 0
            for id in 0..<32 where id >> 3 == t && power[t][id] > p { m |= bit(id) }
            return m
        }
    }
    /// Порядок перебора карт для поиска: сначала козыри, внутри масти — от старших к младшим.
    static let searchOrder: [[Int]] = (0..<4).map { t in
        (0..<32).sorted { a, b in
            let ka = (a >> 3 == t ? 16 : 0) + power[t][a]
            let kb = (b >> 3 == t ? 16 : 0) + power[t][b]
            return ka != kb ? ka > kb : a < b
        }
    }
    /// «Естественный» порядок сброса: чем меньше ключ, тем дешевле карта (козыри — дороже всех).
    static let naturalKey: [[Int]] = (0..<4).map { t in
        (0..<32).map { id in (id >> 3 == t ? 100 : 0) + points[t][id] * 10 + power[t][id] }
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
        result.append(m.trailingZeroBitCount)
        m &= m - 1
    }
    return result
}

/// Сведения о сдаче, от которых зависит итоговый подсчёт. Создаётся на каждый мир.
struct SimContext {
    let rules: RuleSet
    let playerCount: Int
    let trump: Int
    let bidder: Int
    /// Порядок игроков начиная со следующего после сдающего.
    let priority: [Int]
    let pot: Int
    let baitCounts: [Int]
    let nakedCounts: [Int]
    /// Кто записывает терцы/полтинники (−1 — никто) и сколько это очков.
    let meldWinner: Int
    let meldPoints: Int
    /// У кого бэла (−1 — ни у кого).
    let bellaSeat: Int

    let points: [Int]
    let power: [Int]
    let trumpBits: UInt32
    let trumpAbove: [UInt32]

    init(rules: RuleSet, playerCount: Int, trump: Int, bidder: Int, priority: [Int],
         meldWinner: Int, meldPoints: Int, bellaSeat: Int,
         pot: Int, baitCounts: [Int], nakedCounts: [Int]) {
        self.rules = rules
        self.playerCount = playerCount
        self.trump = trump
        self.bidder = bidder
        self.priority = priority
        self.pot = pot
        self.baitCounts = baitCounts
        self.nakedCounts = nakedCounts
        self.meldWinner = meldWinner
        self.meldPoints = meldPoints
        self.bellaSeat = bellaSeat
        points = CardTables.points[trump]
        power = CardTables.power[trump]
        trumpBits = suitMask(trump)
        trumpAbove = CardTables.trumpAbove[trump]
    }

    init(rules: RuleSet, playerCount: Int, trump: Int, bidder: Int, priority: [Int],
         declarations: Declarations, pot: Int, baitCounts: [Int], nakedCounts: [Int]) {
        let w = declarations.meldWinner ?? -1
        self.init(rules: rules, playerCount: playerCount, trump: trump, bidder: bidder, priority: priority,
                  meldWinner: w, meldPoints: w >= 0 ? declarations.meldPoints(for: w, rules: rules) : 0,
                  bellaSeat: declarations.bellaSeat ?? -1,
                  pot: pot, baitCounts: baitCounts, nakedCounts: nakedCounts)
    }
}

/// Компактное состояние розыгрыша для моделирования. Копируется без выделения памяти.
struct SimState {
    var hands: SIMD4<UInt32>
    var cardPoints: SIMD4<Int32>
    var tricks: SIMD4<Int32>
    /// Все вышедшие и известные «мёртвые» карты (открытая, нижняя).
    var played: UInt32
    var turn: Int
    let n: Int
    var tricksLeft: Int
    var finished = false

    // Текущая взятка.
    /// Карты текущей взятки (маска).
    var trickMask: UInt32 = 0
    var trickCount = 0
    /// Масть захода (−1 — взятка пуста).
    var led = -1
    /// Карта, которая сейчас берёт, и её хозяин.
    var winCard = -1
    var winSeat = -1
    var trickPoints = 0
    /// Старшинство старшего козыря во взятке (0 — козырей нет).
    var topTrump = 0

    /// Начальное состояние. `trick` — уже лежащие во взятке карты (по порядку), они должны
    /// входить в `played` и отсутствовать в руках.
    init(hands: [UInt32], turn: Int, cardPoints: [Int], tricks: [Int], played: UInt32,
         tricksLeft: Int, trick: [(seat: Int, card: Int)] = [], ctx: SimContext) {
        n = hands.count
        var h = SIMD4<UInt32>(repeating: 0)
        var cp = SIMD4<Int32>(repeating: 0)
        var tr = SIMD4<Int32>(repeating: 0)
        for i in 0..<n {
            h[i] = hands[i]
            cp[i] = Int32(cardPoints[i])
            tr[i] = Int32(tricks[i])
        }
        self.hands = h
        self.cardPoints = cp
        self.tricks = tr
        self.played = played
        self.turn = turn
        self.tricksLeft = tricksLeft
        for p in trick { addToTrick(p.card, seat: p.seat, ctx) }
    }

    @inline(__always)
    private mutating func addToTrick(_ id: Int, seat: Int, _ ctx: SimContext) {
        let pw = ctx.power[id]
        let suit = id >> 3
        if trickCount == 0 {
            led = suit
            winCard = id
            winSeat = seat
            trickPoints = ctx.points[id]
            topTrump = suit == ctx.trump ? pw : 0
        } else {
            if suit == winCard >> 3 {
                if pw > ctx.power[winCard] { winCard = id; winSeat = seat }
            } else if suit == ctx.trump {
                winCard = id
                winSeat = seat
            }
            trickPoints += ctx.points[id]
            if suit == ctx.trump && pw > topTrump { topTrump = pw }
        }
        trickMask |= bit(id)
        trickCount += 1
    }

    /// Допустимые карты для игрока, чья очередь.
    @inline(__always)
    func legalMask(_ ctx: SimContext) -> UInt32 {
        let hand = hands[turn]
        guard trickCount > 0 else { return hand }
        let same = hand & suitMask(led)
        if same != 0 {
            if led == ctx.trump, ctx.rules.effectiveOvertrump != .never, topTrump > 0 {
                let higher = same & ctx.trumpAbove[topTrump]
                if higher != 0 { return higher }
            }
            return same
        }
        let trumps = hand & ctx.trumpBits
        if ctx.rules.mustTrump && trumps != 0 {
            if ctx.rules.effectiveOvertrump == .always, topTrump > 0 {
                let higher = trumps & ctx.trumpAbove[topTrump]
                if higher != 0 { return higher }
            }
            return trumps
        }
        return hand
    }

    /// Бьёт ли карта `id` то, что сейчас лежит во взятке.
    @inline(__always)
    func beatsTrick(_ id: Int, _ ctx: SimContext) -> Bool {
        guard trickCount > 0 else { return true }
        if id >> 3 == winCard >> 3 { return ctx.power[id] > ctx.power[winCard] }
        return id >> 3 == ctx.trump
    }

    mutating func play(_ id: Int, _ ctx: SimContext) {
        hands[turn] &= ~bit(id)
        played |= bit(id)
        addToTrick(id, seat: turn, ctx)
        if trickCount == n {
            let w = winSeat
            cardPoints[w] += Int32(trickPoints)
            tricks[w] += 1
            tricksLeft -= 1
            trickMask = 0
            trickCount = 0
            led = -1
            winCard = -1
            winSeat = -1
            trickPoints = 0
            topTrump = 0
            turn = w
            if tricksLeft == 0 {
                cardPoints[w] += 10
                finished = true
            }
        } else {
            turn = turn + 1 == n ? 0 : turn + 1
        }
    }

    /// Итог сдачи: изменение счёта каждого игрока (с байтом, висячими очками и штрафами).
    /// Повторяет `Scoring.settle` без выделения памяти; совпадение проверяется тестом.
    func settlementChange(_ ctx: SimContext) -> SIMD4<Int32> {
        let rules = ctx.rules
        var raw = cardPoints
        let w = ctx.meldWinner
        if w >= 0, rules.combosNeedTrick != .all || tricks[w] > 0 {
            raw[w] += Int32(ctx.meldPoints)
        }
        let b = ctx.bellaSeat
        if b >= 0, rules.combosNeedTrick == .none || tricks[b] > 0 {
            raw[b] += Int32(rules.bellaPoints)
        }

        let bidder = ctx.bidder
        var opponentMax: Int32 = 0
        var opponentSum: Int32 = 0
        var first = true
        for s in 0..<n where s != bidder {
            if first || raw[s] > opponentMax { opponentMax = raw[s] }
            first = false
            opponentSum += raw[s]
        }
        let threshold = rules.bidderMustBeat == .opponentsCombined && n == 3 ? opponentSum : opponentMax
        let bp = raw[bidder]

        var outcome: DealScore.Outcome
        if bp > threshold {
            outcome = .made
        } else if bp < threshold {
            outcome = .bait
        } else {
            switch rules.tieRule {
            case .hangingBait: outcome = .hanging
            case .bait: outcome = .bait
            case .eachKeeps: outcome = .tie
            }
        }

        var change = raw
        var potAdded: Int32 = 0
        switch outcome {
        case .bait:
            change[bidder] = 0
            if rules.baitTransfer == .toOpponent {
                // Получатели — в порядке очерёдности (как в Scoring.settle).
                var count: Int32 = 0
                for s in ctx.priority where s != bidder {
                    if rules.baitRecipient == .splitHalf || raw[s] == opponentMax { count += 1 }
                }
                let share = bp / count
                var remainder = bp % count
                for s in ctx.priority where s != bidder {
                    guard rules.baitRecipient == .splitHalf || raw[s] == opponentMax else { continue }
                    change[s] += share
                    if remainder > 0 {
                        change[s] += 1
                        remainder -= 1
                    }
                }
            }
        case .hanging:
            change[bidder] = 0
            potAdded = bp
        default:
            break
        }
        _ = potAdded

        if ctx.pot > 0 && outcome != .hanging {
            var top: Int32 = raw[0]
            for s in 1..<n where raw[s] > top { top = raw[s] }
            var leader = -1
            var leaders = 0
            for s in 0..<n where raw[s] == top { leader = s; leaders += 1 }
            if leaders == 1 { change[leader] += Int32(ctx.pot) }
        }

        if outcome == .bait || (outcome == .hanging && rules.hangingCountsAsBait) {
            let count = ctx.baitCounts[bidder] + 1
            if rules.baitPenaltyEvery > 0 && count % rules.baitPenaltyEvery == 0 {
                change[bidder] -= Int32(rules.baitPenaltyPoints)
            }
        }
        if rules.nakedPenaltyEvery > 0 {
            for s in 0..<n where tricks[s] == 0 {
                if (ctx.nakedCounts[s] + 1) % rules.nakedPenaltyEvery == 0 {
                    change[s] -= Int32(rules.nakedPenaltyPoints)
                }
            }
        }
        if n < 4 { for s in n..<4 { change[s] = 0 } }
        return change
    }

    /// Полезность для каждого игрока: своё изменение счёта минус среднее у соперников.
    /// Вдвоём полезности антисимметричны (u0 = −u1).
    func utilities(_ ctx: SimContext) -> SIMD4<Double> {
        let c = settlementChange(ctx)
        var total: Int32 = 0
        for s in 0..<n { total += c[s] }
        var u = SIMD4<Double>(repeating: 0)
        let others = Double(n - 1)
        for s in 0..<n { u[s] = Double(c[s]) - Double(total - c[s]) / others }
        return u
    }

    /// Полезность для одного игрока.
    @inline(__always)
    func utility(_ ctx: SimContext, for seat: Int) -> Double {
        let c = settlementChange(ctx)
        if n == 2 { return Double(c[seat] - c[1 - seat]) }
        var total: Int32 = 0
        for s in 0..<n { total += c[s] }
        return Double(c[seat]) - Double(total - c[seat]) / Double(n - 1)
    }
}

// MARK: - Точный перебор концовки

enum Search {

    /// Вдвоём: альфа-бета (игра с нулевой суммой). Возвращает полезность для `me`.
    static func alphaBeta(_ s: SimState, _ ctx: SimContext, me: Int, alpha: Double, beta: Double) -> Double {
        if s.finished { return s.utility(ctx, for: me) }
        let legal = s.legalMask(ctx)
        // Последняя взятка: ходы вынужденные, досчитываем напрямую.
        if s.tricksLeft == 1 && legal.nonzeroBitCount == 1 {
            var t = s
            while !t.finished { t.play(t.legalMask(ctx).trailingZeroBitCount, ctx) }
            return t.utility(ctx, for: me)
        }
        var a = alpha, b = beta
        let maximizing = s.turn == me
        var best = maximizing ? -Double.infinity : Double.infinity
        let order = CardTables.searchOrder[ctx.trump]
        var remaining = legal
        for id in order where remaining & bit(id) != 0 {
            remaining &= ~bit(id)
            var t = s
            t.play(id, ctx)
            let v = alphaBeta(t, ctx, me: me, alpha: a, beta: b)
            if maximizing {
                if v > best { best = v }
                if best > a { a = best }
            } else {
                if v < best { best = v }
                if best < b { b = best }
            }
            if a >= b || remaining == 0 { break }
        }
        return best
    }

    /// Втроём: перебор max^n — каждый выбирает лучшее для себя.
    static func maxN(_ s: SimState, _ ctx: SimContext) -> SIMD4<Double> {
        if s.finished { return s.utilities(ctx) }
        let me = s.turn
        var best = SIMD4<Double>(repeating: 0)
        var bestValue = -Double.infinity
        var m = s.legalMask(ctx)
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m - 1
            var t = s
            t.play(id, ctx)
            let u = maxN(t, ctx)
            if u[me] > bestValue {
                bestValue = u[me]
                best = u
            }
        }
        return best
    }
}
