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

    func testRulesTextForcedDealGrammar() {
        var r = RuleSet.house
        r.forcedDealAfterRedeals = 1
        var text = RulesText.markdown(for: r)
        XCTAssertTrue(text.contains("если все спасовали и была пересдача"))
        XCTAssertFalse(text.contains("1 раза"))
        r.forcedDealAfterRedeals = 2
        text = RulesText.markdown(for: r)
        XCTAssertTrue(text.contains("пересдача была 2 раза подряд"))
        r.forcedDealAfterRedeals = 5
        XCTAssertTrue(RulesText.markdown(for: r).contains("пересдача была 5 раз подряд"))
        r.forcedDealAfterRedeals = 0
        text = RulesText.markdown(for: r)
        XCTAssertFalse(text.contains("Обязы"))
        XCTAssertFalse(text.contains("до обязов"), "Без обязов про счёт пересдач не пишем")
    }

    func testRulesTextNewSwitches() {
        let house = RulesText.markdown(for: .house)
        XCTAssertTrue(house.contains("Король и дама из бэлы могут входить и в терц."))
        XCTAssertTrue(house.contains("снова обязы, у нового сдающего"))
        XCTAssertTrue(house.contains("лишнее очко получает тот, кто раньше ходит"))
        XCTAssertTrue(house.contains("Висячие очки, не разыгранные до конца партии, сгорают."))
        XCTAssertTrue(house.contains("по часовой стрелке"))
        var r = RuleSet.house
        r.bellaInMelds = false
        r.fourSevensKeepsForcedStreak = false
        let text = RulesText.markdown(for: r)
        XCTAssertTrue(text.contains("Король и дама из бэлы в терц и полтинник не входят."))
        XCTAssertTrue(text.contains("начинает счёт пересдач до обязов заново"))
    }

    func testRulesDecodeNewSwitchesTolerantly() throws {
        let old = try JSONDecoder().decode(RuleSet.self, from: Data(#"{"targetScore": 501}"#.utf8))
        XCTAssertTrue(old.bellaInMelds)
        XCTAssertTrue(old.fourSevensKeepsForcedStreak)
        var r = RuleSet.house
        r.bellaInMelds = false
        r.fourSevensKeepsForcedStreak = false
        XCTAssertEqual(try JSONDecoder().decode(RuleSet.self, from: JSONEncoder().encode(r)), r)
    }

    // MARK: - RULES.md

    static let generatedStart = "<!-- generated:start -->"
    static let generatedEnd = "<!-- generated:end -->"

    /// RULES.md в корне репозитория (рядом с папкой DebercKit).
    static var rulesFileURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DebercKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DebercKit
            .deletingLastPathComponent()   // корень репозитория
            .appendingPathComponent("RULES.md")
    }

    /// Что стоит между маркерами: разделы правил, отбитые пустыми строками.
    static func generatedBlock() -> String {
        "\n\n" + RulesText.markdownBody(for: .house) + "\n"
    }

    /// Разбивает RULES.md на ручное начало, генерируемую часть и ручной хвост.
    static func splitRules(_ text: String) -> (head: String, body: String, tail: String)? {
        guard let start = text.range(of: generatedStart), let end = text.range(of: generatedEnd),
              start.upperBound <= end.lowerBound else { return nil }
        return (String(text[..<start.upperBound]), String(text[start.upperBound..<end.lowerBound]),
                String(text[end.lowerBound...]))
    }

    /// Генерируемая часть RULES.md совпадает с экраном «Правила» (RulesText, домашние правила).
    /// Если тест упал — перегенерируйте: DEBERC_WRITE_RULES=1 swift test --filter testWriteRulesMarkdown
    func testRulesMarkdownMatchesRepository() throws {
        let url = Self.rulesFileURL
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "RULES.md не найден рядом с пакетом")
        let text = try String(contentsOf: url, encoding: .utf8)
        let parts = try XCTUnwrap(Self.splitRules(text), "В RULES.md нет маркеров генерируемой части")
        XCTAssertEqual(parts.body, Self.generatedBlock(),
                       "RULES.md устарел — перегенерируйте его (см. комментарий к тесту)")
        XCTAssertTrue(parts.head.hasPrefix("# Деберц — наши правила"))
        XCTAssertTrue(parts.tail.contains("## Что уточнить у папы"), "Ручной раздел не должен пропасть")
    }

    /// Перегенерирует часть RULES.md между маркерами, ручные разделы не трогает:
    /// DEBERC_WRITE_RULES=1 swift test --filter testWriteRulesMarkdown
    /// (или DEBERC_WRITE_RULES=/путь/к/RULES.md).
    func testWriteRulesMarkdown() throws {
        guard let value = ProcessInfo.processInfo.environment["DEBERC_WRITE_RULES"] else { return }
        let url = value.hasSuffix(".md") ? URL(fileURLWithPath: value) : Self.rulesFileURL
        let text = try String(contentsOf: url, encoding: .utf8)
        let parts = try XCTUnwrap(Self.splitRules(text), "В RULES.md нет маркеров генерируемой части")
        let updated = parts.head + Self.generatedBlock() + parts.tail
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }
}
