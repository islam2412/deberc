import XCTest
@testable import DebercKit

/// Сценарии на пограничные правила и инварианты подсчёта.
final class RuleEdgeCaseTests: XCTestCase {
    let rules = RuleSet.house

    private func match(players: Int = 2, dealer: Int = 0, rules custom: RuleSet? = nil) -> Match {
        Match(playerCount: players, names: Array(["Вы", "Саша", "Миша"].prefix(players)),
              rules: custom ?? rules, seed: 42, firstDealer: dealer)
    }

    /// Две руки без четырёх семёрок; открыта Кч.
    private func twoPlayerDeck(dealer: Int = 0) -> [Card] {
        arrangedDeck(
            dealer: dealer,
            hands: [cards("Вч 9ч Тп 10п Кп 7т"), cards("7ч 8ч Тб 10б Кб Дт")],
            open: c("Кч"),
            prikup: [cards("Дп Вп 8т"), cards("9т 10т Вт")])
    }

    private func passAll(_ m: inout Match) throws {
        while case .bidding = m.deal?.phase { try m.apply(.pass) }
    }

    // MARK: - Порядок хода и старшинство равных комбинаций

    func testLeadOrder() {
        var r = rules
        XCTAssertEqual(Deal.leadOrder(dealer: 0, bidder: 2, playerCount: 3, rules: r), [1, 2, 0])
        r.firstLead = .bidder
        XCTAssertEqual(Deal.leadOrder(dealer: 0, bidder: 2, playerCount: 3, rules: r), [2, 0, 1])
        XCTAssertEqual(Deal.leadOrder(dealer: 1, bidder: 1, playerCount: 2, rules: r), [1, 0])
    }

    /// Равные некозырные терцы: при «первый ход — играющий» записывает играющий (он ходит раньше).
    private func equalTerzesTwoPlayers(firstLead: RuleSet.FirstLead) throws -> Deal {
        var r = rules
        r.firstLead = firstLead
        var m = match(rules: r)
        m.startDeal(deck: arrangedDeck(
            dealer: 0,
            hands: [cards("7п 8п 9п Тт 10т Кт"), cards("7б 8б 9б Дт Вт 9т")],
            open: c("Кч"),
            prikup: [cards("Тб Дб 8т"), cards("Тп Дп 7т")]), dealer: 0)
        try m.apply(.pass)   // 1-й
        try m.apply(.take)   // сдающий берёт червы
        return try XCTUnwrap(m.deal)
    }

    func testEqualMeldsGoToFirstLeaderWhenBidderLeads() throws {
        let bidderLeads = try equalTerzesTwoPlayers(firstLead: .bidder)
        XCTAssertEqual(bidderLeads.phase, .playing)
        XCTAssertEqual(bidderLeads.turn, 0, "Первым ходит играющий")
        XCTAssertEqual(bidderLeads.declarations?.meldWinner, 0, "При равенстве — кто раньше ходит")
        let afterDealer = try equalTerzesTwoPlayers(firstLead: .afterDealer)
        XCTAssertEqual(afterDealer.turn, 1)
        XCTAssertEqual(afterDealer.declarations?.meldWinner, 1)
    }

    func testEqualMeldsThreePlayersBidderLeads() throws {
        func run(_ firstLead: RuleSet.FirstLead) throws -> Deal {
            var r = rules
            r.firstLead = firstLead
            var m = match(players: 3, rules: r)
            m.startDeal(deck: arrangedDeck(
                dealer: 0,
                hands: [cards("Тт 10т 8т Дб Кп Тч"), cards("7п 8п 9п Кт Дт Вб"), cards("7б 8б 9б 10п Тп 9т")],
                open: c("Кч"),
                prikup: [cards("Вт 7ч Тб"), cards("Кб 9ч 10ч"), cards("8ч Дч 7т")]), dealer: 0)
            try m.apply(.pass)   // 1-й
            try m.apply(.take)   // 2-й берёт червы
            if m.deal?.phase == .exchange { try m.apply(.exchangeSeven(false)) }
            return try XCTUnwrap(m.deal)
        }
        let bidder = try run(.bidder)
        XCTAssertEqual(bidder.turn, 2)
        XCTAssertEqual(bidder.declarations?.meldWinner, 2)
        let afterDealer = try run(.afterDealer)
        XCTAssertEqual(afterDealer.turn, 1)
        XCTAssertEqual(afterDealer.declarations?.meldWinner, 1)
    }

