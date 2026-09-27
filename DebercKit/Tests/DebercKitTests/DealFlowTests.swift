import XCTest
@testable import DebercKit

final class DealFlowTests: XCTestCase {
    let rules = RuleSet.house

    /// Две руки без четырёх семёрок; открыта Кч.
    private func twoPlayerDeck(dealer: Int = 0) -> [Card] {
        arrangedDeck(
            dealer: dealer,
            hands: [cards("Вч 9ч Тп 10п Кп 7т"), cards("7ч 8ч Тб 10б Кб Дт")],
            open: c("Кч"),
            prikup: [cards("Дп Вп 8т"), cards("9т 10т Вт")])
    }

    private func newMatch(players: Int = 2, dealer: Int = 0, rules customRules: RuleSet? = nil) -> Match {
        let names = Array(["Вы", "Саша", "Миша"].prefix(players))
        return Match(playerCount: players, names: names, rules: customRules ?? rules, seed: 42, firstDealer: dealer)
    }

    func testDealingAndFirstRoundTake() throws {
        var match = newMatch()
        match.startDeal(deck: twoPlayerDeck(), dealer: 0)
        let deal = try XCTUnwrap(match.deal)
        XCTAssertEqual(deal.phase, .bidding(round: 1))
        XCTAssertEqual(deal.turn, 1, "Первым говорит следующий после сдающего")
        XCTAssertEqual(deal.hands[0].count, 6)
        XCTAssertEqual(deal.hands[1].count, 6)
        XCTAssertFalse(deal.bottomCardVisible)

        let events = try match.apply(.take)
        XCTAssertTrue(events.contains(.trumpChosen(seat: 1, suit: .hearts, forced: false)))
        let after = try XCTUnwrap(match.deal)
        XCTAssertEqual(after.trump, .hearts)
        XCTAssertEqual(after.bidder, 1)
        XCTAssertEqual(after.hands.map(\.count), [9, 9])
        XCTAssertTrue(after.bottomCardVisible, "Нижняя карта открывается после прикупа")
        XCTAssertEqual(after.stock.count, 32 - 19)
        // У 1-го козырная семёрка — ему предлагается обмен.
        XCTAssertEqual(after.phase, .exchange)
        XCTAssertEqual(after.turn, 1)
    }

    func testSevenExchange() throws {
        var match = newMatch()
        match.startDeal(deck: twoPlayerDeck(), dealer: 0)
        try match.apply(.take)
        let events = try match.apply(.exchangeSeven(true))
        let deal = try XCTUnwrap(match.deal)
        XCTAssertEqual(deal.openCard, c("7ч"))
        XCTAssertTrue(deal.hands[1].contains(c("Кч")))
        XCTAssertFalse(deal.hands[1].contains(c("7ч")))
        XCTAssertEqual(deal.sevenExchange?.took, c("Кч"))
        XCTAssertTrue(events.contains { if case .playStarted = $0 { return true } else { return false } })
        XCTAssertEqual(deal.phase, .playing)
        XCTAssertEqual(deal.turn, 1, "Первым ходит следующий после сдающего")
    }

    func testSevenExchangeOnlyForOpenSuit() throws {
        var match = newMatch()
        match.startDeal(deck: twoPlayerDeck(), dealer: 0)
        try match.apply(.pass)   // 1-й
        try match.apply(.pass)   // 0-й (сдающий)
        XCTAssertEqual(match.deal?.phase, .bidding(round: 2))
        XCTAssertThrowsError(try match.apply(.name(.hearts)), "Открытую масть во 2-м круге назвать нельзя")
        try match.apply(.name(.spades))
        let deal = try XCTUnwrap(match.deal)
        XCTAssertEqual(deal.trump, .spades)
        XCTAssertEqual(deal.bidder, 1)
        XCTAssertEqual(deal.phase, .playing, "Козырь не по открытой карте — обмена нет")
    }

    func testAllPassRedealThenForcedOnThirdTime() throws {
        var match = newMatch()
        for expectedDealer in [0, 1] {
            match.startDeal(deck: twoPlayerDeck(dealer: expectedDealer), dealer: expectedDealer)
            XCTAssertEqual(match.deal?.forced, false)
            for _ in 0..<4 { try match.apply(.pass) }
            XCTAssertEqual(match.history.last?.outcome, .allPassed)
        }
        XCTAssertEqual(match.allPassStreak, 2)
        XCTAssertTrue(match.nextDealIsForced)
        let events = match.startNextDeal()
        let deal = try XCTUnwrap(match.deal)
        XCTAssertTrue(deal.forced)
        XCTAssertEqual(deal.dealer, 0, "Сдача переходит по кругу")
        if deal.fourSevensSeat != nil && deal.bidder == nil { return }
        XCTAssertEqual(deal.bidder, deal.dealer, "На обязах играет сдающий")
        XCTAssertEqual(deal.trump, deal.bids.first?.suit)
        XCTAssertEqual(deal.bids.map(\.kind), [.forced], "Торговли нет")
        XCTAssertTrue(events.contains { if case .trumpChosen(_, _, true) = $0 { return true } else { return false } })
    }

