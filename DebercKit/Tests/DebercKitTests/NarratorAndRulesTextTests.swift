import XCTest
@testable import DebercKit

final class NarratorAndRulesTextTests: XCTestCase {

    func testBidTexts() {
        XCTAssertEqual(Narrator.bidText(Bid(seat: 0, round: 1, kind: .pass, suit: nil)), "Пас")
        XCTAssertEqual(Narrator.bidText(Bid(seat: 0, round: 1, kind: .take, suit: .hearts)), "Беру ♥")
        XCTAssertEqual(Narrator.bidText(Bid(seat: 0, round: 2, kind: .name, suit: .spades)), "Играю ♠")
        XCTAssertEqual(Narrator.bidText(Bid(seat: 0, round: 1, kind: .forced, suit: .clubs)), "Обязы ♣")
    }

    func testPointsGenitive() {
        XCTAssertEqual(Narrator.pointsGenitive(701), "701 очка")
        XCTAssertEqual(Narrator.pointsGenitive(1001), "1001 очка")
        XCTAssertEqual(Narrator.pointsGenitive(511), "511 очков")
        XCTAssertEqual(Narrator.pointsGenitive(500), "500 очков")
    }

    func testMessages() {
        let names = ["Вы", "Саша", "Миша"]
        let rules = RuleSet.house
        XCTAssertEqual(
            Narrator.message(for: .trumpChosen(seat: 1, suit: .hearts, forced: false), names: names, humanSeat: 0, rules: rules),
            "Саша играет, козырь ♥ черви")
        XCTAssertEqual(
            Narrator.message(for: .trumpChosen(seat: 0, suit: .spades, forced: true), names: names, humanSeat: 0, rules: rules),
            "Обязы: Вы играете, козырь ♠ пики")
        XCTAssertEqual(
            Narrator.message(for: .fourSevens(seat: 2), names: names, humanSeat: 0, rules: rules),
            "Миша: четыре семёрки! +100 и пересдача")
        XCTAssertEqual(Narrator.message(for: .bella(seat: 1), names: names, humanSeat: 0, rules: rules), "Саша: бэла!")
        XCTAssertNil(Narrator.message(for: .dealFinished, names: names, humanSeat: 0, rules: rules))
    }

    func testMeldSummary() {
        let decl = Declarations(
            melds: [[Meld(suit: .spades, low: .nine, length: 3)], [Meld(suit: .clubs, low: .ten, length: 4)]],
            meldWinner: 1, bellaSeat: nil)
        XCTAssertEqual(
            Narrator.meldSummary(decl, names: ["Вы", "Саша"], humanSeat: 0, rules: .house),
            "Саша: полтинник 10-В-Д-К♣ — старше")
    }

    func testOutcomeNotesForBaitAndPenalty() throws {
        var match = Match(playerCount: 2, names: ["Вы", "Саша"], rules: .house, seed: 9)
        match.startNextDeal()
        // Разыгрываем, пока не случится сыгранная сдача.
        var guardCounter = 0
        while match.history.last.map({ [.made, .bait, .hanging, .tie].contains($0.outcome) }) != true {
            guardCounter += 1
            if guardCounter > 5_000 { break }
            if match.needsNewDeal { match.startNextDeal(); continue }
            let deal = try XCTUnwrap(match.deal)
            try match.apply(deal.legalActions()[0])
        }
        let score = try XCTUnwrap(match.history.last)
        XCTAssertFalse(Narrator.outcomeTitle(score, names: match.names, humanSeat: 0).isEmpty)
        _ = Narrator.outcomeNotes(score, names: match.names, humanSeat: 0, rules: match.rules)
    }

    func testRulesTextReflectsSettings() {
        let house = RulesText.markdown(for: .house)
        XCTAssertTrue(house.contains("до 701 очка"))
        XCTAssertTrue(house.contains("Обязы"))
        XCTAssertTrue(house.contains("перебивать старшим не нужно"))
        XCTAssertTrue(house.contains("каждый 2-й раз"))
        var other = RuleSet.house
        other.targetScore = 501
        other.overtrump = .always
        other.nakedPenaltyEvery = 0
        other.baitPenaltyEvery = 0
        let text = RulesText.markdown(for: other)
        XCTAssertTrue(text.contains("до 501 очка"))
        XCTAssertTrue(text.contains("старше уже лежащего козыря"))
        XCTAssertTrue(text.contains("Штрафов нет."))
    }

    /// Генерирует RULES.md: DEBERC_WRITE_RULES=/путь/к/файлу swift test --filter testWriteRulesMarkdown
    func testWriteRulesMarkdown() throws {
        guard let path = ProcessInfo.processInfo.environment["DEBERC_WRITE_RULES"] else { return }
        try RulesText.markdown(for: .house).write(toFile: path, atomically: true, encoding: .utf8)
    }
}
