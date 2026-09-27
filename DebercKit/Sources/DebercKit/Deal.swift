import Foundation

public enum GameError: Error, Equatable, CustomStringConvertible {
    case illegalAction(String)

    public var description: String {
        switch self {
        case .illegalAction(let message): return "Недопустимое действие: \(message)"
        }
    }
}

/// Действие игрока.
public enum Action: Codable, Equatable, Hashable, Sendable {
    /// «Пас».
    case pass
    /// 1-й круг: «беру» — козырь по масти открытой карты.
    case take
    /// 2-й круг: назначить другую масть.
    case name(Suit)
    /// Поменять козырную семёрку на открытую карту (или отказаться).
    case exchangeSeven(Bool)
    /// Сходить картой.
    case play(Card)
}

public struct Bid: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case pass, take, name, forced
    }

    public let seat: Int
    public let round: Int
    public let kind: Kind
    public let suit: Suit?

    public init(seat: Int, round: Int, kind: Kind, suit: Suit?) {
        self.seat = seat
        self.round = round
        self.kind = kind
        self.suit = suit
    }
}

public struct PlayedCard: Codable, Equatable, Hashable, Sendable {
    public let seat: Int
    public let card: Card

    public init(seat: Int, card: Card) {
        self.seat = seat
        self.card = card
    }
}

public struct Trick: Codable, Equatable, Sendable {
    public var plays: [PlayedCard] = []
    public var winner: Int?

    public init() {}

    public var leader: Int? { plays.first?.seat }
    public var cards: [Card] { plays.map(\.card) }
    public var ledSuit: Suit? { plays.first?.card.suit }
}

public struct SevenExchangeRecord: Codable, Equatable, Sendable {
    public let seat: Int
    /// Козырная семёрка, которая легла на стол.
    public let gave: Card
    /// Бывшая открытая карта, которую игрок забрал.
    public let took: Card
}

public enum DealPhase: Codable, Equatable, Sendable {
    case bidding(round: Int)
    case exchange
    case playing
    case finished
}

/// События сдачи — для анимаций и подсказок в интерфейсе.
public enum DealEvent: Equatable, Sendable {
    case bid(Bid)
    case trumpChosen(seat: Int, suit: Suit, forced: Bool)
    case allPassed
    case prikupDealt
    case fourSevens(seat: Int)
    case sevenExchanged(SevenExchangeRecord)
    case sevenKept(seat: Int)
    case playStarted(Declarations)
    case cardPlayed(PlayedCard)
    case bella(seat: Int)
    case trickCompleted(Trick)
    case dealFinished
}

/// Одна сдача: раздача, торговля, обмен семёрки, розыгрыш.
public struct Deal: Codable, Equatable, Sendable {
    public let rules: RuleSet
    public let playerCount: Int
    public let dealer: Int
    /// «Обязы»: торговли нет, играет сдающий на масть открытой карты.
    public let forced: Bool

    public private(set) var hands: [[Card]]
    /// Прикуп (по 3 карты), который раздаётся после выбора козыря.
    public private(set) var pendingPrikup: [[Card]]
    /// Нераздаваемый остаток колоды. Последняя карта — нижняя («фреза»).
    public private(set) var stock: [Card]
    /// Открытая карта (после обмена — козырная семёрка).
    public private(set) var openCard: Card
    public private(set) var bottomCardVisible = false
    public private(set) var prikupDealt = false
    public private(set) var trump: Suit?
    public private(set) var bidder: Int?
    public private(set) var bids: [Bid] = []
    public private(set) var phase: DealPhase
    public private(set) var turn: Int
    public private(set) var sevenExchange: SevenExchangeRecord?
    public private(set) var declarations: Declarations?
    public private(set) var tricks: [Trick] = []
    public private(set) var currentTrick = Trick()
    public private(set) var bellaAnnounced = false
    public private(set) var fourSevensSeat: Int?
    public private(set) var allPassed = false

