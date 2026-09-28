import XCTest
import Foundation
@testable import DebercKit

/// Калибровка уровней ИИ дубликатным турниром.
///
/// Дубликат: каждая партия играется столько раз, сколько игроков, с одними и теми же
/// колодами, а место проверяемого бота меняется. Так везение в раздаче взаимно гасится,
/// и разница в силе видна на сотнях, а не на тысячах партий.
///
/// Запуск (release, все ядра):
/// ```
/// DEBERC_LADDER=1 swift test -c release --filter BotExperiments/testLadder
/// DEBERC_PAIR="master:expert" DEBERC_PLAYERS=2 DEBERC_GAMES=100 swift test -c release --filter BotExperiments/testPair
/// DEBERC_DEALS="expert+ps=24:expert" swift test -c release --filter BotExperiments/testDealDuplicate
/// DEBERC_TIMING=master swift test -c release --filter BotExperiments/testTiming
/// ```
/// Настройки бота задаются строкой: уровень и поправки через «+», например
/// `expert+ps=24+bs=32+e2=4+take=0+name=-12+style=bold`.
///
/// Итог калибровки (сентябрь 2026, release, Linux x86; 300 дубликатных пар = 600 партий до 701):
/// ```
/// вдвоём  Любитель — Новичок   65.5% ±3.8   Эло +111   +10.2 очка за сдачу
///         Знаток — Любитель    63.8% ±3.8   Эло  +99    +8.5
///         Мастер — Знаток      63.0% ±3.9   Эло  +92    +8.4
///         Мастер — Новичок     83.3% ±4.2   Эло +280   +25.7   (300 партий)
/// втроём  Мастер против двух Новичков   63.7% (честная доля 33%)
///         Знаток против двух Любителей  41.3%, Любитель против двух Новичков 49.3%
/// Стили (Знаток, 400/300 партий): рисковый 51.7% / 33.7%, осторожный 47.8% / 34.7% —
/// сила в пределах погрешности, а берут игру 52% и 45% сдач против 48% у ровного.
/// ```
/// Что проверено и НЕ дало силы (очки за сдачу против Мастера, дубликат по сдачам, n = 2000–3000):
/// 320 миров вместо 160: +0.00 ±0.34; точный перебор с 7 карт вместо 6: +0.02 ±0.36 (вчетверо дольше);
/// 256 выборок торговли вместо 128: −0.79 ±0.47; пороги 0/−9: −0.14 ±0.45, 8/−2: −0.85 ±0.43;
/// учёт чужих заявок при оценке своей: −0.84 ±0.40 (Знаток −0.29 ±0.53);
/// точная концовка внутри доигрываний (4 взятки): −0.67 ±0.31 (у Знатока +1.26, но это сжимает лестницу);
/// «равноценными» считать карты в пределах 0.5 очка: −0.44 ±0.30.
/// Что дало силу Мастеру: миры с учётом торговли и объявлений +1.13 ±0.37,
/// альфа-бета с 6 карт вместо перебора с 4: +2.14 ±0.41.
/// Новичок: ошибки «на автомате» стоят ему 2.2 ±0.3 очка за сдачу, «настроение» в торговле — основная слабость.
///
/// Точный решатель вдвоём (`TwoPlayerSolver`, сентябрь 2026, M4 Pro; дубликат по сдачам, очки за сдачу):
/// против прежнего Мастера — розыгрыш каждого мира точно +1.35 ±0.58 (n = 1000), и торговля по точным
/// итогам +1.3…+2.0 (n = 1000–1500). Против нового Мастера (оба без предела времени, n = 2000):
/// торговля с ценой паса (`auctionModel`) +1.46 ±0.59 и +1.27 ±0.61 на другой колоде; чтение ходов
/// соперника (`playInference` 0.15) +1.02 ±0.39; пороги торговли ±4 и учёт чужих заявок (`ib`) —
/// в пределах ±0.5, без пользы. Для сравнения, торговля, которая видит чужие карты (только замер),
/// дала бы +9.8 ±1.1 — торговля решает много.
/// Итог, партии до 701 (300 пар, с пределом времени, 12 партий одновременно): новый Мастер против
/// прежнего — 51.5% ±4.0 побед, +2.29 ±0.65 очка за сдачу, берёт игру в 58% сдач.
/// Время хода (M4 Pro под нагрузкой): торговля ≈ 0.4 с, ход ≈ 0.3 с (прежний Мастер — 2 и 19 мс).
/// Лестница с новым Мастером (200 пар, вдвоём): Мастер — Знаток 66.0% ±4.6, Эло +115, +10.43 ±0.90
/// очка за сдачу (было 62.5% и +8.24); Эло вдвоём: Новичок 0, Любитель 123, Знаток 231, Мастер 346.
/// Втроём не помогло ничего (1500 сдач, всё в пределах ±0.5): альфа-бета «играющий против защитников»
/// с 4 и 5 карт вместо max^n с 4, точные концовки внутри доигрываний, max^n с 5 карт, пороги ±4.
final class BotExperiments: XCTestCase {

