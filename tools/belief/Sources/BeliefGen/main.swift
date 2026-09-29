import Foundation
import DebercKit

// Данные для обучения сети «чутья». Боты разного уровня играют партии; перед каждым действием
// с каждого места записываются признаки того, что видно (`BeliefFeatures`), и ответ — где сейчас
// каждая карта: 0 — у следующего по кругу, 1 — у следующего за ним, 2 — ни у кого (колода,
// несданный прикуп), 255 — карта этому месту видна и в ответ не входит.
//
//   BeliefGen <игроков 2|3> <сдач> <зерно> <файл> [потоков] [доля позиций, %] [чутьё Мастера]
//
// Последний параметр — `Config.belief` облегчённого Мастера (0 — без сети; 1 — Мастер с «чутьём»,
// чтобы следующая сеть училась угадывать карты такого соперника).
//
// Запись: `BeliefFeatures.count` байт признаков (значение × 255) и 32 байта ответов.

let args = CommandLine.arguments
guard args.count >= 5, let players = Int(args[1]), [2, 3].contains(players),
      let deals = Int(args[2]), let seed = UInt64(args[3]) else {
    FileHandle.standardError.write("usage: BeliefGen <players 2|3> <deals> <seed> <out> [threads]\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[4]
let threads = args.count > 5 ? max(1, Int(args[5]) ?? 1) : ProcessInfo.processInfo.activeProcessorCount
/// Какую долю позиций записывать (в процентах). Позиции одной сдачи похожи друг на друга:
/// для обучения полезнее больше разных сдач, чем все позиции каждой.
let recordShare: UInt64 = args.count > 6 ? UInt64(args[6]) ?? 100 : (players == 2 ? 100 : 50)
let masterBelief = args.count > 7 ? Double(args[7]) ?? 0 : 0

/// Мастер для данных: те же решения (точный решатель, торговля с ценой паса), но меньше миров
/// и без чтения ходов — иначе данных за разумное время не набрать.
@Sendable func masterLite(_ style: BotStyle) -> Bot {
    var c = Bot.Config.preset(.master, style: style)
    c.playSamples = 32
    c.biddingSamples = 32
    c.playInference = 0
    c.timeBudget = nil
    c.belief = masterBelief
    return Bot(config: c, level: .master, style: style)
}

/// Кто за столом: больше сильных игроков, но есть и слабые — человек играет по-разному.
@Sendable func pickBot(_ rng: inout SplitMix64) -> Bot {
    let style = BotStyle.allCases[Int(rng.next() % 3)]
    switch rng.next() % 100 {
    case 0..<45: return masterLite(style)
    case 45..<75: return Bot(level: .expert, style: style)
    case 75..<92: return Bot(level: .amateur, style: style)
    default: return Bot(level: .novice, style: style)
    }
}

let recordSize = BeliefFeatures.count + 32
FileManager.default.createFile(atPath: outPath, contents: nil)
guard let out = FileHandle(forWritingAtPath: outPath) else {
    FileHandle.standardError.write("cannot open \(outPath)\n".data(using: .utf8)!)
    exit(1)
}
let lock = NSLock()
var written = 0
var dealsDone = 0
let started = Date()

DispatchQueue.concurrentPerform(iterations: threads) { worker in
    let share = deals / threads + (worker < deals % threads ? 1 : 0)
    var rng = SplitMix64(seed: seed &* 0x9E37_79B9 &+ UInt64(worker) &* 7919)
    var played = 0
    var buffer = [UInt8]()
    buffer.reserveCapacity(recordSize * 4096)
    func flush() {
        guard !buffer.isEmpty else { return }
        lock.lock()
        out.write(Data(buffer))
        written += buffer.count / recordSize
        lock.unlock()
        buffer.removeAll(keepingCapacity: true)
    }
    while played < share {
        let bots = (0..<players).map { _ in pickBot(&rng) }
        var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)), rules: .house,
                          seed: rng.next())
        var steps = 0
        while !match.isOver && played < share && steps < 5000 {
            steps += 1
            if match.needsNewDeal {
                if match.deal != nil { played += 1 }
                _ = match.startNextDeal()
                continue
            }
            guard let actor = match.actor, let deal = match.deal else { break }
            for s in 0..<players where rng.next() % 100 < recordShare {
                let v = SeatView(match: match, seat: s)
                for x in BeliefFeatures.encode(v) { buffer.append(UInt8((x * 255).rounded())) }
                let unknown = BeliefFeatures.unknownMask(v)
                for c in 0..<32 {
                    guard unknown & (1 << UInt32(c)) != 0 else { buffer.append(255); continue }
                    var label: UInt8 = 2
                    for holder in 0..<players where holder != s && deal.hands[holder].contains(where: { $0.id == c }) {
                        label = UInt8(BeliefFeatures.rel(holder, v) - 1)
                    }
                    buffer.append(label)
                }
            }
            if buffer.count >= recordSize * 4000 { flush() }
            let action = bots[actor].chooseAction(match: match, seat: actor, rng: &rng)
            do { _ = try match.apply(action) } catch { break }
        }
        flush()
        lock.lock()
        dealsDone += 1
        if dealsDone % 200 == 0 {
            let t = Date().timeIntervalSince(started)
            FileHandle.standardError.write(String(format: "%d matches, %d records, %.0f s\n", dealsDone, written, t).data(using: .utf8)!)
        }
        lock.unlock()
    }
}
try? out.close()
print(String(format: "BeliefGen %dp: %d records (%d bytes each) in %.0f s -> %@", players, written,
             recordSize, Date().timeIntervalSince(started), outPath))
