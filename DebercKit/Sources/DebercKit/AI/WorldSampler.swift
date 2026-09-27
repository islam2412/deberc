import Foundation

/// Случайная расстановка скрытых карт, согласованная со всем, что видит игрок.
enum WorldSampler {

    /// Руки всех игроков на текущий момент розыгрыша (маски карт).
    static func samplePlay(_ v: SeatView, rng: inout SplitMix64) -> [UInt32] {
        let n = v.playerCount
        let known = v.knownCardsOfOthers
        var excluded = Set(v.myHand)
        excluded.formUnion(v.playedCards)
        excluded.insert(v.openCard)
        if let bottom = v.bottomCard { excluded.insert(bottom) }
        for list in known { excluded.formUnion(list) }
        let pool = Card.deck.filter { !excluded.contains($0) }

        var need = [Int](repeating: 0, count: n)
        for s in 0..<n where s != v.seat {
            need[s] = max(0, v.handCounts[s] - known[s].count)
        }
        let stockNeed = max(0, pool.count - need.reduce(0, +))
        let voids = v.voids

        func attempt(respectVoids: Bool, rng: inout SplitMix64) -> [UInt32]? {
            var shuffled = pool
            shuffled.shuffle(using: &rng)
            // Сначала раскладываем самые «стеснённые» карты.
            func options(_ card: Card) -> Int {
                var count = stockNeed > 0 ? 1 : 0
                for s in 0..<n where s != v.seat && need[s] > 0 {
                    if !respectVoids || !voids[s].contains(card.suit) { count += 1 }
                }
                return count
            }
            let ordered = shuffled.enumerated()
                .sorted { a, b in
                    let oa = options(a.element), ob = options(b.element)
                    return oa != ob ? oa < ob : a.offset < b.offset
                }
                .map(\.element)

            var cap = need
            var stockCap = stockNeed
            var hands = [UInt32](repeating: 0, count: n)
            hands[v.seat] = mask(of: v.myHand)
            for s in 0..<n where s != v.seat { hands[s] = mask(of: known[s]) }

            for card in ordered {
                var total = stockCap
                for s in 0..<n where s != v.seat && cap[s] > 0 {
                    if !respectVoids || !voids[s].contains(card.suit) { total += cap[s] }
                }
                if total == 0 { return nil }
                var r = Int(rng.next() % UInt64(total))
                var placed = false
                for s in 0..<n where s != v.seat && cap[s] > 0 {
                    if respectVoids && voids[s].contains(card.suit) { continue }
                    if r < cap[s] {
                        hands[s] |= bit(card.id)
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

        for _ in 0..<40 {
            if let hands = attempt(respectVoids: true, rng: &rng) { return hands }
        }
        return attempt(respectVoids: false, rng: &rng)!
    }

    /// Мир до прикупа: руки по 6 карт у соперников и прикуп всех игроков.
    static func sampleBidding(_ v: SeatView, rng: inout SplitMix64) -> (hands: [[Card]], prikup: [[Card]]) {
        let n = v.playerCount
        var excluded = Set(v.myHand)
        excluded.insert(v.openCard)
        if let bottom = v.bottomCard { excluded.insert(bottom) }
        var pool = Card.deck.filter { !excluded.contains($0) }
        pool.shuffle(using: &rng)
        var index = 0
        var hands = [[Card]](repeating: [], count: n)
        for s in 0..<n {
            if s == v.seat {
                hands[s] = v.myHand
            } else {
                hands[s] = Array(pool[index..<index + 6])
                index += 6
            }
        }
        var prikup = [[Card]](repeating: [], count: n)
        for s in 0..<n {
            prikup[s] = Array(pool[index..<index + 3])
            index += 3
        }
        return (hands, prikup)
    }
}