    // MARK: - Обмен семёрки, бэла и терц

    func testSevenExchangeCreatesBellaAndTerz() throws {
        var m = match()
        m.startDeal(deck: arrangedDeck(
            dealer: 0,
            hands: [cards("8ч 9ч Тп 9п 7п 7т"), cards("7ч Кч Вч Тб 10б Кб")],
            open: c("Дч"),
            prikup: [cards("Дп 8б 8т"), cards("9т Дт 8п")]), dealer: 0)
        try m.apply(.take)
        XCTAssertEqual(m.deal?.phase, .exchange)
        try m.apply(.exchangeSeven(true))
        let deal = try XCTUnwrap(m.deal)
        XCTAssertEqual(deal.declarations?.bellaSeat, 1)
        XCTAssertEqual(deal.declarations?.melds[1], [Meld(suit: .hearts, low: .jack, length: 3)])
        XCTAssertEqual(deal.declarations?.meldWinner, 1)
        XCTAssertTrue(deal.initialHands[1].contains(c("Дч")))
        XCTAssertFalse(deal.initialHands[1].contains(c("7ч")))

        var r = rules
        r.bellaInMelds = false
        var strict = match(rules: r)
        strict.startDeal(deck: arrangedDeck(
            dealer: 0,
            hands: [cards("8ч 9ч Тп 9п 7п 7т"), cards("7ч Кч Вч Тб 10б Кб")],
            open: c("Дч"),
            prikup: [cards("Дп 8б 8т"), cards("9т Дт 8п")]), dealer: 0)
        try strict.apply(.take)
        try strict.apply(.exchangeSeven(true))
        let noTerz = try XCTUnwrap(strict.deal)
        XCTAssertEqual(noTerz.declarations?.bellaSeat, 1)
        XCTAssertEqual(noTerz.declarations?.melds[1], [], "Король и дама бэлы в терц не входят")
        XCTAssertNil(noTerz.declarations?.meldWinner)
    }

    func testInitialHandsStayDuringPlay() throws {
        var m = match()
        m.startDeal(deck: twoPlayerDeck(), dealer: 0)
        try m.apply(.take)
        try m.apply(.exchangeSeven(true))
        let start = try XCTUnwrap(m.deal).initialHands.map { Set($0) }
        XCTAssertEqual(start.map(\.count), [9, 9])
        for _ in 0..<5 {
            let d = try XCTUnwrap(m.deal)
            try m.apply(.play(d.legalCards(for: d.turn)[0]))
        }
        XCTAssertEqual(try XCTUnwrap(m.deal).initialHands.map { Set($0) }, start)
        try playOutFirstLegal(&m)
        let finished = try XCTUnwrap(m.deal)
        XCTAssertEqual(finished.initialHands.map { Set($0) }, start)
        XCTAssertEqual(finished.lastTrick, finished.tricks.last)
        XCTAssertEqual(finished.lastTrick?.card(of: 0) != nil, true)
    }

    // MARK: - Пересдачи, обязы и четыре семёрки

    private func fourSevensAfterPrikupDeck() -> [Card] {
        arrangedDeck(
            dealer: 0,
            hands: [cards("7ч 7п 7т Тп 10п Кп"), cards("8ч 8п 8т Тб 10б Кб")],
            open: c("Кч"),
            prikup: [cards("7б Вп 9т"), cards("9ч 10т Вт")])
    }