    func testStreakResetsAfterPlayedDeal() throws {
        var match = newMatch()
        match.startDeal(deck: twoPlayerDeck(), dealer: 0)
        for _ in 0..<4 { try match.apply(.pass) }
        XCTAssertEqual(match.allPassStreak, 1)
        match.startDeal(deck: twoPlayerDeck(dealer: 1), dealer: 1)
        try match.apply(.take)
        if match.deal?.phase == .exchange { try match.apply(.exchangeSeven(false)) }
        try playOutFirstLegal(&match)
        XCTAssertEqual(match.allPassStreak, 0)
    }

    func testFourSevensInFirstSixCards() throws {
        var match = newMatch()
        let deck = arrangedDeck(
            dealer: 0,
            hands: [cards("7ч 7п 7т 7б Тп 10п"), cards("8ч 8п 8т 8б Тб 10б")],
            open: c("Кч"),
            prikup: [cards("Дп Вп 9т"), cards("9ч 10т Вт")])
        let events = match.startDeal(deck: deck, dealer: 0)
        XCTAssertTrue(events.contains(.fourSevens(seat: 0)))
        XCTAssertEqual(match.history.last?.outcome, .fourSevens)
        XCTAssertEqual(match.totals, [100, 0])
        XCTAssertTrue(match.needsNewDeal)
        XCTAssertEqual(match.allPassStreak, 0)
    }

    func testFourSevensAfterPrikup() throws {
        var match = newMatch()
        let deck = arrangedDeck(
            dealer: 0,
            hands: [cards("7ч 7п 7т Тп 10п Кп"), cards("8ч 8п 8т Тб 10б Кб")],
            open: c("Кч"),
            prikup: [cards("7б Вп 9т"), cards("9ч 10т Вт")])
        match.startDeal(deck: deck, dealer: 0)
        XCTAssertEqual(match.deal?.phase, .bidding(round: 1))
        let events = try match.apply(.take)
        XCTAssertTrue(events.contains(.fourSevens(seat: 0)))
        XCTAssertEqual(match.totals, [100, 0])
        XCTAssertEqual(match.deal?.isFinished, true)
    }

    func testFourSevensRedealKeepsForcedStreak() throws {
        var match = newMatch()
        for d in [0, 1] {
            match.startDeal(deck: twoPlayerDeck(dealer: d), dealer: d)
            for _ in 0..<4 { try match.apply(.pass) }
        }
        let deck = arrangedDeck(
            dealer: 0,
            hands: [cards("7ч 7п 7т 7б Тп 10п"), cards("8ч 8п 8т 8б Тб 10б")],
            open: c("Кч"),
            prikup: [cards("Дп Вп 9т"), cards("9ч 10т Вт")])
        match.startDeal(deck: deck, dealer: 0)
        XCTAssertEqual(match.history.last?.outcome, .fourSevens)
        XCTAssertEqual(match.allPassStreak, 2)
        XCTAssertTrue(match.nextDealIsForced)
    }

    func testBellaAnnouncedWhenFirstCardPlayed() throws {
        var match = newMatch()
        // У 1-го король и дама червей; козыри — червы.
        let deck = arrangedDeck(
            dealer: 0,
            hands: [cards("Вч 9ч Тп 10п Кп 7т"), cards("Кч Дч Тб 10б Кб Дт")],
            open: c("8ч"),
            prikup: [cards("Дп Вп 8т"), cards("9т 10т Вт")])
        match.startDeal(deck: deck, dealer: 0)
        try match.apply(.take)
        let deal = try XCTUnwrap(match.deal)
        XCTAssertEqual(deal.declarations?.bellaSeat, 1)
        XCTAssertEqual(deal.turn, 1)
        let events = try match.apply(.play(c("Дч")))
        XCTAssertTrue(events.contains(.bella(seat: 1)))
    }

    func testFirstLeadVariantBidder() throws {
        var r = rules
        r.firstLead = .bidder
        var match = newMatch(players: 3, dealer: 0, rules: r)
        var deck = Card.deck
        var rng = SplitMix64(seed: 7)
        deck.shuffle(using: &rng)
        match.startDeal(deck: deck, dealer: 0)
        guard match.deal?.fourSevensSeat == nil else { return }
        try match.apply(.pass)   // 1
        try match.apply(.take)   // 2 берёт
        if match.deal?.phase == .exchange { try match.apply(.exchangeSeven(true)) }
        XCTAssertEqual(match.deal?.turn, 2)
    }

    func testThreePlayerDealing() throws {
        var match = newMatch(players: 3, dealer: 2)
        var deck = Card.deck
        var rng = SplitMix64(seed: 11)
        deck.shuffle(using: &rng)
        match.startDeal(deck: deck, dealer: 2)
        let deal = try XCTUnwrap(match.deal)
        guard deal.fourSevensSeat == nil else { return }
        XCTAssertEqual(deal.turn, 0)
        XCTAssertEqual(deal.seatsFromDealer, [0, 1, 2])
        try match.apply(.take)
        let after = try XCTUnwrap(match.deal)
        XCTAssertEqual(after.hands.map(\.count).reduce(0, +) , 27)
        XCTAssertEqual(after.stock.count, 4)
    }

