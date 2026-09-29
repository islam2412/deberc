import XCTest
@testable import DebercKit

/// Тексты итогов сдачи, числа со склонением, причины недопустимого хода.
final class NarratorNotesTests: XCTestCase {
    let names = ["Вы", "Саша", "Миша"]

    /// Итог сдачи для проверки текстов.
    private func score(
        outcome: DealScore.Outcome, bidder: Int? = 0, players n: Int = 2,
        tricks: [Int]? = nil, raw: [Int]? = nil, written: [Int]? = nil,
        meldPoints: [Int]? = nil, bellaPoints: [Int]? = nil,
        potAdded: Int = 0, potAfter: Int = 0,
        naked: [Bool]? = nil, nakedPenalty: [Bool]? = nil,
        totalsAfter: [Int], declarations: Declarations? = nil,
        baitCountsAfter: [Int]? = nil, nakedCountsAfter: [Int]? = nil
    ) -> DealScore {
        let zeros = [Int](repeating: 0, count: n)
        let no = [Bool](repeating: false, count: n)
        return DealScore(
            number: 5, dealer: 1, outcome: outcome, bidder: bidder, trump: .hearts, forced: false,
            cardPoints: raw ?? zeros, tricksTaken: tricks ?? [Int](repeating: 3, count: n),
            meldPoints: meldPoints ?? zeros, bellaPoints: bellaPoints ?? zeros,
            raw: raw ?? zeros, written: written ?? raw ?? zeros, potAwarded: zeros,
            potAdded: potAdded, potAfter: potAfter, penalties: zeros,
            baitPenalty: no, nakedPenalty: nakedPenalty ?? no, naked: naked ?? no,
            bonus: zeros, fourSevensSeat: nil, change: written ?? raw ?? zeros, totalsAfter: totalsAfter,
            declarations: declarations, baitCountsAfter: baitCountsAfter, nakedCountsAfter: nakedCountsAfter)
    }

    private func notes(_ s: DealScore, rules: RuleSet = .house) -> [String] {
        Narrator.outcomeNotes(s, names: names, humanSeat: 0, rules: rules)
    }

    // MARK: - Числа

    func testPointsDeclension() {
        let expected: [Int: String] = [
            0: "0 очков", 1: "1 очко", 2: "2 очка", 4: "4 очка", 5: "5 очков", 11: "11 очков", 12: "12 очков",
            14: "14 очков", 21: "21 очко", 22: "22 очка", 81: "81 очко", 100: "100 очков", 111: "111 очков",
            1001: "1001 очко", -1: "\u{2212}1 очко", -100: "\u{2212}100 очков",
        ]
        for (n, text) in expected { XCTAssertEqual(Narrator.points(n), text) }
    }

    func testSignedNumbers() {
        XCTAssertEqual(Narrator.signed(47), "+47")
        XCTAssertEqual(Narrator.signed(-100), "\u{2212}100")
        XCTAssertEqual(Narrator.signed(0), "0")
        XCTAssertEqual(Narrator.number(-5), "\u{2212}5")
    }

    func testBidderPhraseAndCaption() {
        XCTAssertEqual(Narrator.bidderPhrase(seat: 0, names: names, humanSeat: 0), "играете вы")
        XCTAssertEqual(Narrator.bidderPhrase(seat: 1, names: names, humanSeat: 0), "играет Саша")
        var s = score(outcome: .made, bidder: 0, totalsAfter: [100, 50])
        s.forced = true
        XCTAssertEqual(Narrator.dealCaption(s, names: names, humanSeat: 0), "Сдача 5 · играете вы ♥ (обязы)")
        s.outcome = .fourSevens
        XCTAssertEqual(Narrator.dealCaption(s, names: names, humanSeat: 0), "Сдача 5", "При 4 семёрках сдача не игралась")
    }

    // MARK: - Итоги сдачи

    func testBaitNotesNameReceiverAndCountBaits() {
        let s = score(outcome: .bait, bidder: 1, raw: [102, 60], written: [162, 0], totalsAfter: [300, 200],
                      baitCountsAfter: [0, 2])
        let lines = notes(s)
        XCTAssertTrue(lines.contains("Очки играющего (60) получаете вы"), "\(lines)")
        XCTAssertTrue(lines.contains("Саша: 2-й байт за партию — следующий со штрафом \u{2212}100"), "\(lines)")
        let first = notes(score(outcome: .bait, bidder: 1, raw: [102, 60], written: [162, 0], totalsAfter: [300, 200],
                                baitCountsAfter: [0, 1]))
        XCTAssertTrue(first.contains("Саша: 1-й байт за партию"), "\(first)")
        var burn = RuleSet.house
        burn.baitTransfer = .burn
        XCTAssertTrue(notes(s, rules: burn).contains("Очки играющего сгорают"))
    }

