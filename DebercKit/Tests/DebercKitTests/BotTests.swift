import XCTest
@testable import DebercKit

/// Прогоняет партию, где за всех играют боты указанных уровней.
@discardableResult
func playBotMatch(levels: [BotLevel], seed: UInt64, rules: RuleSet = .house) throws -> Match {
    try playBotMatch(bots: levels.map { Bot(level: $0) }, seed: seed, rules: rules)
}

@discardableResult
func playBotMatch(bots: [Bot], seed: UInt64, rules: RuleSet = .house, maxDeals: Int = .max) throws -> Match {
    let names = Array(["A", "B", "C"].prefix(bots.count))
    var match = Match(playerCount: bots.count, names: names, rules: rules, seed: seed)
    var rng = SplitMix64(seed: seed &+ 99)
    var steps = 0
    while !match.isOver {
        steps += 1
        if steps > 50_000 { XCTFail("Партия не заканчивается"); break }
        if match.needsNewDeal {
            if match.dealCount >= maxDeals { break }
            match.startNextDeal()
            continue
        }
        guard let actor = match.actor else { break }
        let action = bots[actor].chooseAction(match: match, seat: actor, rng: &rng)
        XCTAssertTrue(match.deal!.legalActions().contains(action) || action == .exchangeSeven(false),
                      "Недопустимое действие \(action)")
        try match.apply(action)
    }
    return match
}

/// Колода, в которой ни у кого нет четырёх семёрок (для сдач с «все пас»).
private func calmDeck(dealer: Int, seed: UInt64) -> [Card] {
    var rng = SplitMix64(seed: seed)
    while true {
        var deck = Card.deck
        deck.shuffle(using: &rng)
        let sevens = deck.prefix(12).filter { $0.rank == .seven }.count
        if sevens < 4 { return deck }
    }
}

final class BotTests: XCTestCase {

    // MARK: - Партии целиком

    func testBotsFinishTwoPlayerMatches() throws {
        for seed in 0..<3 {
            let match = try playBotMatch(levels: [.novice, .amateur], seed: UInt64(seed))
            XCTAssertNotNil(match.winner)
        }
    }

    func testBotsFinishThreePlayerMatches() throws {
        for seed in 0..<2 {
            let match = try playBotMatch(levels: [.novice, .amateur, .novice], seed: UInt64(100 + seed))
            XCTAssertNotNil(match.winner)
        }
    }

    func testStrongLevelsPlayLegally() throws {
        for (players, seed) in [(2, 3), (3, 4)] {
            let bots = [Bot(level: .master), Bot(level: .expert), Bot(level: .master, style: .bold)].prefix(players)
            let match = try playBotMatch(bots: Array(bots), seed: UInt64(seed), maxDeals: 2)
            XCTAssertGreaterThanOrEqual(match.dealCount, 1)
        }
    }

    // MARK: - Уровни, стили, персонажи

    func testLevelsAreOrderedAndNamed() {
        XCTAssertEqual(BotLevel.allCases, [.novice, .amateur, .expert, .master])
        XCTAssertEqual(BotLevel.allCases.map(\.title), ["Новичок", "Любитель", "Знаток", "Мастер"])
        XCTAssertTrue(BotLevel.novice < .amateur && .amateur < .expert && .expert < .master)
        XCTAssertEqual(BotLevel.allCases.max(), .master)
        for level in BotLevel.allCases { XCTAssertFalse(level.subtitle.isEmpty) }
        XCTAssertEqual(BotStyle.allCases.map(\.title), ["Осторожный", "Ровный", "Рисковый"])
    }