    private init(deck: [Card], dealer: Int, playerCount: Int, forced: Bool, rules: RuleSet) {
        precondition(deck.count == 32, "Нужна колода из 32 карт")
        precondition((2...3).contains(playerCount), "Поддерживается игра вдвоём и втроём")
        self.rules = rules
        self.playerCount = playerCount
        self.dealer = dealer
        self.forced = forced

        let order = (1...playerCount).map { (dealer + $0) % playerCount }
        var hands = [[Card]](repeating: [], count: playerCount)
        var prikup = [[Card]](repeating: [], count: playerCount)
        var index = 0
        for _ in 0..<2 {
            for seat in order {
                hands[seat].append(contentsOf: deck[index..<index + 3])
                index += 3
            }
        }
        openCard = deck[index]
        index += 1
        for seat in order {
            prikup[seat] = Array(deck[index..<index + 3])
            index += 3
        }
        self.hands = hands
        self.pendingPrikup = prikup
        self.stock = Array(deck[index...])
        self.phase = .bidding(round: 1)
        self.turn = order[0]
    }

    /// Раздать новую сдачу из перетасованной колоды.
    public static func start(deck: [Card], dealer: Int, playerCount: Int, forced: Bool, rules: RuleSet) -> (Deal, [DealEvent]) {
        var deal = Deal(deck: deck, dealer: dealer, playerCount: playerCount, forced: forced, rules: rules)
        var events: [DealEvent] = []
        if rules.bottomCard == .afterDeal { deal.bottomCardVisible = true }

        if rules.fourSevens != .off, let seat = deal.seatWithFourSevens() {
            deal.fourSevensSeat = seat
            deal.phase = .finished
            events.append(.fourSevens(seat: seat))
            events.append(.dealFinished)
            return (deal, events)
        }

        if forced {
            let bid = Bid(seat: dealer, round: 1, kind: .forced, suit: deal.openCard.suit)
            deal.bids.append(bid)
            events.append(.bid(bid))
            deal.chooseTrump(deal.openCard.suit, by: dealer, forced: true, events: &events)
        }
        return (deal, events)
    }

    // MARK: - Справочные свойства

    public func next(_ seat: Int) -> Int { (seat + 1) % playerCount }

    /// Игроки по порядку, начиная со следующего после сдающего (сдающий — последний).
    public var seatsFromDealer: [Int] { (1...playerCount).map { (dealer + $0) % playerCount } }

    public var bottomCard: Card? { stock.last }

    public var isFinished: Bool { phase == .finished }

    /// Кто сейчас должен действовать (nil — сдача окончена).
    public var actor: Int? { phase == .finished ? nil : turn }

    public var handCounts: [Int] { hands.map(\.count) }

    /// Все сыгранные карты (включая текущую взятку).
    public var playedCards: [Card] { tricks.flatMap(\.cards) + currentTrick.cards }

    public var tricksTaken: [Int] {
        var result = [Int](repeating: 0, count: playerCount)
        for trick in tricks { if let w = trick.winner { result[w] += 1 } }
        return result
    }

    /// Очки за карты во взятках плюс 10 за последнюю взятку.
    public var cardPoints: [Int] {
        var result = [Int](repeating: 0, count: playerCount)
        guard let trump else { return result }
        for trick in tricks {
            if let w = trick.winner { result[w] += PlayRules.points(of: trick.cards, trump: trump) }
        }
        if phase == .finished, let last = tricks.last?.winner, hands.allSatisfy(\.isEmpty) {
            result[last] += 10
        }
        return result
    }

    public func legalCards(for seat: Int) -> [Card] {
        guard phase == .playing, seat == turn, let trump else { return [] }
        return PlayRules.legalCards(hand: hands[seat], trick: currentTrick.cards, trump: trump, rules: rules)
    }

    public func legalActions() -> [Action] {
        switch phase {
        case .bidding(let round):
            if round == 1 { return [.take, .pass] }
            return Suit.allCases.filter { $0 != openCard.suit }.map { Action.name($0) } + [.pass]
        case .exchange:
            return [.exchangeSeven(true), .exchangeSeven(false)]
        case .playing:
            return legalCards(for: turn).map { Action.play($0) }
        case .finished:
            return []
        }
    }

    // MARK: - Ход игры

