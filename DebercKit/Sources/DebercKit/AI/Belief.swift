import Foundation

// MARK: - «Чутьё»: у кого какая карта
//
// Небольшая нейросеть по тому, что видно с места игрока — свои карты, торговля, объявления,
// обмен семёрки, все сыгранные карты и кто, когда и как их сыграл, — оценивает для каждой
// невидимой карты, у кого она сейчас: у следующего игрока, у следующего за ним или ни у кого
// (колода, ещё не сданный прикуп). Обучена на сдачах, сыгранных ботами разного уровня.
// Бот по-прежнему видит только стол: на вход сети идёт только `SeatView`.

/// Признаки позиции для сети «чутья». Одинаково считаются при обучении (`tools/belief`) и в игре.
public enum BeliefFeatures {
    /// Признаков на карту: где она, кем и когда сыграна, её вес при козыре.
    public static let perCard = 20
    /// Общих признаков: число игроков, фаза, козырь, торговля, объявления, «чистые» масти.
    public static let global = 69
    public static let count = 32 * perCard + global
    /// Классы ответа на карту: у следующего, у следующего за ним, ни у кого.
    public static let classes = 3

    /// Относительное место: 0 — я, 1 — следующий по кругу, 2 — следующий за ним.
    @inline(__always)
    public static func rel(_ s: Int, _ v: SeatView) -> Int { (s - v.seat + v.playerCount) % v.playerCount }

    /// Карты, которых игрок не видит и про которые точно ничего не известно.
    public static func unknownMask(_ v: SeatView) -> UInt32 {
        var seen = mask(of: v.myHand) | mask(of: v.playedCards) | bit(v.openCard.id)
        if let b = v.bottomCard { seen |= bit(b.id) }
        for cards in v.knownCardsOfOthers { seen |= mask(of: cards) }
        return ~seen
    }

    /// Вектор признаков (значения от 0 до 1, кратные 1/255 — так же, как в данных для обучения).
    public static func encode(_ v: SeatView) -> [Float] {
        var x = [Float](repeating: 0, count: count)
        let n = v.playerCount
        @inline(__always) func set(_ card: Int, _ f: Int, _ value: Float = 1) { x[card * perCard + f] = value }

        // На карту: 0 — у меня; 1…3 — сыграна мной / следующим / следующим за ним; 4 — открытая;
        // 5 — нижняя; 6, 7 — точно у следующего / у следующего за ним; 8 — во взятке на столе;
        // 9 — номер взятки; 10…12 — зашли ею, вторая, третья; 13…15 — взятку взял я / следующий /
        // следующий за ним; 16 — козырь; 17 — очки; 18 — старшинство; 19 — неизвестна.
        for c in ids(in: mask(of: v.myHand)) { set(c, 0) }
        let tricks = v.tricks + [v.currentTrick]
        for (k, trick) in tricks.enumerated() {
            let winner = trick.winner.map { rel($0, v) }
            for (position, p) in trick.plays.enumerated() {
                let c = p.card.id
                set(c, 1 + rel(p.seat, v))
                if k == v.tricks.count { set(c, 8) }
                set(c, 9, Float(k) / 8)
                set(c, 10 + min(position, 2))
                if let winner { set(c, 13 + winner) }
            }
        }
        set(v.openCard.id, 4)
        if let b = v.bottomCard { set(b.id, 5) }
        let known = v.knownCardsOfOthers
        for s in 0..<n where s != v.seat {
            for card in known[s] { set(card.id, 5 + rel(s, v)) }
        }
        let unknown = unknownMask(v)
        for c in 0..<32 {
            let card = Card(id: c)
            // Пока козыря нет, карта считается некозырной.
            let reference = v.trump ?? Suit(rawValue: (card.suit.rawValue + 1) % 4)!
            if card.suit == v.trump { set(c, 16) }
            set(c, 17, Float(card.points(trump: reference)) / 20)
            set(c, 18, Float(card.power(trump: reference)) / 8)
            if unknown & bit(c) != 0 { set(c, 19) }
        }

        var o = 32 * perCard
        func slot(_ size: Int) -> Int {
            defer { o += size }
            return o
        }
        if n == 3 { x[slot(1)] = 1 } else { _ = slot(1) }
        let phase = slot(4)
        switch v.phase {
        case .bidding(let round): x[phase + (round == 1 ? 0 : 1)] = 1
        case .exchange: x[phase + 2] = 1
        case .playing, .finished: x[phase + 3] = 1
        }
        let trump = slot(4)
        if let t = v.trump { x[trump + t.rawValue] = 1 }
        x[slot(4) + v.openCard.suit.rawValue] = 1
        let bidder = slot(3)
        if let b = v.bidder { x[bidder + rel(b, v)] = 1 }
        x[slot(3) + rel(v.dealer, v)] = 1
        // Заявки каждого: 1-й круг «беру» / «пас», 2-й круг — масть или «пас», «обязы».
        let bids = slot(24)
        for bid in v.bids {
            let base = bids + rel(bid.seat, v) * 8
            switch (bid.round, bid.kind) {
            case (_, .forced): x[base + 7] = 1
            case (1, .take): x[base] = 1
            case (1, .pass): x[base + 1] = 1
            case (_, .name): if let s = bid.suit { x[base + 2 + s.rawValue] = 1 }
            case (_, .pass): x[base + 6] = 1
            default: break
            }
        }
        let exchange = slot(3)
        if let ex = v.exchange { x[exchange + rel(ex.seat, v)] = 1 }
        let meld = slot(4)
        if let w = v.meldWinner {
            x[meld + rel(w, v)] = 1
            x[meld + 3] = min(1, Float(v.meldWinnerPoints) / 100)
        }
        let bella = slot(3)
        if let b = v.knownBellaSeat { x[bella + rel(b, v)] = 1 }
        let voids = slot(8)
        let voidMasks = v.voidMasks
        for s in 0..<n where s != v.seat {
            for suit in 0..<4 where voidMasks[s] & (1 << suit) != 0 { x[voids + (rel(s, v) - 1) * 4 + suit] = 1 }
        }
        let counts = slot(3)
        for s in 0..<n { x[counts + rel(s, v)] = Float(v.handCounts[s]) / 9 }
        let taken = slot(3)
        for t in v.tricks { if let w = t.winner { x[taken + rel(w, v)] += 1 } }
        for r in 0..<3 { x[taken + r] /= 9 }
        let progress = slot(2)
        x[progress] = Float(v.tricks.count) / 9
        x[progress + 1] = Float(v.currentTrick.plays.count) / 3
        precondition(o == count, "BeliefFeatures: \(o) != \(count)")
        // Как в данных для обучения: значения округлены до 1/255.
        for i in x.indices where x[i] != 0 && x[i] != 1 { x[i] = (x[i] * 255).rounded() / 255 }
        return x
    }
}