    func testLegacyLevelsDecode() throws {
        let decoder = JSONDecoder()
        func level(_ json: String) throws -> BotLevel { try decoder.decode(BotLevel.self, from: Data(json.utf8)) }
        XCTAssertEqual(try level("\"easy\""), .novice)
        XCTAssertEqual(try level("\"medium\""), .amateur)
        XCTAssertEqual(try level("\"hard\""), .expert)
        XCTAssertEqual(try level("\"master\""), .master)
        XCTAssertEqual(try level("\"что-то новое\""), .amateur)
        XCTAssertEqual(try level("42"), .amateur)
        let encoded = try JSONEncoder().encode([BotLevel.expert])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "[\"expert\"]")
        XCTAssertEqual(try decoder.decode(BotStyle.self, from: Data("\"reckless\"".utf8)), .balanced)
        XCTAssertEqual(BotLevel(tolerant: "hard"), .expert)
    }

    func testPersonas() throws {
        let all = Persona.all
        XCTAssertEqual(all.count, 8)
        XCTAssertEqual(Set(all.map(\.id)).count, 8)
        XCTAssertEqual(Set(all.map(\.name)).count, 8)
        XCTAssertEqual(Set(all.map(\.tint)), Set(0..<8))
        XCTAssertEqual(Set(all.map(\.style)), Set(BotStyle.allCases))
        for level in BotLevel.allCases {
            let pair = all.filter { $0.level == level }
            XCTAssertEqual(pair.count, 2, "\(level)")
            XCTAssertNotEqual(pair[0].style, pair[1].style, "\(level): у пары должна быть разная манера")
        }
        for p in all {
            XCTAssertEqual(p.avatar.count, 1, "\(p.name): аватар — один эмодзи")
            XCTAssertFalse(p.bio.isEmpty)
            XCTAssertLessThanOrEqual(p.name.count, 8)
            XCTAssertFalse(p.bio.contains("(а)"))
            XCTAssertEqual(Persona.byID(p.id), p)
        }
        XCTAssertNil(Persona.byID("нет такого"))

        for level in BotLevel.allCases {
            let one = Persona.defaults(level: level, count: 1)
            XCTAssertEqual(one.count, 1)
            XCTAssertEqual(one[0].level, level)
            let two = Persona.defaults(level: level, count: 2)
            XCTAssertEqual(two.map(\.level), [level, level])
            XCTAssertEqual(Set(two.map(\.id)).count, 2)
            XCTAssertEqual(Persona.defaults(level: level, count: 3).count, 3)
        }

        // Терпимое чтение: сохранён только id.
        let decoded = try JSONDecoder().decode(Persona.self, from: Data("{\"id\":\"boris\"}".utf8))
        XCTAssertEqual(decoded, Persona.byID("boris"))
        let roundTrip = try JSONDecoder().decode(Persona.self, from: JSONEncoder().encode(Persona.all[3]))
        XCTAssertEqual(roundTrip, Persona.all[3])
    }

    func testPersonaPhrases() {
        for p in Persona.all {
            for suit in Suit.allCases {
                let take = p.phrase(for: Bid(seat: 1, round: 1, kind: .take, suit: suit))
                let name = p.phrase(for: Bid(seat: 1, round: 2, kind: .name, suit: suit))
                let forced = p.phrase(for: Bid(seat: 1, round: 1, kind: .forced, suit: suit))
                for text in [take, name, forced] {
                    XCTAssertTrue(text.contains(suit.symbol), "\(p.name): «\(text)» без масти")
                }
            }
            for round in 1...2 {
                let pass = p.phrase(for: Bid(seat: 2, round: round, kind: .pass, suit: nil))
                XCTAssertFalse(pass.isEmpty)
                XCTAssertTrue(pass.lowercased().contains("пас") || pass.count <= 16, pass)
            }
            // Одна и та же заявка — одна и та же фраза.
            let bid = Bid(seat: 1, round: 1, kind: .take, suit: .hearts)
            XCTAssertEqual(p.phrase(for: bid), p.phrase(for: bid))
            // Варианты действительно бывают разные.
            let variants = Set((0..<12).map { p.phrase(for: bid, variant: $0) })
            XCTAssertGreaterThan(variants.count, 1, p.name)
        }
    }

    // MARK: - Торговля

    /// Сильная рука на открытую масть — бот берёт; слабая — пасует.
    func testBiddingJudgement() throws {
        let strong = [Card(.jack, .hearts), Card(.nine, .hearts), Card(.ace, .hearts),
                      Card(.ten, .hearts), Card(.ace, .spades), Card(.ace, .clubs)]
        let weak = [Card(.seven, .spades), Card(.eight, .clubs), Card(.nine, .diamonds),
                    Card(.eight, .spades), Card(.seven, .clubs), Card(.queen, .diamonds)]
        let used = Set(strong + weak + [Card(.king, .hearts)])
        var rest = Card.deck.filter { !used.contains($0) }
        var shuffleRng = SplitMix64(seed: 5)
        rest.shuffle(using: &shuffleRng)
        // Сдаёт 0-й, первым говорит 1-й (у него сильная рука), у 0-го — слабая.
        var deck: [Card] = []
        deck += strong[0..<3]; deck += weak[0..<3]
        deck += strong[3..<6]; deck += weak[3..<6]
        deck.append(Card(.king, .hearts))
        deck += rest
        var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        match.startDeal(deck: deck, dealer: 0)

        var deck2: [Card] = []
        deck2 += weak[0..<3]; deck2 += strong[0..<3]
        deck2 += weak[3..<6]; deck2 += strong[3..<6]
        deck2.append(Card(.king, .hearts))
        deck2 += rest
        var match2 = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        match2.startDeal(deck: deck2, dealer: 0)
        XCTAssertEqual(Set(match2.deal!.hands[1]), Set(weak))

        var rng = SplitMix64(seed: 2)
        for level in BotLevel.allCases {
            for style in BotStyle.allCases {
                let bot = Bot(level: level, style: style)
                XCTAssertEqual(match.actor, 1)
                XCTAssertEqual(bot.chooseAction(match: match, seat: 1, rng: &rng), .take, "\(level) \(style)")
                XCTAssertEqual(bot.chooseAction(match: match2, seat: 1, rng: &rng), .pass, "\(level) \(style)")
            }
        }
    }

    /// В одной и той же ситуации бот торгуется одинаково (зерно торговли — от позиции).
    func testBiddingIsConsistent() {
        var match = Match(playerCount: 3, names: ["A", "B", "C"], rules: .house, seed: 21)
        match.startNextDeal()
        guard let actor = match.actor else { return XCTFail() }
        for level in BotLevel.allCases {
            let bot = Bot(level: level)
            var r1 = SplitMix64(seed: 1), r2 = SplitMix64(seed: 999)
            XCTAssertEqual(bot.chooseAction(match: match, seat: actor, rng: &r1),
                           bot.chooseAction(match: match, seat: actor, rng: &r2), "\(level)")
        }
    }

    /// Рисковый берёт игру чаще ровного, ровный — чаще осторожного.
    func testStylesShiftBidding() {
        var takes: [BotStyle: Int] = [:]
        for seed in 0..<40 {
            var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: UInt64(300 + seed))
            match.startNextDeal()
            guard let actor = match.actor, case .bidding(1) = match.deal!.phase else { continue }
            for style in BotStyle.allCases {
                var rng = SplitMix64(seed: 1)
                let config = Bot.Config.preset(.amateur, style: style)
                if Bot(config: config, level: .amateur, style: style).chooseAction(match: match, seat: actor, rng: &rng) == .take {
                    takes[style, default: 0] += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(takes[.bold, default: 0], takes[.balanced, default: 0])
        XCTAssertGreaterThanOrEqual(takes[.balanced, default: 0], takes[.cautious, default: 0])
        XCTAssertGreaterThan(takes[.bold, default: 0], takes[.cautious, default: 0])
    }

    /// Вдвоём перед «обязами» пасовать выгодно тому, кому после «все пас» играть не придётся,
    /// и дорого тому, кому обязы достанутся. По домашним правилам на обязах играет следующий
    /// после сдающего: следующую сдачу сдаёт соперник, значит, играть будет нынешний сдающий.
    /// При правиле «играет сдающий» — наоборот (так было до настройки).
    func testForcedDealAwareness() throws {
        let expert = Bot(level: .expert)
        // [правило: (кто играет на обязах, сдвиг первого говорящего, сдвиг сдающего)]
        let expected: [RuleSet.ForcedPlayer: (seat: Int, first: Double, dealer: Double)] = [
            .afterDealer: (0, Bot.forcedPassValue, -0.8 * Bot.forcedPassValue),
            .dealer: (1, -0.8 * Bot.forcedPassValue, Bot.forcedPassValue),
        ]
        for player in RuleSet.ForcedPlayer.allCases {
            let want = try XCTUnwrap(expected[player])
            var rules = RuleSet.house
            rules.forcedPlayer = player
            var match = Match(playerCount: 2, names: ["A", "B"], rules: rules, seed: 1)
            match.startDeal(deck: calmDeck(dealer: 0, seed: 11), dealer: 0)
            for _ in 0..<4 { try match.apply(.pass) }
            XCTAssertEqual(match.allPassStreak, 1)
            match.startDeal(deck: calmDeck(dealer: 0, seed: 12), dealer: 0)
            try match.apply(.pass)   // 1-й круг, место 1
            try match.apply(.pass)   // 1-й круг, сдающий
            let first = SeatView(match: match, seat: 1)
            XCTAssertEqual(first.phase, .bidding(round: 2))
            XCTAssertEqual(first.allPassStreak, 1)
            XCTAssertEqual(first.forcedSeatIfAllPass, want.seat, "\(player)")
            XCTAssertEqual(expert.forcedShift(first), want.first, "\(player)")
            XCTAssertEqual(Bot(level: .novice).forcedShift(first), 0)
            try match.apply(.pass)   // 2-й круг, место 1
            let dealer = SeatView(match: match, seat: 0)
            XCTAssertEqual(dealer.forcedSeatIfAllPass, want.seat)
            XCTAssertEqual(expert.forcedShift(dealer), want.dealer, "\(player)")
            // Спасует и сдающий — обязы и правда у того, на кого рассчитывали боты.
            try match.apply(.pass)
            match.startNextDeal()
            let forced = try XCTUnwrap(match.deal)
            XCTAssertTrue(forced.forced)
            if forced.fourSevensSeat == nil || forced.bidder != nil {
                XCTAssertEqual(forced.bidder, want.seat, "\(player)")
            }

            // Без серии «все пас» порог обычный.
            var calm = Match(playerCount: 2, names: ["A", "B"], rules: rules, seed: 1)
            calm.startDeal(deck: calmDeck(dealer: 0, seed: 12), dealer: 0)
            try calm.apply(.pass)
            try calm.apply(.pass)
            let view = SeatView(match: calm, seat: 1)
            XCTAssertNil(view.forcedSeatIfAllPass)
            XCTAssertEqual(expert.forcedShift(view), 0)

            // Втроём сдвиг не применяется; сдаст место 1, играть будет место 2 (или сам сдающий).
            var three = Match(playerCount: 3, names: ["A", "B", "C"], rules: rules, seed: 1)
            three.startDeal(deck: calmDeck(dealer: 0, seed: 13), dealer: 0)
            for _ in 0..<6 { try three.apply(.pass) }
            three.startDeal(deck: calmDeck(dealer: 0, seed: 14), dealer: 0)
            for _ in 0..<3 { try three.apply(.pass) }
            let v3 = SeatView(match: three, seat: 1)
            XCTAssertEqual(v3.forcedSeatIfAllPass, player == .afterDealer ? 2 : 1)
            XCTAssertEqual(expert.forcedShift(v3), 0)
        }
    }

    // MARK: - Обмен семёрки

    func testSevenExchangeKeepsMeld() {
        let hand = mask(of: cards("7ч 8ч 9ч Тп 10т 8б Дп 7т Кб"))
        let rules = RuleSet.house
        // Терц 7-8-9 дороже короля.
        XCTAssertFalse(Bot.exchangeByRule(hand: hand, open: c("Кч"), trump: .hearts, rules: rules))
        XCTAssertFalse(Bot.exchangeByRule(hand: hand, open: c("Тч"), trump: .hearts, rules: rules))
        // Валет и девятку козырей берут всегда.
        XCTAssertTrue(Bot.exchangeByRule(hand: hand, open: c("Вч"), trump: .hearts, rules: rules))
        // Без комбинации — меняем на что угодно.
        let plain = mask(of: cards("7ч 10п Тп 10т 8б Дп 7т Кб 9т"))
        XCTAssertTrue(Bot.exchangeByRule(hand: plain, open: c("Дч"), trump: .hearts, rules: rules))
        // 10 открыта, а на руке 7-8-9: после обмена 8-9-10 — терц остаётся, плюс 10 очков.
        XCTAssertTrue(Bot.exchangeByRule(hand: hand, open: c("10ч"), trump: .hearts, rules: rules))
    }

    func testBotKeepsSevenWhenExchangeBreaksTerz() throws {
        // Сдающий 0, играющий 1 берёт черви; у 1-го 7-8-9 червей, открыт король червей.
        let h1 = cards("7ч 8ч 9ч Тп Тт 10п")
        let h0 = cards("8п 9п 7б 8б 9б Дт")
        let deck = arrangedDeck(dealer: 0, hands: [h0, h1], open: c("Кч"),
                                prikup: [cards("Вп Дп Кп"), cards("10т Вт Кт")])
        var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        match.startDeal(deck: deck, dealer: 0)
        try match.apply(.take)
        XCTAssertEqual(match.deal!.phase, .exchange)
        var rng = SplitMix64(seed: 3)
        XCTAssertEqual(Bot(level: .amateur).chooseAction(match: match, seat: 1, rng: &rng), .exchangeSeven(false))
        XCTAssertEqual(Bot(level: .master).chooseAction(match: match, seat: 1, rng: &rng), .exchangeSeven(false))
        XCTAssertEqual(Bot.hint(match: match, seat: 1), .exchangeSeven(false))
        // Новичок меняет «на автомате».
        XCTAssertEqual(Bot(level: .novice).chooseAction(match: match, seat: 1, rng: &rng), .exchangeSeven(true))
    }

    // MARK: - Розыгрыш

    /// При равных оценках бот кладёт дешёвую карту, а не туза.
    func testTiesPreferCheapCard() {
        let legal = [c("Тп"), c("7п")]
        XCTAssertEqual(Bot.naturalPick(legal: legal, scores: [-100, -100], trump: .hearts), 1)
        XCTAssertEqual(Bot.naturalPick(legal: [c("10ч"), c("7ч")], scores: [5, 5], trump: .hearts), 1)
        // Настоящее преимущество не перебивается.
        XCTAssertEqual(Bot.naturalPick(legal: legal, scores: [-99.5, -100], trump: .hearts), 0)
        // Козырь — в последнюю очередь.
        XCTAssertEqual(Bot.naturalPick(legal: [c("7ч"), c("Кп")], scores: [0, 0], trump: .hearts), 1)
    }

    /// Новичок ошибается по-человечески, но не «дарит» тузы и десятки в чужую взятку.
    func testNoviceDoesNotGiftHighCards() throws {
        var gifts = 0, decisions = 0
        for seed in 0..<6 {
            var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: UInt64(500 + seed))
            var rng = SplitMix64(seed: UInt64(seed))
            let bot = Bot(level: .novice)
            while !match.isOver && match.dealCount < 12 {
                if match.needsNewDeal { match.startNextDeal(); continue }
                guard let actor = match.actor, let deal = match.deal else { break }
                let action = bot.chooseAction(match: match, seat: actor, rng: &rng)
                if case .playing = deal.phase, let trump = deal.trump, deal.currentTrick.plays.count == 1,
                   case .play(let card) = action {
                    let legal = deal.legalCards(for: actor)
                    let led = deal.currentTrick.cards[0]
                    let wins = PlayRules.beats(card, led, led: led.suit, trump: trump)
                    let cheap = legal.contains { $0.points(trump: trump) == 0 && !PlayRules.beats($0, led, led: led.suit, trump: trump) }
                    decisions += 1
                    if !wins && card.points(trump: trump) >= 10 && cheap { gifts += 1 }
                }
                try match.apply(action)
            }
        }
        XCTAssertGreaterThan(decisions, 50)
        XCTAssertEqual(gifts, 0)
    }

    // MARK: - Совет

    func testHintIsDeterministic() throws {
        var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 42)
        match.startNextDeal()
        var rng = SplitMix64(seed: 5)
        let bots = [Bot(level: .amateur), Bot(level: .amateur)]
        var checked = 0
        while let actor = match.actor, checked < 8 {
            let other = (actor + 1) % 2
            XCTAssertNil(Bot.hint(match: match, seat: other))
            let first = Bot.hint(match: match, seat: actor)
            let second = Bot.hint(match: match, seat: actor)
            XCTAssertNotNil(first)
            XCTAssertEqual(first, second)
            if let first { XCTAssertTrue(match.deal!.legalActions().contains(first)) }
            checked += 1
            try match.apply(bots[actor].chooseAction(match: match, seat: actor, rng: &rng))
            if match.needsNewDeal { match.startNextDeal() }
        }
        XCTAssertEqual(checked, 8)
    }

    // MARK: - Бот видит только своё

    /// Бот без предела времени (и Мастер с меньшим числом миров, чтобы отладочная сборка
    /// не считала долго): сколько миров решено, не зависит от загрузки машины.
    private func timeless(_ level: BotLevel) -> Bot {
        var config = Bot.Config.preset(level)
        config.timeBudget = nil
        if level == .master {
            config.playSamples = 40
            config.biddingSamples = 32
        }
        return Bot(config: config, level: level)
    }

    /// Две раздачи с разными чужими картами, но одинаковым видом со своего места,
    /// дают одинаковые решения.
    func testBotDecidesOnlyFromSeatView() throws {
        let mine = cards("Вч 9ч Тп 10т 8б Дп")
        let deckA = arrangedDeck(dealer: 0, hands: [cards("7п 8п 9п Кт Дт Вт"), mine], open: c("Кч"),
                                 prikup: [cards("7б 9б 10б"), cards("Вб Дб Кб")])
        let deckB = arrangedDeck(dealer: 0, hands: [cards("Вб Дб Кб 7б 9б 10б"), mine], open: c("Кч"),
                                 prikup: [cards("7п 8п 9п"), cards("Кт Дт Вт")])
        var a = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        var b = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        a.startDeal(deck: deckA, dealer: 0)
        b.startDeal(deck: deckB, dealer: 0)
        XCTAssertNotEqual(a.deal!.hands[0], b.deal!.hands[0])
        let va = SeatView(match: a, seat: 1), vb = SeatView(match: b, seat: 1)
        XCTAssertEqual(va, vb)
        XCTAssertEqual(va.positionHash, vb.positionHash)
        for level in BotLevel.allCases {
            let bot = timeless(level)
            var r1 = SplitMix64(seed: 7), r2 = SplitMix64(seed: 7), r3 = SplitMix64(seed: 7)
            let fromA = bot.chooseAction(match: a, seat: 1, rng: &r1)
            XCTAssertEqual(fromA, bot.chooseAction(match: b, seat: 1, rng: &r2), "\(level)")
            XCTAssertEqual(fromA, bot.chooseAction(view: va, rng: &r3), "\(level)")
        }
        XCTAssertEqual(Bot.hint(match: a, seat: 1), Bot.hint(match: b, seat: 1))
    }

    /// То же в розыгрыше вдвоём, где Мастер решает каждый мир точно (`TwoPlayerSolver`):
    /// у соперника совсем разные карты, а вид со своего места одинаковый — ход тот же.
    func testSolverPlayDecidesOnlyFromSeatView() throws {
        let mine = cards("Вч 9ч Тп 10т 8б Дп"), myPrikup = cards("7б Вп 7п")
        // Ни у кого нет комбинаций, бэлы и козырной семёрки — объявлений и обмена не будет;
        // нижняя карта колоды (Т♥) одна и та же.
        let deckA = arrangedDeck(dealer: 0, hands: [cards("8п 9п Кт Дт 9б 10б"), mine], open: c("Кч"),
                                 prikup: [cards("8ч 10ч Тб"), myPrikup])
        let deckB = arrangedDeck(dealer: 0, hands: [cards("Кп 10п Вт 9т Кб Дб"), mine], open: c("Кч"),
                                 prikup: [cards("10ч 9б 8т"), myPrikup])
        var a = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        var b = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        a.startDeal(deck: deckA, dealer: 0)
        b.startDeal(deck: deckB, dealer: 0)
        try a.apply(.take)
        try b.apply(.take)
        let va = SeatView(match: a, seat: 1), vb = SeatView(match: b, seat: 1)
        XCTAssertEqual(va.phase, .playing)
        XCTAssertTrue(va.isMyTurn)
        XCTAssertEqual(va.myHand.count, 9)
        XCTAssertNotEqual(a.deal!.hands[0], b.deal!.hands[0])
        XCTAssertEqual(va, vb)
        let bot = timeless(.master)
        XCTAssertTrue(bot.config.exactSolver)
        var r1 = SplitMix64(seed: 7), r2 = SplitMix64(seed: 7)
        XCTAssertEqual(bot.chooseAction(match: a, seat: 1, rng: &r1), bot.chooseAction(match: b, seat: 1, rng: &r2))
        XCTAssertEqual(Bot.hint(match: a, seat: 1), Bot.hint(match: b, seat: 1))

        // Соперник ответил (у A он выбирал из двух козырей, у B ход был вынужден) — Мастер «читает»
        // его ход, но тоже только по столу: решение одно и то же.
        for card in ["9ч", "10ч"] {
            try a.apply(.play(c(card)))
            try b.apply(.play(c(card)))
        }
        let wa = SeatView(match: a, seat: 1), wb = SeatView(match: b, seat: 1)
        XCTAssertTrue(wa.isMyTurn)
        XCTAssertEqual(wa.myHand.count, 8)
        XCTAssertEqual(wa, wb)
        var config = timeless(.master).config
        config.playInference = max(config.playInference, 0.15)
        let reader = Bot(config: config, level: .master)
        var r3 = SplitMix64(seed: 9), r4 = SplitMix64(seed: 9)
        XCTAssertEqual(reader.chooseAction(match: a, seat: 1, rng: &r3), reader.chooseAction(match: b, seat: 1, rng: &r4))
    }

    func testPositionHashIgnoresHandOrder() throws {
        var match = Match(playerCount: 3, names: ["A", "B", "C"], rules: .house, seed: 8)
        match.startNextDeal()
        let v = SeatView(match: match, seat: 1)
        XCTAssertEqual(v.positionHash, SeatView(match: match, seat: 1).positionHash)
        XCTAssertNotEqual(v.positionHash, SeatView(match: match, seat: 2).positionHash)
    }

    /// Бот упорядочивает равные комбинации так же, как ядро: по порядку хода
    /// (при «первый ход — играющий» он отличается от порядка от сдающего).
    func testSeatViewLeadOrderMatchesDeal() throws {
        var rules = RuleSet.house
        rules.firstLead = .bidder
        var checked = 0
        for seed in 0..<12 {
            var match = Match(playerCount: 3, names: ["A", "B", "C"], rules: rules, seed: UInt64(900 + seed))
            var rng = SplitMix64(seed: UInt64(seed))
            let bot = Bot(level: .amateur)
            match.startNextDeal()
            while let deal = match.deal, !deal.isFinished, deal.phase != .playing {
                try match.apply(bot.chooseAction(match: match, seat: deal.turn, rng: &rng))
            }
            guard let deal = match.deal, deal.phase == .playing, let bidder = deal.bidder else { continue }
            for seat in 0..<3 {
                let v = SeatView(match: match, seat: seat)
                XCTAssertEqual(v.leadOrder, deal.leadOrder)
                XCTAssertEqual(v.leadOrder(bidder: bidder), deal.leadOrder)
            }
            XCTAssertEqual(deal.leadOrder.first, deal.turn)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    // MARK: - Время раздумья

    func testDecisionWeight() throws {
        var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 9)
        match.startNextDeal()
        var rng = SplitMix64(seed: 1)
        let bot = Bot(level: .amateur)
        var sawSingle = false
        while let actor = match.actor, !match.needsNewDeal {
            let w = Bot.decisionWeight(match: match, seat: actor)
            XCTAssertTrue((0...1).contains(w))
            XCTAssertEqual(Bot.decisionWeight(match: match, seat: (actor + 1) % 2), 0)
            if match.deal!.phase == .playing && match.deal!.legalCards(for: actor).count == 1 {
                XCTAssertLessThan(w, 0.2)
                sawSingle = true
            }
            try match.apply(bot.chooseAction(match: match, seat: actor, rng: &rng))
        }
        XCTAssertTrue(sawSingle)
    }

    // MARK: - Движок моделирования

    /// Быстрый подсчёт в моделировании совпадает с настоящим `Scoring.settle`.
    func testFastSettlementMatchesScoring() {
        var rng = SplitMix64(seed: 77)
        func r(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        var variants: [RuleSet] = [.house]
        var v = RuleSet.house; v.tieRule = .bait; v.baitRecipient = .splitHalf; variants.append(v)
        v = .house; v.tieRule = .eachKeeps; v.bidderMustBeat = .opponentsCombined; variants.append(v)
        v = .house; v.combosNeedTrick = .none; v.baitTransfer = .burn; v.hangingCountsAsBait = true; variants.append(v)
        v = .house; v.combosNeedTrick = .bellaOnly; v.nakedPenaltyEvery = 0; v.baitPenaltyEvery = 2; variants.append(v)
        for rules in variants {
            for _ in 0..<3000 {
                let n = 2 + r(2)
                let bidder = r(n)
                let dealer = r(n)
                let priority = (1...n).map { (dealer + $0) % n }
                let cardPoints = (0..<n).map { _ in r(4) == 0 ? 0 : r(90) }
                let tricks = cardPoints.map { $0 == 0 && r(2) == 0 ? 0 : 1 + r(4) }
                var melds = [[Meld]](repeating: [], count: n)
                let winner: Int? = r(3) == 0 ? nil : r(n)
                if let winner {
                    melds[winner] = [Meld(suit: .spades, low: .seven, length: 3 + r(3))]
                    if r(3) == 0 { melds[winner].append(Meld(suit: .hearts, low: .ten, length: 3)) }
                }
                let decl = Declarations(melds: melds, meldWinner: winner, bellaSeat: r(3) == 0 ? r(n) : nil)
                let pot = r(3) == 0 ? r(120) : 0
                let bait = (0..<n).map { _ in r(3) }, naked = (0..<n).map { _ in r(2) }
                let reference = Scoring.settle(cardPoints: cardPoints, tricksTaken: tricks, declarations: decl,
                                               bidder: bidder, priority: priority, rules: rules, pot: pot,
                                               baitCounts: bait, nakedCounts: naked)
                let ctx = SimContext(rules: rules, playerCount: n, trump: r(4), bidder: bidder, priority: priority,
                                     declarations: decl, pot: pot, baitCounts: bait, nakedCounts: naked)
                let state = SimState(hands: [UInt32](repeating: 0, count: n), turn: 0, cardPoints: cardPoints,
                                     tricks: tricks, played: 0, tricksLeft: 0, ctx: ctx)
                let fast = state.settlementChange(ctx)
                XCTAssertEqual((0..<n).map { Int(fast[$0]) }, reference.change,
                               "\(rules) cp=\(cardPoints) t=\(tricks) bidder=\(bidder) pot=\(pot)")
            }
        }
    }

    /// Быстрая модель розыгрыша разрешает те же карты, что и правила, при любых «козырять» и «перебивать».
    func testSimulatorLegalMovesMatchRules() {
        var rng = SplitMix64(seed: 77)
        for iteration in 0..<600 {
            var rules = RuleSet.house
            rules.mustTrump = iteration % 2 == 0
            rules.overtrump = RuleSet.Overtrump.allCases[(iteration / 2) % RuleSet.Overtrump.allCases.count]
            var deck = Card.deck
            deck.shuffle(using: &rng)
            let trump = Int(rng.next() % 4)
            let seat = Int(rng.next() % 3)
            let trick = Array(deck[0..<seat])
            let hand = Array(deck[seat..<(seat + 1 + Int(rng.next() % 8))])
            let ctx = SimContext(rules: rules, playerCount: 3, trump: trump, bidder: 0, priority: [1, 2, 0],
                                 meldWinner: -1, meldPoints: 0, bellaSeat: -1,
                                 pot: 0, baitCounts: [0, 0, 0], nakedCounts: [0, 0, 0])
            var hands = [UInt32](repeating: 0, count: 3)
            hands[seat] = mask(of: hand)
            let state = SimState(hands: hands, turn: seat, cardPoints: [0, 0, 0], tricks: [0, 0, 0],
                                 played: mask(of: trick), tricksLeft: hand.count,
                                 trick: trick.enumerated().map { (seat: $0.offset, card: $0.element.id) }, ctx: ctx)
            let want = PlayRules.legalCards(hand: hand, trick: trick, trump: Suit(rawValue: trump)!, rules: rules)
            XCTAssertEqual(state.legalMask(ctx), mask(of: want), "взятка \(trick), рука \(hand), итерация \(iteration)")
        }
    }

    /// Вдвоём альфа-бета даёт то же значение, что полный перебор.
    func testAlphaBetaMatchesFullSearch() throws {
        var checked = 0
        for seed in 0..<12 {
            var match = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: UInt64(700 + seed))
            var rng = SplitMix64(seed: UInt64(seed))
            let bot = Bot(level: .amateur)
            match.startNextDeal()
            while let deal = match.deal, !deal.isFinished, deal.phase != .playing {
                try match.apply(bot.chooseAction(match: match, seat: deal.turn, rng: &rng))
            }
            guard let deal = match.deal, deal.phase == .playing, let trump = deal.trump,
                  let bidder = deal.bidder, let decl = deal.declarations else { continue }
            var d = deal
            var m = match
            // Доиграть случайно до 4 карт на руке.
            while let cur = m.deal, cur.phase == .playing, cur.hands[cur.turn].count > 4 || !cur.currentTrick.plays.isEmpty {
                let legal = cur.legalCards(for: cur.turn)
                try m.apply(.play(legal[Int(rng.next() % UInt64(legal.count))]))
                d = m.deal!
            }
            guard d.phase == .playing else { continue }
            let ctx = SimContext(rules: d.rules, playerCount: 2, trump: trump.rawValue, bidder: bidder,
                                 priority: d.seatsFromDealer, declarations: decl, pot: m.pot,
                                 baitCounts: m.baitCounts, nakedCounts: m.nakedCounts)
            var cp = [0, 0], tr = [0, 0]
            for t in d.tricks {
                cp[t.winner!] += PlayRules.points(of: t.cards, trump: trump)
                tr[t.winner!] += 1
            }
            let state = SimState(hands: d.hands.map { mask(of: $0) }, turn: d.turn, cardPoints: cp, tricks: tr,
                                 played: mask(of: d.playedCards) | bit(d.openCard.id),
                                 tricksLeft: d.hands[d.turn].count, ctx: ctx)
            let full = Search.maxN(state, ctx)
            for me in 0..<2 {
                let ab = Search.alphaBeta(state, ctx, me: me, alpha: -.infinity, beta: .infinity)
                XCTAssertEqual(ab, full[me], accuracy: 1e-9)
            }
            XCTAssertEqual(full[0], -full[1], accuracy: 1e-9)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 5)
    }
}