    func testBaitSplitBetweenOpponents() {
        let s = score(outcome: .bait, bidder: 0, players: 3, raw: [41, 60, 60], written: [0, 81, 80],
                      totalsAfter: [0, 81, 80])
        XCTAssertTrue(notes(s).contains("Очки играющего (41) делят пополам: Саша и Миша"), "\(notes(s))")
    }

    func testHangingPotNotesDuringAndAtEndOfMatch() {
        let during = notes(score(outcome: .hanging, bidder: 1, raw: [81, 81], written: [81, 0],
                                 potAdded: 81, potAfter: 81, totalsAfter: [400, 300]))
        XCTAssertTrue(during.contains("Очки играющего (81) висят — их заберёт тот, кто наберёт больше всех в следующей сдаче"),
                      "\(during)")

        // Соперник перешёл 701 на висячем байте — следующей сдачи не будет.
        let atEnd = notes(score(outcome: .hanging, bidder: 1, raw: [81, 81], written: [81, 0],
                                potAdded: 81, potAfter: 141, totalsAfter: [720, 300]))
        XCTAssertTrue(atEnd.contains("Висячие очки (141) не разыграны — партия окончена, они сгорают"), "\(atEnd)")
        XCTAssertFalse(atEnd.contains { $0.contains("следующ") }, "\(atEnd)")

        // Висячие остались с прошлых сдач, а партия закончилась обычной сдачей.
        let leftover = notes(score(outcome: .made, bidder: 0, raw: [100, 62], potAfter: 60, totalsAfter: [705, 300]))
        XCTAssertTrue(leftover.contains("Висячие очки (60) не разыграны — партия окончена, они сгорают"), "\(leftover)")
        let carried = notes(score(outcome: .made, bidder: 0, raw: [100, 62], potAfter: 60, totalsAfter: [305, 300]))
        XCTAssertTrue(carried.contains("Висячие очки (60) переходят в следующую сдачу"), "\(carried)")
    }

    func testHangingPotAtMatchEndInRealMatch() throws {
        // Партия до 50 очков: ищем раздачу, где она кончается на висячем байте.
        var rules = RuleSet.house
        rules.targetScore = 50
        var found = false
        for seed in 0..<3_000 where !found {
            var m = Match(playerCount: 2, names: ["Вы", "Саша"], rules: rules, seed: UInt64(seed))
            var steps = 0
            while !m.isOver && steps < 400 {
                if m.needsNewDeal { m.startNextDeal() } else { try m.apply(try XCTUnwrap(m.deal).legalActions()[0]) }
                steps += 1
            }
            guard m.isOver, let last = m.history.last, last.outcome == .hanging else { continue }
            found = true
            XCTAssertGreaterThan(m.pot, 0, "Висячие остались неразыгранными")
            let lines = Narrator.outcomeNotes(last, names: m.names, humanSeat: 0, rules: m.rules)
            XCTAssertTrue(lines.contains { $0.contains("не разыграны — партия окончена") }, "\(lines)")
            XCTAssertFalse(lines.contains { $0.contains("следующ") }, "\(lines)")
        }
        XCTAssertTrue(found, "Не нашлась партия, закончившаяся на висячем байте")
    }

    func testTieAboveTargetExplained() {
        let s = score(outcome: .made, bidder: 0, raw: [100, 62], totalsAfter: [720, 720])
        XCTAssertTrue(notes(s).contains("Вы и Саша: по 720 — поровну, играется ещё одна сдача"), "\(notes(s))")
        let below = score(outcome: .made, bidder: 0, raw: [100, 62], totalsAfter: [600, 600])
        XCTAssertFalse(notes(below).contains { $0.contains("поровну") })
    }

