import Foundation

// MARK: - Точный решатель розыгрыша вдвоём

/// Перебор розыгрыша вдвоём при открытых картах («двойной болван»): оба игрока видят обе руки.
///
/// Ищет лучшую для каждой стороны разницу «сырых» очков до конца сдачи: очки карт, +10 за
/// последнюю взятку и комбинации с бэлой, которые засчитываются только тому, кто взял взятку.
/// Итог сдачи вдвоём — неубывающая функция этой разницы (сделал → висячий → байт), поэтому
/// лучшая игра «на разницу» совпадает с лучшей игрой «на итог», а ценность позиции на границе
/// взяток не зависит от уже набранных очков — её можно запоминать в таблице.
///
/// Приёмы: альфа-бета с таблицей позиций, склейка соседних по старшинству карт с равными очками,
/// порядок ходов «сначала ход из таблицы, отвечающий — самой дешёвой бьющей».
final class TwoPlayerSolver {

    private struct Entry {
        var h0: UInt32 = 0
        var h1: UInt32 = 0
        /// 0 — пусто, иначе 1 + заходящий + флаги × 2.
        var tag: UInt8 = 0
        var move: Int8 = -1
        /// Поколение: запись годится, только если совпадает с текущим (козырь, прибавки, правила).
        var generation: UInt16 = 0
        var lower: Int16 = -Solver.infinity
        var upper: Int16 = Solver.infinity
    }

    private var table: [Entry]
    private let tableMask: Int
    private var generation: UInt16 = 1
    private var ruleKey = -1
    /// Сколько позиций на границе взяток просмотрено (для замеров).
    private(set) var nodes = 0

    // Параметры сдачи.
    private var trump = -1
    private var pts = [Int](repeating: 0, count: 32)
    private var pwr = [Int](repeating: 0, count: 32)
    private var trumpBits: UInt32 = 0
    private var trumpAbove = [UInt32](repeating: 0, count: 10)
    private var mustTrump = true
    private var overtrumpOnTrumpLead = false
    /// Единовременная прибавка игроку за первую взятку (комбинации и бэла по правилу «нужна взятка»).
    private var bonus = [0, 0]
    /// Порядок перебора заходов: козыри, затем по убыванию старшинства.
    private var leadOrder = [Int](repeating: 0, count: 32)
    /// Порядок перебора ответов: от дешёвых к дорогим.
    private var followOrder = [Int](repeating: 0, count: 32)
    /// Карты каждой масти по возрастанию старшинства.
    private var suitAscending = [[Int]](repeating: [], count: 4)

    init(tableBits: Int = 16) {
        table = [Entry](repeating: Entry(), count: 1 << tableBits)
        tableMask = (1 << tableBits) - 1
    }

    /// Настроить под сдачу. `bonus` — прибавка за первую взятку для каждого игрока
    /// (0, если прибавки нет или взятка уже взята).
    func configure(trump: Int, rules: RuleSet, bonus: [Int]) {
        var changed = false
        if trump != self.trump {
            self.trump = trump
            pts = CardTables.points[trump]
            pwr = CardTables.power[trump]
            trumpBits = suitMask(trump)
            trumpAbove = CardTables.trumpAbove[trump]
            leadOrder = CardTables.searchOrder[trump]
            followOrder = (0..<32).sorted { a, b in
                let ka = (a >> 3 == trump ? 1000 : 0) + pts[a] * 10 + pwr[a]
                let kb = (b >> 3 == trump ? 1000 : 0) + pts[b] * 10 + pwr[b]
                return ka != kb ? ka < kb : a < b
            }
            suitAscending = (0..<4).map { s in (s * 8 ..< s * 8 + 8).sorted { pwr[$0] < pwr[$1] } }
            changed = true
        }
        let key = (rules.mustTrump ? 1 : 0) | (rules.effectiveOvertrump != .never ? 2 : 0)
        if key != ruleKey {
            ruleKey = key
            mustTrump = rules.mustTrump
            overtrumpOnTrumpLead = rules.effectiveOvertrump != .never
            changed = true
        }
        if bonus != self.bonus {
            self.bonus = bonus
            changed = true
        }
        if changed {
            // Старые записи относятся к другой сдаче — просто начинаем новое поколение.
            generation &+= 1
            if generation == 0 {
                for i in table.indices { table[i] = Entry() }
                generation = 1
            }
        }
    }

