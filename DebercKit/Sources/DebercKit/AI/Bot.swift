import Foundation

/// Компьютерный соперник.
///
/// Торговля: для каждой возможной масти козыря много раз разыгрывает сдачу
/// со случайно розданными скрытыми картами и считает средний итог (с байтами и штрафами).
/// Новичок торгуется «на глаз» — по простой оценке руки, как человек.
///
/// Розыгрыш: для каждой допустимой карты моделирует доигрывание сдачи в случайных
/// мирах, согласованных с тем, что видно на столе; в конце сдачи — точный перебор
/// (вдвоём — альфа-бета). Мастер вдобавок раздаёт миры с учётом торговли соперников.
/// Новичок играет по простым правилам, забывает старые взятки и иногда ходит «на автомате».
///
/// Бот принимает решения только по `SeatView` — чужих карт он не видит.
public struct Bot: Sendable {

    /// Как решать обмен козырной семёрки.
    public enum ExchangeMode: String, Sendable, Equatable {
        /// Менять всегда (как делают почти все новички).
        case always
        /// Менять, если это не ломает свою комбинацию и не стоит очков.
        case rule
        /// Сравнить обе возможности моделированием.
        case simulate
    }

    /// Параметры силы бота.
    public struct Config: Sendable, Equatable {
        // MARK: Торговля
        /// Сколько миров моделировать при оценке заявки. 0 — торговля «на глаз» (по модели руки).
        public var biddingSamples: Int
        /// Порог ожидаемого итога сдачи, чтобы взять открытую масть.
        public var takeThreshold: Double
        /// Порог, чтобы назвать свою масть во 2-м круге.
        public var nameThreshold: Double
        /// Сдвиг логита при торговле «на глаз» (характер Новичка).
        public var feelShift: Double
        /// Непостоянство оценки «на глаз»: разброс логита (одна и та же рука — одно решение).
        public var feelNoise: Double
        /// Вдвоём учитывать «обязы»: кому достанется сдача втёмную, если все спасуют.
        public var forcedAware: Bool
        public var exchange: ExchangeMode
        // MARK: Розыгрыш
        /// Сколько миров на ход. 0 — играть по правилам, без моделирования.
        public var playSamples: Int
        /// С какого числа карт на руке перебирать концовку точно (вдвоём / втроём).
        public var exactTwoPlayers: Int
        public var exactThreePlayers: Int
        /// Раздавать миры с учётом торговли соперников и объявленных комбинаций.
        public var inferFromBidding: Bool
        /// То же при оценке своей заявки: учитывать, что соперники уже спасовали или взяли.
        public var inferInBidding: Bool
        // MARK: «Человеческие» ошибки
        /// Сколько последних взяток бот помнит (nil — помнит все).
        public var memoryTricks: Int?
        /// Вероятность (в процентах) сыграть «на автомате»: побить старшей, зайти с крупной карты.
        public var slipPercent: Int
        /// В доигрываниях последние столько взяток перебирать точно (0 — всё по эвристике).
        public var rolloutExact: Int
        /// Карты, чья средняя оценка хуже лучшей не больше чем на столько очков, считаются
        /// равноценными — из них бот кладёт самую дешёвую (как сделал бы человек).
        public var tieMargin: Double
        /// Мягкий предел времени на ход в секундах (nil — без предела). Когда он исчерпан,
        /// бот доигрывает с тем числом миров, что успел (но не меньше четверти).
        public var timeBudget: Double?