    func testBurnedCombosAndBellaExplained() {
        let fifty = Meld(suit: .clubs, low: .seven, length: 4)
        let decl = Declarations(melds: [[Meld(suit: .spades, low: .eight, length: 3)], [fifty]], meldWinner: 1, bellaSeat: 1)
        let s = score(outcome: .made, bidder: 0, tricks: [9, 0], raw: [162, 0], naked: [false, true],
                      totalsAfter: [300, 100], declarations: decl, nakedCountsAfter: [0, 1])
        let lines = notes(s)
        XCTAssertTrue(lines.contains(
            "Саша: полтинник 7-8-9-10♣ не в зачёт — ни одной взятки; младшие комбинации других тоже не пишутся"), "\(lines)")
        XCTAssertTrue(lines.contains("Саша: бэла не в зачёт — ни одной взятки"), "\(lines)")
        XCTAssertTrue(lines.contains("Саша: ни одной взятки (голый) — в следующий раз штраф \u{2212}100"), "\(lines)")
        XCTAssertNil(Narrator.meldLine(s, names: names, humanSeat: 0, rules: .house))

        let written = score(outcome: .made, bidder: 1, tricks: [3, 6], raw: [40, 192], meldPoints: [0, 50],
                            bellaPoints: [0, 20], totalsAfter: [300, 300], declarations: decl)
        XCTAssertFalse(notes(written).contains { $0.contains("не в зачёт") })
        XCTAssertEqual(Narrator.meldLine(written, names: names, humanSeat: 0, rules: .house), "Саша: полтинник 7-8-9-10♣, бэла")

        // Старое сохранение без объявлений — просто без пояснения.
        let old = score(outcome: .made, bidder: 0, tricks: [9, 0], raw: [162, 0], totalsAfter: [300, 100])
        XCTAssertFalse(notes(old).contains { $0.contains("не в зачёт") })
    }

    func testBurnedCombosRecordedInRealDeal() throws {
        // Ищем сдачу, где у записывающего комбинации не оказалось ни одной взятки.
        var found = false
        for seed in 0..<400 where !found {
            var m = Match(playerCount: 3, names: names, rules: .house, seed: UInt64(seed))
            var steps = 0
            while !m.isOver && steps < 3_000 && !found {
                if m.needsNewDeal { m.startNextDeal() } else { try m.apply(try XCTUnwrap(m.deal).legalActions()[0]) }
                steps += 1
                if let last = m.history.last, m.deal?.isFinished == true, let w = last.burnedMeldSeat {
                    found = true
                    XCTAssertEqual(last.tricksTaken[w], 0)
                    let lines = Narrator.outcomeNotes(last, names: m.names, humanSeat: 0, rules: m.rules)
                    XCTAssertTrue(lines.contains { $0.contains("не в зачёт — ни одной взятки") }, "\(lines)")
                }
            }
        }
        XCTAssertTrue(found, "Не нашлась сдача со сгоревшими комбинациями")
    }

    func testNakedPenaltyNote() {
        let s = score(outcome: .made, bidder: 0, tricks: [9, 0], raw: [162, 0], naked: [false, true],
                      nakedPenalty: [false, true], totalsAfter: [300, -100], nakedCountsAfter: [0, 2])
        XCTAssertTrue(notes(s).contains("Саша: ни одной взятки, голый 2-й раз — штраф \u{2212}100"), "\(notes(s))")
    }

    // MARK: - События

    /// Предупреждение о сдаче на обязах называет того, кто будет играть, а не сдающего:
    /// вдвоём после двух пересдач сдаёте снова вы, а обязы — у соперника.
    func testAllPassedMessageWarnsAboutForcedDeal() throws {
        for (player, who) in [(RuleSet.ForcedPlayer.afterDealer, "играет Саша"), (.dealer, "играете вы")] {
            var rules = RuleSet.house
            rules.forcedPlayer = player
            var match = Match(playerCount: 2, names: ["Вы", "Саша"], rules: rules, seed: 3, firstDealer: 0)
            let deck = { (dealer: Int) in
                arrangedDeck(dealer: dealer, hands: [cards("Вч 9ч Тп 10п Кп 7т"), cards("7ч 8ч Тб 10б Кб Дт")],
                             open: c("Кч"), prikup: [cards("Дп Вп 8т"), cards("9т 10т Вт")])
            }
            match.startDeal(deck: deck(0), dealer: 0)
            for _ in 0..<4 { try match.apply(.pass) }
            XCTAssertEqual(Narrator.message(for: .allPassed, in: match, humanSeat: 0), "Все спасовали — пересдача")
            match.startDeal(deck: deck(1), dealer: 1)
            for _ in 0..<4 { try match.apply(.pass) }
            XCTAssertEqual(match.upcomingDealer, 0)
            XCTAssertEqual(Narrator.message(for: .allPassed, in: match, humanSeat: 0),
                           "Все спасовали — пересдача. Следующая — на обязах: \(who)")
            XCTAssertNil(Narrator.message(for: .dealFinished, in: match, humanSeat: 0))
            // Сообщение не расходится с тем, кто и правда играет.
            match.startDeal(deck: deck(0), dealer: 0)
            let bidder = try XCTUnwrap(match.deal?.bidder)
            XCTAssertEqual(Narrator.bidderPhrase(seat: bidder, names: match.names, humanSeat: 0), who)
        }
    }