    /// Ценности (для `me`) каждого хода `me` из `moves`: разница будущих «сырых» очков
    /// (свои − соперника) от этого хода до конца сдачи при лучшей игре обоих.
    /// `tableCard` — карта, которой уже зашёл соперник (или nil, если заходит `me`).
    /// `flags`: бит игрока установлен, если прибавки за первую взятку у него нет (уже взял или нечего).
    func moveValues(hands: [UInt32], me: Int, tableCard: Int?, flags: Int, moves: [Int]) -> [Int] {
        let h = (hands[0], hands[1])
        return moves.map { m in
            if let lead = tableCard {
                // Я отвечаю на заход соперника.
                let other = 1 - me
                var nh = h
                if me == 0 { nh.0 &= ~bit(m) } else { nh.1 &= ~bit(m) }
                return -resolve(nh.0, nh.1, leader: other, lead: lead, response: m, flags: flags,
                                alpha: -Solver.inf, beta: Solver.inf)
            } else {
                var nh = h
                if me == 0 { nh.0 &= ~bit(m) } else { nh.1 &= ~bit(m) }
                return followerMin(nh.0, nh.1, leader: me, lead: m, flags: flags,
                                   alpha: -Solver.inf, beta: Solver.inf)
            }
        }
    }

    /// Ценность всей оставшейся игры для заходящего `leader` (никто ещё не зашёл в эту взятку).
    func value(hands: [UInt32], leader: Int, flags: Int) -> Int {
        solve(hands[0], hands[1], leader: leader, flags: flags, alpha: -Solver.inf, beta: Solver.inf)
    }

    /// Допустимые карты руки `hand`: заход (`tableCard` = nil) или ответ на `tableCard`.
    func legalMoves(_ hand: UInt32, tableCard: Int?) -> UInt32 {
        guard let lead = tableCard else { return hand }
        return followerLegal(hand, lead: lead)
    }

    // MARK: Перебор

    /// Ценность оставшихся взяток для заходящего `leader` (руки перед заходом).
    private func solve(_ h0: UInt32, _ h1: UInt32, leader: Int, flags: Int, alpha: Int, beta: Int) -> Int {
        let lh = leader == 0 ? h0 : h1
        if lh == 0 { return 0 }
        nodes += 1
        var a = alpha, b = beta
        let tag = UInt8(1 + leader + flags * 2)
        let index = TwoPlayerSolver.hash(h0, h1, tag) & tableMask
        var ttMove = -1
        let e = table[index]
        if e.generation == generation && e.tag == tag && e.h0 == h0 && e.h1 == h1 {
            let lo = Int(e.lower), hi = Int(e.upper)
            if lo == hi { return lo }
            if lo >= b { return lo }
            if hi <= a { return hi }
            if lo > a { a = lo }
            if hi < b { b = hi }
            ttMove = Int(e.move)
        }
        let alphaOrig = a
        let remaining = h0 | h1
        let leads = equivalentFree(lh, remaining: remaining)
        var best = -Solver.inf
        var bestMove = -1
        let first = ttMove >= 0 && leads & bit(ttMove) != 0 ? ttMove : -1
        // Сначала ход из таблицы, потом остальные в обычном порядке.
        var i = first >= 0 ? -1 : 0
        while i < 32 {
            let c = i < 0 ? first : leadOrder[i]
            i += 1
            if leads & bit(c) == 0 || (i > 0 && c == first) { continue }
            var n0 = h0, n1 = h1
            if leader == 0 { n0 &= ~bit(c) } else { n1 &= ~bit(c) }
            let v = followerMin(n0, n1, leader: leader, lead: c, flags: flags, alpha: a, beta: b)
            if v > best { best = v; bestMove = c }
            if best > a { a = best }
            if a >= b { break }
        }

        var entry = Entry(h0: h0, h1: h1, tag: tag, move: Int8(bestMove), generation: generation,
                          lower: -Solver.infinity, upper: Solver.infinity)
        if best <= alphaOrig {
            entry.upper = Int16(best)
        } else if best >= b {
            entry.lower = Int16(best)
        } else {
            entry.lower = Int16(best)
            entry.upper = Int16(best)
        }
        table[index] = entry
        return best
    }