        public init(biddingSamples: Int, takeThreshold: Double, nameThreshold: Double,
                    feelShift: Double = 0, feelNoise: Double = 0, forcedAware: Bool, exchange: ExchangeMode,
                    playSamples: Int, exactTwoPlayers: Int, exactThreePlayers: Int, inferFromBidding: Bool,
                    inferInBidding: Bool = false, memoryTricks: Int? = nil, slipPercent: Int = 0,
                    rolloutExact: Int = 0, tieMargin: Double = 0, timeBudget: Double? = nil) {
            self.biddingSamples = biddingSamples
            self.takeThreshold = takeThreshold
            self.nameThreshold = nameThreshold
            self.feelShift = feelShift
            self.feelNoise = feelNoise
            self.forcedAware = forcedAware
            self.exchange = exchange
            self.playSamples = playSamples
            self.exactTwoPlayers = exactTwoPlayers
            self.exactThreePlayers = exactThreePlayers
            self.inferFromBidding = inferFromBidding
            self.inferInBidding = inferInBidding
            self.memoryTricks = memoryTricks
            self.slipPercent = slipPercent
            self.tieMargin = tieMargin
            self.rolloutExact = rolloutExact
            self.timeBudget = timeBudget
        }

        /// Настройки уровня и стиля.
        public static func preset(_ level: BotLevel, style: BotStyle = .balanced) -> Config {
            var c: Config
            switch level {
            case .novice:
                c = Config(biddingSamples: 0, takeThreshold: 0, nameThreshold: 0,
                           feelNoise: 3.2, forcedAware: false, exchange: .always,
                           playSamples: 0, exactTwoPlayers: 0, exactThreePlayers: 0, inferFromBidding: false,
                           memoryTricks: 1, slipPercent: 30)
            case .amateur:
                c = Config(biddingSamples: 20, takeThreshold: 4, nameThreshold: -5,
                           forcedAware: true, exchange: .rule,
                           playSamples: 4, exactTwoPlayers: 2, exactThreePlayers: 1, inferFromBidding: false)
            case .expert:
                c = Config(biddingSamples: 48, takeThreshold: 4, nameThreshold: -5,
                           forcedAware: true, exchange: .simulate,
                           playSamples: 16, exactTwoPlayers: 3, exactThreePlayers: 2, inferFromBidding: false,
                           timeBudget: 0.5)
            case .master:
                c = Config(biddingSamples: 128, takeThreshold: 4, nameThreshold: -5,
                           forcedAware: true, exchange: .simulate,
                           playSamples: 160, exactTwoPlayers: 6, exactThreePlayers: 4, inferFromBidding: true,
                           timeBudget: 0.9)
            }
            c.takeThreshold += style.takeShift
            c.nameThreshold += style.nameShift
            c.feelShift += style.feelShift
            return c
        }
    }

    public let level: BotLevel
    public let style: BotStyle
    public let config: Config
    /// Личное зерно: в одинаковой ситуации бот торгуется одинаково.
    let personalSeed: UInt64

    public init(level: BotLevel, style: BotStyle = .balanced) {
        self.init(config: .preset(level, style: style), level: level, style: style)
    }

    public init(persona: Persona) {
        self.init(config: .preset(persona.level, style: persona.style), level: persona.level,
                  style: persona.style, seedKey: persona.id)
    }

    /// Бот с произвольными настройками (для экспериментов).
    public init(config: Config, level: BotLevel = .expert, style: BotStyle = .balanced) {
        self.init(config: config, level: level, style: style, seedKey: "\(level.rawValue)-\(style.rawValue)")
    }

    private init(config: Config, level: BotLevel, style: BotStyle, seedKey: String) {
        self.level = level
        self.style = style
        self.config = config
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seedKey.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        personalSeed = h
    }

    // MARK: - Публичный интерфейс

    /// Выбор действия, когда очередь игрока `view.seat`. Бот видит только `view`.
    public func chooseAction(view: SeatView, rng: inout SplitMix64) -> Action {
        guard view.isMyTurn else { return .pass }
        switch view.phase {
        case .bidding(let round):
            var local = SplitMix64(seed: view.positionHash ^ personalSeed)
            return bid(view, round: round, rng: &local)
        case .exchange:
            var local = SplitMix64(seed: view.positionHash ^ personalSeed ^ 0x7E7E)
            return .exchangeSeven(shouldExchange(view, rng: &local))
        case .playing:
            return .play(chooseCard(view, rng: &rng))
        case .finished:
            return .pass
        }
    }

    /// То же по партии: бот получает только то, что видит игрок `seat`.
    public func chooseAction(match: Match, seat: Int, rng: inout SplitMix64) -> Action {
        guard let deal = match.deal, !match.isOver, deal.actor == seat else { return .pass }
        return chooseAction(view: SeatView(match: match, seat: seat), rng: &rng)
    }

