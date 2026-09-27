import Foundation

public enum BotLevel: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    public var title: String {
        switch self {
        case .easy: return "Лёгкий"
        case .medium: return "Средний"
        case .hard: return "Сильный"
        }
    }
}

/// Компьютерный соперник.
///
/// Торговля: для каждой возможной масти козыря много раз разыгрывает сдачу
/// со случайно розданными скрытыми картами и считает средний итог (с байтами и штрафами).
/// Розыгрыш: для каждой допустимой карты моделирует доигрывание сдачи в случайных
/// мирах, согласованных с тем, что видно на столе; в конце сдачи — точный перебор.
public struct Bot: Sendable {

    /// Параметры силы бота.
    public struct Config: Sendable, Equatable {
        public var biddingSamples: Int
        public var playSamples: Int
        /// Сколько карт на руке должно остаться, чтобы перебирать концовку точно (вдвоём / втроём).
        public var exactTwoPlayers: Int
        public var exactThreePlayers: Int
        /// Порог ожидаемого выигрыша, чтобы взять открытую масть.
        public var takeThreshold: Double
        /// Порог, чтобы назвать свою масть во 2-м круге.
        public var nameThreshold: Double
        /// Разброс порогов (для «живости» лёгкого уровня).
        public var bidNoise: Int
        /// Доля случайных ходов, в процентах.
        public var randomMovePercent: Int

        public init(biddingSamples: Int, playSamples: Int, exactTwoPlayers: Int, exactThreePlayers: Int,
                    takeThreshold: Double, nameThreshold: Double, bidNoise: Int, randomMovePercent: Int) {
            self.biddingSamples = biddingSamples
            self.playSamples = playSamples
            self.exactTwoPlayers = exactTwoPlayers
            self.exactThreePlayers = exactThreePlayers
            self.takeThreshold = takeThreshold
            self.nameThreshold = nameThreshold
            self.bidNoise = bidNoise
            self.randomMovePercent = randomMovePercent
        }

        public static func preset(_ level: BotLevel) -> Config {
            switch level {
            case .easy:
                return Config(biddingSamples: 16, playSamples: 0, exactTwoPlayers: 0, exactThreePlayers: 0,
                              takeThreshold: 8, nameThreshold: 0, bidNoise: 15, randomMovePercent: 15)
            case .medium:
                return Config(biddingSamples: 48, playSamples: 20, exactTwoPlayers: 3, exactThreePlayers: 2,
                              takeThreshold: 4, nameThreshold: -5, bidNoise: 0, randomMovePercent: 0)
            case .hard:
                return Config(biddingSamples: 96, playSamples: 48, exactTwoPlayers: 4, exactThreePlayers: 3,
                              takeThreshold: 4, nameThreshold: -5, bidNoise: 0, randomMovePercent: 0)
            }
        }
    }

    public var level: BotLevel
    public var config: Config

    public init(level: BotLevel) {
        self.level = level
        self.config = .preset(level)
    }

    public init(config: Config) {
        self.level = .hard
        self.config = config
    }

    private var biddingSamples: Int { config.biddingSamples }
    private var playSamples: Int { config.playSamples }

    /// Сколько карт на руке должно остаться, чтобы перебирать концовку точно.
    private func exactThreshold(players: Int) -> Int {
        players == 2 ? config.exactTwoPlayers : config.exactThreePlayers
    }

    /// Выбор действия для игрока `seat`, когда его очередь.
    public func chooseAction(match: Match, seat: Int, rng: inout SplitMix64) -> Action {
        guard let deal = match.deal, deal.actor == seat else { return .pass }
        let view = SeatView(match: match, seat: seat)
        switch deal.phase {
        case .bidding(let round):
            return bid(view, round: round, rng: &rng)
        case .exchange:
            return .exchangeSeven(true)
        case .playing:
            return .play(chooseCard(view, rng: &rng))
        case .finished:
            return .pass
        }
    }

    // MARK: - Торговля

    func bid(_ v: SeatView, round: Int, rng: inout SplitMix64) -> Action {
        let spread = config.bidNoise
        let noise: Double = spread > 0 ? Double(Int(rng.next() % UInt64(2 * spread + 1)) - spread) : 0
        if round == 1 {
            let ev = evaluateBid(v, trump: v.openCard.suit, rng: &rng)
            return ev + noise >= config.takeThreshold ? .take : .pass
        }
        var bestSuit: Suit?
        var bestEV = -Double.infinity
        for suit in Suit.allCases where suit != v.openCard.suit {
            let ev = evaluateBid(v, trump: suit, rng: &rng)
            if ev > bestEV { bestEV = ev; bestSuit = suit }
        }
        if let bestSuit, bestEV + noise >= config.nameThreshold { return .name(bestSuit) }
        return .pass
    }

