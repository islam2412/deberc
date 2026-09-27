import XCTest
@testable import DebercKit

final class CardsTests: XCTestCase {

    func testDeckHas32UniqueCards() {
        XCTAssertEqual(Card.deck.count, 32)
        XCTAssertEqual(Set(Card.deck).count, 32)
        for card in Card.deck {
            XCTAssertEqual(Card(id: card.id), card)
        }
    }

    func testDeckPointsAre152ForAnyTrump() {
        for trump in Suit.allCases {
            XCTAssertEqual(PlayRules.points(of: Card.deck, trump: trump), 152)
        }
    }

    func testTrumpPointsAndOrder() {
        let trump = Suit.hearts
        XCTAssertEqual(c("Вч").points(trump: trump), 20)
        XCTAssertEqual(c("9ч").points(trump: trump), 14)
        XCTAssertEqual(c("Тч").points(trump: trump), 11)
        XCTAssertEqual(c("10ч").points(trump: trump), 10)
        XCTAssertEqual(c("Кч").points(trump: trump), 4)
        XCTAssertEqual(c("Дч").points(trump: trump), 3)
        XCTAssertEqual(c("8ч").points(trump: trump), 0)
        let trumpOrder = cards("Вч 9ч Тч 10ч Кч Дч 8ч 7ч").map { $0.power(trump: trump) }
        XCTAssertEqual(trumpOrder, trumpOrder.sorted(by: >))
    }

    func testPlainPointsAndOrder() {
        let trump = Suit.hearts
        XCTAssertEqual(c("Вп").points(trump: trump), 2)
        XCTAssertEqual(c("9п").points(trump: trump), 0)
        XCTAssertEqual(c("Тп").points(trump: trump), 11)
        let plainOrder = cards("Тп 10п Кп Дп Вп 9п 8п 7п").map { $0.power(trump: trump) }
        XCTAssertEqual(plainOrder, plainOrder.sorted(by: >))
    }

    func testDisplaySortingPutsTrumpFirst() {
        let hand = cards("7п Тч Вч 9ч Кб").sortedForDisplay(trump: .hearts)
        XCTAssertEqual(hand.first, c("Вч"))
        XCTAssertEqual(hand[1], c("9ч"))
    }

    func testDisplayOrderAlternatesSuitColors() {
        for trump in Suit.allCases {
            let order = Suit.displayOrder(trump: trump)
            XCTAssertEqual(order.first, trump, "Козыри — слева")
            XCTAssertEqual(Set(order), Set(Suit.allCases))
            for i in 1..<order.count {
                XCTAssertNotEqual(order[i].isRed, order[i - 1].isRed, "Соседние масти разного цвета при козыре \(trump)")
            }
        }
        XCTAssertEqual(Suit.displayOrder(trump: .clubs), [.clubs, .hearts, .spades, .diamonds])
        XCTAssertEqual(Suit.displayOrder(trump: .hearts), [.hearts, .spades, .diamonds, .clubs])
        XCTAssertEqual(Suit.displayOrder(trump: nil), [.spades, .hearts, .clubs, .diamonds])
    }

    func testDisplaySortingFromScreenshot() {
        // Рука со скриншота аудита: козырь ♣, пики и трефы больше не стоят рядом.
        let hand = cards("10п Кп Дп Вп 8п Вч 8б Дт").sortedForDisplay(trump: .clubs)
        XCTAssertEqual(hand, cards("Дт Вч 10п Кп Дп Вп 8п 8б"))
        let trumps = cards("7т Тт Вт 9т 10т").sortedForDisplay(trump: .clubs)
        XCTAssertEqual(trumps, cards("Вт 9т Тт 10т 7т"), "Козыри по старшинству: В 9 Т 10 … 7")
    }