    func testForcedDealWithFourSevensKeepsForcedAndRotatesDealer() throws {
        var m = match()
        for d in [0, 1] {
            m.startDeal(deck: twoPlayerDeck(dealer: d), dealer: d)
            try passAll(&m)
        }
        XCTAssertTrue(m.nextDealIsForced)
        let events = m.startDeal(deck: fourSevensAfterPrikupDeck(), dealer: 0)
        XCTAssertTrue(events.contains(.fourSevens(seat: 0)))
        let score = try XCTUnwrap(m.history.last)
        XCTAssertEqual(score.outcome, .fourSevens)
        XCTAssertTrue(score.forced)
        XCTAssertEqual(m.totals, [100, 0])
        XCTAssertEqual(m.allPassStreak, 2, "Пересдача из-за 4 семёрок не сбрасывает счёт до обязов")
        XCTAssertTrue(m.nextDealIsForced)
        XCTAssertEqual(m.upcomingDealer, 1)
        XCTAssertEqual(Narrator.message(for: .fourSevens(seat: 0), in: m, humanSeat: 0),
                       "Вы: четыре семёрки! +100 и пересдача. Следующая — на обязах: играет Саша")
        m.startNextDeal()
        let next = try XCTUnwrap(m.deal)
        XCTAssertEqual(next.dealer, 1)
        XCTAssertTrue(next.forced, "Обязы переходят к новому сдающему")
    }

    func testFourSevensResetsForcedStreakWhenSwitchedOff() throws {
        var r = rules
        r.fourSevensKeepsForcedStreak = false
        var m = match(rules: r)
        for d in [0, 1] {
            m.startDeal(deck: twoPlayerDeck(dealer: d), dealer: d)
            try passAll(&m)
        }
        m.startDeal(deck: fourSevensAfterPrikupDeck(), dealer: 0)
        XCTAssertEqual(m.history.last?.outcome, .fourSevens)
        XCTAssertEqual(m.allPassStreak, 0)
        XCTAssertFalse(m.nextDealIsForced)
        XCTAssertEqual(Narrator.message(for: .fourSevens(seat: 0), in: m, humanSeat: 0), "Вы: четыре семёрки! +100 и пересдача")
    }

    func testThreePlayersSixPassesRedeal() throws {
        var m = match(players: 3)
        var deck = Card.deck
        var rng = SplitMix64(seed: 11)
        deck.shuffle(using: &rng)
        m.startDeal(deck: deck, dealer: 0)
        guard m.deal?.fourSevensSeat == nil else { return }
        var passes = 0
        while case .bidding = m.deal?.phase {
            XCTAssertEqual(m.deal?.turn, [1, 2, 0][passes % 3], "Говорят по кругу, начиная со следующего после сдающего")
            try m.apply(.pass)
            passes += 1
        }
        XCTAssertEqual(passes, 6)
        XCTAssertEqual(m.history.last?.outcome, .allPassed)
        XCTAssertEqual(m.allPassStreak, 1)
        XCTAssertEqual(m.upcomingDealer, 1)
        m.startNextDeal()
        XCTAssertEqual(m.deal?.dealer, 1)
    }

    // MARK: - Смена сдающего

    func testDealWinnerDealsNext() throws {
        var r = rules
        r.dealerRotation = .dealWinner
        var m = match(rules: r)
        m.startDeal(deck: twoPlayerDeck(), dealer: 0)
        try m.apply(.take)
        try m.apply(.exchangeSeven(true))
        try playOutFirstLegal(&m)
        let score = try XCTUnwrap(m.history.last)
        let top = try XCTUnwrap(score.written.max())
        let leaders = (0..<2).filter { score.written[$0] == top }
        let expected = leaders.count == 1 ? leaders[0] : 1
        XCTAssertEqual(m.upcomingDealer, expected)
        m.startNextDeal()
        XCTAssertEqual(m.deal?.dealer, expected)
    }

    func testDealWinnerRotationAfterAllPassGoesAround() throws {
        var r = rules
        r.dealerRotation = .dealWinner
        var m = match(rules: r)
        m.startDeal(deck: twoPlayerDeck(), dealer: 0)
        try passAll(&m)
        XCTAssertEqual(m.upcomingDealer, 1, "После пересдачи — следующий по кругу")
    }

    // MARK: - Ничья выше цели

