import XCTest
@testable import DebercKit

/// Подначки соперников: фразы, частота, поводы.
final class BanterTests: XCTestCase {

    // MARK: - Фразы

    func testEveryEventHasPhrasesForEveryStyle() {
        for event in BanterEvent.allCases {
            for style in BotStyle.allCases {
                XCTAssertGreaterThanOrEqual(Banter.phrases(event, style: style).count, 3, "\(event) / \(style)")
            }
        }
    }

    /// Коротко, на «вы», без жаргона и без намёков, что соперник видит карты.
    func testPhrasesFollowTheToneRules() {
        let forbiddenWords: Set<String> = ["ты", "тебя", "тебе", "тобой", "твой", "твоя", "твои", "твоё",
                                           "изи", "кринж", "лол", "рофл"]
        let forbiddenPhrases = ["вижу ваши", "ваши карты", "знаю, что у вас"]
        for event in BanterEvent.allCases {
            for style in BotStyle.allCases {
                for raw in Banter.phrases(event, style: style) {
                    for feminine in [false, true] {
                        let text = Banter.gendered(raw, feminine: feminine)
                        XCTAssertFalse(text.contains("{") || text.contains("}"), "скобки: \(raw)")
                        XCTAssertLessThanOrEqual(text.count, 44, "длинно: \(text)")
                        XCTAssertGreaterThanOrEqual(text.count, 2, "пусто: \(raw)")
                        let lower = text.lowercased()
                        let words = lower.split { !$0.isLetter }.map(String.init)
                        for word in words {
                            XCTAssertFalse(forbiddenWords.contains(word), "«\(word)» в «\(text)»")
                        }
                        for phrase in forbiddenPhrases {
                            XCTAssertFalse(lower.contains(phrase), "«\(phrase)» в «\(text)»")
                        }
                        XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation },
                                       "эмодзи: \(text)")
                    }
                }
            }
        }
    }

    func testGenderedPicksTheSpeakersForm() {
        XCTAssertEqual(Banter.gendered("Я {взял|взяла} своё", feminine: false), "Я взял своё")
        XCTAssertEqual(Banter.gendered("Я {взял|взяла} своё", feminine: true), "Я взяла своё")
        XCTAssertEqual(Banter.gendered("{Рад|Рада}, {готов|готова}!", feminine: true), "Рада, готова!")
        XCTAssertEqual(Banter.gendered("Без скобок", feminine: true), "Без скобок")
        XCTAssertEqual(Banter.gendered("Сломано {взял", feminine: true), "Сломано {взял")
    }

    func testLineAvoidsRecentPhrases() {
        let persona = Persona.byID("misha")!
        let all = Banter.phrases(.trumpedHigh, style: persona.style).map { Banter.gendered($0, feminine: false) }
        guard all.count >= 2 else { return XCTFail("мало фраз") }
        let avoid = Set(all.dropFirst())
        for variant in 0..<20 {
            XCTAssertEqual(Banter.line(.trumpedHigh, persona: persona, variant: UInt64(variant), avoid: avoid), all[0])
        }
        // Всё уже сказано — повтор лучше молчания.
        XCTAssertNotNil(Banter.line(.trumpedHigh, persona: persona, variant: 3, avoid: Set(all)))
    }

    func testFemininePersonaSpeaksInFeminine() {
        let vera = Persona.byID("vera")!
        for event in BanterEvent.allCases {
            for variant in 0..<8 {
                let line = Banter.line(event, persona: vera, variant: UInt64(variant)) ?? ""
                XCTAssertFalse(line.contains("{"), line)
            }
        }
    }

    // MARK: - Частота

    func testShouldSpeakRespectsLevelCooldownAndWeight() {
        XCTAssertFalse(Banter.shouldSpeak(.humanBait, level: .off, sinceLast: 1000, roll: 0))
        XCTAssertFalse(Banter.shouldSpeak(.humanBait, level: .normal, sinceLast: 5, roll: 0))
        XCTAssertTrue(Banter.shouldSpeak(.humanBait, level: .normal, sinceLast: 60, roll: 0.1))
        // Будничный повод при «Иногда» — редко: 0.3 × 1.
        XCTAssertFalse(Banter.shouldSpeak(.bigTrick, level: .normal, sinceLast: 60, roll: 0.5))
        XCTAssertTrue(Banter.shouldSpeak(.bigTrick, level: .often, sinceLast: 60, roll: 0.4))
        // «Часто» не значит «всегда».
        XCTAssertFalse(Banter.shouldSpeak(.longThink, level: .often, sinceLast: 60, roll: 0.97))
        XCTAssertLessThan(BanterLevel.often.cooldown, BanterLevel.normal.cooldown)
        XCTAssertLessThan(BanterLevel.normal.cooldown, BanterLevel.rare.cooldown)
    }

    // MARK: - Поводы по взятке

    private func trick(_ plays: [(Int, String)], winner: Int) -> Trick {
        var t = Trick()
        t.plays = plays.map { PlayedCard(seat: $0.0, card: c($0.1)) }
        t.winner = winner
        return t
    }

    func testBotTrumpsHumansAce() {
        let t = trick([(0, "Тп"), (1, "7ч")], winner: 1)
        let say = BanterTriggers.afterTrick(t, trump: .hearts, humanSeat: 0)
        XCTAssertEqual(say?.seat, 1)
        XCTAssertEqual(say?.event, .trumpedHigh)
    }

    func testBotTakesRichTrickWithoutTrumping() {
        let t = trick([(0, "10п"), (1, "Тп")], winner: 1)
        let say = BanterTriggers.afterTrick(t, trump: .hearts, humanSeat: 0)
        XCTAssertEqual(say?.event, .bigTrick)
    }

    func testSmallTrickIsNotWorthATaunt() {
        let t = trick([(0, "7п"), (1, "8п")], winner: 1)
        XCTAssertNil(BanterTriggers.afterTrick(t, trump: .hearts, humanSeat: 0))
    }

    func testBotGrumblesWhenHumanTakesItsTen() {
        let t = trick([(1, "10б"), (2, "7б"), (0, "Тб")], winner: 0)
        let say = BanterTriggers.afterTrick(t, trump: .hearts, humanSeat: 0)
        XCTAssertEqual(say?.seat, 1)
        XCTAssertEqual(say?.event, .lostHighCard)
    }

    func testTrickWithoutHumanOrTrumpSaysNothing() {
        XCTAssertNil(BanterTriggers.afterTrick(trick([(1, "Тп"), (2, "7ч")], winner: 2), trump: .hearts, humanSeat: 0))
        XCTAssertNil(BanterTriggers.afterTrick(trick([(0, "Тп"), (1, "7ч")], winner: 1), trump: nil, humanSeat: 0))
    }

    // MARK: - Поводы в начале сдачи

    /// Играет компьютеры за всех, пока не найдётся сдача, после которой должен сработать повод.
    func testDealStartTauntsFollowThePreviousDeal() {
        var checked = 0
        for seed in UInt64(1)...40 {
            var match = Match(playerCount: 2, names: ["Вы", "Миша"], rules: .house, seed: seed)
            var rng = SplitMix64(seed: seed &* 31)
            let bot = Bot(level: .novice)
            var guardSteps = 0
            while !match.isOver && guardSteps < 4000 {
                guardSteps += 1
                if match.needsNewDeal {
                    if let last = match.history.last, last.wasPlayed {
                        let say = BanterTriggers.atDealStart(match, humanSeat: 0, bots: [1], pick: { _ in 0 })
                        let failed = last.outcome == .bait || last.outcome == .hanging
                        if last.naked[0] {
                            XCTAssertEqual(say?.event, .humanNaked)
                            checked += 1
                        } else if last.bidder == 0 && failed {
                            XCTAssertEqual(say?.event, .humanBait)
                            checked += 1
                        } else if last.bidder == 1 && failed {
                            XCTAssertEqual(say?.event, .botBait)
                            XCTAssertEqual(say?.seat, 1)
                            checked += 1
                        } else if last.bidder == 0 && last.outcome == .made {
                            XCTAssertEqual(say?.event, .humanMade)
                            checked += 1
                        }
                    }
                    match.startNextDeal()
                    continue
                }
                guard let actor = match.actor else { break }
                let action = bot.chooseAction(match: match, seat: actor, rng: &rng)
                if (try? match.apply(action)) == nil {
                    guard let fallback = match.deal?.legalActions().first, (try? match.apply(fallback)) != nil else { break }
                }
            }
        }
        XCTAssertGreaterThan(checked, 20, "проверено сдач: \(checked)")
    }

    func testNoTauntBeforeTheFirstDeal() {
        let match = Match(playerCount: 3, names: ["Вы", "Саша", "Оля"], rules: .house, seed: 7)
        XCTAssertNil(BanterTriggers.atDealStart(match, humanSeat: 0, bots: [1, 2], pick: { _ in 0 }))
        XCTAssertNil(BanterTriggers.atDealStart(match, humanSeat: 0, bots: [], pick: { _ in 0 }))
    }
}