    // MARK: - Описание бота строкой

    static func bot(_ spec: String) -> Bot {
        var parts = spec.split(separator: "+").map(String.init)
        let base = parts.removeFirst()
        var level = BotLevel(tolerant: base)
        if base == "hint" { level = .master }
        var style = BotStyle.balanced
        for p in parts where p.hasPrefix("style=") {
            style = BotStyle(rawValue: String(p.dropFirst(6))) ?? .balanced
        }
        var c = Bot.Config.preset(level, style: style)
        if base == "hint" { c.timeBudget = nil }
        for p in parts {
            let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { fatalError("Не понял поправку \(p)") }
            let v = Double(kv[1]) ?? 0
            switch kv[0] {
            case "style": break
            case "ps": c.playSamples = Int(v)
            case "bs": c.biddingSamples = Int(v)
            case "e2": c.exactTwoPlayers = Int(v)
            case "e3": c.exactThreePlayers = Int(v)
            case "take": c.takeThreshold = v
            case "name": c.nameThreshold = v
            case "feel": c.feelShift = v
            case "mood": c.feelNoise = v
            case "forced": c.forcedAware = v != 0
            case "infer": c.inferFromBidding = v != 0
            case "ib": c.inferInBidding = v != 0
            case "mem": c.memoryTricks = v < 0 ? nil : Int(v)
            case "slip": c.slipPercent = Int(v)
            case "tie": c.tieMargin = v
            case "rx": c.rolloutExact = Int(v)
            case "budget": c.timeBudget = v <= 0 ? nil : v
            case "sv": c.exactSolver = v != 0
            case "pi": c.playInference = v
            case "am": c.auctionModel = v != 0
            case "ex": c.exchange = Bot.ExchangeMode(rawValue: kv[1]) ?? .always
            default: fatalError("Неизвестная поправка \(kv[0])")
            }
        }
        return Bot(config: c, level: level, style: style)
    }

    // MARK: - Параллельный прогон

    static var threads: Int {
        Int(ProcessInfo.processInfo.environment["DEBERC_THREADS"] ?? "")
            ?? max(1, ProcessInfo.processInfo.activeProcessorCount)
    }

    /// Выполнить `count` независимых задач на всех ядрах; результаты — по порядку.
    static func parallel<T>(_ count: Int, _ body: @escaping (Int) -> T) -> [T] {
        var results = [T?](repeating: nil, count: count)
        let lock = NSLock()
        let workers = min(threads, max(count, 1))
        DispatchQueue.concurrentPerform(iterations: workers) { w in
            var i = w
            while i < count {
                let r = body(i)
                lock.lock()
                results[i] = r
                lock.unlock()
                i += workers
            }
        }
        return results.map { $0! }
    }

    // MARK: - Партии

