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

public extension Array where Element == Card {
    /// Карты, отсортированные для показа на руке: по мастям, внутри — по старшинству.
    func sortedForDisplay(trump: Suit?) -> [Card] {
        let suitOrder: [Suit] = [.spades, .hearts, .clubs, .diamonds]
        func suitKey(_ s: Suit) -> Int {
            if let trump, s == trump { return -1 }
            return suitOrder.firstIndex(of: s) ?? 0
        }
        return sorted { a, b in
            if a.suit != b.suit { return suitKey(a.suit) < suitKey(b.suit) }
            let t = trump ?? .spades
            let pa = trump == nil ? a.rank.rawValue : a.power(trump: t)
            let pb = trump == nil ? b.rank.rawValue : b.power(trump: t)
            return pa > pb
        }
    }
}