    /// Втроём обязы у сидящего слева от сдающего: сдаёт Миша — играете вы.
    func testAllPassedMessageNamesForcedPlayerThreePlayers() throws {
        var match = Match(playerCount: 3, names: ["Вы", "Саша", "Миша"], rules: .house, seed: 3, firstDealer: 0)
        let deck = { (dealer: Int) in
            arrangedDeck(dealer: dealer,
                         hands: [cards("Вч 9ч Тп 10п Кп 7т"), cards("7ч 8ч Тб 10б Кб Дт"), cards("Дч 10ч Тт 7п 8п 9п")],
                         open: c("Кч"), prikup: [cards("Дп Вп 8т"), cards("9т 10т Вт"), cards("7б 8б 9б")])
        }
        for dealer in [0, 1] {
            match.startDeal(deck: deck(dealer), dealer: dealer)
            for _ in 0..<6 { try match.apply(.pass) }
        }
        XCTAssertEqual(match.upcomingDealer, 2)
        XCTAssertEqual(Narrator.message(for: .allPassed, in: match, humanSeat: 0),
                       "Все спасовали — пересдача. Следующая — на обязах: играете вы")
    }

    // MARK: - Недопустимый ход

    private func dealOnHearts(rules: RuleSet) throws -> Match {
        var match = Match(playerCount: 2, names: ["Вы", "Саша"], rules: rules, seed: 1, firstDealer: 0)
        match.startDeal(deck: arrangedDeck(
            dealer: 0,
            hands: [cards("7ч Тч Тп 10п Кп 7т"), cards("10ч 8ч Тб 10б Кб Дт")],
            open: c("Кч"),
            prikup: [cards("Дп Вп 8т"), cards("9т 10т Вт")]), dealer: 0)
        return match
    }

    func testIllegalCardReasonOvertrump() throws {
        var r = RuleSet.house
        r.overtrump = .trumpLeadOnly
        var match = try dealOnHearts(rules: r)
        let bidding = try XCTUnwrap(match.deal)
        XCTAssertEqual(Narrator.illegalCardReason(deal: bidding, seat: 1, card: c("10ч")), "Сейчас идёт торговля")
        try match.apply(.take)                 // Саша играет червы
        let exchange = try XCTUnwrap(match.deal)
        XCTAssertEqual(Narrator.illegalCardReason(deal: exchange, seat: 0, card: c("7ч")),
                       "Сначала решите, менять ли козырную семёрку")
        try match.apply(.exchangeSeven(false)) // у вас козырная семёрка — оставляете
        try match.apply(.play(c("10ч")))       // Саша заходит с козыря
        let deal = try XCTUnwrap(match.deal)
        XCTAssertEqual(deal.turn, 0)
        XCTAssertEqual(Narrator.illegalCardReason(deal: deal, seat: 0, card: c("7ч")), "Нужно перебить: козырь старше, чем 10♥")
        XCTAssertEqual(Narrator.illegalCardReason(deal: deal, seat: 0, card: c("Тп")), "Зашли с козыря — ходите козырем: ♥")
        XCTAssertEqual(Narrator.illegalCardReason(deal: deal, seat: 0, card: c("Тч")), "")
        XCTAssertEqual(Narrator.illegalCardReason(deal: deal, seat: 1, card: c("8ч")), "Сейчас не ваш ход")
    }

    func testIllegalCardReasonMustTrump() throws {
        var match = try dealOnHearts(rules: .house)
        try match.apply(.take)
        try match.apply(.exchangeSeven(false))
        try match.apply(.play(c("Тб")))
        let deal = try XCTUnwrap(match.deal)
        XCTAssertEqual(Narrator.illegalCardReason(deal: deal, seat: 0, card: c("Тп")), "Бубен нет — бейте козырем: ♥")
        XCTAssertEqual(Narrator.illegalCardReason(deal: deal, seat: 0, card: c("7ч")), "")
        try match.apply(.play(c("7ч")))        // вы берёте козырем
        try match.apply(.play(c("7т")))        // и заходите с треф
        let follow = try XCTUnwrap(match.deal)
        XCTAssertEqual(follow.turn, 1)
        XCTAssertEqual(Narrator.illegalCardReason(deal: follow, seat: 1, card: c("Кб")), "Нужно ходить в масть: ♣")
    }
}