    /// Худшая для заходящего ценность после его захода `lead` (руки уже без этой карты).
    private func followerMin(_ h0: UInt32, _ h1: UInt32, leader: Int, lead: Int, flags: Int, alpha: Int, beta: Int) -> Int {
        let fh = leader == 0 ? h1 : h0
        let legal = followerLegal(fh, lead: lead)
        let responses = equivalentFree(legal, remaining: h0 | h1 | bit(lead))
        // Сначала самые дешёвые бьющие карты, затем самые дешёвые небьющие.
        let winners = beating(responses, lead: lead)
        var worst = Solver.inf
        for pass in 0..<2 {
            let set = pass == 0 ? winners : responses & ~winners
            if set == 0 { continue }
            for r in followOrder where set & bit(r) != 0 {
                var n0 = h0, n1 = h1
                if leader == 0 { n1 &= ~bit(r) } else { n0 &= ~bit(r) }
                let v = resolve(n0, n1, leader: leader, lead: lead, response: r, flags: flags,
                                alpha: alpha, beta: min(beta, worst))
                if v < worst { worst = v }
                if worst <= alpha { return worst }
            }
        }
        return worst
    }

    /// Ценность для заходящего взятки «`lead` — `response`» и всего, что после неё.
    @inline(__always)
    private func resolve(_ h0: UInt32, _ h1: UInt32, leader: Int, lead: Int, response: Int, flags: Int,
                         alpha: Int, beta: Int) -> Int {
        let leaderWins: Bool
        if response >> 3 == lead >> 3 {
            leaderWins = pwr[lead] > pwr[response]
        } else {
            leaderWins = response >> 3 != trump
        }
        let winner = leaderWins ? leader : 1 - leader
        var p = pts[lead] + pts[response]
        if (h0 | h1) == 0 { p += 10 }
        var nf = flags
        if nf & (1 << winner) == 0 {
            p += bonus[winner]
            nf |= 1 << winner
        }
        if leaderWins {
            return p + solve(h0, h1, leader: winner, flags: nf, alpha: alpha - p, beta: beta - p)
        }
        return -p - solve(h0, h1, leader: winner, flags: nf, alpha: -beta - p, beta: -alpha - p)
    }

    /// Допустимые ответы на заход `lead`.
    @inline(__always)
    private func followerLegal(_ hand: UInt32, lead: Int) -> UInt32 {
        let led = lead >> 3
        let same = hand & suitMask(led)
        if same != 0 {
            if led == trump && overtrumpOnTrumpLead {
                let higher = same & trumpAbove[pwr[lead]]
                if higher != 0 { return higher }
            }
            return same
        }
        let trumps = hand & trumpBits
        if mustTrump && trumps != 0 { return trumps }
        return hand
    }

    /// Какие из карт `set` бьют заход `lead`.
    @inline(__always)
    private func beating(_ set: UInt32, lead: Int) -> UInt32 {
        let led = lead >> 3
        var result: UInt32 = 0
        var m = set
        while m != 0 {
            let r = m.trailingZeroBitCount
            m &= m - 1
            if r >> 3 == led ? pwr[r] > pwr[lead] : r >> 3 == trump { result |= bit(r) }
        }
        return result
    }

    /// Убирает из `set` карты, равноценные соседней младшей: та же масть, та же рука,
    /// те же очки и между ними по старшинству нет ни одной оставшейся чужой карты.
    @inline(__always)
    private func equivalentFree(_ set: UInt32, remaining: UInt32) -> UInt32 {
        var result = set
        for s in 0..<4 {
            let inSuit = set & suitMask(s)
            if inSuit & (inSuit &- 1) == 0 { continue }  // меньше двух карт
            var previous = -1
            for c in suitAscending[s] where remaining & bit(c) != 0 {
                if previous >= 0 && set & bit(previous) != 0 && set & bit(c) != 0 && pts[previous] == pts[c] {
                    result &= ~bit(c)
                }
                previous = c
            }
        }
        return result
    }

    @inline(__always)
    private static func hash(_ h0: UInt32, _ h1: UInt32, _ tag: UInt8) -> Int {
        var x = UInt64(h0) | UInt64(h1) << 32
        x ^= UInt64(tag) &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int(truncatingIfNeeded: x ^ (x >> 31))
    }
}

enum Solver {
    static let infinity: Int16 = 30_000
    static let inf = Int(infinity)
}
