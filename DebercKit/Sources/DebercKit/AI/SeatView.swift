import Foundation

/// То, что видит один игрок: его карты и всё открытое на столе.
/// Боты принимают решения только по этому представлению — без подглядывания.
public struct SeatView: Sendable {
    public let seat: Int
    public let playerCount: Int
    public let rules: RuleSet
    public let dealer: Int
    public let phase: DealPhase
    public let turn: Int
    public let myHand: [Card]
    public let handCounts: [Int]
    public let openCard: Card
    public let bottomCard: Card?
    public let stockCount: Int
    public let prikupDealt: Bool
    public let trump: Suit?
    public let bidder: Int?
    public let bids: [Bid]
    public let tricks: [Trick]
    public let currentTrick: Trick
    public let meldWinner: Int?
    public let meldWinnerPoints: Int
    /// Бэла известна всем, только когда объявлена; до этого — только своя.
    public let knownBellaSeat: Int?
    public let exchange: SevenExchangeRecord?
    public let seatsFromDealer: [Int]
    public let pot: Int
    public let baitCounts: [Int]
    public let nakedCounts: [Int]
    public let totals: [Int]

    public init(match: Match, seat: Int) {
        let deal = match.deal!
        self.seat = seat
        playerCount = deal.playerCount
        rules = deal.rules
        dealer = deal.dealer
        phase = deal.phase
        turn = deal.turn
        myHand = deal.hands[seat]
        handCounts = deal.handCounts
        openCard = deal.openCard
        bottomCard = deal.bottomCardVisible ? deal.bottomCard : nil
        stockCount = deal.stock.count
        prikupDealt = deal.prikupDealt
        trump = deal.trump
        bidder = deal.bidder
        bids = deal.bids
        tricks = deal.tricks
        currentTrick = deal.currentTrick
        let decl = deal.declarations
        meldWinner = decl?.meldWinner
        if let decl, let w = decl.meldWinner {
            meldWinnerPoints = decl.meldPoints(for: w, rules: deal.rules)
        } else {
            meldWinnerPoints = 0
        }
        if let b = decl?.bellaSeat, deal.bellaAnnounced || b == seat {
            knownBellaSeat = b
        } else {
            knownBellaSeat = nil
        }
        winnerMelds = decl.flatMap { d in d.meldWinner.map { d.melds[$0] } } ?? []
        exchange = deal.sevenExchange
        seatsFromDealer = deal.seatsFromDealer
        pot = match.pot
        baitCounts = match.baitCounts
        nakedCounts = match.nakedCounts
        totals = match.totals
    }

    /// Последовательности победителя объявлений — их карты показаны всем.
    public let winnerMelds: [Meld]

    public var playedCards: [Card] { tricks.flatMap(\.cards) + currentTrick.cards }

    public func next(_ s: Int) -> Int { (s + 1) % playerCount }

    /// Масти, которых точно нет у игроков (по тому, как они ходили).
    public var voids: [Set<Suit>] {
        var result = [Set<Suit>](repeating: [], count: playerCount)
        guard let trump else { return result }
        var all = tricks
        if !currentTrick.plays.isEmpty { all.append(currentTrick) }
        for trick in all {
            guard let led = trick.ledSuit else { continue }
            for play in trick.plays.dropFirst() where play.card.suit != led {
                result[play.seat].insert(led)
                if rules.mustTrump && play.card.suit != trump {
                    result[play.seat].insert(trump)
                }
            }
        }
        return result
    }

    /// Карты, про которые точно известно, что они у других игроков.
    public var knownCardsOfOthers: [[Card]] {
        var result = [[Card]](repeating: [], count: playerCount)
        let played = Set(playedCards)
        func add(_ card: Card, to s: Int) {
            guard s != seat, !played.contains(card), !result[s].contains(card) else { return }
            result[s].append(card)
        }
        if let ex = exchange { add(ex.took, to: ex.seat) }
        if let w = meldWinner {
            for meld in winnerMelds { for card in meld.cards { add(card, to: w) } }
        }
        if let b = knownBellaSeat, let trump {
            add(Card(.king, trump), to: b)
            add(Card(.queen, trump), to: b)
        }
        return result
    }
}
