import Foundation
import DebercKit

// Данные для сети оценки позиции втроём. Мастера играют партии; в розыгрыше позиция с открытыми
// картами записывается с каждого места, а когда сдача кончится, к записи дописывается её итог.
//
//   ValueGen <сдач> <зерно> <файл> [потоков] [доля позиций, %]
//
// Запись: `ValueFeatures.count` байт признаков (значение × 255) и 3 × int16 — полезность сдачи
// (как `SimState.utility`, умноженная на 2) для мест 0, 1, 2 относительно того, с чьего места позиция.

let args = CommandLine.arguments
guard args.count >= 4, let deals = Int(args[1]), let seed = UInt64(args[2]) else {
    FileHandle.standardError.write("usage: ValueGen <deals> <seed> <out> [threads] [share %]\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[3]
let threads = args.count > 4 ? max(1, Int(args[4]) ?? 1) : ProcessInfo.processInfo.activeProcessorCount
let share = args.count > 5 ? UInt64(args[5]) ?? 30 : 30
let players = 3
let recordSize = ValueFeatures.count + 6

FileManager.default.createFile(atPath: outPath, contents: nil)
guard let out = FileHandle(forWritingAtPath: outPath) else { exit(1) }
let lock = NSLock()
var written = 0
let started = Date()

DispatchQueue.concurrentPerform(iterations: threads) { worker in
    let target = deals / threads + (worker < deals % threads ? 1 : 0)
    var rng = SplitMix64(seed: seed &* 0x9E37_79B9 &+ UInt64(worker) &* 7919)
    let bot = Bot(level: .master)
    var played = 0
    var buffer = [UInt8]()
    while played < target {
        var match = Match(playerCount: players, names: ["A", "B", "C"], rules: .house, seed: rng.next())
        var pending: [(features: [UInt8], seat: Int)] = []
        var steps = 0
        while !match.isOver && played < target && steps < 5000 {
            steps += 1
            if match.needsNewDeal {
                if match.deal != nil {
                    played += 1
                    if let score = match.history.last, !pending.isEmpty {
                        let total = score.change.reduce(0, +)
                        let utility = (0..<players).map { 2 * score.change[$0] - (total - score.change[$0]) }  // ×2
                        for record in pending {
                            buffer += record.features
                            for r in 0..<players {
                                let u = Int16(clamping: utility[(record.seat + r) % players])
                                buffer.append(UInt8(truncatingIfNeeded: u))
                                buffer.append(UInt8(truncatingIfNeeded: u >> 8))
                            }
                        }
                    }
                    pending.removeAll()
                }
                _ = match.startNextDeal()
                continue
            }
            guard let actor = match.actor else { break }
            if match.deal?.phase == .playing && rng.next() % 100 < share {
                for seat in 0..<players {
                    if let x = ValueFeatures.encode(match: match, perspective: seat) {
                        pending.append((x.map { UInt8(($0 * 255).rounded()) }, seat))
                    }
                }
            }
            do { _ = try match.apply(bot.chooseAction(match: match, seat: actor, rng: &rng)) } catch { break }
        }
        if buffer.count >= recordSize * 2000 || played >= target {
            lock.lock()
            out.write(Data(buffer))
            written += buffer.count / recordSize
            lock.unlock()
            buffer.removeAll(keepingCapacity: true)
        }
    }
}
try? out.close()
print(String(format: "ValueGen 3p: %d records (%d bytes each) in %.0f s -> %@", written, recordSize,
             Date().timeIntervalSince(started), outPath))
