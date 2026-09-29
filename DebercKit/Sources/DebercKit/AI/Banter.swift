import Foundation

/// Повод для подначки соперника. Говорит всегда соперник (компьютер).
public enum BanterEvent: String, CaseIterable, Codable, Sendable {
    /// Побил козырем ваш туз или десятку.
    case trumpedHigh
    /// Забрал у вас «жирную» взятку (20 очков и больше).
    case bigTrick
    /// Вы забрали его туз или десятку — ворчит.
    case lostHighCard
    /// Взял игру (назначил козырь).
    case botTakesGame
    /// Игру взяли вы.
    case humanTakesGame
    /// В прошлой сдаче у вас байт.
    case humanBait
    /// В прошлой сдаче байт у него самого.
    case botBait
    /// В прошлой сдаче он сделал игру.
    case botMade
    /// В прошлой сдаче игру сделали вы.
    case humanMade
    /// У вас бэла.
    case humanBella
    /// У него бэла.
    case botBella
    /// Он записал терц или полтинник.
    case botMelds
    /// Вы долго думаете над ходом.
    case longThink
    /// Он далеко впереди по счёту.
    case botLeads
    /// Вы далеко впереди по счёту.
    case humanLeads
    /// Ему немного осталось до победы.
    case nearWin
    /// В прошлой сдаче вы остались без взяток (голый).
    case humanNaked
    /// Все спасовали — пересдача.
    case allPassed

    /// Насколько повод хорош для реплики (0…1): яркие моменты — чаще, будничные — реже.
    public var weight: Double {
        switch self {
        case .longThink, .humanBait, .humanNaked: return 0.85
        case .botBait, .trumpedHigh, .humanMade, .nearWin: return 0.6
        case .humanBella, .lostHighCard: return 0.5
        case .humanTakesGame, .humanLeads, .botMade, .botBella: return 0.4
        case .bigTrick, .botLeads, .botTakesGame, .botMelds, .allPassed: return 0.3
        }
    }
}

/// Как часто соперники подначивают.
public enum BanterLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, rare, normal, often

    public var id: String { rawValue }

    /// «Выключены», «Редко», «Иногда», «Часто».
    public var title: String {
        switch self {
        case .off: return "Выключены"
        case .rare: return "Редко"
        case .normal: return "Иногда"
        case .often: return "Часто"
        }
    }

    /// Во сколько раз реже или чаще, чем «Иногда».
    var factor: Double {
        switch self {
        case .off: return 0
        case .rare: return 0.5
        case .normal: return 1
        case .often: return 1.6
        }
    }

    /// Самое меньшее — столько секунд между репликами (любых соперников).
    public var cooldown: TimeInterval {
        switch self {
        case .off: return .infinity
        case .rare: return 60
        case .normal: return 28
        case .often: return 12
        }
    }
}

/// Подначки соперников: короткие реплики в характере персонажа — весело, без грубости и не часто.
public enum Banter {
    /// Сказать ли что-нибудь. `sinceLast` — секунд с прошлой реплики, `roll` — случайное число 0…1.
    public static func shouldSpeak(_ event: BanterEvent, level: BanterLevel, sinceLast: TimeInterval,
                                   roll: Double) -> Bool {
        guard level != .off, sinceLast >= level.cooldown else { return false }
        return roll < min(0.95, event.weight * level.factor)
    }

    /// Реплика персонажа по поводу (nil — сказать нечего). `variant` выбирает фразу;
    /// `avoid` — недавно сказанное: повторов по возможности нет.
    public static func line(_ event: BanterEvent, persona: Persona, variant: UInt64,
                            avoid: Set<String> = []) -> String? {
        let phrases = phrases(event, style: persona.style)
        guard !phrases.isEmpty else { return nil }
        let rendered = phrases.map { gendered($0, feminine: persona.feminine) }
        let fresh = rendered.filter { !avoid.contains($0) }
        let pool = fresh.isEmpty ? rendered : fresh
        return pool[Int(variant % UInt64(pool.count))]
    }

    /// Все фразы повода для манеры (в исходном виде, с «{взял|взяла}»).
    public static func phrases(_ event: BanterEvent, style: BotStyle) -> [String] {
        BanterBank.phrases[event]?[style] ?? []
    }

    /// «{взял|взяла}» → «взял» или «взяла» — по роду говорящего.
    public static func gendered(_ text: String, feminine: Bool) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                result += rest[open...]
                return result
            }
            let options = rest[rest.index(after: open)..<close].split(separator: "|", omittingEmptySubsequences: false)
            if options.count == 2 {
                result += feminine ? options[1] : options[0]
            } else {
                result += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}

/// Поводы для подначек по ходу игры — чистые функции, чтобы их можно было проверить.
public enum BanterTriggers {
    /// Кто и что скажет о только что собранной взятке (nil — повода нет).
    public static func afterTrick(_ trick: Trick, trump: Suit?, humanSeat: Int) -> (seat: Int, event: BanterEvent)? {
        guard let winner = trick.winner, let trump,
              let human = trick.plays.first(where: { $0.seat == humanSeat }) else { return nil }
        func high(_ card: Card) -> Bool { card.rank == .ace || card.rank == .ten }
        if winner != humanSeat {
            let winning = trick.plays.first { $0.seat == winner }?.card
            if high(human.card), human.card.suit != trump, winning?.suit == trump {
                return (winner, .trumpedHigh)
            }
            if PlayRules.points(of: trick.cards, trump: trump) >= 20 {
                return (winner, .bigTrick)
            }
            return nil
        }
        // Взятка ваша: ворчит тот, чей туз или десятка в неё легли.
        if let loser = trick.plays.first(where: { $0.seat != humanSeat && high($0.card) }) {
            return (loser.seat, .lostHighCard)
        }
        return nil
    }

    /// Что скажут в начале новой сдачи о прошлой и о счёте: один повод, самый яркий.
    /// `bots` — места соперников; `pick` выбирает одного из нескольких.
    public static func atDealStart(_ match: Match, humanSeat: Int, bots: [Int],
                            pick: (Int) -> Int) -> (seat: Int, event: BanterEvent)? {
        guard !bots.isEmpty else { return nil }
        let anyBot = bots[pick(bots.count) % bots.count]
        if let last = match.history.last, last.wasPlayed {
            if last.naked.indices.contains(humanSeat), last.naked[humanSeat] {
                return (anyBot, .humanNaked)
            }
            if let bidder = last.bidder {
                let failed = last.outcome == .bait || last.outcome == .hanging
                if bidder == humanSeat {
                    if failed { return (anyBot, .humanBait) }
                    if last.outcome == .made { return (anyBot, .humanMade) }
                } else if bots.contains(bidder) {
                    if failed { return (bidder, .botBait) }
                    if last.outcome == .made { return (bidder, .botMade) }
                }
            }
        }
        let totals = match.totals
        let target = match.rules.targetScore
        guard totals.indices.contains(humanSeat) else { return nil }
        if let leader = bots.max(by: { totals[$0] < totals[$1] }) {
            if target - totals[leader] <= 100, totals[leader] > totals[humanSeat] {
                return (leader, .nearWin)
            }
            if totals[leader] - totals[humanSeat] >= 150 {
                return (leader, .botLeads)
            }
            if totals[humanSeat] - totals[leader] >= 150 {
                return (anyBot, .humanLeads)
            }
        }
        return nil
    }
}
