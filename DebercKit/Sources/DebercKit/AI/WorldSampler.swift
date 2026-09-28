import Foundation

/// Случайная расстановка скрытых карт, согласованная со всем, что видит игрок.
enum WorldSampler {

    /// Всё, что нужно для быстрой раздачи миров в розыгрыше; считается один раз на решение.
    struct PlayInfo {
        let n: Int
        let seat: Int
        let myHand: UInt32
        /// Неизвестные карты (у соперников или в колоде).
        let pool: [Int]
        /// Сколько неизвестных карт у каждого соперника.
        let need: [Int]
        /// Известные карты соперников (обмен семёрки, показанные комбинации, объявленная бэла).
        let known: [UInt32]
        /// Масти, которых точно нет (биты мастей).
        let voids: [Int]
        /// Сколько неизвестных карт лежит в колоде.
        let stockNeed: Int
        /// Карты, которые каждый уже сыграл в этой сдаче.
        let playedBy: [UInt32]

        init(_ v: SeatView) {
            n = v.playerCount
            seat = v.seat
            myHand = mask(of: v.myHand)
            let knownCards = v.knownCardsOfOthers
            known = knownCards.map { mask(of: $0) }
            var excluded = myHand | mask(of: v.playedCards) | bit(v.openCard.id)
            if let bottom = v.bottomCard { excluded |= bit(bottom.id) }
            for k in known { excluded |= k }
            pool = ids(in: ~excluded)
            var need = [Int](repeating: 0, count: n)
            for s in 0..<n where s != v.seat {
                need[s] = max(0, v.handCounts[s] - knownCards[s].count)
            }
            self.need = need
            stockNeed = max(0, pool.count - need.reduce(0, +))
            voids = v.voidMasks
            var playedBy = [UInt32](repeating: 0, count: n)
            for trick in v.tricks + [v.currentTrick] {
                for p in trick.plays { playedBy[p.seat] |= bit(p.card.id) }
            }
            self.playedBy = playedBy
        }
    }

    /// Руки всех игроков на текущий момент розыгрыша (маски карт).
    static func samplePlay(_ v: SeatView, rng: inout SplitMix64) -> [UInt32] {
        samplePlay(PlayInfo(v), rng: &rng)
    }

    static func samplePlay(_ info: PlayInfo, rng: inout SplitMix64) -> [UInt32] {
        for _ in 0..<40 {
            if let hands = attempt(info, respectVoids: true, rng: &rng) { return hands }
        }
        return attempt(info, respectVoids: false, rng: &rng)!
    }

    private static func attempt(_ info: PlayInfo, respectVoids: Bool, rng: inout SplitMix64) -> [UInt32]? {
        let n = info.n
        var shuffled = info.pool
        shuffled.shuffle(using: &rng)
        // Сначала раскладываем самые «стеснённые» карты (их можно положить меньшему числу игроков).
        var optionsBySuit = [Int](repeating: 0, count: 4)
        for suit in 0..<4 {
            var count = info.stockNeed > 0 ? 1 : 0
            for s in 0..<n where s != info.seat && info.need[s] > 0 {
                if !respectVoids || info.voids[s] & (1 << suit) == 0 { count += 1 }
            }
            optionsBySuit[suit] = count
        }
        var ordered: [Int] = []
        ordered.reserveCapacity(shuffled.count)
        for options in 0...3 {
            for id in shuffled where optionsBySuit[id >> 3] == options { ordered.append(id) }
        }

        var cap = info.need
        var stockCap = info.stockNeed
        var hands = [UInt32](repeating: 0, count: n)
        hands[info.seat] = info.myHand
        for s in 0..<n where s != info.seat { hands[s] = info.known[s] }

        for id in ordered {
            let suitBit = 1 << (id >> 3)
            var total = stockCap
            for s in 0..<n where s != info.seat && cap[s] > 0 {
                if !respectVoids || info.voids[s] & suitBit == 0 { total += cap[s] }
            }
            if total == 0 { return nil }
            var r = Int(rng.next() % UInt64(total))
            var placed = false
            for s in 0..<n where s != info.seat && cap[s] > 0 {
                if respectVoids && info.voids[s] & suitBit != 0 { continue }
                if r < cap[s] {
                    hands[s] |= bit(id)
                    cap[s] -= 1
                    placed = true
                    break
                }
                r -= cap[s]
            }
            if !placed { stockCap -= 1 }
        }
        return hands
    }

    // MARK: - Миры с учётом торговли и объявлений

    /// Руки на начало розыгрыша (после обмена семёрки) в мире `world`.
    static func startHands(_ info: PlayInfo, world: [UInt32]) -> [UInt32] {
        (0..<info.n).map { world[$0] | info.playedBy[$0] }
    }

    /// Согласован ли мир с объявлениями: победитель комбинаций тот же, что за столом,
    /// и никто не сыграл короля или даму козырей, держа бэлу, без объявления.
    static func consistentWithDeclarations(_ v: SeatView, info: PlayInfo, world: [UInt32], trump: Suit) -> Bool {
        let start = startHands(info, world: world)
        if v.knownBellaSeat == nil {
            let king = bit(Card(.king, trump).id), queen = bit(Card(.queen, trump).id)
            for s in 0..<info.n where s != v.seat {
                let pair = king | queen
                if start[s] & pair == pair && info.playedBy[s] & pair != 0 { return false }
            }
        }
        let hands = start.map { m in ids(in: m).map { Card(id: $0) } }
        let decl = Combinations.declarations(hands: hands, trump: trump, rules: v.rules, priority: v.leadOrder)
        return decl.meldWinner == v.meldWinner
    }

