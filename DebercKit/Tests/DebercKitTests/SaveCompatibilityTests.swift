import XCTest
@testable import DebercKit

/// Совместимость сохранений: партии, записанные старыми версиями, должны читаться новыми.
/// Фикстуры — в SaveFixturesV1.swift (формат версии 1, записан кодом до терпимого чтения).
final class SaveCompatibilityTests: XCTestCase {

    private func decode(_ json: String) throws -> Match {
        try JSONDecoder().decode(Match.self, from: Data(json.utf8))
    }

    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> Match {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Match.self, from: data)
    }

    /// Доиграть из сохранения, выбирая первое допустимое действие (как делал код версии 1).
    private func continueFirstLegal(_ match: inout Match, steps: Int = 200) throws {
        var n = 0
        while !match.isOver && n < steps {
            if match.needsNewDeal {
                match.startNextDeal()
            } else {
                try match.apply(try XCTUnwrap(match.deal).legalActions()[0])
            }
            n += 1
        }
    }

    // MARK: - Формат версии 1

    func testDecodesV1ThreePlayersMidPlay() throws {
        var m = try decode(SaveFixturesV1.threePlayersPlaying)
        XCTAssertEqual(m.playerCount, 3)
        XCTAssertEqual(m.names, ["Вы", "Саша", "Миша"])
        XCTAssertEqual(m.totals, [518, 573, 418])
        XCTAssertEqual(m.pot, 58)
        XCTAssertEqual(m.dealCount, 15)
        XCTAssertEqual(m.dealer, 0)
        XCTAssertEqual(m.allPassStreak, 0)
        XCTAssertEqual(m.history.count, 14)
        XCTAssertEqual(m.history.last?.outcome, .hanging)
        XCTAssertNil(m.history.last?.declarations, "В версии 1 объявлений в итогах не было")
        XCTAssertEqual(m.baitCounts, [2, 1, 0])
        XCTAssertEqual(m.nakedCounts, [2, 0, 0])
        XCTAssertNil(m.winner)
        XCTAssertEqual(m.rng.state, 70812576259628645)
        let deal = try XCTUnwrap(m.deal)
        XCTAssertEqual(deal.phase, .playing)
        XCTAssertEqual(deal.tricks.count, 2)
        XCTAssertEqual(deal.currentTrick.plays.count, 1)
        XCTAssertEqual(deal.handCounts, [7, 6, 7])
        XCTAssertEqual(deal.trump, .hearts)
        XCTAssertEqual(deal.bidder, 1)
        XCTAssertEqual(deal.turn, 2)
        XCTAssertEqual(deal.declarations?.meldWinner, 2)
        XCTAssertEqual(deal.sevenExchange, SevenExchangeRecord(seat: 1, gave: c("7ч"), took: c("Дч")))
        XCTAssertEqual(deal.initialHands.map(\.count), [9, 9, 9])
        XCTAssertEqual(deal.lastTrick, deal.tricks.last)

        try continueFirstLegal(&m)
        XCTAssertEqual(m.totals, [701, 573, 478], "Партия из сохранения доигрывается так же, как в версии 1")
        XCTAssertEqual(m.winner, 0)
        XCTAssertEqual(m.history.count, 15)
        XCTAssertEqual(m.pot, 0)
    }

    func testDecodesV1TwoPlayersSecondRoundBidding() throws {
        var m = try decode(SaveFixturesV1.twoPlayersBidding)
        XCTAssertEqual(m.totals, [485, 181])
        XCTAssertEqual(m.dealCount, 12)
        XCTAssertEqual(m.dealer, 1)
        XCTAssertEqual(m.history.count, 11)
        XCTAssertEqual(m.baitCounts, [1, 2])
        XCTAssertEqual(m.nakedCounts, [0, 1])
        let deal = try XCTUnwrap(m.deal)
        XCTAssertEqual(deal.phase, .bidding(round: 2))
        XCTAssertEqual(deal.handCounts, [6, 6])
        XCTAssertNil(deal.trump)
        XCTAssertEqual(deal.turn, 0)

        try continueFirstLegal(&m)
        XCTAssertEqual(m.totals, [794, 500])
        XCTAssertEqual(m.dealCount, 18)
        XCTAssertEqual(m.winner, 0)
    }

    func testDecodesV1TwoPlayersExchangeWithCustomRules() throws {
        var m = try decode(SaveFixturesV1.twoPlayersExchange)
        XCTAssertEqual(m.names, ["Папа", "Нина"])
        XCTAssertEqual(m.rules.targetScore, 501)
        XCTAssertEqual(m.rules.overtrump, .always)
        XCTAssertTrue(m.rules.hundredForFive)
        XCTAssertEqual(m.rules.firstLead, .bidder)
        XCTAssertTrue(m.rules.bellaInMelds, "Новые правила — по умолчанию")
        XCTAssertTrue(m.rules.fourSevensKeepsForcedStreak)
        XCTAssertEqual(m.totals, [179, 286])
        XCTAssertEqual(m.allPassStreak, 2)
        let deal = try XCTUnwrap(m.deal)
        XCTAssertEqual(deal.phase, .exchange)
        XCTAssertEqual(deal.trump, .diamonds)
        XCTAssertEqual(deal.bidder, 1)
        XCTAssertTrue(deal.forced)

        try continueFirstLegal(&m)
        XCTAssertEqual(m.totals, [189, 555])
        XCTAssertEqual(m.winner, 1)
    }

    func testDecodesV1ThreePlayersAfterDealSummary() throws {
        var m = try decode(SaveFixturesV1.threePlayersDealFinished)
        XCTAssertEqual(m.totals, [40, 484, 341])
        XCTAssertEqual(m.baitCounts, [3, 2, 1])
        XCTAssertTrue(m.needsNewDeal, "Сохранено на итогах сдачи — дальше новая раздача")
        let deal = try XCTUnwrap(m.deal)
        XCTAssertEqual(deal.phase, .finished)
        XCTAssertEqual(deal.tricks.count, 9)
        XCTAssertEqual(deal.declarations?.bellaSeat, 1)
        XCTAssertTrue(deal.bellaAnnounced)

        try continueFirstLegal(&m)
        XCTAssertEqual(m.totals, [434, 645, 676])
        XCTAssertEqual(m.dealCount, 15)
        XCTAssertEqual(m.history.count, 14)
        XCTAssertNil(m.winner)
    }

    func testDecodesV1FinishedMatch() throws {
        let m = try decode(SaveFixturesV1.twoPlayersOver)
        XCTAssertEqual(m.rules.targetScore, 301)
        XCTAssertEqual(m.totals, [213, 389])
        XCTAssertEqual(m.winner, 1)
        XCTAssertTrue(m.isOver)
        XCTAssertFalse(m.needsNewDeal)
        XCTAssertTrue(m.history.contains { $0.forced })
        XCTAssertTrue(m.history.contains { $0.outcome == .fourSevens })
    }

    // MARK: - Текущий формат

    func testEncodesSchemaVersionAndRoundTrips() throws {
        for json in [SaveFixturesV1.threePlayersPlaying, SaveFixturesV1.twoPlayersBidding,
                     SaveFixturesV1.twoPlayersExchange, SaveFixturesV1.threePlayersDealFinished,
                     SaveFixturesV1.twoPlayersOver] {
            let old = try decode(json)
            let data = try JSONEncoder().encode(old)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["schemaVersion"] as? Int, Match.schemaVersion)
            XCTAssertEqual(try JSONDecoder().decode(Match.self, from: data), old)
        }
    }

    func testNewDealScoreFieldsAreSavedAndRead() throws {
        var m = Match(playerCount: 3, names: ["Вы", "Саша", "Миша"], rules: .house, seed: 21)
        while !m.history.contains(where: \.wasPlayed) {
            if m.needsNewDeal { m.startNextDeal() } else { try m.apply(try XCTUnwrap(m.deal).legalActions()[0]) }
        }
        let played = try XCTUnwrap(m.history.first(where: \.wasPlayed))
        XCTAssertNotNil(played.declarations)
        XCTAssertNotNil(played.baitCountsAfter)
        XCTAssertNotNil(played.nakedCountsAfter)
        let decoded = try JSONDecoder().decode(Match.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(decoded, m)
    }

    // MARK: - Терпимое чтение

    func testMissingKeysUseDefaults() throws {
        var object = try object(SaveFixturesV1.threePlayersPlaying)
        for key in ["pot", "allPassStreak", "dealCount", "baitCounts", "nakedCounts", "names", "winner"] {
            object.removeValue(forKey: key)
        }
        var deal = try XCTUnwrap(object["deal"] as? [String: Any])
        for key in ["bellaAnnounced", "allPassed", "prikupDealt", "bottomCardVisible", "bids", "forced"] {
            deal.removeValue(forKey: key)
        }
        object["deal"] = deal
        var m = try decode(object)
        XCTAssertEqual(m.pot, 0)
        XCTAssertEqual(m.allPassStreak, 0)
        XCTAssertEqual(m.baitCounts, [0, 0, 0])
        XCTAssertEqual(m.names.count, 3)
        XCTAssertEqual(m.dealCount, 15, "Номер недоигранной сдачи — следующий за последней записанной")
        let restored = try XCTUnwrap(m.deal)
        XCTAssertEqual(restored.phase, .playing)
        XCTAssertTrue(restored.prikupDealt, "Прикуп уже роздан — это видно по картам")
        XCTAssertTrue(restored.bottomCardVisible)
        XCTAssertFalse(restored.allPassed)
        try m.apply(try XCTUnwrap(m.deal).legalActions()[0])
    }

    func testInferredDealFlagsMatchSavedOnes() throws {
        for json in [SaveFixturesV1.threePlayersPlaying, SaveFixturesV1.twoPlayersBidding,
                     SaveFixturesV1.twoPlayersExchange, SaveFixturesV1.threePlayersDealFinished,
                     SaveFixturesV1.twoPlayersOver] {
            var object = try object(json)
            var deal = try XCTUnwrap(object["deal"] as? [String: Any])
            for key in ["bellaAnnounced", "allPassed", "prikupDealt", "bottomCardVisible"] {
                deal.removeValue(forKey: key)
            }
            object["deal"] = deal
            XCTAssertEqual(try decode(object), try decode(json), "Флаги сдачи восстанавливаются по картам")
        }
    }

    func testUnknownKeysAreIgnored() throws {
        var object = try object(SaveFixturesV1.threePlayersPlaying)
        object["futureField"] = ["a": 1]
        var deal = try XCTUnwrap(object["deal"] as? [String: Any])
        deal["futureDealField"] = true
        object["deal"] = deal
        var history = try XCTUnwrap(object["history"] as? [[String: Any]])
        history[0]["futureScoreField"] = "x"
        object["history"] = history
        XCTAssertEqual(try decode(object), try decode(SaveFixturesV1.threePlayersPlaying))
    }

    func testUnreadableCurrentDealIsRedealtKeepingScore() throws {
        var object = try object(SaveFixturesV1.threePlayersPlaying)
        var deal = try XCTUnwrap(object["deal"] as? [String: Any])
        var stock = try XCTUnwrap(deal["stock"] as? [Any])
        stock.removeLast()   // одна карта потерялась — сдача несогласованная
        deal["stock"] = stock
        object["deal"] = deal
        var m = try decode(object)
        XCTAssertNil(m.deal)
        XCTAssertTrue(m.needsNewDeal)
        XCTAssertEqual(m.totals, [518, 573, 418])
        XCTAssertEqual(m.pot, 58)
        XCTAssertEqual(m.history.count, 14)
        XCTAssertEqual(m.dealCount, 14)
        m.startNextDeal()
        XCTAssertEqual(m.deal?.dealer, 0, "Недоигранную сдачу пересдаёт тот же сдающий")
        XCTAssertEqual(m.dealCount, 15)
    }

    func testUnreadableFinishedDealMovesDealerOn() throws {
        var object = try object(SaveFixturesV1.threePlayersDealFinished)
        object["deal"] = ["broken": true]
        var m = try decode(object)
        XCTAssertNil(m.deal)
        XCTAssertEqual(m.dealCount, 8)
        XCTAssertEqual(m.dealer, 0, "Сдача 8 уже записана — следующую сдаёт следующий после 2-го")
        m.startNextDeal()
        XCTAssertEqual(m.deal?.dealer, 0)
        XCTAssertEqual(m.dealCount, 9)
    }

    func testUnreadableHistoryEntryIsSkipped() throws {
        var object = try object(SaveFixturesV1.threePlayersPlaying)
        var history = try XCTUnwrap(object["history"] as? [[String: Any]])
        history[3]["outcome"] = "somethingNew"
        object["history"] = history
        let m = try decode(object)
        XCTAssertEqual(m.history.count, 13)
        XCTAssertEqual(m.totals, [518, 573, 418])
        XCTAssertNotNil(m.deal)
    }

    func testMissingOptionalScoreArraysAreZeros() throws {
        var object = try object(SaveFixturesV1.twoPlayersBidding)
        var history = try XCTUnwrap(object["history"] as? [[String: Any]])
        for key in ["bonus", "naked", "potAwarded", "bellaPoints", "trump"] { history[0].removeValue(forKey: key) }
        object["history"] = history
        let m = try decode(object)
        XCTAssertEqual(m.history.count, 11)
        XCTAssertEqual(m.history[0].bonus, [0, 0])
        XCTAssertEqual(m.history[0].naked, [false, false])
    }

    func testSaveWithoutScoreIsRejected() throws {
        var object = try object(SaveFixturesV1.twoPlayersBidding)
        object.removeValue(forKey: "totals")
        XCTAssertThrowsError(try decode(object), "Без счёта партию не восстановить — приложение отложит файл")
        XCTAssertThrowsError(try JSONDecoder().decode(Match.self, from: Data("[]".utf8)))
    }

    func testPlayerStatsDecodeTolerantly() throws {
        let stats = try JSONDecoder().decode(PlayerStats.self, from: Data(#"{"total": {"played": 3}, "bestStreak": 2, "x": 1}"#.utf8))
        XCTAssertEqual(stats.total, PlayerStats.Record(played: 3, won: 0))
        XCTAssertEqual(stats.bestStreak, 2)
        XCTAssertEqual(stats.byLevel, [:])
        XCTAssertEqual(try JSONDecoder().decode(PlayerStats.self, from: Data("{}".utf8)), PlayerStats())
    }
}
