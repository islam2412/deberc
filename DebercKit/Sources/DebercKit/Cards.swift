import Foundation

/// Масть.
public enum Suit: Int, CaseIterable, Codable, Hashable, Sendable {
    case spades = 0, clubs, diamonds, hearts

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        }
    }

    public var isRed: Bool { self == .diamonds || self == .hearts }

    /// «пики», «трефы», «бубны», «черви».
    public var name: String {
        switch self {
        case .spades: return "пики"
        case .clubs: return "трефы"
        case .diamonds: return "бубны"
        case .hearts: return "черви"
        }
    }
}

/// Достоинство карты. Сырые значения идут в «естественном» порядке 7…Т,
/// который используется для терцев и полтинников.
public enum Rank: Int, CaseIterable, Codable, Hashable, Comparable, Sendable {
    case seven = 7, eight, nine, ten, jack, queen, king, ace

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Обозначение на карте: 7, 8, 9, 10, В, Д, К, Т.
    public var symbol: String {
        switch self {
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .ten: return "10"
        case .jack: return "В"
        case .queen: return "Д"
        case .king: return "К"
        case .ace: return "Т"
        }
    }

    public var name: String {
        switch self {
        case .seven: return "семёрка"
        case .eight: return "восьмёрка"
        case .nine: return "девятка"
        case .ten: return "десятка"
        case .jack: return "валет"
        case .queen: return "дама"
        case .king: return "король"
        case .ace: return "туз"
        }
    }

    /// Номер в естественном порядке: 0 для семёрки … 7 для туза.
    public var index: Int { rawValue - 7 }
}

public struct Card: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// Номер карты 0…31 (масть * 8 + номер достоинства).
    public var id: Int { suit.rawValue * 8 + rank.index }

    public init(id: Int) {
        self.init(Rank(rawValue: id % 8 + 7)!, Suit(rawValue: id / 8)!)
    }

    public var description: String { rank.symbol + suit.symbol }

    /// Колода из 32 карт в фиксированном порядке.
    public static let deck: [Card] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { Card($0, suit) }
    }

    /// Очки карты при данном козыре.
    public func points(trump: Suit) -> Int {
        if suit == trump {
            switch rank {
            case .jack: return 20
            case .nine: return 14
            case .ace: return 11
            case .ten: return 10
            case .king: return 4
            case .queen: return 3
            case .eight, .seven: return 0
            }
        }
        switch rank {
        case .ace: return 11
        case .ten: return 10
        case .king: return 4
        case .queen: return 3
        case .jack: return 2
        case .nine, .eight, .seven: return 0
        }
    }

    /// Старшинство внутри своей масти (1 — младшая, 8 — старшая).
    /// Козыри: В, 9, Т, 10, К, Д, 8, 7. Остальные: Т, 10, К, Д, В, 9, 8, 7.
    public func power(trump: Suit) -> Int {
        if suit == trump {
            switch rank {
            case .jack: return 8
            case .nine: return 7
            case .ace: return 6
            case .ten: return 5
            case .king: return 4
            case .queen: return 3
            case .eight: return 2
            case .seven: return 1
            }
        }
        switch rank {
        case .ace: return 8
        case .ten: return 7
        case .king: return 6
        case .queen: return 5
        case .jack: return 4
        case .nine: return 3
        case .eight: return 2
        case .seven: return 1
        }
    }
}

public extension Suit {
    /// Порядок мастей на руке слева направо: козырь первым, дальше цвета чередуются
    /// (после чёрного козыря — красная масть, после красного — чёрная).
    /// Порядок постоянный для козыря и не прыгает, когда какая-то масть кончается.
    /// Без козыря: ♠ ♥ ♣ ♦.
    static func displayOrder(trump: Suit?) -> [Suit] {
        let base: [Suit] = [.spades, .hearts, .clubs, .diamonds]
        guard let trump else { return base }
        let others = base.filter { $0 != trump }
        let opposite = others.filter { $0.isRed != trump.isRed }
        let same = others.filter { $0.isRed == trump.isRed }
        // Козырь, масть другого цвета, вторая масть цвета козыря, вторая масть другого цвета.
        return [trump] + [opposite.first, same.first, opposite.dropFirst().first].compactMap { $0 }
    }
}

public extension Array where Element == Card {
    /// Карты, отсортированные для показа на руке: козыри слева, цвета мастей чередуются
    /// (см. `Suit.displayOrder(trump:)`), внутри масти — по старшинству
    /// (козыри: В 9 Т 10 К Д 8 7; остальные: Т 10 К Д В 9 8 7).
    /// Пока козыря нет — по порядку для комбинаций (Т К Д В 10 9 8 7).
    func sortedForDisplay(trump: Suit?) -> [Card] {
        sortedForDisplay(trump: trump, naturalOrder: false)
    }

    /// То же, но при `naturalOrder` внутри масти карты идут в порядке для комбинаций
    /// (Т К Д В 10 9 8 7) — так терцы и полтинники лежат подряд.
    func sortedForDisplay(trump: Suit?, naturalOrder: Bool) -> [Card] {
        let order = Suit.displayOrder(trump: trump)
        func suitKey(_ s: Suit) -> Int { order.firstIndex(of: s) ?? order.count }
        func strength(_ card: Card) -> Int {
            if naturalOrder { return card.rank.rawValue }
            guard let trump else { return card.rank.rawValue }
            return card.power(trump: trump)
        }
        return sorted { a, b in
            if a.suit != b.suit { return suitKey(a.suit) < suitKey(b.suit) }
            return strength(a) > strength(b)
        }
    }
}
