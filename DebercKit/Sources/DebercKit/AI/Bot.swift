import Foundation

/// Компьютерный соперник.
///
/// Торговля: для каждой возможной масти козыря много раз разыгрывает сдачу
/// со случайно розданными скрытыми картами и считает средний итог (с байтами и штрафами).
/// Новичок торгуется «на глаз» — по простой оценке руки, как человек.
///
/// Розыгрыш: для каждой допустимой карты моделирует доигрывание сдачи в случайных
/// мирах, согласованных с тем, что видно на столе; в конце сдачи — точный перебор
/// (вдвоём — альфа-бета). Мастер вдобавок раздаёт миры с учётом торговли соперников,
/// а вдвоём решает каждый мир точно от первой карты до последней (`TwoPlayerSolver`) —
/// и в розыгрыше, и при оценке заявки.
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
        /// Вдвоём решать каждый мир точно до конца сдачи (`TwoPlayerSolver`) — и в розыгрыше,
        /// и в торговле — вместо доигрывания по эвристике.
        public var exactSolver: Bool
        /// Вдвоём (вместе с `exactSolver`) «читать» уже сделанные ходы соперника: миры, где его ходы
        /// выглядят разумными, вероятнее. Число — крутизна модели соперника на очко разницы
        /// (0 — не читать). Бот по-прежнему видит только стол: вес мира считается по его догадке.
        public var playInference: Double
        /// Вдвоём (вместе с `exactSolver`) сравнивать заявку не с постоянным порогом, а с ценой
        /// паса: что потом скажет соперник и что останется самому (`auctionBid`).
        public var auctionModel: Bool
        /// «Чутьё» (`BeliefNet`): миры, в которых карты лежат так, как подсказывает сеть по торговле
        /// и ходам, вероятнее. Число — насколько доверять сети (0 — не использовать).
        public var belief: Double
        /// Втроём оценивать ход сетью (`ValueNet`) вместо доигрывания сдачи по простым правилам.
        public var valueNet: Bool
        /// Втроём оценивать заявку той же сетью (с первого хода) вместо доигрывания.
        public var valueBid: Bool

        public init(biddingSamples: Int, takeThreshold: Double, nameThreshold: Double,
                    feelShift: Double = 0, feelNoise: Double = 0, forcedAware: Bool, exchange: ExchangeMode,
                    playSamples: Int, exactTwoPlayers: Int, exactThreePlayers: Int, inferFromBidding: Bool,
                    inferInBidding: Bool = false, memoryTricks: Int? = nil, slipPercent: Int = 0,
                    rolloutExact: Int = 0, tieMargin: Double = 0, timeBudget: Double? = nil,
                    exactSolver: Bool = false, playInference: Double = 0, auctionModel: Bool = false,
                    belief: Double = 0, valueNet: Bool = false, valueBid: Bool = false) {
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
            self.exactSolver = exactSolver
            self.playInference = playInference
            self.auctionModel = auctionModel
            self.belief = belief
            self.valueNet = valueNet
            self.valueBid = valueBid
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
                           timeBudget: 0.9, exactSolver: true, playInference: 0.15, auctionModel: true)
                #if DEBUG
                // Отладочная сборка в десятки раз медленнее: меньше миров и без чтения ходов,
                // иначе Мастер думает над ходом десятки секунд.
                c.playSamples = 40
                c.biddingSamples = 32
                c.playInference = 0
                #endif
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
        // Без предела времени: сколько миров успеть, зависело бы от загрузки, и совет мог бы меняться.
        config.timeBudget = nil
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
        if config.auctionModel && config.exactSolver && v.playerCount == 2 {
            return auctionBid(v, round: round, rng: &rng)
        }
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

    // MARK: Торговля с ценой паса (вдвоём)

    /// Пороги уровня, от которых отсчитывается сдвиг стиля (см. `Config.preset`).
    static let baseTakeThreshold = 4.0
    static let baseNameThreshold = -5.0

    /// Вдвоём при точном решателе: заявка сравнивается с ценой паса на тех же мирах.
    /// В каждом мире сдача решается точно при каждом козыре — и когда играть возьмусь я, и когда
    /// соперник. Что соперник скажет в ответ, оценивает модель торговли (`BidModel.strong2`)
    /// по его руке в этом мире, его прошлые заявки дают вес миру. Свои будущие решения бот
    /// принимает по тем же мирам. Стиль — запас над ценой паса (у ровного — ноль).
    func auctionBid(_ v: SeatView, round: Int, rng: inout SplitMix64) -> Action {
        let me = v.seat, opp = 1 - v.seat
        let open = v.openCard.suit.rawValue
        let iSpeakFirst = me == v.next(v.dealer)
        let trumps = round == 1 ? Suit.allCases : Suit.allCases.filter { $0.rawValue != open }
        let samples = max(1, config.biddingSamples)
        let net = config.belief > 0 ? BeliefNet.shared : nil
        // С «чутьём» миры уже подобраны под сказанное соперником — вес по модели торговли не нужен.
        let worlds = net != nil ? biddingWorlds(v, count: samples, rng: &rng)
            : (0..<samples).map { _ in WorldSampler.sampleBidding(v, rng: &rng) }
        // [масть][0 — играю я, 1 — играет соперник] — итог сдачи для меня.
        let tables = Bot.solveWorlds(worlds.count, minimum: max(8, samples / 4), budget: config.timeBudget) { solver, i -> [[Double]] in
            var u = [[Double]](repeating: [0, 0], count: 4)
            for t in trumps {
                for (k, bidder) in [me, opp].enumerated() {
                    u[t.rawValue][k] = self.solvedDeal(v, hands6: worlds[i].hands, prikup: worlds[i].prikup,
                                                       trump: t, bidder: bidder, solver: solver)
                }
            }
            return u
        }
        let n = tables.count
        // Соперник в каждом мире: правдоподобие сказанного, «беру» в 1-м круге, «называю» во 2-м и какую.
        let model = BidModel.strong(players: 2)
        let oppFirst = !iSpeakFirst
        var weight = [Double](repeating: 1, count: n), takes = weight, names = weight
        var named = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let h = worlds[i].hands[opp]
            weight[i] = net != nil ? 1 : BidModel.likelihood(bids: v.bids, seat: opp, hand6: h, open: v.openCard,
                                                             dealer: v.dealer, players: 2)
            takes[i] = BidModel.probability(h, trump: open, open: v.openCard, round: 1, leadsFirst: oppFirst,
                                            weights: model)
            var pass = 1.0, top = -1.0
            for s in 0..<4 where s != open {
                let p = BidModel.probability(h, trump: s, open: v.openCard, round: 2, leadsFirst: oppFirst,
                                             weights: model)
                pass *= 1 - p
                if p > top { top = p; named[i] = s }
            }
            names[i] = 1 - pass
        }
        // «Все пас»: пересдача или, при «обязах», сдача втёмную тому, кто говорит первым.
        var redeal = 0.0
        if config.forcedAware, let forced = v.forcedSeatIfAllPass {
            redeal = forced == me ? -0.8 * Bot.forcedPassValue : Bot.forcedPassValue
        }
        func mean(_ value: (Int) -> Double, _ w: (Int) -> Double) -> Double {
            var sum = 0.0, total = 0.0
            for i in 0..<n {
                let x = w(i)
                sum += x * value(i)
                total += x
            }
            return total > 0 ? sum / total : 0
        }
        let takeMargin = config.takeThreshold - Bot.baseTakeThreshold
        let nameMargin = config.nameThreshold - Bot.baseNameThreshold
        let seconds = trumps.filter { $0.rawValue != open }.map(\.rawValue)
        /// Мой выбор во 2-м круге при весах миров `w`: лучшая масть и назвать ли её.
        func secondRound(_ w: (Int) -> Double, last: Bool) -> (name: Bool, suit: Int, pass: (Int) -> Double) {
            var suit = seconds[0], best = -Double.infinity
            for s in seconds {
                let ev = mean({ tables[$0][s][0] }, w)
                if ev > best { best = ev; suit = s }
            }
            // Спасую последним — пересдача; первым — соперник ещё может назвать свою.
            let pass: (Int) -> Double = last
                ? { _ in redeal }
                : { i in names[i] * tables[i][named[i]][1] + (1 - names[i]) * redeal }
            return (best - mean(pass, w) >= nameMargin, suit, pass)
        }
        if round == 1 {
            let take = mean({ tables[$0][open][0] }, { weight[$0] })
            let pass: (Int) -> Double
            if iSpeakFirst {
                // Отвечает сдающий; спасует и он — во 2-м круге я говорю первым.
                let later = secondRound({ weight[$0] * (1 - takes[$0]) }, last: false)
                pass = { i in
                    let mine = later.name ? tables[i][later.suit][0] : later.pass(i)
                    return takes[i] * tables[i][open][1] + (1 - takes[i]) * mine
                }
            } else {
                // Во 2-м круге первым говорит соперник, я — последним.
                let later = secondRound({ weight[$0] * (1 - names[$0]) }, last: true)
                pass = { i in
                    let mine = later.name ? tables[i][later.suit][0] : redeal
                    return names[i] * tables[i][named[i]][1] + (1 - names[i]) * mine
                }
            }
            return take - mean(pass, { weight[$0] }) >= takeMargin ? .take : .pass
        }
        let choice = secondRound({ weight[$0] }, last: !iSpeakFirst)
        return choice.name ? .name(Suit(rawValue: choice.suit)!) : .pass
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
        let worlds = biddingWorlds(v, count: samples, rng: &rng)
        if config.exactSolver && v.playerCount == 2 {
            // Каждый мир решается точно; миры считаются параллельно, сумма — в одном порядке.
            let perWorld = Bot.solveWorlds(worlds.count, minimum: max(8, samples / 4), budget: config.timeBudget) { solver, i in
                trumps.map { self.solvedDeal(v, hands6: worlds[i].hands, prikup: worlds[i].prikup, trump: $0,
                                             bidder: v.seat, solver: solver) }
            }
            for values in perWorld { for i in values.indices { totals[i] += values[i] } }
            return totals.map { $0 / Double(perWorld.count) }
        }
        let net = config.valueBid && v.playerCount == 3 && ValueFeatures.supports(v.rules) ? ValueNet.shared : nil
        for world in worlds {
            for (i, trump) in trumps.enumerated() {
                if let net {
                    totals[i] += valuedDeal(v, hands6: world.hands, prikup: world.prikup, trump: trump, bidder: v.seat, net: net)
                } else {
                    totals[i] += simulateDeal(v, hands6: world.hands, prikup: world.prikup, trump: trump, bidder: v.seat)
                }
            }
        }
        return totals.map { $0 / Double(samples) }
    }

    /// Миры торговли: по «чутью» (если включено), по модели торговли соперников или просто случайные.
    private func biddingWorlds(_ v: SeatView, count: Int, rng: inout SplitMix64) -> [(hands: [UInt32], prikup: [UInt32])] {
        if config.belief > 0, let net = BeliefNet.shared {
            let pool = (0..<(count * 3)).map { _ in WorldSampler.sampleBidding(v, rng: &rng) }
            let logP = net.logProbabilities(v)
            let unknown = BeliefFeatures.unknownMask(v)
            let logs = pool.map { config.belief * WorldSampler.beliefLogWeight(v, logP: logP, unknown: unknown, hands: $0.hands) }
            let top = logs.max() ?? 0
            return WorldSampler.resample(pool, weights: logs.map { exp($0 - top) }, count: count, rng: &rng)
        }
        if config.inferInBidding && v.bids.contains(where: { $0.seat != v.seat }) {
            return WorldSampler.sampleBiddingInformed(v, count: count, rng: &rng)
        }
        return (0..<count).map { _ in WorldSampler.sampleBidding(v, rng: &rng) }
    }

    /// Доигрывание сдачи по правилам в мире торговли, где козырь `trump` назначил `bidder`.
    func simulateDeal(_ v: SeatView, hands6: [UInt32], prikup: [UInt32], trump: Suit, bidder: Int) -> Double {
        let deal = dealHands(v, hands6: hands6, prikup: prikup, trump: trump, bidder: bidder)
        return rollout(v, hands: deal.hands, trump: trump, bidder: bidder, seen: deal.seen, firstLead: deal.firstLead)
    }

    /// Руки после прикупа и обмена семёрки (по быстрому правилу), видимые карты и первый заход.
    private func dealHands(_ v: SeatView, hands6: [UInt32], prikup: [UInt32], trump: Suit,
                           bidder: Int) -> (hands: [UInt32], seen: UInt32, firstLead: Int) {
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
        return (hands, seen, firstLead)
    }

    /// Итог сдачи для `v.seat` в мире торговли при точной игре обоих (только вдвоём).
    private func solvedDeal(_ v: SeatView, hands6: [UInt32], prikup: [UInt32], trump: Suit, bidder: Int,
                            solver: TwoPlayerSolver) -> Double {
        let deal = dealHands(v, hands6: hands6, prikup: prikup, trump: trump, bidder: bidder)
        let order = v.leadOrder(bidder: bidder)
        let decl = Combinations.declarations(hands: deal.hands.map { m in ids(in: m).map { Card(id: $0) } },
                                             trump: trump, rules: v.rules, priority: order)
        let ctx = SimContext(rules: v.rules, playerCount: 2, trump: trump.rawValue, bidder: bidder, priority: order,
                             declarations: decl, pot: v.pot, baitCounts: v.baitCounts, nakedCounts: v.nakedCounts)
        let zeros = [0, 0]
        let bonus = Bot.firstTrickBonus(ctx, tricks: zeros)
        solver.configure(trump: trump.rawValue, rules: v.rules, bonus: bonus)
        let value = solver.value(hands: deal.hands, leader: deal.firstLead, flags: Bot.bonusFlags(bonus))
        var remaining = 0
        for id in ids(in: deal.hands[0] | deal.hands[1]) { remaining += ctx.points[id] }
        return Bot.solvedUtility(ctx, me: v.seat, cardPoints: zeros, tricks: zeros, remainingPoints: remaining,
                                 bonus: bonus, diff: deal.firstLead == v.seat ? value : -value)
    }

    /// Втроём: итог сдачи по сети оценки позиции — с первого хода, после прикупа и обмена семёрки.
    private func valuedDeal(_ v: SeatView, hands6: [UInt32], prikup: [UInt32], trump: Suit, bidder: Int,
                            net: ValueNet) -> Double {
        let deal = dealHands(v, hands6: hands6, prikup: prikup, trump: trump, bidder: bidder)
        let n = v.playerCount
        let order = v.leadOrder(bidder: bidder)
        let decl = Combinations.declarations(hands: deal.hands.map { m in ids(in: m).map { Card(id: $0) } },
                                             trump: trump, rules: v.rules, priority: order)
        let ctx = SimContext(rules: v.rules, playerCount: n, trump: trump.rawValue, bidder: bidder, priority: order,
                             declarations: decl, pot: v.pot, baitCounts: v.baitCounts, nakedCounts: v.nakedCounts)
        let zeros = [Int](repeating: 0, count: n)
        let state = SimState(hands: deal.hands, turn: deal.firstLead, cardPoints: zeros, tricks: zeros, played: deal.seen,
                             tricksLeft: deal.hands[0].nonzeroBitCount, ctx: ctx)
        return net.utility(state, ctx, me: v.seat)
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
        if config.exactSolver && n == 2 && handSize > config.exactTwoPlayers {
            return solvedCard(v, legal: legal, trump: trump, bidder: bidder, table: t, info: info, rng: &rng)
        }
        let alphaBeta = n == 2 && handSize <= config.exactTwoPlayers
        let maxN = n == 3 && handSize <= config.exactThreePlayers
        let valueNet = config.valueNet && n == 3 && ValueFeatures.supports(v.rules) ? ValueNet.shared : nil
        let target = config.playSamples
        let minimum = max(4, target / 4)
        let started = DispatchTime.now().uptimeNanoseconds
        let budget = config.timeBudget.map { UInt64($0 * 1e9) }

        var worlds: [[UInt32]] = []
        if config.inferFromBidding {
            worlds = informedWorlds(v, info: info, count: target, trump: trump, bidder: bidder, rng: &rng)
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
                } else if let valueNet {
                    scores[i] += valueNet.utility(s, ctx, me: v.seat)
                } else {
                    scores[i] += finishRollout(s, ctx, me: v.seat)
                }
            }
        }
        let tolerance = 0.25 + config.tieMargin * Double(done)
        return legal[Bot.naturalPick(legal: legal, scores: scores, trump: trump, tolerance: tolerance)]
    }

    /// Вдвоём: в каждом мире — точное решение до конца сдачи (`TwoPlayerSolver`), миры — параллельно.
    private func solvedCard(_ v: SeatView, legal: [Card], trump: Suit, bidder: Int, table t: Table,
                            info: WorldSampler.PlayInfo, rng: inout SplitMix64) -> Card {
        let count = config.playSamples
        let started = DispatchTime.now().uptimeNanoseconds
        let worlds = config.inferFromBidding
            ? informedWorlds(v, info: info, count: count, trump: trump, bidder: bidder, rng: &rng)
            : (0..<count).map { _ in WorldSampler.samplePlay(info, rng: &rng) }
        let moves = legal.map(\.id)
        let tableCard = t.trick.first?.card
        let minimum = max(4, count / 4)
        // Время, ушедшее на чтение ходов соперника, вычитается из общего предела.
        let budget = config.timeBudget.map { max(0, $0 - Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9) }
        let perWorld = Bot.solveWorlds(worlds.count, minimum: minimum, budget: budget) { solver, i -> [Double] in
            let hands = worlds[i]
            let ctx = self.context(v, trump: trump, bidder: bidder, worldHands: hands)
            let bonus = Bot.firstTrickBonus(ctx, tricks: t.tricks)
            solver.configure(trump: trump.rawValue, rules: v.rules, bonus: bonus)
            var remaining = 0
            for id in ids(in: hands[0] | hands[1]) { remaining += ctx.points[id] }
            for p in t.trick { remaining += ctx.points[p.card] }
            let values = solver.moveValues(hands: hands, me: v.seat, tableCard: tableCard,
                                           flags: Bot.bonusFlags(bonus), moves: moves)
            return values.map {
                Bot.solvedUtility(ctx, me: v.seat, cardPoints: t.cardPoints, tricks: t.tricks,
                                  remainingPoints: remaining, bonus: bonus, diff: $0)
            }
        }
        var scores = [Double](repeating: 0, count: legal.count)
        for values in perWorld { for i in values.indices { scores[i] += values[i] } }
        let tolerance = 0.25 + config.tieMargin * Double(perWorld.count)
        return legal[Bot.naturalPick(legal: legal, scores: scores, trump: trump, tolerance: tolerance)]
    }

    /// Миры с учётом торговли и объявлений, а вдвоём с `playInference` — ещё и того, как соперник
    /// уже сыграл: кандидатов вдвое больше, каждый получает вес «насколько его ходы разумны в этом
    /// мире», затем `count` миров перевыбираются по весам.
    private func informedWorlds(_ v: SeatView, info: WorldSampler.PlayInfo, count: Int, trump: Suit, bidder: Int,
                                rng: inout SplitMix64) -> [[UInt32]] {
        let beta = config.playInference
        let readPlays = beta > 0 && config.exactSolver && v.playerCount == 2
            && (v.tricks + [v.currentTrick]).contains(where: { $0.plays.contains { $0.seat != v.seat } })
        let net = config.belief > 0 ? BeliefNet.shared : nil
        guard readPlays || net != nil else { return WorldSampler.sampleInformed(v, info: info, count: count, rng: &rng) }
        var candidates: (worlds: [[UInt32]], weights: [Double])
        if let net {
            // «Чутьё»: из вчетверо большего числа миров оставляем правдоподобные по сети (она уже
            // учитывает торговлю, поэтому вес по модели торговли не нужен).
            let pool = WorldSampler.informedCandidates(v, info: info, trump: trump, count: count * 4,
                                                       biddingWeights: false, rng: &rng)
            let logP = net.logProbabilities(v)
            let unknown = BeliefFeatures.unknownMask(v)
            let logs = pool.worlds.map { config.belief * WorldSampler.beliefLogWeight(v, logP: logP, unknown: unknown, hands: $0) }
            let top = logs.max() ?? 0
            let kept = WorldSampler.resample(pool.worlds, weights: logs.map { exp($0 - top) },
                                             count: readPlays ? count * 2 : count, rng: &rng)
            guard readPlays else { return kept }
            candidates = (kept, [Double](repeating: 1, count: kept.count))
        } else {
            candidates = WorldSampler.informedCandidates(v, info: info, trump: trump, count: count * 2, rng: &rng)
        }
        // На чтение — не больше трети предела; не успели — берём тех кандидатов, что успели оценить
        // (но не меньше четверти от нужного числа миров — остальные повторятся при перевыборе).
        let logs = Bot.solveWorlds(candidates.worlds.count, minimum: max(8, count / 4),
                                   budget: config.timeBudget.map { $0 / 3 }) { solver, i in
            self.playLogLikelihood(v, info: info, world: candidates.worlds[i], trump: trump, bidder: bidder,
                                   beta: beta, solver: solver)
        }
        let worlds = Array(candidates.worlds.prefix(logs.count))
        // Веса — относительно самого правдоподобного кандидата, чтобы произведения не обнулились.
        let top = logs.max() ?? 0
        let weights = logs.indices.map { candidates.weights[$0] * exp(logs[$0] - top) }
        return WorldSampler.resample(worlds, weights: weights, count: count, rng: &rng)
    }

    /// Вдвоём: логарифм правдоподобия уже сделанных ходов соперника в мире `world`. Модель
    /// соперника — «мягкий максимум» по точным оценкам ходов: ход тем вероятнее, чем меньше он
    /// теряет против лучшего (`beta` — крутизна на очко). Вынужденные ходы ничего не говорят.
    private func playLogLikelihood(_ v: SeatView, info: WorldSampler.PlayInfo, world: [UInt32], trump: Suit,
                                   bidder: Int, beta: Double, solver: TwoPlayerSolver) -> Double {
        var hands = WorldSampler.startHands(info, world: world)
        let ctx = context(v, trump: trump, bidder: bidder, worldHands: hands)
        var tricks = [0, 0]
        var logL = 0.0
        for trick in v.tricks + [v.currentTrick] {
            var tableCard: Int? = nil
            for p in trick.plays {
                let card = p.card.id
                if p.seat != v.seat {
                    let bonus = Bot.firstTrickBonus(ctx, tricks: tricks)
                    solver.configure(trump: trump.rawValue, rules: v.rules, bonus: bonus)
                    let legal = solver.legalMoves(hands[p.seat], tableCard: tableCard)
                    if legal & bit(card) != 0 && legal.nonzeroBitCount > 1 {
                        let moves = ids(in: legal)
                        let values = solver.moveValues(hands: hands, me: p.seat, tableCard: tableCard,
                                                       flags: Bot.bonusFlags(bonus), moves: moves)
                        let top = Double(values.max()!)
                        var sum = 0.0
                        var chosen = 0.0
                        for (m, value) in zip(moves, values) {
                            let e = beta * (Double(value) - top)
                            sum += exp(e)
                            if m == card { chosen = e }
                        }
                        logL += chosen - log(sum)
                    }
                }
                hands[p.seat] &= ~bit(card)
                tableCard = tableCard == nil ? card : nil
            }
            if let w = trick.winner, trick.plays.count == 2 { tricks[w] += 1 }
        }
        return logL
    }

    /// Прибавка за первую взятку вдвоём: комбинации и бэла, которые по правилу «нужна взятка»
    /// ещё не засчитаны, потому что у владельца пока нет ни одной взятки.
    static func firstTrickBonus(_ ctx: SimContext, tricks: [Int]) -> [Int] {
        var bonus = [0, 0]
        for s in 0..<2 where tricks[s] == 0 {
            if ctx.meldWinner == s && ctx.rules.combosNeedTrick == .all { bonus[s] += ctx.meldPoints }
            if ctx.bellaSeat == s && ctx.rules.combosNeedTrick != .none { bonus[s] += ctx.rules.bellaPoints }
        }
        return bonus
    }

    /// Флаги решателя: бит игрока — «прибавки за первую взятку у него нет».
    static func bonusFlags(_ bonus: [Int]) -> Int {
        (bonus[0] == 0 ? 1 : 0) | (bonus[1] == 0 ? 2 : 0)
    }

    /// Итог сдачи для `me` вдвоём по точной будущей разнице «сырых» очков `diff`.
    /// Будущая сумма известна: оставшиеся карты, +10 за последнюю взятку и отложенные прибавки
    /// (считаем их полученными — владелец почти всегда берёт хоть одну взятку). Счёт идёт
    /// обычным `settlementChange` — с байтом, висячими, банком и штрафами.
    static func solvedUtility(_ ctx: SimContext, me: Int, cardPoints: [Int], tricks: [Int],
                              remainingPoints: Int, bonus: [Int], diff: Int) -> Double {
        let rules = ctx.rules
        var raw = cardPoints.map(Double.init)
        let w = ctx.meldWinner
        if w >= 0, rules.combosNeedTrick != .all || tricks[w] > 0 { raw[w] += Double(ctx.meldPoints) }
        let b = ctx.bellaSeat
        if b >= 0, rules.combosNeedTrick == .none || tricks[b] > 0 { raw[b] += Double(rules.bellaPoints) }
        let total = Double(remainingPoints + 10 + bonus[0] + bonus[1])
        raw[me] += (total + Double(diff)) / 2
        raw[1 - me] += (total - Double(diff)) / 2
        let plain = SimContext(rules: rules, playerCount: 2, trump: ctx.trump, bidder: ctx.bidder,
                               priority: ctx.priority, meldWinner: -1, meldPoints: 0, bellaSeat: -1,
                               pot: ctx.pot, baitCounts: ctx.baitCounts, nakedCounts: ctx.nakedCounts)
        let final = SimState(hands: [0, 0], turn: 0, cardPoints: raw.map { Int($0.rounded()) },
                             tricks: tricks.map { max($0, 1) }, played: 0, tricksLeft: 0, ctx: plain)
        return final.utility(plain, for: me)
    }

    /// Решить `count` миров параллельно (у каждого потока свой решатель) партиями, пока не выйдет
    /// время `budget` — но не меньше `minimum` миров. Результаты — по индексу мира, поэтому сумма
    /// не зависит от того, какой поток что успел.
    static func solveWorlds<T>(_ count: Int, minimum: Int, budget: Double?,
                               _ body: (TwoPlayerSolver, Int) -> T) -> [T] {
        guard count > 0 else { return [] }
        let threads = min(count, max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))
        let solvers = (0..<threads).map { _ in TwoPlayerSolver() }
        let started = DispatchTime.now().uptimeNanoseconds
        let limit = budget.map { UInt64($0 * 1e9) }
        var results: [T] = []
        results.reserveCapacity(count)
        let lock = NSLock()
        while results.count < count {
            let first = results.count
            let size = min(count - first, threads * 4)
            var batch = [T?](repeating: nil, count: size)
            DispatchQueue.concurrentPerform(iterations: threads) { t in
                var local: [(Int, T)] = []
                var i = t
                while i < size {
                    local.append((i, body(solvers[t], first + i)))
                    i += threads
                }
                lock.lock()
                for (index, value) in local { batch[index] = value }
                lock.unlock()
            }
            results += batch.map { $0! }
            if let limit, results.count >= minimum, DispatchTime.now().uptimeNanoseconds - started > limit { break }
        }
        return results
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
