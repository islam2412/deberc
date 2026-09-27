import XCTest
import DebercKit

/// Подбор параметров ИИ. Запуск:
/// DEBERC_EXPERIMENT=1 swift test -c release -Xswiftc -enable-testing --filter BotExperiments
final class BotExperiments: XCTestCase {

    private func tournament(_ a: Bot.Config, _ b: Bot.Config, games: Int, players: Int = 2, seedBase: UInt64) throws -> (Int, Int) {
        var winsA = 0, winsB = 0
        for g in 0..<games {
            // Чередуем места, чтобы уравнять очерёдность.
            let aSeat = g % players
            var configs = [Bot.Config](repeating: b, count: players)
            configs[aSeat] = a
            let bots = configs.map { Bot(config: $0) }
            var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)),
                              rules: .house, seed: seedBase &+ UInt64(g / players))
            var rng = SplitMix64(seed: seedBase &+ UInt64(g) &* 31)
            while !match.isOver {
                if match.needsNewDeal { match.startNextDeal(); continue }
                guard let actor = match.actor else { break }
                try match.apply(bots[actor].chooseAction(match: match, seat: actor, rng: &rng))
            }
            if match.winner == aSeat { winsA += 1 } else { winsB += 1 }
        }
        return (winsA, winsB)
    }

    func testCompareConfigs() throws {
        guard ProcessInfo.processInfo.environment["DEBERC_EXPERIMENT"] != nil else { return }
        let games = Int(ProcessInfo.processInfo.environment["DEBERC_GAMES"] ?? "") ?? 100
        let hard = Bot.Config.preset(.hard)
        let medium = Bot.Config.preset(.medium)
        var variants: [(String, Bot.Config)] = []
        var more = hard; more.playSamples = 128; more.biddingSamples = 160
        variants.append(("больше выборок", more))
        for t in [0.0, 16.0, 25.0] {
            var v = hard; v.takeThreshold = t
            variants.append(("порог взять \(Int(t))", v))
        }
        for t in [-10.0, 10.0] {
            var v = hard; v.nameThreshold = t
            variants.append(("порог назвать \(Int(t))", v))
        }
        let start = Date()
        let (h, m) = try tournament(hard, medium, games: games, seedBase: 5000)
        print("EXP hard vs medium: \(h)–\(m)")
        for (label, config) in variants {
            let (a, b) = try tournament(config, hard, games: games, seedBase: 7000)
            print("EXP \(label) vs hard: \(a)–\(b)")
        }
        print("EXP time \(Int(Date().timeIntervalSince(start)))s")
    }
}