    /// Совет для игрока `seat` — как сыграл бы Мастер. Детерминирован: в одной и той же
    /// позиции всегда один и тот же ответ. nil — сейчас не ход этого игрока.
    public static func hint(match: Match, seat: Int) -> Action? {
        guard let deal = match.deal, !match.isOver, deal.actor == seat else { return nil }
        let view = SeatView(match: match, seat: seat)
        var config = Config.preset(.master)
        #if DEBUG
        // Отладочная сборка в разы медленнее: ограничиваем время, чтобы совет не заставлял ждать.
        config.timeBudget = 2.0
        #else
        config.timeBudget = nil
        #endif
        let bot = Bot(config: config, level: .master, style: .balanced)
        var rng = SplitMix64(seed: view.positionHash ^ 0x5EED_C0DE)
        return bot.chooseAction(view: view, rng: &rng)
    }

    /// Насколько трудное сейчас решение (0…1) — чтобы «думать» дольше над трудным
    /// и не медлить с единственной картой. Считается мгновенно.
    public static func decisionWeight(match: Match, seat: Int) -> Double {
        guard let deal = match.deal, !match.isOver, deal.actor == seat else { return 0 }
        let n = deal.playerCount
        let hand = mask(of: deal.hands[seat])
        let leadsFirst = seat == (deal.dealer + 1) % n
        func closeness(_ p: Double) -> Double { 1 - abs(2 * p - 1) }
        switch deal.phase {
        case .bidding(let round):
            let weights = BidModel.strong(players: n)
            if round == 1 {
                let p = BidModel.probability(hand, trump: deal.openCard.suit.rawValue, open: deal.openCard,
                                             round: 1, leadsFirst: leadsFirst, weights: weights)
                return clamp(0.3 + 0.6 * closeness(p))
            }
            var best = 0.0
            for s in 0..<4 where s != deal.openCard.suit.rawValue {
                best = max(best, BidModel.probability(hand, trump: s, open: deal.openCard, round: 2,
                                                      leadsFirst: leadsFirst, weights: weights))
            }
            // Выбрать масть труднее, чем ответить «беру/пас».
            return clamp(0.4 + 0.6 * max(closeness(best), best > 0.5 ? 0.5 : 0))
        case .exchange:
            return 0.35
        case .playing:
            let legal = deal.legalCards(for: seat)
            if legal.count <= 1 { return 0.05 }
            var w = 0.25 + 0.08 * Double(min(legal.count - 1, 6))
            if deal.tricks.isEmpty && deal.currentTrick.plays.isEmpty { w += 0.2 }  // первый ход — «разбирает карты»
            if deal.currentTrick.plays.isEmpty { w += 0.1 }                          // заход труднее ответа
            if legal.allSatisfy({ $0.suit == legal[0].suit }) && !deal.currentTrick.plays.isEmpty { w -= 0.1 }
            return clamp(w)
        case .finished:
            return 0
        }
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    // MARK: - Торговля

    func bid(_ v: SeatView, round: Int, rng: inout SplitMix64) -> Action {
        if config.biddingSamples == 0 { return bidByFeel(v, round: round, rng: &rng) }
        let open = v.openCard.suit
        if round == 1 {
            let ev = evaluateBid(v, trumps: [open], rng: &rng)[0]
            return ev >= config.takeThreshold ? .take : .pass
        }
        let suits = Suit.allCases.filter { $0 != open }
        let evs = evaluateBid(v, trumps: suits, rng: &rng)
        var best = 0
        for i in 1..<suits.count where evs[i] > evs[best] { best = i }
        return evs[best] >= nameThreshold(v) ? .name(suits[best]) : .pass
    }

    /// Порог «назвать масть» во 2-м круге с учётом «обязов».
    func nameThreshold(_ v: SeatView) -> Double {
        config.nameThreshold + forcedShift(v)
    }

    /// Вдвоём при угрозе «обязов» пас стоит не ноль: если спасует сдающий, соперник
    /// сыграет втёмную (≈ +30 нам), а если спасуем мы, первым говорящим, — втёмную играть нам.
    /// Втроём замеры пользы не показали — там порог не меняется.
    func forcedShift(_ v: SeatView) -> Double {
        guard config.forcedAware, v.playerCount == 2, let forced = v.forcedSeatIfAllPass else { return 0 }
        if v.seat == v.dealer { return Bot.forcedPassValue }
        if v.seat == forced { return -0.8 * Bot.forcedPassValue }
        return 0
    }

    /// Во сколько очков обходится сдача «на обязах» сдающему (вдвоём, замер на самоигре).
    static let forcedPassValue = 30.0

    /// Торговля «на глаз»: простая оценка руки, как у начинающего игрока.
    func bidByFeel(_ v: SeatView, round: Int, rng: inout SplitMix64) -> Action {
        let n = v.playerCount
        let hand = mask(of: v.myHand)
        let weights = n == 2 ? BidModel.novice2 : BidModel.novice3
        let leadsFirst = v.seat == v.next(v.dealer)
        // «Настроение»: человек оценивает похожие руки то смелее, то осторожнее.
        func mood() -> Double { config.feelNoise * Bot.gaussian(&rng) }
        if round == 1 {
            let z = BidModel.logit(hand, trump: v.openCard.suit.rawValue, open: v.openCard, round: 1,
                                   leadsFirst: leadsFirst, weights: weights)
            return z + config.feelShift + mood() >= 0 ? .take : .pass
        }
        var bestSuit = -1
        var bestZ = -Double.infinity
        for s in 0..<4 where s != v.openCard.suit.rawValue {
            let z = BidModel.logit(hand, trump: s, open: v.openCard, round: 2, leadsFirst: leadsFirst, weights: weights)
                + mood()
            if z > bestZ { bestZ = z; bestSuit = s }
        }
        return bestZ + config.feelShift >= 0 ? .name(Suit(rawValue: bestSuit)!) : .pass
    }

    /// Нормальная случайная величина (Бокс — Мюллер).
    static func gaussian(_ rng: inout SplitMix64) -> Double {
        let u1 = (Double(rng.next() >> 11) + 0.5) / Double(1 << 53)
        let u2 = Double(rng.next() >> 11) / Double(1 << 53)
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    /// Средний итог сдачи для игрока, если он назначит козырем каждую из мастей `trumps`.
    /// Все масти оцениваются на одних и тех же мирах — сравнение честнее.
    func evaluateBid(_ v: SeatView, trumps: [Suit], rng: inout SplitMix64) -> [Double] {
        let samples = max(1, config.biddingSamples)
        var totals = [Double](repeating: 0, count: trumps.count)
        let worlds = config.inferInBidding && v.bids.contains(where: { $0.seat != v.seat })
            ? WorldSampler.sampleBiddingInformed(v, count: samples, rng: &rng)
            : (0..<samples).map { _ in WorldSampler.sampleBidding(v, rng: &rng) }
        for world in worlds {
            for (i, trump) in trumps.enumerated() {
                totals[i] += simulateDeal(v, hands6: world.hands, prikup: world.prikup, trump: trump, bidder: v.seat)
            }
        }
        return totals.map { $0 / Double(samples) }
    }

    /// Доигрывание сдачи по правилам в мире торговли, где козырь `trump` назначил `bidder`.
    func simulateDeal(_ v: SeatView, hands6: [UInt32], prikup: [UInt32], trump: Suit, bidder: Int) -> Double {
        let rules = v.rules
        let n = v.playerCount
        var hands = (0..<n).map { hands6[$0] | prikup[$0] }
        var open = v.openCard
        if trump == v.openCard.suit && rules.sevenExchange != .off {
            let seven = Card(.seven, trump)
            if let holder = hands.firstIndex(where: { $0 & bit(seven.id) != 0 }),
               rules.sevenExchange == .anyPlayer || holder == bidder,
               Bot.exchangeByRule(hand: hands[holder], open: open, trump: trump, rules: rules) {
                hands[holder] = (hands[holder] & ~bit(seven.id)) | bit(open.id)
                open = seven
            }
        }
        var seen = bit(open.id)
        if let bottom = v.bottomCard { seen |= bit(bottom.id) }
        let firstLead = rules.firstLead == .afterDealer ? v.next(v.dealer) : bidder
        return rollout(v, hands: hands, trump: trump, bidder: bidder, seen: seen, firstLead: firstLead)
    }

    /// Разыграть сдачу с начала по эвристике; полезность для `v.seat`.
    private func rollout(_ v: SeatView, hands: [UInt32], trump: Suit, bidder: Int, seen: UInt32, firstLead: Int) -> Double {
        let n = v.playerCount
        let cardHands = hands.map { m in ids(in: m).map { Card(id: $0) } }
        let order = v.leadOrder(bidder: bidder)
        let decl = Combinations.declarations(hands: cardHands, trump: trump, rules: v.rules, priority: order)
        let ctx = SimContext(
            rules: v.rules, playerCount: n, trump: trump.rawValue, bidder: bidder,
            priority: order, declarations: decl, pot: v.pot,
            baitCounts: v.baitCounts, nakedCounts: v.nakedCounts)
        let zeros = [Int](repeating: 0, count: n)
        var state = SimState(hands: hands, turn: firstLead, cardPoints: zeros, tricks: zeros,
                             played: seen, tricksLeft: hands[0].nonzeroBitCount, ctx: ctx)
        while !state.finished { state.play(HeuristicPolicy.choose(state, ctx), ctx) }
        return state.utility(ctx, for: v.seat)
    }

    // MARK: - Обмен козырной семёрки

    func shouldExchange(_ v: SeatView, rng: inout SplitMix64) -> Bool {
        guard let trump = v.trump else { return true }
        switch config.exchange {
        case .always:
            return true
        case .rule:
            return Bot.exchangeByRule(hand: mask(of: v.myHand), open: v.openCard, trump: trump, rules: v.rules)
        case .simulate:
            return exchangeBySimulation(v, trump: trump, rng: &rng)
        }
    }

    /// Быстрое правило: меняем, если очки открытой карты, её сила и комбинации после обмена
    /// не хуже, чем было. Валет и девятку козырей берём всегда.
    static func exchangeByRule(hand: UInt32, open: Card, trump: Suit, rules: RuleSet) -> Bool {
        let seven = Card(.seven, trump)
        guard hand & bit(seven.id) != 0 else { return false }
        if open.rank == .jack || open.rank == .nine { return true }
        let after = (hand & ~bit(seven.id)) | bit(open.id)
        let delta = meldValue(after, trump: trump, rules: rules) - meldValue(hand, trump: trump, rules: rules)
        return delta + open.points(trump: trump) >= 0
    }

    /// Очки своих комбинаций и бэлы (оценка «на руке»).
    static func meldValue(_ hand: UInt32, trump: Suit, rules: RuleSet) -> Int {
        var total = 0
        for suit in 0..<4 {
            let byte = Int((hand >> UInt32(suit * 8)) & 0xFF)
            var run = 0
            for r in 0...8 {
                if r < 8 && byte & (1 << r) != 0 {
                    run += 1
                } else {
                    if run >= 5 && rules.hundredForFive {
                        total += 100
                    } else if run >= 4 {
                        total += rules.fiftyPoints
                    } else if run == 3 {
                        total += rules.terzPoints
                    }
                    run = 0
                }
            }
        }
        let pair = bit(Card(.king, trump).id) | bit(Card(.queen, trump).id)
        if hand & pair == pair { total += rules.bellaPoints }
        return total
    }

    /// Сравнить «поменять» и «оставить» на одних и тех же мирах.
    private func exchangeBySimulation(_ v: SeatView, trump: Suit, rng: inout SplitMix64) -> Bool {
        let seven = Card(.seven, trump)
        let myHand = mask(of: v.myHand)
        guard myHand & bit(seven.id) != 0, let bidder = v.bidder else { return true }
        if v.openCard.rank == .jack || v.openCard.rank == .nine { return true }
        let info = WorldSampler.PlayInfo(v)
        let samples = max(24, config.biddingSamples / 2)
        let firstLead = v.rules.firstLead == .afterDealer ? v.next(v.dealer) : bidder
        var bottomSeen: UInt32 = 0
        if let bottom = v.bottomCard { bottomSeen = bit(bottom.id) }
        var gain = 0.0
        for _ in 0..<samples {
            var hands = WorldSampler.samplePlay(info, rng: &rng)
            let keep = rollout(v, hands: hands, trump: trump, bidder: bidder,
                               seen: bit(v.openCard.id) | bottomSeen, firstLead: firstLead)
            hands[v.seat] = (myHand & ~bit(seven.id)) | bit(v.openCard.id)
            let swap = rollout(v, hands: hands, trump: trump, bidder: bidder,
                               seen: bit(seven.id) | bottomSeen, firstLead: firstLead)
            gain += swap - keep
        }
        return gain >= 0
    }

    // MARK: - Розыгрыш

    func chooseCard(_ v: SeatView, rng: inout SplitMix64) -> Card {
        guard let trump = v.trump, let bidder = v.bidder else { return v.myHand[0] }
        let legal = PlayRules.legalCards(hand: v.myHand, trick: v.currentTrick.cards, trump: trump, rules: v.rules)
        if legal.count == 1 { return legal[0] }
        if config.playSamples == 0 {
            return humanLikeCard(v, legal: legal, trump: trump, bidder: bidder, rng: &rng)
        }
        return searchCard(v, legal: legal, trump: trump, bidder: bidder, rng: &rng)
    }

    /// Что известно о сыгранном: очки и взятки каждого, видимые карты.
    private struct Table {
        var seen: UInt32
        var cardPoints: [Int]
        var tricks: [Int]
        var tricksLeft: Int
        var trick: [(seat: Int, card: Int)]
    }

    private func table(_ v: SeatView, trump: Suit) -> Table {
        let n = v.playerCount
        var seen = mask(of: v.playedCards) | bit(v.openCard.id)
        if let bottom = v.bottomCard { seen |= bit(bottom.id) }
        var cardPoints = [Int](repeating: 0, count: n)
        var tricks = [Int](repeating: 0, count: n)
        for trick in v.tricks {
            guard let w = trick.winner else { continue }
            cardPoints[w] += PlayRules.points(of: trick.cards, trump: trump)
            tricks[w] += 1
        }
        let tricksLeft = v.myHand.count + (v.currentTrick.plays.contains { $0.seat == v.seat } ? 1 : 0)
        return Table(seen: seen, cardPoints: cardPoints, tricks: tricks, tricksLeft: tricksLeft,
                     trick: v.currentTrick.plays.map { (seat: $0.seat, card: $0.card.id) })
    }

    /// Моделирование: для каждой карты — средний итог сдачи по мирам.
    private func searchCard(_ v: SeatView, legal: [Card], trump: Suit, bidder: Int, rng: inout SplitMix64) -> Card {
        let n = v.playerCount
        let t = table(v, trump: trump)
        let info = WorldSampler.PlayInfo(v)
        let handSize = v.myHand.count
        let alphaBeta = n == 2 && handSize <= config.exactTwoPlayers
        let maxN = n == 3 && handSize <= config.exactThreePlayers
        let target = config.playSamples
        let minimum = max(4, target / 4)
        let started = DispatchTime.now().uptimeNanoseconds
        let budget = config.timeBudget.map { UInt64($0 * 1e9) }

        var worlds: [[UInt32]] = []
        if config.inferFromBidding {
            worlds = WorldSampler.sampleInformed(v, info: info, count: target, rng: &rng)
        }

        var scores = [Double](repeating: 0, count: legal.count)
        var done = 0
        while done < target {
            if let budget, done >= minimum, done % 4 == 0,
               DispatchTime.now().uptimeNanoseconds - started > budget { break }
            let hands = config.inferFromBidding ? worlds[done] : WorldSampler.samplePlay(info, rng: &rng)
            done += 1
            let ctx = context(v, trump: trump, bidder: bidder, worldHands: hands)
            let base = SimState(hands: hands, turn: v.seat, cardPoints: t.cardPoints, tricks: t.tricks,
                                played: t.seen, tricksLeft: t.tricksLeft, trick: t.trick, ctx: ctx)
            for (i, card) in legal.enumerated() {
                var s = base
                s.play(card.id, ctx)
                if alphaBeta {
                    scores[i] += Search.alphaBeta(s, ctx, me: v.seat, alpha: -.infinity, beta: .infinity)
                } else if maxN {
                    scores[i] += Search.maxN(s, ctx)[v.seat]
                } else {
                    scores[i] += finishRollout(s, ctx, me: v.seat)
                }
            }
        }
        let tolerance = 0.25 + config.tieMargin * Double(done)
        return legal[Bot.naturalPick(legal: legal, scores: scores, trump: trump, tolerance: tolerance)]
    }

    /// Доиграть сдачу по эвристике; последние `rolloutExact` взяток — точным перебором.
    @inline(__always)
    private func finishRollout(_ start: SimState, _ ctx: SimContext, me: Int) -> Double {
        var s = start
        let exact = config.rolloutExact
        while !s.finished {
            if exact > 0 && s.trickCount == 0 && s.tricksLeft <= exact {
                return s.n == 2
                    ? Search.alphaBeta(s, ctx, me: me, alpha: -.infinity, beta: .infinity)
                    : Search.maxN(s, ctx)[me]
            }
            s.play(HeuristicPolicy.choose(s, ctx), ctx)
        }
        return s.utility(ctx, for: me)
    }

    /// Среди карт с почти одинаковой оценкой — «естественная»: самая дешёвая и младшая,
    /// козырь — в последнюю очередь. Так бот не «дарит» тузы и десятки, когда всё равно.
    /// `tolerance` — допуск на сумму оценок по мирам (полезности кратны 0.5, поэтому 0.25 —
    /// только точные ничьи).
    static func naturalPick(legal: [Card], scores: [Double], trump: Suit, tolerance: Double = 0.25) -> Int {
        var best = 0
        for i in 1..<legal.count where scores[i] > scores[best] { best = i }
        let key = CardTables.naturalKey[trump.rawValue]
        var pick = best
        var pickKey = key[legal[best].id]
        for i in legal.indices where scores[i] >= scores[best] - tolerance && key[legal[i].id] < pickKey {
            pick = i
            pickKey = key[legal[i].id]
        }
        return pick
    }

    /// Объявления в конкретном мире: последовательности победителя известны,
    /// бэла — у того, у кого в этом мире король и дама козырей.
    private func context(_ v: SeatView, trump: Suit, bidder: Int, worldHands: [UInt32]) -> SimContext {
        let n = v.playerCount
        var bellaSeat = v.knownBellaSeat ?? -1
        if v.knownBellaSeat == nil {
            let king = Card(.king, trump), queen = Card(.queen, trump)
            let played = mask(of: v.playedCards)
            let pair = bit(king.id) | bit(queen.id)
            if played & pair == 0 {
                bellaSeat = (0..<n).first { worldHands[$0] & pair == pair } ?? -1
            }
        }
        return SimContext(
            rules: v.rules, playerCount: n, trump: trump.rawValue, bidder: bidder, priority: v.leadOrder(bidder: bidder),
            meldWinner: v.meldWinner ?? -1, meldPoints: v.meldWinnerPoints, bellaSeat: bellaSeat,
            pot: v.pot, baitCounts: v.baitCounts, nakedCounts: v.nakedCounts)
    }

    // MARK: - Игра «по-человечески» (Новичок)

    /// Играет по простым правилам, но помнит только последние взятки
    /// и иногда ходит «на автомате». Тузы и десятки зря не сбрасывает.
    private func humanLikeCard(_ v: SeatView, legal: [Card], trump: Suit, bidder: Int, rng: inout SplitMix64) -> Card {
        let n = v.playerCount
        let t = table(v, trump: trump)
        var remembered = t.seen
        if let memory = config.memoryTricks {
            remembered = mask(of: v.currentTrick.cards) | bit(v.openCard.id)
            if let bottom = v.bottomCard { remembered |= bit(bottom.id) }
            for trick in v.tricks.suffix(memory) { remembered |= mask(of: trick.cards) }
            // Старшие козыри запоминает каждый.
            let jack = bit(Card(.jack, trump).id), nine = bit(Card(.nine, trump).id)
            remembered |= t.seen & (jack | nine)
        }
        var hands = [UInt32](repeating: 0, count: n)
        hands[v.seat] = mask(of: v.myHand)
        let ctx = context(v, trump: trump, bidder: bidder, worldHands: hands)
        let state = SimState(hands: hands, turn: v.seat, cardPoints: t.cardPoints, tricks: t.tricks,
                             played: remembered, tricksLeft: t.tricksLeft, trick: t.trick, ctx: ctx)
        if config.slipPercent > 0 && Int(rng.next() % 100) < config.slipPercent,
           let slip = HumanSlips.choose(state, ctx, rng: &rng) {
            return Card(id: slip)
        }
        return Card(id: HeuristicPolicy.choose(state, ctx))
    }
}

/// Типичные ходы «на автомате» у начинающих. Все они допустимы и выглядят по-человечески:
/// защищаясь, «выбить козыри»; зайти с десятки, не добрав козыри; не побить, «придержав» старшую;
/// побить самой старшей.
/// Тузы и десятки в чужую взятку новичок зря не сбрасывает.
enum HumanSlips {
    static func choose(_ s: SimState, _ ctx: SimContext, rng: inout SplitMix64) -> Int? {
        let legal = s.legalMask(ctx)
        if legal & (legal &- 1) == 0 { return nil }
        let hand = s.hands[s.turn]
        if s.trickCount == 0 {
            // Защищаясь, «выбивает козыри» старшим козырем — частая ошибка начинающих.
            let trumps = legal & ctx.trumpBits
            if s.turn != ctx.bidder && trumps != 0 && rng.next() % 2 == 0 {
                var top = -1
                var m = trumps
                while m != 0 {
                    let id = m.trailingZeroBitCount
                    m &= m &- 1
                    if top < 0 || ctx.power[id] > ctx.power[top] { top = id }
                }
                return top
            }
            let plain = legal & ~ctx.trumpBits
            guard plain != 0 else { return nil }
            // «Повёл десяткой»: десятка без своего туза.
            for suit in 0..<4 where suit != ctx.trump {
                let ten = bit(suit * 8 + Rank.ten.index), ace = bit(suit * 8 + Rank.ace.index)
                if plain & ten != 0 && hand & ace == 0 { return suit * 8 + Rank.ten.index }
            }
            // Иначе — с самой дорогой некозырной карты (даже не добрав козыри).
            var best = -1
            var m = plain
            while m != 0 {
                let id = m.trailingZeroBitCount
                m &= m &- 1
                if best < 0 || ctx.points[id] > ctx.points[best]
                    || (ctx.points[id] == ctx.points[best] && ctx.power[id] > ctx.power[best]) { best = id }
            }
            return ctx.points[best] >= 3 ? best : nil
        }
        var winners: UInt32 = 0
        var m = legal
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m &- 1
            if s.beatsTrick(id, ctx) { winners |= bit(id) }
        }
        guard winners != 0 else { return nil }
        let losers = legal & ~winners
        let isLast = s.trickCount == s.n - 1
        if !isLast && winners & ~ctx.trumpBits != 0 && losers != 0 && s.trickPoints >= 3 {
            // «Придержал старшую»: не стал бить и сбросил мелкую.
            return HeuristicPolicy.cheapest(losers, ctx)
        }
        // Бьёт самой старшей картой (козырем — старшим козырем).
        var top = -1
        m = winners
        while m != 0 {
            let id = m.trailingZeroBitCount
            m &= m &- 1
            if top < 0 || ctx.power[id] > ctx.power[top] { top = id }
        }
        return top
    }
}
