import Foundation

/// Партия: последовательность сдач до победы одного из игроков.
public struct Match: Codable, Equatable, Sendable {
    public let rules: RuleSet
    public let playerCount: Int
    public var names: [String]

    public private(set) var totals: [Int]
    /// Сколько байтов у каждого за партию (для штрафа).
    public private(set) var baitCounts: [Int]
    /// Сколько раз каждый остался «голым» за партию (для штрафа).
    public private(set) var nakedCounts: [Int]
    /// Висячие очки, которые достанутся победителю следующей сдачи.
    public private(set) var pot = 0
    public private(set) var dealer: Int
    /// Сколько сдач подряд все спасовали.
    public private(set) var allPassStreak = 0
    public private(set) var history: [DealScore] = []
    public private(set) var deal: Deal?
    public private(set) var winner: Int?
    public private(set) var dealCount = 0
    public private(set) var rng: SplitMix64

    public init(playerCount: Int, names: [String], rules: RuleSet, seed: UInt64, firstDealer: Int? = nil) {
        precondition((2...3).contains(playerCount))
        precondition(names.count == playerCount)
        self.rules = rules
        self.playerCount = playerCount
        self.names = names
        self.totals = [Int](repeating: 0, count: playerCount)
        self.baitCounts = [Int](repeating: 0, count: playerCount)
        self.nakedCounts = [Int](repeating: 0, count: playerCount)
        var rng = SplitMix64(seed: seed)
        self.dealer = firstDealer ?? Int(rng.next() % UInt64(playerCount))
        self.rng = rng
    }

    public var isOver: Bool { winner != nil }

    /// Пора раздавать следующую сдачу.
    public var needsNewDeal: Bool {
        guard winner == nil else { return false }
        guard let deal else { return true }
        return deal.isFinished
    }

    /// Следующая сдача будет «на обязах».
    public var nextDealIsForced: Bool {
        rules.forcedDealAfterRedeals > 0 && allPassStreak >= rules.forcedDealAfterRedeals
    }

    /// Кто сейчас должен действовать.
    public var actor: Int? {
        guard winner == nil else { return nil }
        return deal?.actor
    }

    public func next(_ seat: Int) -> Int { (seat + 1) % playerCount }

    /// Раздать следующую сдачу. Возвращает события начала сдачи.
    @discardableResult
    public mutating func startNextDeal() -> [DealEvent] {
        precondition(needsNewDeal, "Текущая сдача ещё не закончена")
        if deal != nil { dealer = nextDealer() }
        var deck = Card.deck
        deck.shuffle(using: &rng)
        return startDeal(deck: deck)
    }

    /// Раздать сдачу из заданной колоды (для тестов и воспроизведения).
    @discardableResult
    public mutating func startDeal(deck: [Card], dealer customDealer: Int? = nil) -> [DealEvent] {
        precondition(needsNewDeal, "Текущая сдача ещё не закончена")
        if let customDealer { dealer = customDealer }
        dealCount += 1
        let (newDeal, events) = Deal.start(
            deck: deck, dealer: dealer, playerCount: playerCount, forced: nextDealIsForced, rules: rules)
        deal = newDeal
        if newDeal.isFinished { finishDeal() }
        return events
    }

    @discardableResult
    public mutating func apply(_ action: Action) throws -> [DealEvent] {
        guard winner == nil, var current = deal else {
            throw GameError.illegalAction("партия не идёт")
        }
        let events = try current.apply(action)
        deal = current
        if current.isFinished { finishDeal() }
        return events
    }

    // MARK: - Подсчёт

    private func nextDealer() -> Int {
        if rules.dealerRotation == .dealWinner, let last = history.last,
           [.made, .bait, .tie].contains(last.outcome) {
            let top = last.written.max() ?? 0
            let leaders = (0..<playerCount).filter { last.written[$0] == top }
            if leaders.count == 1 { return leaders[0] }
        }
        return next(dealer)
    }

    private mutating func finishDeal() {
        guard let deal, deal.isFinished else { return }
        let n = playerCount
        let zeros = [Int](repeating: 0, count: n)
        let noFlags = [Bool](repeating: false, count: n)
        var score = DealScore(
            number: dealCount, dealer: deal.dealer, outcome: .made, bidder: deal.bidder, trump: deal.trump,
            forced: deal.forced, cardPoints: zeros, tricksTaken: zeros, meldPoints: zeros, bellaPoints: zeros,
            raw: zeros, written: zeros, potAwarded: zeros, potAdded: 0, potAfter: pot, penalties: zeros,
            baitPenalty: noFlags, nakedPenalty: noFlags, naked: noFlags, bonus: zeros, fourSevensSeat: nil,
            change: zeros, totalsAfter: totals)

        if let seat = deal.fourSevensSeat {
            score.outcome = .fourSevens
            score.fourSevensSeat = seat
            if rules.fourSevens == .bonusAndRedeal {
                score.bonus[seat] = rules.fourSevensBonus
            }
            score.change = score.bonus
        } else if deal.allPassed {
            score.outcome = .allPassed
            allPassStreak += 1
        } else if let bidder = deal.bidder {
            allPassStreak = 0
            let settlement = Scoring.settle(
                cardPoints: deal.cardPoints, tricksTaken: deal.tricksTaken, declarations: deal.declarations,
                bidder: bidder, priority: deal.seatsFromDealer, rules: rules, pot: pot,
                baitCounts: baitCounts, nakedCounts: nakedCounts)
            score.outcome = settlement.outcome
            score.cardPoints = deal.cardPoints
            score.tricksTaken = deal.tricksTaken
            score.meldPoints = settlement.meldPoints
            score.bellaPoints = settlement.bellaPoints
            score.raw = settlement.raw
            score.written = settlement.written
            score.potAwarded = settlement.potAwarded
            score.potAdded = settlement.potAdded
            score.potAfter = settlement.potAfter
            score.penalties = settlement.penalties
            score.baitPenalty = settlement.baitPenalty
            score.nakedPenalty = settlement.nakedPenalty
            score.naked = settlement.naked
            score.change = settlement.change
            pot = settlement.potAfter
            baitCounts = settlement.baitCountsAfter
            nakedCounts = settlement.nakedCountsAfter
        }

        for seat in 0..<n { totals[seat] += score.change[seat] }
        score.totalsAfter = totals
        score.potAfter = pot
        history.append(score)
        checkWinner()
    }

    private mutating func checkWinner() {
        guard let top = totals.max(), top >= rules.targetScore else { return }
        let leaders = (0..<playerCount).filter { totals[$0] == top }
        if leaders.count == 1 { winner = leaders[0] }
    }
}
