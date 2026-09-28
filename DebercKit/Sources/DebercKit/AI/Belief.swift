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

// MARK: - Сеть

/// Небольшая полносвязная сеть с ReLU между слоями. Веса — в ресурсе пакета: число слоёв, затем для
/// каждого — входы, выходы, веса [выход][вход] и сдвиги; веса во float32 у формата BLF1 и во float16
/// у BLF2, сдвиги — всегда float32. Файлы пишут скрипты из `tools/belief`.
/// Считается на процессоре за доли миллисекунды: нулевые входы пропускаются.
final class DenseNet: @unchecked Sendable {
    private struct Layer {
        let inputs: Int
        let outputs: Int
        /// Веса по входам: `weights[i * outputs + j]` — вклад входа `i` в выход `j`.
        let weights: [Float]
        let bias: [Float]
    }

    private let layers: [Layer]
    var inputs: Int { layers[0].inputs }
    var outputs: Int { layers[layers.count - 1].outputs }

    /// Сеть из ресурса пакета `name.bin` (nil — ресурса нет или он не читается).
    static func resource(_ name: String) -> DenseNet? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return nil }
        return DenseNet(data: data)
    }

    init?(data: Data) {
        let bytes = [UInt8](data)
        var offset = 0
        func u32() -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            defer { offset += 4 }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        func floats(_ n: Int) -> [Float]? {
            guard offset + 4 * n <= bytes.count else { return nil }
            defer { offset += 4 * n }
            return (0..<n).map { k in
                let p = offset + 4 * k
                let raw = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
                return Float(bitPattern: raw)
            }
        }
        func halves(_ n: Int) -> [Float]? {
            guard offset + 2 * n <= bytes.count else { return nil }
            defer { offset += 2 * n }
            return (0..<n).map { k in DenseNet.float(half: UInt16(bytes[offset + 2 * k]) | UInt16(bytes[offset + 2 * k + 1]) << 8) }
        }
        guard bytes.count >= 8 else { return nil }
        let magic = Array(bytes[0..<4])
        let half = magic == Array("BLF2".utf8)
        guard half || magic == Array("BLF1".utf8) else { return nil }
        offset = 4
        guard let count = u32(), count > 0 else { return nil }
        var layers: [Layer] = []
        for _ in 0..<count {
            guard let inputs = u32(), let outputs = u32(),
                  let w = half ? halves(inputs * outputs) : floats(inputs * outputs), let b = floats(outputs) else { return nil }
            if let previous = layers.last, previous.outputs != inputs { return nil }
            var transposed = [Float](repeating: 0, count: inputs * outputs)
            for j in 0..<outputs { for i in 0..<inputs { transposed[i * outputs + j] = w[j * inputs + i] } }
            layers.append(Layer(inputs: inputs, outputs: outputs, weights: transposed, bias: b))
        }
        guard offset == bytes.count else { return nil }
        self.layers = layers
    }

    /// float16 → float32 (IEEE 754), без `Float16`: он есть не на всех платформах.
    static func float(half h: UInt16) -> Float {
        let sign: UInt32 = UInt32(h >> 15) << 31
        let exponent = Int((h >> 10) & 0x1F)
        let fraction = UInt32(h & 0x3FF)
        if exponent == 0 {
            let value = Float(fraction) * Float(bitPattern: 0x3380_0000)   // 2^-24
            return sign == 0 ? value : -value
        }
        if exponent == 31 { return Float(bitPattern: sign | 0x7F80_0000 | fraction << 13) }
        return Float(bitPattern: sign | UInt32(exponent + 112) << 23 | fraction << 13)
    }

    /// Выход сети для входа `features`.
    func forward(_ features: [Float]) -> [Float] {
        var input = features
        for (k, layer) in layers.enumerated() {
            var output = layer.bias
            output.withUnsafeMutableBufferPointer { out in
                layer.weights.withUnsafeBufferPointer { w in
                    input.withUnsafeBufferPointer { x in
                        for i in 0..<layer.inputs {
                            let xi = x[i]
                            if xi == 0 { continue }
                            let row = i * layer.outputs
                            for j in 0..<layer.outputs { out[j] += xi * w[row + j] }
                        }
                    }
                }
            }
            if k < layers.count - 1 {
                for j in output.indices where output[j] < 0 { output[j] = 0 }
            }
            input = output
        }
        return input
    }
}

/// Сеть «чутья» (веса — `belief.bin`, обучает `tools/belief/train.py`).
final class BeliefNet: @unchecked Sendable {
    private let net: DenseNet

    /// Сеть из ресурсов пакета (nil — ресурса нет или он не той формы).
    static let shared: BeliefNet? = DenseNet.resource("belief").flatMap(BeliefNet.init(net:))