    func testFullDealPointsAddUp() throws {
        var match = newMatch()
        match.startDeal(deck: twoPlayerDeck(), dealer: 0)
        try match.apply(.take)
        try match.apply(.exchangeSeven(true))
        let deal0 = try XCTUnwrap(match.deal)
        let inPlay = deal0.hands.flatMap { $0 }
        let expected = PlayRules.points(of: inPlay, trump: .hearts) + 10
        try playOutFirstLegal(&match)
        let deal = try XCTUnwrap(match.deal)
        XCTAssertTrue(deal.isFinished)
        XCTAssertEqual(deal.tricks.count, 9)
        XCTAssertEqual(deal.cardPoints.reduce(0, +), expected)
        let score = try XCTUnwrap(match.history.last)
        XCTAssertEqual(score.totalsAfter, match.totals)
    }

    func testIllegalCardThrows() throws {
        var match = newMatch()
        match.startDeal(deck: twoPlayerDeck(), dealer: 0)
        try match.apply(.take)
        try match.apply(.exchangeSeven(false))
        let deal = try XCTUnwrap(match.deal)
        // 1-й ходит, 0-й должен отвечать в масть.
        try match.apply(.play(c("Тб")))
        let follower = try XCTUnwrap(match.deal)
        XCTAssertEqual(follower.turn, 0)
        let illegal = follower.hands[0].first { !follower.legalCards(for: 0).contains($0) }
        if let illegal {
            XCTAssertThrowsError(try match.apply(.play(illegal)))
        }
        XCTAssertEqual(deal.bidder, 1)
    }
}

final class MatchTests: XCTestCase {

    func testRandomMatchesFinishWithConsistentScores() throws {
        for players in [2, 3] {
            for seed in 0..<40 {
                var rng = SplitMix64(seed: UInt64(seed) &* 7919 &+ 1)
                var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)),
                                  rules: .house, seed: UInt64(seed), firstDealer: nil)
                var guardCounter = 0
                while !match.isOver {
                    guardCounter += 1
                    XCTAssertLessThan(guardCounter, 20_000, "Партия не заканчивается")
                    if guardCounter > 20_000 { break }
                    if match.needsNewDeal {
                        match.startNextDeal()
                        continue
                    }
                    let deal = try XCTUnwrap(match.deal)
                    var actions = deal.legalActions()
                    if case .bidding = deal.phase, rng.next() % 3 != 0 {
                        actions = [.pass]   // чаще пасуем, чтобы проверить пересдачи и обязы
                    }
                    let action = actions[Int(rng.next() % UInt64(actions.count))]
                    try match.apply(action)
                }
                // Итоги сходятся с историей.
                var totals = [Int](repeating: 0, count: players)
                for score in match.history {
                    for seat in 0..<players { totals[seat] += score.change[seat] }
                    XCTAssertEqual(score.totalsAfter, totals)
                    if [.made, .bait, .hanging, .tie].contains(score.outcome) {
                        let cardSum = score.cardPoints.reduce(0, +)
                        XCTAssertGreaterThan(cardSum, 0)
                        XCTAssertEqual(score.tricksTaken.reduce(0, +), 9)
                    }
                }
                XCTAssertEqual(totals, match.totals)
                let winner = try XCTUnwrap(match.winner)
                XCTAssertGreaterThanOrEqual(match.totals[winner], 701)
                XCTAssertEqual(match.totals.max(), match.totals[winner])
                XCTAssertEqual(match.totals.filter { $0 == match.totals[winner] }.count, 1)
            }
        }
    }

    func testMatchIsCodable() throws {
        var match = Match(playerCount: 3, names: ["A", "B", "C"], rules: .house, seed: 5)
        match.startNextDeal()
        if let deal = match.deal, !deal.isFinished { try match.apply(deal.legalActions()[0]) }
        let data = try JSONEncoder().encode(match)
        let decoded = try JSONDecoder().decode(Match.self, from: data)
        XCTAssertEqual(decoded, match)
    }

    func testRulesDecodeWithMissingKeys() throws {
        let json = #"{"targetScore": 501, "overtrump": "unknownValue"}"#.data(using: .utf8)!
        let rules = try JSONDecoder().decode(RuleSet.self, from: json)
        XCTAssertEqual(rules.targetScore, 501)
        XCTAssertEqual(rules.overtrump, .never)
        XCTAssertEqual(rules.baitPenaltyEvery, 3)
    }

    func testHouseDefaults() {
        let r = RuleSet.house
        XCTAssertEqual(r.targetScore, 701)
        XCTAssertEqual(r.forcedDealAfterRedeals, 2)
        XCTAssertEqual(r.overtrump, .never)
        XCTAssertEqual(r.tieRule, .hangingBait)
        XCTAssertEqual(r.combosNeedTrick, .all)
        XCTAssertEqual(r.fourSevens, .bonusAndRedeal)
        XCTAssertEqual(r.bottomCard, .afterPrikup)
    }
}