    /// Вес мира: правдоподобие заявок соперников по модели торговли.
    static func biddingWeight(_ v: SeatView, info: PlayInfo, world: [UInt32]) -> Double {
        let start = startHands(info, world: world)
        let open = v.exchange?.took ?? v.openCard
        var w = 1.0
        for s in 0..<info.n where s != v.seat {
            var h = start[s]
            if let ex = v.exchange, ex.seat == s {
                h = (h & ~bit(ex.took.id)) | bit(ex.gave.id)
            }
            w *= BidModel.likelihood9(bids: v.bids, seat: s, hand9: h, open: open, dealer: v.dealer, players: info.n)
        }
        return w
    }

    /// Миры с учётом торговли (перевыбор по весам) и объявлений (отбраковка).
    static func sampleInformed(_ v: SeatView, info: PlayInfo, count: Int, rng: inout SplitMix64) -> [[UInt32]] {
        guard let trump = v.trump else { return (0..<count).map { _ in samplePlay(info, rng: &rng) } }
        let candidates = informedCandidates(v, info: info, trump: trump, count: count * 3, rng: &rng)
        // Систематический перевыбор: меньше шума, чем независимый.
        return resample(candidates.worlds, weights: candidates.weights, count: count, rng: &rng)
    }

    /// Кандидаты для перевыбора: миры, согласованные с объявлениями, и их веса по торговле.
    static func informedCandidates(_ v: SeatView, info: PlayInfo, trump: Suit, count: Int,
                                   rng: inout SplitMix64) -> (worlds: [[UInt32]], weights: [Double]) {
        var worlds: [[UInt32]] = []
        var weights: [Double] = []
        worlds.reserveCapacity(count)
        weights.reserveCapacity(count)
        for _ in 0..<count {
            var world = samplePlay(info, rng: &rng)
            for _ in 0..<12 {
                if consistentWithDeclarations(v, info: info, world: world, trump: trump) { break }
                world = samplePlay(info, rng: &rng)
            }
            worlds.append(world)
            weights.append(biddingWeight(v, info: info, world: world))
        }
        return (worlds, weights)
    }

    /// Систематический перевыбор `count` кандидатов по весам.
    static func resample<T>(_ candidates: [T], weights: [Double], count: Int, rng: inout SplitMix64) -> [T] {
        let total = weights.reduce(0, +)
        guard total > 0 else { return Array(candidates.prefix(count)) }
        var result: [T] = []
        result.reserveCapacity(count)
        let step = total / Double(count)
        var u = Double(rng.next() % 1_000_000) / 1_000_000 * step
        var acc = 0.0
        var i = 0
        for _ in 0..<count {
            while i < weights.count - 1 && acc + weights[i] <= u {
                acc += weights[i]
                i += 1
            }
            result.append(candidates[i])
            u += step
        }
        return result
    }

    // MARK: - Торговля

    /// Миры торговли с учётом уже сказанного соперниками (кто спасовал — вряд ли силён в этой масти).
    static func sampleBiddingInformed(_ v: SeatView, count: Int, rng: inout SplitMix64) -> [(hands: [UInt32], prikup: [UInt32])] {
        let factor = 3
        var candidates: [(hands: [UInt32], prikup: [UInt32])] = []
        var weights: [Double] = []
        for _ in 0..<(count * factor) {
            let world = sampleBidding(v, rng: &rng)
            var w = 1.0
            for s in 0..<v.playerCount where s != v.seat {
                w *= BidModel.likelihood(bids: v.bids, seat: s, hand6: world.hands[s], open: v.openCard,
                                         dealer: v.dealer, players: v.playerCount)
            }
            candidates.append(world)
            weights.append(w)
        }
        return resample(candidates, weights: weights, count: count, rng: &rng)
    }

    /// Мир до прикупа: руки по 6 карт у соперников и прикуп всех игроков (маски).
    static func sampleBidding(_ v: SeatView, rng: inout SplitMix64) -> (hands: [UInt32], prikup: [UInt32]) {
        let n = v.playerCount
        var excluded = mask(of: v.myHand) | bit(v.openCard.id)
        if let bottom = v.bottomCard { excluded |= bit(bottom.id) }
        var pool = ids(in: ~excluded)
        pool.shuffle(using: &rng)
        var index = 0
        var hands = [UInt32](repeating: 0, count: n)
        for s in 0..<n {
            if s == v.seat {
                hands[s] = mask(of: v.myHand)
            } else {
                for _ in 0..<6 { hands[s] |= bit(pool[index]); index += 1 }
            }
        }
        var prikup = [UInt32](repeating: 0, count: n)
        for s in 0..<n {
            for _ in 0..<3 { prikup[s] |= bit(pool[index]); index += 1 }
        }
        return (hands, prikup)
    }
}
