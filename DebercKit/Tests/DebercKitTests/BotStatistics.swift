import XCTest
import DebercKit

/// Статистика самоигры ботов. Запуск:
/// DEBERC_STATS=1 swift test -c release -Xswiftc -enable-testing --filter BotStatistics
final class BotStatistics: XCTestCase {

    func testSelfPlayStatistics() throws {
        guard ProcessInfo.processInfo.environment["DEBERC_STATS"] != nil else { return }
        for players in [2, 3] {
            for level in [BotLevel.medium, .hard] {
                var outcomes: [DealScore.Outcome: Int] = [:]
                var deals = 0
                var forced = 0
                var nakedPenalties = 0
                var baitPenalties = 0
                let matches = 40
                for m in 0..<matches {
                    let match = try playBotMatch(levels: Array(repeating: level, count: players), seed: UInt64(900 + m))
                    for score in match.history {
                        deals += 1
                        outcomes[score.outcome, default: 0] += 1
                        if score.forced { forced += 1 }
                        nakedPenalties += score.nakedPenalty.filter { $0 }.count
                        baitPenalties += score.baitPenalty.filter { $0 }.count
                    }
                }
                func pct(_ n: Int) -> String { String(format: "%.1f%%", 100.0 * Double(n) / Double(max(deals, 1))) }
                print("STATS \(players)p \(level.rawValue): сдач на партию \(String(format: "%.1f", Double(deals) / Double(matches))),"
                      + " сыграно \(pct(outcomes[.made, default: 0])), байт \(pct(outcomes[.bait, default: 0])),"
                      + " висячий \(pct(outcomes[.hanging, default: 0])), все пас \(pct(outcomes[.allPassed, default: 0])),"
                      + " обязы \(pct(forced)), 4×7 \(pct(outcomes[.fourSevens, default: 0])),"
                      + " штрафов за байты \(baitPenalties), за голого \(nakedPenalties)")
            }
        }
    }
}
