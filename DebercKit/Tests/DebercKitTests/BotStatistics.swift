import XCTest
import Foundation
@testable import DebercKit

/// Статистика самоигры каждого уровня: как часто берут игру, байты, «все пас», обязы,
/// штрафы и «подарки» (последним во взятке отдал 10+ очков, хотя мог сбросить мелочь).
/// Запуск:
/// DEBERC_STATS=1 swift test -c release -Xswiftc -enable-testing --filter BotStatistics
final class BotStatistics: XCTestCase {

    struct Tally {
        var deals = 0, matches = 0
        var outcomes: [DealScore.Outcome: Int] = [:]
        var forced = 0, nakedPenalties = 0, baitPenalties = 0
        var lastToPlay = 0, gifts = 0

        mutating func add(_ o: Tally) {
            deals += o.deals; matches += o.matches
            for (k, v) in o.outcomes { outcomes[k, default: 0] += v }
            forced += o.forced; nakedPenalties += o.nakedPenalties; baitPenalties += o.baitPenalties
            lastToPlay += o.lastToPlay; gifts += o.gifts
        }
    }

    static func selfPlay(level: BotLevel, players: Int, seed: UInt64) -> Tally {
        let bot = Bot(level: level)
        var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)), rules: .house, seed: seed)
        var rng = SplitMix64(seed: seed &+ 5)
        var t = Tally()
        while !match.isOver {
            if match.needsNewDeal { match.startNextDeal(); continue }
            guard let actor = match.actor, let deal = match.deal else { break }
            let action = bot.chooseAction(match: match, seat: actor, rng: &rng)
            if case .play(let card) = action, let trump = deal.trump,
               deal.currentTrick.plays.count == players - 1 {
                let trick = deal.currentTrick.cards
                let best = trick[PlayRules.winningIndex(trick, trump: trump)]
                let led = trick[0].suit
                let legal = deal.legalCards(for: actor)
                t.lastToPlay += 1
                let loses = !PlayRules.beats(card, best, led: led, trump: trump)
                let cheapLoser = legal.contains {
                    $0.points(trump: trump) <= 4 && !PlayRules.beats($0, best, led: led, trump: trump)
                }
                if loses && card.points(trump: trump) >= 10 && cheapLoser { t.gifts += 1 }
            }
            try! match.apply(action)
        }
        t.matches = 1
        for score in match.history {
            t.deals += 1
            t.outcomes[score.outcome, default: 0] += 1
            if score.forced { t.forced += 1 }
            t.nakedPenalties += score.nakedPenalty.filter { $0 }.count
            t.baitPenalties += score.baitPenalty.filter { $0 }.count
        }
        return t
    }

    func testSelfPlayStatistics() throws {
        guard ProcessInfo.processInfo.environment["DEBERC_STATS"] != nil else { return }
        let matches = Int(ProcessInfo.processInfo.environment["DEBERC_GAMES"] ?? "") ?? 40
        for players in [2, 3] {
            for level in BotLevel.allCases {
                let parts = BotExperiments.parallel(matches) { m in
                    BotStatistics.selfPlay(level: level, players: players, seed: UInt64(900 + m))
                }
                var t = Tally()
                for p in parts { t.add(p) }
                func pct(_ n: Int) -> String { String(format: "%.1f%%", 100.0 * Double(n) / Double(max(t.deals, 1))) }
                let played = t.outcomes[.made, default: 0] + t.outcomes[.bait, default: 0]
                    + t.outcomes[.hanging, default: 0] + t.outcomes[.tie, default: 0]
                print("STATS \(players)p \(level.title): сдач на партию \(String(format: "%.1f", Double(t.deals) / Double(matches))),"
                      + " сыграно \(pct(t.outcomes[.made, default: 0])), байт \(pct(t.outcomes[.bait, default: 0]))"
                      + " (\(String(format: "%.1f%%", 100.0 * Double(t.outcomes[.bait, default: 0]) / Double(max(played, 1)))) взятых игр),"
                      + " висячий \(pct(t.outcomes[.hanging, default: 0])), все пас \(pct(t.outcomes[.allPassed, default: 0])),"
                      + " обязы \(pct(t.forced)), 4×7 \(pct(t.outcomes[.fourSevens, default: 0])),"
                      + " штрафов за байты \(t.baitPenalties), за голого \(t.nakedPenalties),"
                      + " подарков \(String(format: "%.2f%%", 100.0 * Double(t.gifts) / Double(max(t.lastToPlay, 1))))")
            }
        }
    }
}