    /// Средний итог сдачи для игрока, если он назначит козырь `trump`.
    func evaluateBid(_ v: SeatView, trump: Suit, rng: inout SplitMix64) -> Double {
        let rules = v.rules
        let n = v.playerCount
        let samples = biddingSamples
        var total = 0.0
        for _ in 0..<samples {
            let world = WorldSampler.sampleBidding(v, rng: &rng)
            var hands = (0..<n).map { world.hands[$0] + world.prikup[$0] }
            var open = v.openCard
            if trump == v.openCard.suit && rules.sevenExchange != .off {
                let seven = Card(.seven, trump)
                if let holder = hands.firstIndex(where: { $0.contains(seven) }),
                   rules.sevenExchange == .anyPlayer || holder == v.seat,
                   let i = hands[holder].firstIndex(of: seven) {
                    hands[holder].remove(at: i)
                    hands[holder].append(open)
                    open = seven
                }
            }
            let decl = Combinations.declarations(hands: hands, trump: trump, rules: rules, priority: v.seatsFromDealer)
            let ctx = SimContext(
                rules: rules, playerCount: n, trump: trump.rawValue, bidder: v.seat,
                priority: v.seatsFromDealer, declarations: decl, pot: v.pot,
                baitCounts: v.baitCounts, nakedCounts: v.nakedCounts)
            var seen = bit(open.id)
            if let bottom = v.bottomCard { seen |= bit(bottom.id) }
            let firstLead = rules.firstLead == .afterDealer ? (v.dealer + 1) % n : v.seat
            var state = SimState(
                hands: hands.map { mask(of: $0) }, turn: firstLead,
                cardPoints: [Int](repeating: 0, count: n), tricks: [Int](repeating: 0, count: n),
                played: seen, tricksLeft: hands[0].count)
            while !state.finished {
                state.play(HeuristicPolicy.choose(state, ctx, bidder: v.seat), ctx)
            }
            total += state.utilities(ctx)[v.seat]
        }
        return total / Double(samples)
    }

    // MARK: - Розыгрыш

    func chooseCard(_ v: SeatView, rng: inout SplitMix64) -> Card {
        guard let trump = v.trump, let bidder = v.bidder else { return v.myHand[0] }
        let legal = PlayRules.legalCards(hand: v.myHand, trick: v.currentTrick.cards, trump: trump, rules: v.rules)
        if legal.count == 1 { return legal[0] }

        let n = v.playerCount
        var seen = mask(of: v.playedCards) | bit(v.openCard.id)
        if let bottom = v.bottomCard { seen |= bit(bottom.id) }
        var cardPoints = [Int](repeating: 0, count: n)
        var tricksTaken = [Int](repeating: 0, count: n)
        for trick in v.tricks {
            guard let w = trick.winner else { continue }
            cardPoints[w] += PlayRules.points(of: trick.cards, trump: trump)
            tricksTaken[w] += 1
        }
        let tricksLeft = v.myHand.count + (v.currentTrick.plays.contains { $0.seat == v.seat } ? 1 : 0)

        func baseState(hands: [UInt32]) -> SimState {
            SimState(
                hands: hands, trickCards: v.currentTrick.cards.map(\.id),
                trickSeats: v.currentTrick.plays.map(\.seat), turn: v.seat,
                cardPoints: cardPoints, tricks: tricksTaken, played: seen, tricksLeft: tricksLeft)
        }

        if playSamples == 0 {
            if rng.next() % 100 < UInt64(config.randomMovePercent) {
                return legal[Int(rng.next() % UInt64(legal.count))]
            }
            var hands = [UInt32](repeating: 0, count: n)
            hands[v.seat] = mask(of: v.myHand)
            let ctx = context(v, trump: trump, bidder: bidder, worldHands: hands)
            return Card(id: HeuristicPolicy.choose(baseState(hands: hands), ctx, bidder: bidder))
        }

        let threshold = exactThreshold(players: n)
        var scores = [Double](repeating: 0, count: legal.count)
        for _ in 0..<playSamples {
            let hands = WorldSampler.samplePlay(v, rng: &rng)
            let ctx = context(v, trump: trump, bidder: bidder, worldHands: hands)
            let base = baseState(hands: hands)
            let exact = v.myHand.count <= threshold
            for (i, card) in legal.enumerated() {
                var s = base
                s.play(card.id, ctx)
                let u: Double
                if exact {
                    u = Bot.search(s, ctx)[v.seat]
                } else {
                    while !s.finished { s.play(HeuristicPolicy.choose(s, ctx, bidder: bidder), ctx) }
                    u = s.utilities(ctx)[v.seat]
                }
                scores[i] += u
            }
        }
        var best = 0
        for i in 1..<legal.count where scores[i] > scores[best] + 1e-9 { best = i }
        return legal[best]
    }

    /// Объявления в конкретном мире: последовательности победителя известны,
    /// бэла — у того, у кого в этом мире король и дама козырей.
    private func context(_ v: SeatView, trump: Suit, bidder: Int, worldHands: [UInt32]) -> SimContext {
        let n = v.playerCount
        var melds = [[Meld]](repeating: [], count: n)
        if let w = v.meldWinner { melds[w] = v.winnerMelds }
        var bellaSeat = v.knownBellaSeat
        if bellaSeat == nil {
            let king = Card(.king, trump), queen = Card(.queen, trump)
            let played = Set(v.playedCards)
            if !played.contains(king) && !played.contains(queen) {
                let pair = bit(king.id) | bit(queen.id)
                bellaSeat = (0..<n).first { worldHands[$0] & pair == pair }
            }
        }
        return SimContext(
            rules: v.rules, playerCount: n, trump: trump.rawValue, bidder: bidder,
            priority: v.seatsFromDealer,
            declarations: Declarations(melds: melds, meldWinner: v.meldWinner, bellaSeat: bellaSeat),
            pot: v.pot, baitCounts: v.baitCounts, nakedCounts: v.nakedCounts)
    }

    /// Точный перебор до конца сдачи: каждый игрок выбирает лучшее для себя.
    static func search(_ s: SimState, _ ctx: SimContext) -> [Double] {
        if s.finished { return s.utilities(ctx) }
        let me = s.turn
        var best: [Double] = []
        var bestValue = -Double.infinity
        for id in ids(in: s.legalMask(ctx)) {
            var t = s
            t.play(id, ctx)
            let u = search(t, ctx)
            if u[me] > bestValue {
                bestValue = u[me]
                best = u
            }
        }
        return best
    }
}