    func testDisplaySortingNaturalOrderShowsRuns() {
        let hand = cards("10п Кп Дп Вп 8п").sortedForDisplay(trump: .clubs, naturalOrder: true)
        XCTAssertEqual(hand, cards("Кп Дп Вп 10п 8п"))
        let noTrump = cards("9б Кп Тч 7п").sortedForDisplay(trump: nil)
        XCTAssertEqual(noTrump, cards("Кп 7п Тч 9б"))
    }
}

final class CombinationsTests: XCTestCase {
    let rules = RuleSet.house

    func testFindsTerzAndFifty() {
        let melds = Combinations.melds(in: cards("7ч 8ч 9ч Кп Дп Вп 10п Тб 7б"))
        XCTAssertEqual(melds.count, 2)
        XCTAssertTrue(melds.contains(Meld(suit: .hearts, low: .seven, length: 3)))
        XCTAssertTrue(melds.contains(Meld(suit: .spades, low: .ten, length: 4)))
        let points = melds.map { $0.points(rules) }.sorted()
        XCTAssertEqual(points, [20, 50])
    }

    func testLongRunIsOneFifty() {
        let melds = Combinations.melds(in: cards("7т 8т 9т 10т Вт Дт Кб Тб 7ч"))
        XCTAssertEqual(melds, [Meld(suit: .clubs, low: .seven, length: 6)])
        XCTAssertEqual(melds[0].points(rules), 50)
        var withHundred = rules
        withHundred.hundredForFive = true
        XCTAssertEqual(melds[0].points(withHundred), 100)
    }

    func testTwoTerzesInOneSuitWithGap() {
        let melds = Combinations.melds(in: cards("7б 8б 9б Вб Дб Кб 7ч 8п Тт"))
        XCTAssertEqual(melds.count, 2)
    }

    func testRunUsesNaturalOrderNotTrickOrder() {
        // Т-10-К — не терц; Т-К-Д — терц.
        XCTAssertTrue(Combinations.melds(in: cards("Тп 10п Кп")).isEmpty)
        XCTAssertEqual(Combinations.melds(in: cards("Тп Кп Дп")).count, 1)
    }

    func testFiftyBeatsTerz() {
        let fifty = Meld(suit: .spades, low: .seven, length: 4)
        let terz = Meld(suit: .hearts, low: .queen, length: 3)
        XCTAssertGreaterThan(Combinations.compare(fifty, terz, trump: .hearts, rules: rules), 0)
    }

    func testLongerFirstVersusValueThenTopCard() {
        let five = Meld(suit: .spades, low: .seven, length: 5)   // 7-8-9-10-В
        let four = Meld(suit: .clubs, low: .ten, length: 4)       // 10-В-Д-К
        XCTAssertGreaterThan(Combinations.compare(five, four, trump: .hearts, rules: rules), 0)
        var classic = rules
        classic.meldOrder = .valueThenTopCard
        XCTAssertLessThan(Combinations.compare(five, four, trump: .hearts, rules: classic), 0)
    }

    func testHigherTopCardWins() {
        let akq = Meld(suit: .spades, low: .queen, length: 3)
        let kqj = Meld(suit: .clubs, low: .jack, length: 3)
        XCTAssertGreaterThan(Combinations.compare(akq, kqj, trump: .hearts, rules: rules), 0)
    }

    func testTrumpWinsOnEqualMelds() {
        let trumpTerz = Meld(suit: .hearts, low: .eight, length: 3)
        let plainTerz = Meld(suit: .spades, low: .eight, length: 3)
        XCTAssertGreaterThan(Combinations.compare(trumpTerz, plainTerz, trump: .hearts, rules: rules), 0)
    }

    func testEqualPlainMeldsGoToEarlierSeat() {
        let melds: [[Meld]] = [
            [Meld(suit: .spades, low: .eight, length: 3)],
            [],
            [Meld(suit: .clubs, low: .eight, length: 3)],
        ]
        // Сдаёт 0-й: первым ходит 1-й, затем 2-й, затем 0-й.
        let winner = Combinations.winningSeat(meldsBySeat: melds, trump: .hearts, rules: rules, priority: [1, 2, 0])
        XCTAssertEqual(winner, 2)
    }

