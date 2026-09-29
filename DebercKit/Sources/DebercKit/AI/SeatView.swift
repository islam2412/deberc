import Foundation

/// То, что видит один игрок: его карты и всё открытое на столе.
/// Боты принимают решения только по этому представлению — без подглядывания:
/// `Bot.chooseAction(view:rng:)` не получает ни чужих рук, ни прикупа, ни колоды.
public struct SeatView: Equatable, Sendable {
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
    /// Последовательности победителя объявлений — их карты показаны всем.
    public let winnerMelds: [Meld]
    // Партия.
    public let pot: Int
    public let baitCounts: [Int]
    public let nakedCounts: [Int]
    public let totals: [Int]
    /// Сколько сдач подряд все спасовали (для «обязов»).
    public let allPassStreak: Int
    /// Сдача «на обязах» (торговли нет).
    public let forced: Bool

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
        allPassStreak = match.allPassStreak
        forced = deal.forced
    }

    public var playedCards: [Card] { tricks.flatMap(\.cards) + currentTrick.cards }

    public func next(_ s: Int) -> Int { (s + 1) % playerCount }

    /// Порядок хода в розыгрыше при данном играющем, начиная с первого ходящего.
    /// Так же, как в `Deal.startPlay`: старшинство равных комбинаций и делёж нечётного очка.
    public func leadOrder(bidder: Int) -> [Int] {
        Deal.leadOrder(dealer: dealer, bidder: bidder, playerCount: playerCount, rules: rules)
    }

    /// Порядок хода в розыгрыше для текущего играющего; пока его нет — `seatsFromDealer`.
    public var leadOrder: [Int] { bidder.map { leadOrder(bidder: $0) } ?? seatsFromDealer }

    /// Мой ли сейчас ход (сдача не окончена).
    public var isMyTurn: Bool { turn == seat && phase != .finished }

    /// Кто будет играть «на обязах», если и эта сдача закончится «все пас» (иначе nil).
    /// После «все пас» сдаёт следующий по кругу при любом правиле смены сдающего,
    /// а играет — кого назначает `RuleSet.forcedPlayer` при этом сдающем.
    public var forcedSeatIfAllPass: Int? {
        guard rules.forcedDealAfterRedeals > 0,
              allPassStreak + 1 >= rules.forcedDealAfterRedeals else { return nil }
        return rules.forcedSeat(dealer: next(dealer), playerCount: playerCount)
    }

    /// Масти, которых точно нет у игроков (по тому, как они ходили).
    public var voids: [Set<Suit>] {
        voidMasks.map { m in Set(Suit.allCases.filter { m & (1 << $0.rawValue) != 0 }) }
    }

    /// То же, что `voids`, битами мастей.
    var voidMasks: [Int] {
        var result = [Int](repeating: 0, count: playerCount)
        guard let trump else { return result }
        var all = tricks
        if !currentTrick.plays.isEmpty { all.append(currentTrick) }
        for trick in all {
            guard let led = trick.ledSuit else { continue }
            for play in trick.plays.dropFirst() where play.card.suit != led {
                result[play.seat] |= 1 << led.rawValue
                if rules.mustTrump && play.card.suit != trump {
                    result[play.seat] |= 1 << trump.rawValue
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

    /// Устойчивый отпечаток позиции (FNV-1a) по всему, что видит игрок.
    /// Одинаков в любом процессе и при любом порядке карт на руке; чужие карты в него не входят.
    public var positionHash: UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ x: Int) {
            var v = UInt64(bitPattern: Int64(x))
            for _ in 0..<8 {
                h ^= v & 0xFF
                h = h &* 0x0000_0100_0000_01B3
                v >>= 8
            }
        }
        mix(seat); mix(playerCount); mix(dealer); mix(turn)
        switch phase {
        case .bidding(let round): mix(10 + round)
        case .exchange: mix(20)
        case .playing: mix(30)
        case .finished: mix(40)
        }
        mix(Int(truncatingIfNeeded: mask(of: myHand)))
        for c in handCounts { mix(c) }
        mix(openCard.id)
        mix(bottomCard?.id ?? 99)
        mix(trump?.rawValue ?? 9)
        mix(bidder ?? 9)
        for bid in bids {
            let kind: Int
            switch bid.kind {
            case .pass: kind = 1
            case .take: kind = 2
            case .name: kind = 3
            case .forced: kind = 4
            }
            mix(bid.seat * 1000 + bid.round * 100 + (bid.suit?.rawValue ?? 9) * 10 + kind)
        }
        mix(-1)
        for trick in tricks + [currentTrick] {
            for p in trick.plays { mix(p.seat * 100 + p.card.id) }
            mix(-2)
        }
        mix(meldWinner ?? 9); mix(meldWinnerPoints); mix(knownBellaSeat ?? 9)
        if let ex = exchange { mix(ex.seat * 100 + ex.took.id) }
        mix(pot)
        for x in baitCounts + nakedCounts + totals { mix(x) }
        mix(allPassStreak)
        mix(forced ? 1 : 0)
        return h
    }
}
