import Foundation

/// Последовательность карт одной масти подряд (терц, полтинник, сотня).
public struct Meld: Codable, Hashable, Sendable, CustomStringConvertible {
    public let suit: Suit
    public let low: Rank
    public let length: Int

    public init(suit: Suit, low: Rank, length: Int) {
        self.suit = suit
        self.low = low
        self.length = length
    }

    public var high: Rank { Rank(rawValue: low.rawValue + length - 1)! }

    public var cards: [Card] {
        (0..<length).map { Card(Rank(rawValue: low.rawValue + $0)!, suit) }
    }

    public func points(_ rules: RuleSet) -> Int {
        if length >= 5 && rules.hundredForFive { return 100 }
        return length >= 4 ? rules.fiftyPoints : rules.terzPoints
    }

    /// «терц», «полтинник», «сотня».
    public func name(_ rules: RuleSet) -> String {
        if length >= 5 && rules.hundredForFive { return "сотня" }
        return length >= 4 ? "полтинник" : "терц"
    }

    public var description: String {
        cards.map(\.description).joined(separator: " ")
    }
}

/// Итоги объявления комбинаций перед розыгрышем.
public struct Declarations: Codable, Equatable, Sendable {
    /// Все последовательности каждого игрока.
    public var melds: [[Meld]]
    /// Кто записывает свои терцы/полтинники (у кого старшая комбинация).
    public var meldWinner: Int?
    /// У кого бэла (король и дама козырей).
    public var bellaSeat: Int?

    public init(melds: [[Meld]], meldWinner: Int?, bellaSeat: Int?) {
        self.melds = melds
        self.meldWinner = meldWinner
        self.bellaSeat = bellaSeat
    }

    /// Очки за последовательности победителя (без учёта взяток).
    public func meldPoints(for seat: Int, rules: RuleSet) -> Int {
        guard seat == meldWinner, melds.indices.contains(seat) else { return 0 }
        return melds[seat].reduce(0) { $0 + $1.points(rules) }
    }

    /// Последовательности, которые записывает победитель объявлений (пусто, если победителя нет).
    public var winnerMelds: [Meld] {
        guard let w = meldWinner, melds.indices.contains(w) else { return [] }
        return melds[w]
    }
}

public enum Combinations {

    /// Все максимальные последовательности длиной от 3 карт.
    /// Одна карта входит только в одну последовательность.
    public static func melds(in hand: [Card]) -> [Meld] {
        var result: [Meld] = []
        for suit in Suit.allCases {
            var present = [Bool](repeating: false, count: 8)
            for card in hand where card.suit == suit {
                present[card.rank.index] = true
            }
            var i = 0
            while i < 8 {
                guard present[i] else { i += 1; continue }
                var j = i
                while j + 1 < 8 && present[j + 1] { j += 1 }
                let length = j - i + 1
                if length >= 3 {
                    result.append(Meld(suit: suit, low: Rank(rawValue: i + 7)!, length: length))
                }
                i = j + 1
            }
        }
        return result
    }

    /// Последовательности с учётом правил: если `bellaInMelds` выключено,
    /// король и дама бэлы (у кого она есть) в последовательностях не участвуют.
    public static func melds(in hand: [Card], trump: Suit, rules: RuleSet) -> [Meld] {
        guard !rules.bellaInMelds, hasBella(hand, trump: trump) else { return melds(in: hand) }
        let bella: Set<Card> = [Card(.king, trump), Card(.queen, trump)]
        return melds(in: hand.filter { !bella.contains($0) })
    }

    public static func hasBella(_ hand: [Card], trump: Suit) -> Bool {
        hand.contains(Card(.king, trump)) && hand.contains(Card(.queen, trump))
    }

    /// Положительное число — `a` старше, отрицательное — `b` старше, 0 — равны.
    public static func compare(_ a: Meld, _ b: Meld, trump: Suit, rules: RuleSet) -> Int {
        switch rules.meldOrder {
        case .longerFirst:
            if a.length != b.length { return a.length - b.length }
        case .valueThenTopCard:
            let pa = a.points(rules), pb = b.points(rules)
            if pa != pb { return pa - pb }
        }
        if a.high != b.high { return a.high.rawValue - b.high.rawValue }
        let at = a.suit == trump, bt = b.suit == trump
        if at != bt { return at ? 1 : -1 }
        return 0
    }

    public static func best(_ melds: [Meld], trump: Suit, rules: RuleSet) -> Meld? {
        var best: Meld?
        for meld in melds {
            if let current = best {
                if compare(meld, current, trump: trump, rules: rules) > 0 { best = meld }
            } else {
                best = meld
            }
        }
        return best
    }

    /// Чьи последовательности засчитываются. `priority` — порядок игроков,
    /// начиная с того, кто ходит первым: при полном равенстве побеждает более ранний.
    public static func winningSeat(meldsBySeat: [[Meld]], trump: Suit, rules: RuleSet, priority: [Int]) -> Int? {
        var winner: Int?
        var winnerBest: Meld?
        for seat in priority {
            guard let candidate = best(meldsBySeat[seat], trump: trump, rules: rules) else { continue }
            if let current = winnerBest {
                if compare(candidate, current, trump: trump, rules: rules) > 0 {
                    winner = seat
                    winnerBest = candidate
                }
            } else {
                winner = seat
                winnerBest = candidate
            }
        }
        return winner
    }

    /// Объявления для рук на начало розыгрыша. `priority` — порядок хода в розыгрыше,
    /// начиная с того, кто ходит первым (см. `Deal.leadOrder`): при полном равенстве
    /// комбинаций записывает тот, кто раньше ходит.
    public static func declarations(hands: [[Card]], trump: Suit, rules: RuleSet, priority: [Int]) -> Declarations {
        let melds = hands.map { Combinations.melds(in: $0, trump: trump, rules: rules) }
        let winner = winningSeat(meldsBySeat: melds, trump: trump, rules: rules, priority: priority)
        let bella = hands.firstIndex { hasBella($0, trump: trump) }
        return Declarations(melds: melds, meldWinner: winner, bellaSeat: bella)
    }
}