    @discardableResult
    public mutating func apply(_ action: Action) throws -> [DealEvent] {
        var events: [DealEvent] = []
        switch (phase, action) {
        case (.bidding(let round), .pass):
            let bid = Bid(seat: turn, round: round, kind: .pass, suit: nil)
            bids.append(bid)
            events.append(.bid(bid))
            if turn == dealer {
                if round == 1 {
                    phase = .bidding(round: 2)
                    turn = next(dealer)
                } else {
                    allPassed = true
                    phase = .finished
                    events.append(.allPassed)
                    events.append(.dealFinished)
                }
            } else {
                turn = next(turn)
            }

        case (.bidding(1), .take):
            let bid = Bid(seat: turn, round: 1, kind: .take, suit: openCard.suit)
            bids.append(bid)
            events.append(.bid(bid))
            chooseTrump(openCard.suit, by: turn, forced: false, events: &events)

        case (.bidding(2), .name(let suit)):
            guard suit != openCard.suit else {
                throw GameError.illegalAction("во 2-м круге нельзя назвать масть открытой карты")
            }
            let bid = Bid(seat: turn, round: 2, kind: .name, suit: suit)
            bids.append(bid)
            events.append(.bid(bid))
            chooseTrump(suit, by: turn, forced: false, events: &events)

        case (.exchange, .exchangeSeven(let accept)):
            guard let trump else { throw GameError.illegalAction("козырь не выбран") }
            let seven = Card(.seven, trump)
            if accept {
                let took = openCard
                if let i = hands[turn].firstIndex(of: seven) { hands[turn].remove(at: i) }
                hands[turn].append(took)
                openCard = seven
                let record = SevenExchangeRecord(seat: turn, gave: seven, took: took)
                sevenExchange = record
                events.append(.sevenExchanged(record))
            } else {
                events.append(.sevenKept(seat: turn))
            }
            startPlay(events: &events)

        case (.playing, .play(let card)):
            guard legalCards(for: turn).contains(card) else {
                throw GameError.illegalAction("этой картой сейчас ходить нельзя: \(card)")
            }
            play(card, events: &events)

        default:
            throw GameError.illegalAction("\(action) в фазе \(phase)")
        }
        return events
    }

    // MARK: - Внутренние шаги

    private func seatWithFourSevens() -> Int? {
        hands.firstIndex { hand in hand.filter { $0.rank == .seven }.count == 4 }
    }

    private mutating func chooseTrump(_ suit: Suit, by seat: Int, forced: Bool, events: inout [DealEvent]) {
        trump = suit
        bidder = seat
        events.append(.trumpChosen(seat: seat, suit: suit, forced: forced))
        dealPrikup(events: &events)
    }

    private mutating func dealPrikup(events: inout [DealEvent]) {
        for seat in 0..<playerCount {
            hands[seat].append(contentsOf: pendingPrikup[seat])
            pendingPrikup[seat] = []
        }
        prikupDealt = true
        if rules.bottomCard == .afterPrikup { bottomCardVisible = true }
        events.append(.prikupDealt)

        if rules.fourSevens != .off, rules.fourSevensAfterPrikup, let seat = seatWithFourSevens() {
            fourSevensSeat = seat
            phase = .finished
            events.append(.fourSevens(seat: seat))
            events.append(.dealFinished)
            return
        }

        if let trump, trump == openCard.suit, rules.sevenExchange != .off {
            let seven = Card(.seven, trump)
            if let holder = hands.firstIndex(where: { $0.contains(seven) }),
               rules.sevenExchange == .anyPlayer || holder == bidder {
                phase = .exchange
                turn = holder
                return
            }
        }
        startPlay(events: &events)
    }

    private mutating func startPlay(events: inout [DealEvent]) {
        guard let trump, let bidder else { return }
        let decl = Combinations.declarations(hands: hands, trump: trump, rules: rules, priority: seatsFromDealer)
        declarations = decl
        phase = .playing
        turn = rules.firstLead == .afterDealer ? next(dealer) : bidder
        currentTrick = Trick()
        events.append(.playStarted(decl))
    }

    private mutating func play(_ card: Card, events: inout [DealEvent]) {
        guard let trump else { return }
        if let i = hands[turn].firstIndex(of: card) { hands[turn].remove(at: i) }
        let played = PlayedCard(seat: turn, card: card)
        currentTrick.plays.append(played)
        events.append(.cardPlayed(played))

        if !bellaAnnounced, declarations?.bellaSeat == turn, card.suit == trump,
           card.rank == .king || card.rank == .queen {
            bellaAnnounced = true
            events.append(.bella(seat: turn))
        }

        if currentTrick.plays.count == playerCount {
            let winnerIndex = PlayRules.winningIndex(currentTrick.cards, trump: trump)
            let winner = currentTrick.plays[winnerIndex].seat
            currentTrick.winner = winner
            tricks.append(currentTrick)
            events.append(.trickCompleted(currentTrick))
            currentTrick = Trick()
            turn = winner
            if hands.allSatisfy(\.isEmpty) {
                phase = .finished
                events.append(.dealFinished)
            }
        } else {
            turn = next(turn)
        }
    }
}
