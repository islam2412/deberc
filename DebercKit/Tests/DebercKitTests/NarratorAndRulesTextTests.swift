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

    // MARK: - Словами для VoiceOver

    func testSpokenMessagesUseWordsInsteadOfSymbols() {
        let names = ["Вы", "Саша", "Вера"]
        let rules = RuleSet.house
        func spoken(_ event: DealEvent) -> String? {
            Narrator.spokenMessage(for: event, names: names, humanSeat: 0, rules: rules)
        }
        XCTAssertEqual(spoken(.trumpChosen(seat: 1, suit: .hearts, forced: false)), "Саша играет, козырь черви")
        XCTAssertEqual(spoken(.trumpChosen(seat: 0, suit: .spades, forced: true)), "Обязы: Вы играете, козырь пики")
        let exchange = SevenExchangeRecord(seat: 2, gave: Card(.seven, .hearts), took: Card(.ace, .hearts))
        XCTAssertEqual(spoken(.sevenExchanged(exchange)), "Вера забирает туз червей за козырную семёрку")
        let decl = Declarations(
            melds: [[Meld(suit: .spades, low: .nine, length: 3)], [Meld(suit: .clubs, low: .ten, length: 4)], []],
            meldWinner: 1, bellaSeat: nil)
        XCTAssertEqual(spoken(.playStarted(decl)), "Саша: полтинник от десятки до короля треф — старше")
        // На экране — по-прежнему значками.
        XCTAssertEqual(Narrator.message(for: .sevenExchanged(exchange), names: names, humanSeat: 0, rules: rules),
                       "Вера забирает Т♥ за козырную семёрку")
    }

    func testSpokenFreeText() {
        XCTAssertEqual(Narrator.spoken("Заход: Саша, Т\u{2665}\u{FE0E}"), "Заход: Саша, туз червей")
        XCTAssertEqual(Narrator.spoken("Нужно перебить: козырь старше, чем 10♥"),
                       "Нужно перебить: козырь старше, чем десятка червей")
        XCTAssertEqual(Narrator.spoken("Бубен нет — бейте козырем: ♥"), "Бубен нет — бейте козырем: черви")
        XCTAssertEqual(Narrator.spoken("Сдача 3 · играет Саша"), "Сдача 3, играет Саша")
        XCTAssertEqual(Narrator.spoken("Рискну: ♠"), "Рискну: пики")
        XCTAssertEqual(Narrator.spoken("Беру ♦!"), "Беру бубны!")
        XCTAssertEqual(Narrator.spoken("Вы: терц 7-8-9♠, бэла"), "Вы: терц от семёрки до девятки пик, бэла")
        // Без значков масти текст не меняется: ни числа, ни буквы достоинств в словах.
        let plain = "Сдача 10, Дама, Туз и 110 очков, В меню"
        XCTAssertEqual(Narrator.spoken(plain), plain)
    }

    func testSpokenCardsAndMelds() {
        XCTAssertEqual(Narrator.spokenCard(Card(.queen, .hearts)), "дама червей")
        XCTAssertEqual(Narrator.spokenCard(Card(.ten, .diamonds)), "десятка бубен")
        XCTAssertEqual(Narrator.spokenMeld(Meld(suit: .spades, low: .nine, length: 3), rules: .house), "терц от девятки до валета пик")
        var hundred = RuleSet.house
        hundred.hundredForFive = true
        XCTAssertEqual(Narrator.spokenMeld(Meld(suit: .clubs, low: .ten, length: 5), rules: hundred), "сотня от десятки до туза треф")
        for card in Card.deck {
            XCTAssertEqual(Narrator.spoken(card.description), Narrator.spokenCard(card))
        }
    }

    // MARK: - Род манеры

    func testStyleTitlesAgreeWithGender() {
        XCTAssertEqual(BotStyle.cautious.title(feminine: true), "Осторожная")
        XCTAssertEqual(BotStyle.balanced.title(feminine: true), "Ровная")
        XCTAssertEqual(BotStyle.bold.title(feminine: true), "Рисковая")
        for style in BotStyle.allCases {
            XCTAssertEqual(style.title(feminine: false), style.title, "Прежнее title — мужской род")
        }
        let vera = Persona.byID("vera")
        XCTAssertEqual(vera.map { $0.style.title(feminine: $0.feminine) }, "Осторожная")
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
        XCTAssertFalse(text.contains("соперник сдающего"))
        XCTAssertFalse(text.contains("до обязов"), "Без обязов про счёт пересдач не пишем")
    }

    /// Кто играет на обязах: по домашним правилам — следующий после сдающего, не сам сдающий.
    func testRulesTextForcedPlayer() {
        var r = RuleSet.house
        var text = RulesText.markdown(for: r)
        XCTAssertTrue(text.contains("в следующей сдаче торговли нет — играет следующий после сдающего (вдвоём — соперник сдающего), козырь — масть открытой карты."))
        XCTAssertFalse(text.contains("сдающий играет сам"))
        r.forcedPlayer = .dealer
        text = RulesText.markdown(for: r)
        XCTAssertTrue(text.contains("в следующей сдаче торговли нет — сдающий играет сам, козырь — масть открытой карты."))
        r.forcedDealAfterRedeals = 1
        XCTAssertTrue(RulesText.markdown(for: r).contains("Обязы: если все спасовали и была пересдача, в следующей сдаче торговли нет — сдающий играет сам"))
    }

    func testRulesTextNewSwitches() {
        let house = RulesText.markdown(for: .house)
        XCTAssertTrue(house.contains("Король и дама из бэлы могут входить и в терц."))
        XCTAssertTrue(house.contains("следующая сдача — снова обязы."))
        XCTAssertFalse(house.contains("у нового сдающего"))
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
        XCTAssertEqual(old.forcedPlayer, .afterDealer)
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
