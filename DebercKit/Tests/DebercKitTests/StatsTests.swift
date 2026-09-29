import XCTest
@testable import DebercKit

final class StatsTests: XCTestCase {

    /// Доигрывает партию первым допустимым действием.
    private func finishedMatch(seed: UInt64, players: Int = 2, rules: RuleSet = .house) throws -> Match {
        var m = Match(playerCount: players, names: Array(["Вы", "Саша", "Миша"].prefix(players)),
                      rules: rules, seed: seed)
        while !m.isOver {
            if m.needsNewDeal { m.startNextDeal() } else { try m.apply(try XCTUnwrap(m.deal).legalActions()[0]) }
        }
        return m
    }

    func testRecordsFinishedMatchOnce() throws {
        let m = try finishedMatch(seed: 7)
        var stats = PlayerStats()
        XCTAssertTrue(stats.record(match: m, humanSeat: 0, personaIDs: ["misha"], levelKey: "expert"))
        XCTAssertFalse(stats.record(match: m, humanSeat: 0, personaIDs: ["misha"], levelKey: "expert"),
                       "Одну партию дважды не записываем")
        let won = m.winner == 0
        XCTAssertEqual(stats.total, PlayerStats.Record(played: 1, won: won ? 1 : 0))
        XCTAssertEqual(stats.byLevel["expert"], stats.total)
        XCTAssertEqual(stats.byPersona["misha"], stats.total)
        XCTAssertEqual(stats.currentStreak, won ? 1 : -1)
        XCTAssertEqual(stats.bestStreak, won ? 1 : 0)
        XCTAssertEqual(stats.bestMatchScore, max(0, m.totals[0]))
        let asBidder = m.history.filter { $0.wasPlayed && $0.bidder == 0 }
        XCTAssertEqual(stats.dealsAsBidder, asBidder.count)
        XCTAssertEqual(stats.dealsMade, asBidder.filter { $0.outcome == .made }.count)
        let countsHanging = m.rules.hangingCountsAsBait
        XCTAssertEqual(stats.baits, asBidder.filter { $0.outcome == .bait || (countsHanging && $0.outcome == .hanging) }.count)
        XCTAssertGreaterThan(stats.dealsAsBidder, 0)
    }

    /// Висячий байт идёт в «Байтов», только если по правилам партии он считается байтом.
    func testHangingCountsAsBaitOnlyByRule() throws {
        for counts in [false, true] {
            var rules = RuleSet.house
            rules.hangingCountsAsBait = counts
            var checked = false
            for seed in 0..<300 {
                let m = try finishedMatch(seed: UInt64(seed), rules: rules)
                let asBidder = m.history.filter { $0.wasPlayed && $0.bidder == 0 }
                let hanging = asBidder.filter { $0.outcome == .hanging }.count
                guard hanging > 0 else { continue }
                var stats = PlayerStats()
                stats.record(match: m, humanSeat: 0, personaIDs: [], levelKey: nil)
                let plain = asBidder.filter { $0.outcome == .bait }.count
                XCTAssertEqual(stats.baits, plain + (counts ? hanging : 0), "seed \(seed)")
                checked = true
                break
            }
            XCTAssertTrue(checked, "Не нашлось партии с висячим байтом (правило: \(counts))")
        }
    }

    func testMatchResultTitle() throws {
        let m = try finishedMatch(seed: 7)
        let winner = try XCTUnwrap(m.winner)
        XCTAssertEqual(Narrator.matchResult(m, humanSeat: winner), "Вы выиграли партию!")
        XCTAssertEqual(Narrator.matchResult(m, humanSeat: 1 - winner), "Победа: \(m.names[winner])")
        XCTAssertNil(Narrator.matchResult(Match(playerCount: 2, names: ["Вы", "Саша"], rules: .house, seed: 1), humanSeat: 0))
    }

    func testUnfinishedMatchIsNotRecorded() {
        var m = Match(playerCount: 2, names: ["Вы", "Саша"], rules: .house, seed: 1)
        m.startNextDeal()
        var stats = PlayerStats()
        XCTAssertFalse(stats.record(match: m, humanSeat: 0, personaIDs: [], levelKey: nil))
        XCTAssertEqual(stats, PlayerStats())
    }

    func testStreaksAcrossMatches() throws {
        var stats = PlayerStats()
        var expectedStreak = 0
        var best = 0
        var wins = 0
        for seed in 0..<12 {
            let m = try finishedMatch(seed: UInt64(seed), players: seed % 2 == 0 ? 2 : 3)
            let won = m.winner == 0
            stats.record(match: m, humanSeat: 0, personaIDs: seed % 2 == 0 ? ["a"] : ["a", "b"],
                         levelKey: seed % 2 == 0 ? "novice" : "master")
            if won {
                wins += 1
                expectedStreak = expectedStreak > 0 ? expectedStreak + 1 : 1
                best = max(best, expectedStreak)
            } else {
                expectedStreak = expectedStreak < 0 ? expectedStreak - 1 : -1
            }
            XCTAssertEqual(stats.currentStreak, expectedStreak)
        }
        XCTAssertEqual(stats.bestStreak, best)
        XCTAssertEqual(stats.total.played, 12)
        XCTAssertEqual(stats.total.won, wins)
        XCTAssertEqual(stats.byPersona["a"]?.played, 12)
        XCTAssertEqual(stats.byPersona["b"]?.played, 6)
        XCTAssertEqual(stats.byLevel["novice"]?.played, 6)
        XCTAssertEqual(stats.byLevel["master"]?.played, 6)
        XCTAssertEqual(try JSONDecoder().decode(PlayerStats.self, from: JSONEncoder().encode(stats)), stats)
    }

    func testRecordRates() {
        XCTAssertNil(PlayerStats.Record().winRate)
        let r = PlayerStats.Record(played: 3, won: 2)
        XCTAssertEqual(r.lost, 1)
        XCTAssertEqual(r.winPercent, 67)
    }
}
