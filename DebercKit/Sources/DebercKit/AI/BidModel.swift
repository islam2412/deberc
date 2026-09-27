import Foundation

/// Приблизительная модель торговли: вероятность, что игрок с такими 6 картами
/// возьмёт (назовёт) масть. Логистическая регрессия, обученная на решениях сильного бота
/// (точность 95–96%). Нужна, чтобы по заявкам соперников догадываться об их картах,
/// и для «торговли на глаз» у Новичка.
enum BidModel {

    struct Weights {
        let w: [Double]
    }

    /// Признаки: [1, число козырей, В, 9, Т, 10 козырные, К∧Д, К+Д козырные,
    /// побочные тузы, побочные десятки, 1-й круг, козырная 7 × очки открытой / 10, первым ходит].
    static let strong2 = Weights(w: [-12.940, 2.331, 5.251, 2.940, 0.910, 1.095, 1.634, 1.222, 1.972, 1.271, 0.119, 2.188, 0.144])
    static let strong3 = Weights(w: [-13.548, 2.658, 5.450, 2.927, 0.933, 1.064, 1.359, 0.972, 1.792, 0.947, 0.223, 2.417, 0.134])

    /// «На глаз», как играет новичок: переоценивает тузы, бэлу и длину козырей,
    /// недооценивает девятку козырей и не думает об открытой карте.
    static let novice2 = Weights(w: [-13.10, 2.65, 5.00, 1.20, 1.10, 1.00, 2.50, 1.20, 2.40, 1.00, 0.00, 0.40, 0.00])
    static let novice3 = Weights(w: [-13.70, 2.90, 5.20, 1.20, 1.10, 1.00, 2.30, 1.00, 2.20, 0.80, 0.00, 0.40, 0.00])

    private static let aces: UInt32 = bit(7) | bit(15) | bit(23) | bit(31)
    private static let tens: UInt32 = bit(3) | bit(11) | bit(19) | bit(27)

    /// Логит (до сигмоиды) для руки `hand` (маска 6 карт) и козыря `trump`.
    static func logit(_ hand: UInt32, trump: Int, open: Card, round: Int, leadsFirst: Bool, weights: Weights) -> Double {
        let w = weights.w
        let t = suitMask(trump)
        let base = trump * 8
        @inline(__always) func has(_ rankIndex: Int) -> Double { hand & bit(base + rankIndex) != 0 ? 1 : 0 }
        let count = Double((hand & t).nonzeroBitCount)
        let jack = has(Rank.jack.index), nine = has(Rank.nine.index)
        let ace = has(Rank.ace.index), ten = has(Rank.ten.index)
        let king = has(Rank.king.index), queen = has(Rank.queen.index)
        let seven = has(Rank.seven.index)
        let sideA = Double((hand & aces & ~t).nonzeroBitCount)
        let sideT = Double((hand & tens & ~t).nonzeroBitCount)
        let r1 = round == 1 ? 1.0 : 0.0
        let openValue = r1 * seven * Double(open.points(trump: Suit(rawValue: trump)!)) / 10
        var z = w[0]
        z += w[1] * count + w[2] * jack + w[3] * nine + w[4] * ace + w[5] * ten
        z += w[6] * king * queen + w[7] * (king + queen)
        z += w[8] * sideA + w[9] * sideT + w[10] * r1 + w[11] * openValue
        z += w[12] * (leadsFirst ? 1 : 0)
        return z
    }

    @inline(__always)
    static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-z)) }

    static func probability(_ hand: UInt32, trump: Int, open: Card, round: Int, leadsFirst: Bool, weights: Weights) -> Double {
        sigmoid(logit(hand, trump: trump, open: open, round: round, leadsFirst: leadsFirst, weights: weights))
    }

    static func strong(players: Int) -> Weights { players == 2 ? strong2 : strong3 }

    /// Правдоподобие заявок игрока `seat`, если его 6 карт до прикупа — `hand6`.
    static func likelihood(bids: [Bid], seat: Int, hand6: UInt32, open: Card, dealer: Int, players: Int) -> Double {
        let weights = strong(players: players)
        let leadsFirst = seat == (dealer + 1) % players
        var l = 1.0
        for bid in bids where bid.seat == seat {
            switch (bid.round, bid.kind) {
            case (_, .forced):
                break
            case (1, .pass):
                l *= 1 - probability(hand6, trump: open.suit.rawValue, open: open, round: 1, leadsFirst: leadsFirst, weights: weights)
            case (1, .take):
                l *= probability(hand6, trump: open.suit.rawValue, open: open, round: 1, leadsFirst: leadsFirst, weights: weights)
            case (_, .pass):
                for s in 0..<4 where s != open.suit.rawValue {
                    l *= 1 - probability(hand6, trump: s, open: open, round: 2, leadsFirst: leadsFirst, weights: weights)
                }
            case (_, .name):
                if let s = bid.suit {
                    l *= probability(hand6, trump: s.rawValue, open: open, round: 2, leadsFirst: leadsFirst, weights: weights)
                }
            default:
                break
            }
        }
        return l
    }

    /// Правдоподобие по 9 картам на начало розыгрыша: какие 3 из них пришли из прикупа,
    /// неизвестно, поэтому усредняем по всем 84 вариантам.
    static func likelihood9(bids: [Bid], seat: Int, hand9: UInt32, open: Card, dealer: Int, players: Int) -> Double {
        guard bids.contains(where: { $0.seat == seat && $0.kind != .forced }) else { return 1 }
        guard hand9.nonzeroBitCount == 9 else { return 1 }
        var cardIDs = [Int](repeating: 0, count: 9)
        var m = hand9
        var k = 0
        while m != 0 { cardIDs[k] = m.trailingZeroBitCount; m &= m &- 1; k += 1 }
        var total = 0.0
        var count = 0.0
        for a in 0..<7 {
            for b in (a + 1)..<8 {
                for c in (b + 1)..<9 {
                    let h6 = hand9 & ~(bit(cardIDs[a]) | bit(cardIDs[b]) | bit(cardIDs[c]))
                    total += likelihood(bids: bids, seat: seat, hand6: h6, open: open, dealer: dealer, players: players)
                    count += 1
                }
            }
        }
        return total / count
    }
}