    func testWinnerScoresAllOwnMelds() {
        let hands = [
            cards("7ч 8ч 9ч 7п 8п 9п 10п Тб Дп"),   // терц + полтинник = 70
            cards("Вт Дт Кт Тт 7б 8б 9б Кч Дч"),     // полтинник от туза — старше
        ]
        let decl = Combinations.declarations(hands: hands, trump: .diamonds, rules: rules, priority: [1, 0])
        XCTAssertEqual(decl.meldWinner, 1)
        XCTAssertEqual(decl.meldPoints(for: 1, rules: rules), 70)
        XCTAssertEqual(decl.meldPoints(for: 0, rules: rules), 0)
    }

    func testBellaDetection() {
        XCTAssertTrue(Combinations.hasBella(cards("Кч Дч 7п"), trump: .hearts))
        XCTAssertFalse(Combinations.hasBella(cards("Кч Дп 7п"), trump: .hearts))
    }

    func testBellaCardsExcludedFromRunsWhenRuleOff() {
        var r = rules
        r.bellaInMelds = false
        let hand = cards("10ч Вч Дч Кч 7п 8т 9б Тп 7б")
        XCTAssertEqual(Combinations.melds(in: hand, trump: .hearts, rules: rules), [Meld(suit: .hearts, low: .ten, length: 4)])
        XCTAssertEqual(Combinations.melds(in: hand, trump: .hearts, rules: r), [], "10-В без короля и дамы — не терц")
        // Без бэлы (козырь другой) король и дама в последовательности участвуют.
        XCTAssertEqual(Combinations.melds(in: hand, trump: .spades, rules: r), [Meld(suit: .hearts, low: .ten, length: 4)])
        let decl = Combinations.declarations(hands: [hand, cards("7ч 8ч 9ч Тч 8п 9п 10п Вп Дп")],
                                             trump: .hearts, rules: r, priority: [1, 0])
        XCTAssertEqual(decl.bellaSeat, 0)
        XCTAssertEqual(decl.melds[0], [])
        XCTAssertEqual(decl.meldWinner, 1)
    }

    func testBellaCardsMayBePartOfRun() {
        let hand = cards("Вч Дч Кч 7п 8т 9б Тп 10т 7б")
        let decl = Combinations.declarations(hands: [hand, cards("7ч 8ч 9ч 10ч Тч 8п 9п 10п Вп")],
                                             trump: .hearts, rules: rules, priority: [1, 0])
        XCTAssertEqual(decl.bellaSeat, 0)
        XCTAssertEqual(decl.melds[0], [Meld(suit: .hearts, low: .jack, length: 3)])
    }
}

final class PlayRulesTests: XCTestCase {
    let rules = RuleSet.house

    func testViolationReasons() {
        // Есть масть хода — нужно ходить в неё.
        XCTAssertEqual(PlayRules.violation(of: c("Вп"), hand: cards("7ч Тч Вп"), trick: [c("Кч")], trump: .spades, rules: rules),
                       .mustFollowSuit(.hearts))
        // Масти нет — нужно бить козырем.
        XCTAssertEqual(PlayRules.violation(of: c("9т"), hand: cards("7п Вп 9т"), trick: [c("Кч")], trump: .spades, rules: rules),
                       .mustTrump(.spades))
        // Допустимая карта — нет причины.
        XCTAssertNil(PlayRules.violation(of: c("7п"), hand: cards("7п Вп 9т"), trick: [c("Кч"), c("Тп")], trump: .spades, rules: rules))
        // Правило «перебивать всегда»: нужен козырь старше туза.
        var strict = rules
        strict.overtrump = .always
        XCTAssertEqual(PlayRules.violation(of: c("7п"), hand: cards("7п Вп 9т"), trick: [c("Кч"), c("Тп")], trump: .spades, rules: strict),
                       .mustOvertrump(over: c("Тп")))
        // Ход с козыря при «перебивать на ход с козыря»: младший козырь нельзя, некозырь — нужно в масть.
        var trumpLead = rules
        trumpLead.overtrump = .trumpLeadOnly
        XCTAssertEqual(PlayRules.violation(of: c("7п"), hand: cards("7п Вп 9т"), trick: [c("Тп")], trump: .spades, rules: trumpLead),
                       .mustOvertrump(over: c("Тп")))
        XCTAssertEqual(PlayRules.violation(of: c("9т"), hand: cards("7п Вп 9т"), trick: [c("Тп")], trump: .spades, rules: trumpLead),
                       .mustFollowSuit(.spades))
    }

