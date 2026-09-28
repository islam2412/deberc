import Foundation
import DebercKit

// Данные для сети заявок соперника (вдвоём): только торговля, без розыгрыша. Два облегчённых Мастера
// торгуются; каждое их решение записывается. Когда кто-то взял игру, партия бросается и начинается
// новая; «все пас» ведут к следующей сдаче той же партии — так встречаются и «обязы».
//
//   BidGen <решений> <зерно> <файл> [потоков] [чутьё Мастера]
//
// Запись: `BidFeatures.count` байт признаков (0/1) и байт ответа (0 — пас, 1 — беру, 2…5 — масть).

let args = CommandLine.arguments
guard args.count >= 4, let target = Int(args[1]), let seed = UInt64(args[2]) else {
    FileHandle.standardError.write("usage: BidGen <decisions> <seed> <out> [threads] [belief]\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[3]
let threads = args.count > 4 ? max(1, Int(args[4]) ?? 1) : ProcessInfo.processInfo.activeProcessorCount
let belief = args.count > 5 ? Double(args[5]) ?? 0 : 0
let recordSize = BidFeatures.count + 1

@Sendable func master(_ style: BotStyle) -> Bot {
    var c = Bot.Config.preset(.master, style: style)
    c.biddingSamples = 48
    c.playInference = 0
    c.timeBudget = nil
    c.belief = belief
    return Bot(config: c, level: .master, style: style)
}

FileManager.default.createFile(atPath: outPath, contents: nil)
guard let out = FileHandle(forWritingAtPath: outPath) else { exit(1) }
let lock = NSLock()
var written = 0
let started = Date()

DispatchQueue.concurrentPerform(iterations: threads) { worker in
    let share = target / threads + (worker < target % threads ? 1 : 0)
    var rng = SplitMix64(seed: seed &* 0x9E37_79B9 &+ UInt64(worker) &* 7919)
    var done = 0
    var buffer = [UInt8]()
    while done < share {
        let bots = (0..<2).map { _ in master(BotStyle.allCases[Int(rng.next() % 3)]) }
        var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: rng.next())
        _ = match.startNextDeal()
        var deals = 0
        while done < share, deals < 6, let deal = match.deal, case .bidding = deal.phase, let actor = match.actor {
            let v = SeatView(match: match, seat: actor)
            let action = bots[actor].chooseAction(view: v, rng: &rng)
            if let x = BidFeatures.encode(v), let label = BidFeatures.label(action) {
                for value in x { buffer.append(UInt8(value)) }
                buffer.append(UInt8(label))
                done += 1
            }
            guard (try? match.apply(action)) != nil else { break }
            if match.needsNewDeal {           // все спасовали — следующая сдача той же партии
                deals += 1
                _ = match.startNextDeal()
            }
        }
        if buffer.count >= recordSize * 2000 || done >= share {
            lock.lock()
            out.write(Data(buffer))
            written += buffer.count / recordSize
            lock.unlock()
            buffer.removeAll(keepingCapacity: true)
        }
    }
}
try? out.close()
print(String(format: "BidGen: %d decisions in %.0f s -> %@", written, Date().timeIntervalSince(started), outPath))