    func testTieAboveTargetContinues() throws {
        var r = rules
        r.tieRule = .eachKeeps
        r.targetScore = 1
        var found = false
        for seed in 0..<5_000 where !found {
            var m = Match(playerCount: 2, names: ["Вы", "Саша"], rules: r, seed: UInt64(seed))
            while m.history.isEmpty {
                if m.needsNewDeal { m.startNextDeal() } else { try m.apply(try XCTUnwrap(m.deal).legalActions()[0]) }
            }
            guard m.history.last?.outcome == .tie else { continue }
            found = true
            XCTAssertEqual(m.totals[0], m.totals[1])
            XCTAssertNil(m.winner, "Поровну выше цели — победителя нет")
            XCTAssertTrue(m.needsNewDeal)
            XCTAssertEqual(m.tiedLeadersOverTarget, [0, 1])
            let lines = Narrator.outcomeNotes(try XCTUnwrap(m.history.last), names: m.names, humanSeat: 0, rules: r)
            XCTAssertTrue(lines.contains { $0.contains("поровну, играется ещё одна сдача") }, "\(lines)")
            m.startNextDeal()
            XCTAssertNotNil(m.deal)
        }
        XCTAssertTrue(found, "Не нашлась ничейная сдача")
    }

    // MARK: - Дележ байта

    func testSplitHalfOddPointGoesToEarlierInLeadOrder() {
        var r = rules
        r.baitRecipient = .splitHalf
        func settle(_ priority: [Int]) -> Settlement {
            Scoring.settle(cardPoints: [41, 60, 50], tricksTaken: [3, 3, 3], declarations: nil, bidder: 0,
                           priority: priority, rules: r, pot: 0, baitCounts: [0, 0, 0], nakedCounts: [0, 0, 0])
        }
        XCTAssertEqual(settle([1, 2, 0]).written, [0, 81, 70])
        XCTAssertEqual(settle([2, 0, 1]).written, [0, 80, 71])
    }

    // MARK: - Инварианты подсчёта на случайных партиях

    func testRandomMatchInvariants() throws {
        for players in [2, 3] {
            for seed in 0..<40 {
                var rng = SplitMix64(seed: UInt64(seed) &* 104_729 &+ 3)
                var m = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)),
                              rules: .house, seed: UInt64(seed) &+ 1_000)
                var steps = 0
                var checked = 0
                while !m.isOver && steps < 20_000 {
                    steps += 1
                    if m.needsNewDeal {
                        m.startNextDeal()
                    } else {
                        let deal = try XCTUnwrap(m.deal)
                        var actions = deal.legalActions()
                        if case .bidding = deal.phase, rng.next() % 3 != 0 { actions = [.pass] }
                        try m.apply(actions[Int(rng.next() % UInt64(actions.count))])
                    }
                    if steps % 7 == 0 {
                        let copy = try JSONDecoder().decode(Match.self, from: JSONEncoder().encode(m))
                        XCTAssertEqual(copy, m, "Сохранение туда-обратно, seed \(seed)")
                    }
                    guard m.history.count > checked else { continue }
                    let score = m.history[checked]
                    let potBefore = checked > 0 ? m.history[checked - 1].potAfter : 0
                    checked += 1
                    XCTAssertEqual(score.potAfter, potBefore - score.potAwarded.reduce(0, +) + score.potAdded)
                    XCTAssertEqual(score.baitCountsAfter, m.baitCounts)
                    XCTAssertEqual(score.nakedCountsAfter, m.nakedCounts)
                    if score.wasPlayed {
                        let deal = try XCTUnwrap(m.deal)
                        let inPlay = PlayRules.points(of: deal.initialHands.flatMap { $0 }, trump: try XCTUnwrap(deal.trump))
                        XCTAssertEqual(score.cardPoints.reduce(0, +), inPlay + 10, "Карты в игре + 10 за последнюю")
                        XCTAssertEqual(score.tricksTaken.reduce(0, +), 9)
                        XCTAssertEqual(score.written.reduce(0, +) + score.potAdded, score.raw.reduce(0, +))
                        XCTAssertEqual(score.change, (0..<players).map { score.written[$0] + score.potAwarded[$0] + score.penalties[$0] })
                        XCTAssertNotNil(score.declarations)
                        XCTAssertEqual(deal.initialHands.map(\.count), [Int](repeating: 9, count: players))
                        XCTAssertEqual(Set(deal.initialHands.flatMap { $0 }).count, 9 * players)
                    } else if score.outcome == .fourSevens {
                        XCTAssertEqual(score.change, score.bonus)
                    }
                }
                XCTAssertTrue(m.isOver, "Партия не закончилась, seed \(seed)")
            }
        }
    }
}