    init?(net: DenseNet) {
        guard net.inputs == BeliefFeatures.count, net.outputs == 32 * BeliefFeatures.classes else { return nil }
        self.net = net
    }

    convenience init?(data: Data) {
        guard let net = DenseNet(data: data) else { return nil }
        self.init(net: net)
    }

    /// Выход сети — «сырые» оценки: [карта × 3 класса].
    func logits(_ features: [Float]) -> [Float] { net.forward(features) }

    /// Логарифмы вероятностей, где сейчас каждая карта: `[карта * 3 + класс]`, класс 0 — у следующего
    /// по кругу, 1 — у следующего за ним, 2 — ни у кого. Вдвоём класс 1 невозможен (−∞).
    func logProbabilities(_ v: SeatView) -> [Float] {
        let z = logits(BeliefFeatures.encode(v))
        var result = [Float](repeating: 0, count: 32 * 3)
        let three = v.playerCount == 3
        for c in 0..<32 {
            let a = z[c * 3], b = three ? z[c * 3 + 1] : -Float.infinity, n = z[c * 3 + 2]
            let top = max(a, b, n)
            let log = top + Foundation.log(exp(a - top) + exp(b - top) + exp(n - top))
            result[c * 3] = a - log
            result[c * 3 + 1] = b - log
            result[c * 3 + 2] = n - log
        }
        return result
    }
}

extension WorldSampler {
    /// Мир, в котором каждая невидимая карта положена туда, где она вероятнее по «чутью» (с крутизной
    /// `tau`), с учётом того, сколько карт у кого должно быть и у кого кончились масти.
    /// Сначала раскладываются карты, которым меньше всего мест. nil — расклад не сложился.
    static func sampleFromBelief(_ info: PlayInfo, v: SeatView, logP: [Float], tau: Double,
                                 rng: inout SplitMix64) -> [UInt32]? {
        let n = info.n
        var cards = info.pool
        cards.shuffle(using: &rng)
        var optionsBySuit = [Int](repeating: 0, count: 4)
        for suit in 0..<4 {
            var count = info.stockNeed > 0 ? 1 : 0
            for s in 0..<n where s != info.seat && info.need[s] > 0 && info.voids[s] & (1 << suit) == 0 { count += 1 }
            optionsBySuit[suit] = count
        }
        var ordered: [Int] = []
        ordered.reserveCapacity(cards.count)
        for options in 0...3 {
            for id in cards where optionsBySuit[id >> 3] == options { ordered.append(id) }
        }
        var cap = info.need
        var stockCap = info.stockNeed
        var hands = [UInt32](repeating: 0, count: n)
        hands[info.seat] = info.myHand
        for s in 0..<n where s != info.seat { hands[s] = info.known[s] }
        var targets = [Int](repeating: 0, count: 3)
        var weights = [Double](repeating: 0, count: 3)
        for c in ordered {
            var k = 0
            var total = 0.0
            for s in 0..<n where s != info.seat && cap[s] > 0 && info.voids[s] & (1 << (c >> 3)) == 0 {
                let w = exp(tau * Double(logP[c * 3 + BeliefFeatures.rel(s, v) - 1]))
                targets[k] = s
                weights[k] = w
                total += w
                k += 1
            }
            if stockCap > 0 {
                let w = exp(tau * Double(logP[c * 3 + 2]))
                targets[k] = -1
                weights[k] = w
                total += w
                k += 1
            }
            guard k > 0 else { return nil }
            var r = Double(rng.next() >> 11) / Double(1 << 53) * total
            var pick = k - 1
            for j in 0..<k {
                r -= weights[j]
                if r <= 0 { pick = j; break }
            }
            let t = targets[pick]
            if t < 0 {
                stockCap -= 1
            } else {
                hands[t] |= bit(c)
                cap[t] -= 1
            }
        }
        return hands
    }

    /// Вес мира по «чутью»: сумма логарифмов вероятностей того, где в этом мире лежит каждая
    /// невидимая карта (`hands` — у кого что сейчас; остальные невидимые — ни у кого).
    static func beliefLogWeight(_ v: SeatView, logP: [Float], unknown: UInt32, hands: [UInt32]) -> Double {
        var total: Float = 0
        var m = unknown
        while m != 0 {
            let c = m.trailingZeroBitCount
            m &= m &- 1
            var cls = 2
            for s in 0..<v.playerCount where s != v.seat && hands[s] & (1 << UInt32(c)) != 0 {
                cls = BeliefFeatures.rel(s, v) - 1
            }
            total += logP[c * 3 + cls]
        }
        return Double(total)
    }
}