    func testMustFollowSuit() {
        let hand = cards("7ч Тч Вп 9т")
        let legal = PlayRules.legalCards(hand: hand, trick: [c("Кч")], trump: .spades, rules: rules)
        XCTAssertEqual(Set(legal), Set(cards("7ч Тч")))
    }

    func testMustTrumpWhenVoidButAnyTrump() {
        let hand = cards("7п Вп 9т Дб")
        // Во взятке уже лежит козырный туз — перебивать не обязательно.
        let legal = PlayRules.legalCards(hand: hand, trick: [c("Кч"), c("Тп")], trump: .spades, rules: rules)
        XCTAssertEqual(Set(legal), Set(cards("7п Вп")))
    }

    func testTrumpLeadNoObligationToOvertrump() {
        let hand = cards("7п Вп 9т")
        let legal = PlayRules.legalCards(hand: hand, trick: [c("Тп")], trump: .spades, rules: rules)
        XCTAssertEqual(Set(legal), Set(cards("7п Вп")))
    }

    func testOvertrumpAlwaysVariant() {
        var strict = rules
        strict.overtrump = .always
        let hand = cards("7п Вп 9т")
        let legal = PlayRules.legalCards(hand: hand, trick: [c("Кч"), c("Тп")], trump: .spades, rules: strict)
        XCTAssertEqual(legal, [c("Вп")])
        var trumpLeadOnly = rules
        trumpLeadOnly.overtrump = .trumpLeadOnly
        let legal2 = PlayRules.legalCards(hand: hand, trick: [c("Кч"), c("Тп")], trump: .spades, rules: trumpLeadOnly)
        XCTAssertEqual(Set(legal2), Set(cards("7п Вп")))
        let legal3 = PlayRules.legalCards(hand: hand, trick: [c("Тп")], trump: .spades, rules: trumpLeadOnly)
        XCTAssertEqual(legal3, [c("Вп")])
    }

    func testAnyCardWhenNoSuitAndNoTrump() {
        let hand = cards("7т 9б")
        let legal = PlayRules.legalCards(hand: hand, trick: [c("Кч")], trump: .spades, rules: rules)
        XCTAssertEqual(Set(legal), Set(hand))
    }

    func testNoTrumpObligationVariant() {
        var loose = rules
        loose.mustTrump = false
        let hand = cards("7п 9б")
        let legal = PlayRules.legalCards(hand: hand, trick: [c("Кч")], trump: .spades, rules: loose)
        XCTAssertEqual(Set(legal), Set(hand))
    }

    func testTrickWinner() {
        XCTAssertEqual(PlayRules.winningIndex(cards("Кч Тч 10ч"), trump: .spades), 1)
        XCTAssertEqual(PlayRules.winningIndex(cards("Кч Тб 7п"), trump: .spades), 2)
        XCTAssertEqual(PlayRules.winningIndex(cards("9п Тп Вп"), trump: .spades), 2)
        XCTAssertEqual(PlayRules.winningIndex(cards("9п Тп"), trump: .spades), 0)
        XCTAssertEqual(PlayRules.winningIndex(cards("7ч Тб"), trump: .spades), 0)
    }
}
