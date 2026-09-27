import Foundation

/// Партия: последовательность сдач до победы одного из игроков.
///
/// Сохраняется в JSON (Storage приложения). Правило для новых хранимых полей: добавлять их
/// в `CodingKeys`, `encode(to:)` и `init(from:)` ниже, читать через `decodeIfPresent` со значением
/// по умолчанию — иначе после обновления старое сохранение не прочитается.
/// Совместимость со старыми форматами проверяет SaveCompatibilityTests (фикстуры не удалять).
public struct Match: Codable, Equatable, Sendable {
    public let rules: RuleSet
    public let playerCount: Int
    public var names: [String]

    public private(set) var totals: [Int]
    /// Сколько байтов у каждого за партию (для штрафа).
    public private(set) var baitCounts: [Int]
    /// Сколько раз каждый остался «голым» за партию (для штрафа).
    public private(set) var nakedCounts: [Int]
    /// Висячие очки, которые достанутся тому, кто наберёт больше всех в следующей сдаче.
    /// Не разыгранные до конца партии — сгорают (на победителя не влияют).
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

    /// Кто сдаёт следующую сдачу (если текущая окончена — с учётом правила смены сдающего;
    /// если сдачи ещё не было — текущий сдающий).
    public var upcomingDealer: Int {
        deal == nil ? dealer : nextDealer()
    }

    /// Последняя записанная сдача.
    public var lastScore: DealScore? { history.last }

    /// Лидеры, у которых поровну очков и не меньше нужного для победы: партия продолжается
    /// ещё одной сдачей. Пусто, если такой ничьей нет.
    public var tiedLeadersOverTarget: [Int] {
        guard winner == nil, let top = totals.max(), top >= rules.targetScore else { return [] }
        let leaders = (0..<playerCount).filter { totals[$0] == top }
        return leaders.count > 1 ? leaders : []
    }

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

        score.declarations = deal.declarations

        if let seat = deal.fourSevensSeat {
            score.outcome = .fourSevens
            score.fourSevensSeat = seat
            if rules.fourSevens == .bonusAndRedeal {
                score.bonus[seat] = rules.fourSevensBonus
            }
            score.change = score.bonus
            if !rules.fourSevensKeepsForcedStreak { allPassStreak = 0 }
        } else if deal.allPassed {
            score.outcome = .allPassed
            allPassStreak += 1
        } else if let bidder = deal.bidder {
            allPassStreak = 0
            let settlement = Scoring.settle(
                cardPoints: deal.cardPoints, tricksTaken: deal.tricksTaken, declarations: deal.declarations,
                bidder: bidder, priority: deal.leadOrder, rules: rules, pot: pot,
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
        score.baitCountsAfter = baitCounts
        score.nakedCountsAfter = nakedCounts
        history.append(score)
        checkWinner()
    }

    private mutating func checkWinner() {
        guard let top = totals.max(), top >= rules.targetScore else { return }
        let leaders = (0..<playerCount).filter { totals[$0] == top }
        if leaders.count == 1 { winner = leaders[0] }
    }
}

// MARK: - Сохранение

extension Match {
    /// Версия формата сохранения. 1 — первый формат (без ключа `schemaVersion`),
    /// 2 — терпимое чтение, новые поля итогов сдачи. Пишется в JSON как `"schemaVersion"`.
    public static let schemaVersion = 2

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case rules, playerCount, names, totals, baitCounts, nakedCounts, pot, dealer
        case allPassStreak, history, deal, winner, dealCount, rng
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Match.schemaVersion, forKey: .schemaVersion)
        try c.encode(rules, forKey: .rules)
        try c.encode(playerCount, forKey: .playerCount)
        try c.encode(names, forKey: .names)
        try c.encode(totals, forKey: .totals)
        try c.encode(baitCounts, forKey: .baitCounts)
        try c.encode(nakedCounts, forKey: .nakedCounts)
        try c.encode(pot, forKey: .pot)
        try c.encode(dealer, forKey: .dealer)
        try c.encode(allPassStreak, forKey: .allPassStreak)
        try c.encode(history, forKey: .history)
        try c.encodeIfPresent(deal, forKey: .deal)
        try c.encodeIfPresent(winner, forKey: .winner)
        try c.encode(dealCount, forKey: .dealCount)
        try c.encode(rng, forKey: .rng)
    }

    /// Терпимое чтение сохранения любой версии: обязателен только счёт партии (`totals`).
    /// Отсутствующие или нечитаемые поля берутся по умолчанию, нечитаемые строки истории
    /// пропускаются. Если не читается текущая сдача, партия продолжается с пересдачи:
    /// `deal == nil`, `needsNewDeal == true`, счёт и история сохраняются.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func optional<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            try? c.decodeIfPresent(T.self, forKey: key)
        }

        let totals = try c.decode([Int].self, forKey: .totals)
        let n = optional(Int.self, .playerCount) ?? totals.count
        guard (2...3).contains(n), totals.count == n else {
            throw DecodingError.dataCorruptedError(
                forKey: .totals, in: c, debugDescription: "Счёт не совпадает с числом игроков")
        }
        let seats = 0..<n
        let zeros = [Int](repeating: 0, count: n)
        func counts(_ key: CodingKeys) -> [Int] {
            guard let value = optional([Int].self, key), value.count == n else { return zeros }
            return value
        }

        rules = optional(RuleSet.self, .rules) ?? .house
        playerCount = n
        let storedNames = optional([String].self, .names) ?? []
        names = seats.map { $0 < storedNames.count ? storedNames[$0] : "Игрок \($0 + 1)" }
        self.totals = totals
        baitCounts = counts(.baitCounts)
        nakedCounts = counts(.nakedCounts)
        pot = max(0, optional(Int.self, .pot) ?? 0)
        allPassStreak = max(0, optional(Int.self, .allPassStreak) ?? 0)
        let lossy = optional([Lossy<DealScore>].self, .history) ?? []
        history = lossy.compactMap(\.value).filter { $0.change.count == n }
        if let w = optional(Int.self, .winner), seats.contains(w) { winner = w } else { winner = nil }
        rng = optional(SplitMix64.self, .rng)
            ?? SplitMix64(seed: UInt64(truncatingIfNeeded: totals.reduce(n) { $0 &* 31 &+ $1 }))

        var loadedDeal: Deal?
        if let d = optional(Deal.self, .deal), d.playerCount == n { loadedDeal = d }
        let dealWasLost = c.contains(.deal) && loadedDeal == nil
        deal = loadedDeal
        let storedDealer = optional(Int.self, .dealer)
        dealer = storedDealer.flatMap { seats.contains($0) ? $0 : nil } ?? loadedDeal?.dealer ?? 0
        let lastNumber = history.last?.number ?? 0
        // Без номера в сохранении: недоигранная сдача — следующий номер, записанная — последний.
        let storedCount = optional(Int.self, .dealCount)
            ?? loadedDeal.map { $0.isFinished ? lastNumber : lastNumber + 1 } ?? lastNumber
        dealCount = max(storedCount, lastNumber)

        if dealWasLost && winner == nil {
            if storedCount > lastNumber {
                // Не прочиталась недоигранная сдача: её пересдаёт тот же сдающий под тем же номером.
                dealCount = lastNumber
            } else if !history.isEmpty {
                // Сдача была уже записана: следующую сдаёт тот, кому положено по правилам.
                // (startNextDeal при deal == nil сдающего не меняет.)
                dealer = nextDealer()
            }
        }
    }
}

/// Элемент массива, который при ошибке чтения превращается в nil, а не роняет весь массив.
fileprivate struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