    struct MatchResult {
        var won: Bool
        /// Сумма по сдачам: (изменение счёта A) − (среднее у соперников).
        var diff: Double
        var deals: Int
        var bids = 0, made = 0, baits = 0
        var oppBids = 0, oppMade = 0
    }

    /// Партия, где бот `a` сидит на месте `aSeat`, остальные — `b`.
    static func playMatch(a: Bot, b: Bot, aSeat: Int, players: Int, seed: UInt64) -> MatchResult {
        var bots = [Bot](repeating: b, count: players)
        bots[aSeat] = a
        var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)),
                          rules: .house, seed: seed)
        var rng = SplitMix64(seed: seed &* 7919 &+ UInt64(aSeat) &+ 17)
        var steps = 0
        while !match.isOver && steps < 100_000 {
            steps += 1
            if match.needsNewDeal { match.startNextDeal(); continue }
            guard let actor = match.actor else { break }
            let action = bots[actor].chooseAction(match: match, seat: actor, rng: &rng)
            try! match.apply(action)
        }
        var r = MatchResult(won: match.winner == aSeat, diff: 0, deals: 0)
        for score in match.history where score.outcome != .allPassed && score.outcome != .fourSevens {
            r.deals += 1
            let others = (0..<players).filter { $0 != aSeat }
            r.diff += Double(score.change[aSeat]) - others.map { Double(score.change[$0]) }.reduce(0, +) / Double(players - 1)
            guard let bidder = score.bidder, !score.forced else { continue }
            if bidder == aSeat {
                r.bids += 1
                if score.outcome == .made { r.made += 1 }
                if score.outcome == .bait { r.baits += 1 }
            } else {
                r.oppBids += 1
                if score.outcome == .made { r.oppMade += 1 }
            }
        }
        return r
    }

    struct PairResult {
        var label: String
        var players: Int
        var games = 0
        var wins = 0
        var perSeed: [Double] = []   // очков за сдачу, по дубликатной паре
        var deals = 0
        var bids = 0, made = 0, oppBids = 0, oppMade = 0, dealsA = 0

        var winRate: Double { Double(wins) / Double(max(games, 1)) }
        var winCI: Double { 1.96 * (winRate * (1 - winRate) / Double(max(games, 1))).squareRoot() }
        var pointsPerDeal: Double { perSeed.reduce(0, +) / Double(max(perSeed.count, 1)) }
        var pointsSE: Double {
            let m = pointsPerDeal
            let v = perSeed.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(max(perSeed.count - 1, 1))
            return (v / Double(max(perSeed.count, 1))).squareRoot()
        }
        /// Эло по доле побед (для игры втроём — относительно честной доли 1/3).
        var elo: Double {
            let fair = 1.0 / Double(players)
            let p = min(max(winRate, 0.001), 0.999)
            if players == 2 { return -400 * log10(1 / p - 1) }
            // Втроём: переводим «доля побед против честной» в шансы один на один.
            let odds = (p / (1 - p)) / (fair / (1 - fair))
            return 400 * log10(odds)
        }

        var line: String {
            String(format: "%-26@ %dp  побед %5.1f%% ±%4.1f  (%d/%d)  Эло %+5.0f  очков/сдачу %+5.2f ±%4.2f  A берёт %4.1f%% сделано %4.1f%% | B сделано %4.1f%%",
                   label as NSString, players, 100 * winRate, 100 * winCI, wins, games, elo,
                   pointsPerDeal, pointsSE,
                   100 * Double(bids) / Double(max(dealsA, 1)),
                   100 * Double(made) / Double(max(bids, 1)),
                   100 * Double(oppMade) / Double(max(oppBids, 1)))
        }
    }

    /// Дубликатный турнир: `seeds` колодных последовательностей, на каждой A по очереди на всех местах.
    static func duplicate(_ aSpec: String, _ bSpec: String, players: Int, seeds: Int, seedBase: UInt64 = 40_000) -> PairResult {
        let a = bot(aSpec), b = bot(bSpec)
        let results = parallel(seeds * players) { i -> MatchResult in
            let seed = seedBase &+ UInt64(i / players)
            return playMatch(a: a, b: b, aSeat: i % players, players: players, seed: seed)
        }
        var r = PairResult(label: "\(aSpec) — \(bSpec)", players: players)
        for s in 0..<seeds {
            var diff = 0.0, deals = 0
            for k in 0..<players {
                let m = results[s * players + k]
                r.games += 1
                if m.won { r.wins += 1 }
                diff += m.diff
                deals += m.deals
                r.bids += m.bids; r.made += m.made; r.oppBids += m.oppBids; r.oppMade += m.oppMade
                r.dealsA += m.deals
            }
            r.deals += deals
            r.perSeed.append(diff / Double(max(deals, 1)))
        }
        return r
    }

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    // MARK: - Лестница уровней

    func testLadder() throws {
        guard env["DEBERC_LADDER"] != nil else { return }
        let seeds = Int(env["DEBERC_GAMES"] ?? "") ?? 100
        let seeds3 = Int(env["DEBERC_GAMES3"] ?? "") ?? max(seeds / 2, 20)
        let start = Date()
        var elo: [Double] = [0]
        let strict = env["DEBERC_LADDER_STRICT"] != nil
        for (a, b) in [("amateur", "novice"), ("expert", "amateur"), ("master", "expert")] {
            let r = BotExperiments.duplicate(a, b, players: 2, seeds: seeds)
            print("LADDER " + r.line)
            elo.append(elo.last! + r.elo)
            if strict { XCTAssertGreaterThanOrEqual(r.winRate, 0.6, r.label) }
        }
        let direct = BotExperiments.duplicate("master", "novice", players: 2, seeds: max(seeds / 2, 20))
        print("LADDER " + direct.line)
        for (a, b) in [("master", "novice"), ("expert", "amateur"), ("amateur", "novice")] {
            let r = BotExperiments.duplicate(a, b, players: 3, seeds: seeds3)
            print("LADDER " + r.line)
        }
        print("LADDER Эло вдвоём (Новичок = 0): "
              + zip(BotLevel.allCases, elo).map { "\($0.title) \(Int($1.rounded()))" }.joined(separator: ", "))
        print("LADDER время \(Int(Date().timeIntervalSince(start))) с")
    }

    /// Произвольная пара: DEBERC_PAIR="a:b".
    func testPair() throws {
        guard let spec = env["DEBERC_PAIR"] else { return }
        let names = spec.split(separator: ":").map(String.init)
        let players = Int(env["DEBERC_PLAYERS"] ?? "") ?? 2
        let seeds = Int(env["DEBERC_GAMES"] ?? "") ?? 100
        let seedBase = UInt64(env["DEBERC_SEED"] ?? "") ?? 40_000
        let start = Date()
        let r = BotExperiments.duplicate(names[0], names[1], players: players, seeds: seeds, seedBase: seedBase)
        print("PAIR " + r.line + "  \(Int(Date().timeIntervalSince(start))) с")
    }

    /// Стили торговли против ровного стиля того же уровня.
    func testStyles() throws {
        guard env["DEBERC_STYLES"] != nil else { return }
        let seeds = Int(env["DEBERC_GAMES"] ?? "") ?? 100
        let level = env["DEBERC_STYLES"].flatMap { BotLevel(rawValue: $0) } ?? .expert
        for players in [2, 3] {
            for style in [BotStyle.bold, .cautious] {
                let r = BotExperiments.duplicate("\(level.rawValue)+style=\(style.rawValue)", level.rawValue,
                                                 players: players, seeds: players == 2 ? seeds : seeds / 2)
                print("STYLE " + r.line)
            }
        }
    }

    // MARK: - Дубликат по отдельным сдачам (быстрая оценка в очках)

    func testDealDuplicate() throws {
        guard let spec = env["DEBERC_DEALS"] else { return }
        let names = spec.split(separator: ":").map(String.init)
        let players = Int(env["DEBERC_PLAYERS"] ?? "") ?? 2
        let deals = Int(env["DEBERC_COUNT"] ?? "") ?? 1000
        let seedBase = UInt64(env["DEBERC_SEED"] ?? "") ?? 1
        let v = BotExperiments.bot(names[0]), b = BotExperiments.bot(names[1])
        let start = Date()
        let diffs = BotExperiments.parallel(deals) { d -> Double in
            var deckRng = SplitMix64(seed: seedBase &* 1_000_003 &+ UInt64(d))
            var deck = Card.deck
            deck.shuffle(using: &deckRng)
            var sum = 0.0
            for vSeat in 0..<players {
                var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)),
                                  rules: .house, seed: 1)
                match.startDeal(deck: deck, dealer: 0)
                var rng = SplitMix64(seed: seedBase &+ UInt64(d) &* 7919 &+ UInt64(vSeat))
                while let actor = match.actor, !match.needsNewDeal {
                    let bot = actor == vSeat ? v : b
                    try! match.apply(bot.chooseAction(match: match, seat: actor, rng: &rng))
                }
                let score = match.history.last!
                let others = (0..<players).filter { $0 != vSeat }
                sum += Double(score.change[vSeat]) - others.map { Double(score.change[$0]) }.reduce(0, +) / Double(players - 1)
            }
            return sum / Double(players)
        }
        let mean = diffs.reduce(0, +) / Double(diffs.count)
        let variance = diffs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(diffs.count - 1, 1))
        let se = (variance / Double(diffs.count)).squareRoot()
        print(String(format: "DEALS %@ vs %@ %dp: %+.2f ± %.2f очков за сдачу (n=%d) %d с",
                     names[0], names[1], players, mean, se, deals, Int(Date().timeIntervalSince(start))))
    }

    // MARK: - Время на решение

    func testTiming() throws {
        guard var spec = env["DEBERC_TIMING"] else { return }
        if spec == "all" { spec = BotLevel.allCases.map(\.rawValue).joined(separator: ",") + ",hint" }
        let players = Int(env["DEBERC_PLAYERS"] ?? "") ?? 2
        let matches = Int(env["DEBERC_GAMES"] ?? "") ?? 3
        for name in spec.split(separator: ",").map(String.init) {
            let bot = BotExperiments.bot(name)
            var bidTimes: [Double] = [], playTimes: [Double] = [], otherTimes: [Double] = []
            for m in 0..<matches {
                var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)),
                                  rules: .house, seed: UInt64(77 + m))
                var rng = SplitMix64(seed: UInt64(m))
                while !match.isOver {
                    if match.needsNewDeal { match.startNextDeal(); continue }
                    guard let actor = match.actor, let deal = match.deal else { break }
                    let t0 = DispatchTime.now().uptimeNanoseconds
                    let action = bot.chooseAction(match: match, seat: actor, rng: &rng)
                    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                    switch deal.phase {
                    case .bidding: bidTimes.append(dt)
                    case .playing: if deal.legalCards(for: actor).count > 1 { playTimes.append(dt) }
                    default: otherTimes.append(dt)
                    }
                    try match.apply(action)
                }
            }
            print("TIME \(players)p \(name): торговля \(BotExperiments.stat(bidTimes)) | ход \(BotExperiments.stat(playTimes)) | обмен \(BotExperiments.stat(otherTimes))")
        }
    }

    static func stat(_ a: [Double]) -> String {
        guard !a.isEmpty else { return "—" }
        let s = a.sorted()
        let mean = s.reduce(0, +) / Double(s.count)
        return String(format: "n=%d среднее %.1f мс, p95 %.0f, макс %.0f", s.count, mean,
                      s[min(s.count - 1, Int(Double(s.count) * 0.95))], s.last!)
    }
}
