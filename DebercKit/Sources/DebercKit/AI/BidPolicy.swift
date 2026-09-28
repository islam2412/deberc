import Foundation

// MARK: - Что скажет соперник в торговле
//
// В торговле с ценой паса (`Bot.auctionBid`) Мастер прикидывает, что ответит соперник, если сам он
// спасует. Раньше для этого была простая формула (`BidModel.strong2`), подобранная под прежнего бота;
// сеть заявок обучена на решениях сильного игрока (облегчённый Мастер) из партий `tools/belief`.

/// Признаки решения в торговле: своя шестёрка, открытая карта, круг, место относительно сдающего,
/// что уже сказали другие, грозят ли «обязы».
public enum BidFeatures {
    public static let count = 32 + 32 + 2 + 3 + 1 + 2 * 7 + 3
    /// Ответы: 0 — пас, 1 — беру (1-й круг), 2…5 — назвать масть 0…3 (2-й круг).
    public static let classes = 6

    static func encode(hand6: UInt32, open: Card, round: Int, seat: Int, dealer: Int, playerCount n: Int,
                       bids: [Bid], forcedSeat: Int?) -> [Float] {
        var x = [Float](repeating: 0, count: count)
        for c in ids(in: hand6) { x[c] = 1 }
        x[32 + open.id] = 1
        x[64 + (round == 1 ? 0 : 1)] = 1
        x[66 + (seat - dealer + n) % n] = 1
        if n == 3 { x[69] = 1 }
        for bid in bids where bid.seat != seat {
            let base = 70 + ((bid.seat - seat + n) % n - 1) * 7
            switch (bid.round, bid.kind) {
            case (1, .take): x[base] = 1
            case (1, .pass): x[base + 1] = 1
            case (_, .name): if let s = bid.suit { x[base + 2 + s.rawValue] = 1 }
            case (_, .pass): x[base + 6] = 1
            default: break
            }
        }
        switch forcedSeat {
        case .some(let f) where f == seat: x[84] = 1
        case .some: x[85] = 1
        case .none: x[86] = 1
        }
        return x
    }

    /// Признаки решения игрока, чья сейчас очередь в торговле (nil — сейчас не торговля).
    public static func encode(_ v: SeatView) -> [Float]? {
        guard case .bidding(let round) = v.phase else { return nil }
        return encode(hand6: mask(of: v.myHand), open: v.openCard, round: round, seat: v.seat, dealer: v.dealer,
                      playerCount: v.playerCount, bids: v.bids, forcedSeat: v.forcedSeatIfAllPass)
    }

    /// Номер ответа для действия в торговле.
    public static func label(_ action: Action) -> Int? {
        switch action {
        case .pass: return 0
        case .take: return 1
        case .name(let s): return 2 + s.rawValue
        default: return nil
        }
    }
}

/// Сеть заявок соперника (веса — `bidpolicy.bin`, обучает `tools/belief/train_bid.py`).
final class BidPolicyNet: @unchecked Sendable {
    private let net: DenseNet

    static let shared: BidPolicyNet? = DenseNet.resource("bidpolicy").flatMap(BidPolicyNet.init(net:))

    init?(net: DenseNet) {
        guard net.inputs == BidFeatures.count, net.outputs == BidFeatures.classes else { return nil }
        self.net = net
    }

    /// Вероятности ответов (пас, беру, масть 0…3) — только допустимых в этом круге.
    func probabilities(hand6: UInt32, open: Card, round: Int, seat: Int, dealer: Int, playerCount: Int,
                       bids: [Bid], forcedSeat: Int?) -> [Double] {
        let z = net.forward(BidFeatures.encode(hand6: hand6, open: open, round: round, seat: seat, dealer: dealer,
                                               playerCount: playerCount, bids: bids, forcedSeat: forcedSeat))
        var allowed = [Bool](repeating: false, count: BidFeatures.classes)
        allowed[0] = true
        if round == 1 {
            allowed[1] = true
        } else {
            for s in 0..<4 where s != open.suit.rawValue { allowed[2 + s] = true }
        }
        let top = z.indices.filter { allowed[$0] }.map { z[$0] }.max() ?? 0
        var p = z.indices.map { allowed[$0] ? exp(Double(z[$0] - top)) : 0 }
        let sum = p.reduce(0, +)
        for i in p.indices { p[i] /= sum }
        return p
    }
}
