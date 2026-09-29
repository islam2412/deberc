import Foundation
import DebercKit

// Дуэль по сдачам: бот A на одном месте против ботов B на остальных; каждая сдача играется
// столько раз, сколько игроков, с A на каждом месте (везение в раздаче взаимно гасится).
//
//   BeliefDuel <A> <B> <игроков> <сдач> <зерно> [потоков]
//
// Бот задаётся строкой: уровень и поправки через «+», например `master+bl=1` (с «чутьём»),
// `master+sv=0` (прежний Мастер без точного решателя), `master+pi=0`, `master+budget=0`.

func bot(_ spec: String) -> Bot {
    var parts = spec.split(separator: "+").map(String.init)
    let level = BotLevel(rawValue: parts.removeFirst()) ?? .master
    var c = Bot.Config.preset(level)
    for p in parts {
        let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
        let v = Double(kv[1]) ?? 0
        switch kv[0] {
        case "sv": c.exactSolver = v != 0
        case "pi": c.playInference = v
        case "am": c.auctionModel = v != 0
        case "bl": c.belief = v
        case "ps": c.playSamples = Int(v)
        case "bs": c.biddingSamples = Int(v)
        case "budget": c.timeBudget = v <= 0 ? nil : v
        default: fatalError("unknown tweak \(kv[0])")
        }
    }
    return Bot(config: c, level: level)
}

let args = CommandLine.arguments
guard args.count >= 6 else { print("usage: BeliefDuel <A> <B> <players> <deals> <seed> [threads]"); exit(2) }
let a = bot(args[1]), b = bot(args[2])
let players = Int(args[3]) ?? 2
let deals = Int(args[4]) ?? 1000
let seedBase = UInt64(args[5]) ?? 1
let workers = args.count > 6 ? Int(args[6]) ?? ProcessInfo.processInfo.activeProcessorCount : ProcessInfo.processInfo.activeProcessorCount

let start = Date()
var diffs = [Double](repeating: 0, count: deals)
let lock = NSLock()
DispatchQueue.concurrentPerform(iterations: workers) { w in
    var d = w
    while d < deals {
        var deckRng = SplitMix64(seed: seedBase &* 1_000_003 &+ UInt64(d))
        var deck = Card.deck
        deck.shuffle(using: &deckRng)
        var sum = 0.0
        for aSeat in 0..<players {
            var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)), rules: .house, seed: 1)
            match.startDeal(deck: deck, dealer: 0)
            var rng = SplitMix64(seed: seedBase &+ UInt64(d) &* 7919 &+ UInt64(aSeat))
            while let actor = match.actor, !match.needsNewDeal {
                let action = (actor == aSeat ? a : b).chooseAction(match: match, seat: actor, rng: &rng)
                _ = try! match.apply(action)
            }
            let score = match.history.last!
            let others = (0..<players).filter { $0 != aSeat }
            sum += Double(score.change[aSeat]) - others.map { Double(score.change[$0]) }.reduce(0, +) / Double(players - 1)
        }
        lock.lock()
        diffs[d] = sum / Double(players)
        lock.unlock()
        d += workers
    }
}
let mean = diffs.reduce(0, +) / Double(deals)
let variance = diffs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(deals - 1, 1))
let se = (variance / Double(deals)).squareRoot()
print(String(format: "DUEL %@ vs %@ %dp: %+.2f ± %.2f points/deal (n=%d, seed %d) %d s",
             args[1], args[2], players, mean, se, deals, Int(seedBase), Int(Date().timeIntervalSince(start))))
