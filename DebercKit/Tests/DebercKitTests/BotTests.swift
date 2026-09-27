import XCTest
import DebercKit

/// Прогоняет партию, где за всех играют боты указанных уровней.
@discardableResult
func playBotMatch(levels: [BotLevel], seed: UInt64, rules: RuleSet = .house) throws -> Match {
    let names = Array(["A", "B", "C"].prefix(levels.count))
    var match = Match(playerCount: levels.count, names: names, rules: rules, seed: seed)
    var rng = SplitMix64(seed: seed &+ 99)
    let bots = levels.map { Bot(level: $0) }
    var steps = 0
    while !match.isOver {
        steps += 1
        if steps > 50_000 { XCTFail("Партия не заканчивается"); break }
        if match.needsNewDeal {
            match.startNextDeal()
            continue
        }
        guard let actor = match.actor else { break }
        let action = bots[actor].chooseAction(match: match, seat: actor, rng: &rng)
        try match.apply(action)
    }
    return match
}

final class BotTests: XCTestCase {

    func testBotsFinishTwoPlayerMatches() throws {
        for seed in 0..<3 {
            let match = try playBotMatch(levels: [.easy, .medium], seed: UInt64(seed))
            XCTAssertNotNil(match.winner)
        }
    }

    func testBotsFinishThreePlayerMatches() throws {
        for seed in 0..<2 {
            let match = try playBotMatch(levels: [.easy, .medium, .easy], seed: UInt64(100 + seed))
            XCTAssertNotNil(match.winner)
        }
    }

    func testHardBotPlaysLegallyForAWhile() throws {
        var match = Match(playerCount: 3, names: ["A", "B", "C"], rules: .house, seed: 3)
        var rng = SplitMix64(seed: 1)
        let bot = Bot(level: .hard)
        var deals = 0
        while deals < 3 && !match.isOver {
            if match.needsNewDeal {
                match.startNextDeal()
                deals += 1
                continue
            }
            guard let actor = match.actor else { break }
            try match.apply(bot.chooseAction(match: match, seat: actor, rng: &rng))
        }
    }

    /// Сильная рука на открытую масть — бот берёт; слабая — пасует.
    func testBiddingJudgement() throws {
        let strong = [Card(.jack, .hearts), Card(.nine, .hearts), Card(.ace, .hearts),
                      Card(.ten, .hearts), Card(.ace, .spades), Card(.ace, .clubs)]
        let weak = [Card(.seven, .spades), Card(.eight, .clubs), Card(.nine, .diamonds),
                    Card(.eight, .spades), Card(.seven, .clubs), Card(.queen, .diamonds)]
        let used = Set(strong + weak + [Card(.king, .hearts)])
        var rest = Card.deck.filter { !used.contains($0) }
        var shuffleRng = SplitMix64(seed: 5)
        rest.shuffle(using: &shuffleRng)
        // Сдаёт 0-й, первым говорит 1-й (у него сильная рука), у 0-го — слабая.
        var deck: [Card] = []
        deck += strong[0..<3]; deck += weak[0..<3]
        deck += strong[3..<6]; deck += weak[3..<6]
        deck.append(Card(.king, .hearts))
        deck += rest
        var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        match.startDeal(deck: deck, dealer: 0)
        var rng = SplitMix64(seed: 2)
        let bot = Bot(level: .medium)
        XCTAssertEqual(match.actor, 1)
        XCTAssertEqual(bot.chooseAction(match: match, seat: 1, rng: &rng), .take)

        // Та же сдача, но слабая рука у первого говорящего.
        var deck2: [Card] = []
        deck2 += weak[0..<3]; deck2 += strong[0..<3]
        deck2 += weak[3..<6]; deck2 += strong[3..<6]
        deck2.append(Card(.king, .hearts))
        deck2 += rest
        var match2 = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        match2.startDeal(deck: deck2, dealer: 0)
        XCTAssertEqual(Set(match2.deal!.hands[1]), Set(weak))
        XCTAssertEqual(bot.chooseAction(match: match2, seat: 1, rng: &rng), .pass)
    }

    /// Турнир для оценки силы. Запуск: DEBERC_BENCH=1 swift test -c release --filter BotTests/testBenchmark
    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["DEBERC_BENCH"] != nil else { return }
        for (label, levels) in [("hard vs easy", [BotLevel.hard, .easy]),
                                ("medium vs easy", [.medium, .easy]),
                                ("hard vs medium", [.hard, .medium])] {
            var wins = [0, 0]
            let start = Date()
            let games = 20
            for g in 0..<games {
                // Меняем места, чтобы уравнять очерёдность.
                let swapped = g % 2 == 1
                let seatLevels = swapped ? levels.reversed() : levels
                let match = try playBotMatch(levels: Array(seatLevels), seed: UInt64(1000 + g))
                guard let w = match.winner else { continue }
                let winnerLevelIndex = swapped ? 1 - w : w
                wins[winnerLevelIndex] += 1
            }
            print("BENCH \(label): \(wins[0])–\(wins[1]) за \(games) партий, \(Int(Date().timeIntervalSince(start)))с")
        }
    }
}
