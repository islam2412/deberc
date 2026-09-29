import Foundation

/// Русские тексты для событий и итогов — чтобы интерфейс оставался простым.
public enum Narrator {

    /// Имя в начале фразы: «Саша», а для себя — «Вы».
    public static func name(_ seat: Int, names: [String], humanSeat: Int?) -> String {
        seat == humanSeat ? "Вы" : names[seat]
    }

    /// «Вы и Саша», «Саша и Миша».
    static func nameList(_ seats: [Int], names: [String], humanSeat: Int?) -> String {
        seats.map { name($0, names: names, humanSeat: humanSeat) }.joined(separator: " и ")
    }

    // MARK: - Числа

    /// Число с настоящим минусом (U+2212): «47», «−100».
    public static func number(_ n: Int) -> String {
        n < 0 ? "\u{2212}\(n.magnitude)" : "\(n)"
    }

    /// Изменение счёта со знаком: «+47», «−100», «0».
    public static func signed(_ n: Int) -> String {
        n > 0 ? "+\(n)" : number(n)
    }

    /// Очки со склонением: «1 очко», «3 очка», «47 очков», «−100 очков».
    public static func points(_ n: Int) -> String {
        let a = n.magnitude
        let last = a % 10, lastTwo = a % 100
        let word: String
        if (11...14).contains(lastTwo) {
            word = "очков"
        } else if last == 1 {
            word = "очко"
        } else if (2...4).contains(last) {
            word = "очка"
        } else {
            word = "очков"
        }
        return "\(number(n)) \(word)"
    }

    /// «до 701 очка», «до 500 очков».
    public static func pointsGenitive(_ n: Int) -> String {
        let last = n.magnitude % 10, lastTwo = n.magnitude % 100
        return last == 1 && lastTwo != 11 ? "\(n) очка" : "\(n) очков"
    }

    // MARK: - Торговля и объявления

    /// Реплика игрока при торговле.
    public static func bidText(_ bid: Bid) -> String {
        switch bid.kind {
        case .pass: return "Пас"
        case .take: return "Беру \(bid.suit?.symbol ?? "")"
        case .name: return "Играю \(bid.suit?.symbol ?? "")"
        case .forced: return "Обязы \(bid.suit?.symbol ?? "")"
        }
    }

    public static func suitTitle(_ suit: Suit) -> String {
        "\(suit.symbol) \(suit.name)"
    }

    public static func meldTitle(_ meld: Meld, rules: RuleSet) -> String {
        let ranks = meld.cards.map(\.rank.symbol).joined(separator: "-")
        return "\(meld.name(rules)) \(ranks)\(meld.suit.symbol)"
    }

    /// «играете вы» / «играет Саша» — для подписи сдачи.
    public static func bidderPhrase(seat: Int, names: [String], humanSeat: Int?) -> String {
        seat == humanSeat ? "играете вы" : "играет \(names[seat])"
    }

    /// Подпись сдачи: «Сдача 3 · играет Саша ♥ (обязы)». Для пересдач — только номер.
    public static func dealCaption(_ score: DealScore, names: [String], humanSeat: Int?) -> String {
        var text = "Сдача \(score.number)"
        if score.wasPlayed, let bidder = score.bidder, let trump = score.trump {
            text += " · \(bidderPhrase(seat: bidder, names: names, humanSeat: humanSeat)) \(trump.symbol)"
            if score.forced { text += " (обязы)" }
        }
        return text
    }

    // MARK: - События сдачи

    /// Сообщение о событии для всплывающей подсказки (nil — не показывать).
    public static func message(for event: DealEvent, names: [String], humanSeat: Int?, rules: RuleSet) -> String? {
        switch event {
        case .bid:
            return nil
        case .trumpChosen(let seat, let suit, let forced):
            let who = name(seat, names: names, humanSeat: humanSeat)
            let verb = seat == humanSeat ? "играете" : "играет"
            let prefix = forced ? "Обязы: " : ""
            return "\(prefix)\(who) \(verb), козырь \(suitTitle(suit))"
        case .allPassed:
            return "Все спасовали — пересдача"
        case .prikupDealt:
            return nil
        case .fourSevens(let seat):
            let who = name(seat, names: names, humanSeat: humanSeat)
            let bonus = rules.fourSevens == .bonusAndRedeal ? " +\(rules.fourSevensBonus)" : ""
            return "\(who): четыре семёрки!\(bonus) и пересдача"
        case .sevenExchanged(let record):
            let who = name(record.seat, names: names, humanSeat: humanSeat)
            let verb = record.seat == humanSeat ? "забираете" : "забирает"
            return "\(who) \(verb) \(record.took) за козырную семёрку"
        case .sevenKept:
            return nil
        case .playStarted(let decl):
            return meldSummary(decl, names: names, humanSeat: humanSeat, rules: rules)
        case .cardPlayed:
            return nil
        case .bella(let seat):
            return "\(name(seat, names: names, humanSeat: humanSeat)): бэла!"
        case .trickCompleted, .dealFinished:
            return nil
        }
    }

    /// То же, но с учётом состояния партии после события (`match` — уже после хода):
    /// при пересдаче предупреждает, что следующая сдача — на обязах, и кто играет.
    public static func message(for event: DealEvent, in match: Match, humanSeat: Int?) -> String? {
        guard var text = message(for: event, names: match.names, humanSeat: humanSeat, rules: match.rules) else {
            return nil
        }
        switch event {
        case .allPassed, .fourSevens:
            if !match.isOver, match.needsNewDeal, match.nextDealIsForced {
                let dealer = match.upcomingDealer
                text += ". Следующая — на обязах: \(bidderPhrase(seat: dealer, names: match.names, humanSeat: humanSeat))"
            }
        default:
            break
        }
        return text
    }

    /// Кто записывает комбинации перед розыгрышем.
    public static func meldSummary(_ decl: Declarations, names: [String], humanSeat: Int?, rules: RuleSet) -> String? {
        guard let winner = decl.meldWinner else { return nil }
        let who = name(winner, names: names, humanSeat: humanSeat)
        let list = decl.melds[winner].map { meldTitle($0, rules: rules) }.joined(separator: ", ")
        var text = "\(who): \(list)"
        let othersHave = decl.melds.enumerated().contains { $0.offset != winner && !$0.element.isEmpty }
        if othersHave {
            text += " — старше"
        }
        return text
    }

    /// Какие комбинации засчитаны в сдаче: «Саша: полтинник 10-В-Д-К♣ · Вы: бэла».
    /// nil — ничего не засчитано или сохранение старое (нет объявлений).
    public static func meldLine(_ score: DealScore, names: [String], humanSeat: Int?, rules: RuleSet) -> String? {
        guard let decl = score.declarations else { return nil }
        var parts: [(seat: Int, items: [String])] = []
        func add(_ seat: Int, _ item: String) {
            if let i = parts.firstIndex(where: { $0.seat == seat }) {
                parts[i].items.append(item)
            } else {
                parts.append((seat, [item]))
            }
        }
        if let w = decl.meldWinner, score.meldPoints.indices.contains(w), score.meldPoints[w] > 0 {
            for meld in decl.winnerMelds { add(w, meldTitle(meld, rules: rules)) }
        }
        if let b = decl.bellaSeat, score.bellaPoints.indices.contains(b), score.bellaPoints[b] > 0 {
            add(b, "бэла")
        }
        guard !parts.isEmpty else { return nil }
        return parts.map { "\(name($0.seat, names: names, humanSeat: humanSeat)): \($0.items.joined(separator: ", "))" }
            .joined(separator: " · ")
    }

    // MARK: - Итоги сдачи

    /// Заголовок итогов сдачи.
    public static func outcomeTitle(_ score: DealScore, names: [String], humanSeat: Int?) -> String {
        let bidder = score.bidder.map { name($0, names: names, humanSeat: humanSeat) } ?? ""
        switch score.outcome {
        case .made:
            return score.bidder == humanSeat ? "Вы сделали игру" : "Игра сделана: \(bidder)"
        case .bait:
            return score.bidder == humanSeat ? "Байт у вас" : "Байт: \(bidder)"
        case .hanging:
            return score.bidder == humanSeat ? "Висячий байт у вас" : "Висячий байт: \(bidder)"
        case .tie:
            return "Ничья"
        case .allPassed:
            return "Все спасовали — пересдача"
        case .fourSevens:
            let who = score.fourSevensSeat.map { name($0, names: names, humanSeat: humanSeat) } ?? ""
            return "Четыре семёрки: \(who)"
        }
    }

    /// Пояснения к итогам сдачи: куда ушли очки, висячие, сгоревшие комбинации, штрафы
    /// и предупреждения о следующем штрафе, ничья выше цели. Конец партии определяется
    /// по счёту после сдачи (`totalsAfter`) — как в `Match`.
    public static func outcomeNotes(_ score: DealScore, names: [String], humanSeat: Int?, rules: RuleSet) -> [String] {
        var notes: [String] = []
        let n = score.change.count
        func who(_ seat: Int) -> String { name(seat, names: names, humanSeat: humanSeat) }
        let top = score.totalsAfter.max() ?? 0
        let leaders = (0..<n).filter { score.totalsAfter[$0] == top }
        let reachedTarget = top >= rules.targetScore
        let matchOver = reachedTarget && leaders.count == 1
        let potBurnedText = "Висячие очки (\(score.potAfter)) не разыграны — партия окончена, они сгорают"
        let potRule = "их заберёт тот, кто наберёт больше всех в следующей сдаче"

        switch score.outcome {
        case .bait:
            if rules.baitTransfer == .burn {
                notes.append("Очки играющего сгорают")
            } else if let b = score.bidder {
                let receivers = (0..<n).filter { $0 != b && score.written[$0] > score.raw[$0] }
                let amount = score.raw[b]
                if receivers.count == 1 {
                    let r = receivers[0]
                    notes.append(r == humanSeat
                        ? "Очки играющего (\(amount)) получаете вы"
                        : "Очки играющего (\(amount)) получает \(names[r])")
                } else if receivers.count > 1 {
                    notes.append("Очки играющего (\(amount)) делят пополам: \(nameList(receivers, names: names, humanSeat: humanSeat))")
                }
            }
        case .hanging:
            if matchOver {
                notes.append(potBurnedText)
            } else if score.potAfter > score.potAdded {
                notes.append("Очки играющего (\(score.potAdded)) тоже повисли, всего висит \(score.potAfter) — \(potRule)")
            } else {
                notes.append("Очки играющего (\(score.potAdded)) висят — \(potRule)")
            }
        case .fourSevens:
            if let s = score.fourSevensSeat, score.bonus.indices.contains(s), score.bonus[s] > 0 {
                notes.append("\(who(s)): +\(score.bonus[s]) за четыре семёрки")
            }
        default:
            break
        }

        for seat in 0..<n where score.potAwarded[seat] > 0 {
            let verb = seat == humanSeat ? "забираете" : "забирает"
            notes.append("\(who(seat)) \(verb) висячие очки: +\(score.potAwarded[seat])")
        }

        // Комбинации и бэла без единой взятки не пишутся — объясняем, куда делись объявленные очки.
        if let w = score.burnedMeldSeat, let decl = score.declarations, decl.meldPoints(for: w, rules: rules) > 0 {
            let list = decl.winnerMelds.map { meldTitle($0, rules: rules) }.joined(separator: ", ")
            var text = "\(who(w)): \(list) не в зачёт — ни одной взятки"
            if decl.melds.enumerated().contains(where: { $0.offset != w && !$0.element.isEmpty }) {
                text += "; младшие комбинации других тоже не пишутся"
            }
            notes.append(text)
        }
        if let b = score.burnedBellaSeat, rules.bellaPoints > 0 {
            notes.append("\(who(b)): бэла не в зачёт — ни одной взятки")
        }

        let countedBait = score.outcome == .bait || (score.outcome == .hanging && rules.hangingCountsAsBait)
        for seat in 0..<n {
            let w = who(seat)
            if score.baitPenalty[seat] {
                let count = score.baitCountsAfter?[seat] ?? rules.baitPenaltyEvery
                notes.append("\(w): \(count)-й байт — штраф \(number(-rules.baitPenaltyPoints))")
            } else if countedBait, seat == score.bidder, let counts = score.baitCountsAfter, rules.baitPenaltyEvery > 1 {
                let count = counts[seat], every = rules.baitPenaltyEvery
                if count % every == every - 1 {
                    notes.append("\(w): \(count)-й байт за партию — следующий со штрафом \(number(-rules.baitPenaltyPoints))")
                } else {
                    notes.append("\(w): \(count)-й байт за партию")
                }
            }
            if score.nakedPenalty[seat] {
                let count = score.nakedCountsAfter?[seat] ?? rules.nakedPenaltyEvery
                notes.append("\(w): ни одной взятки, голый \(count)-й раз — штраф \(number(-rules.nakedPenaltyPoints))")
            } else if score.naked[seat] {
                var text = "\(w): ни одной взятки (голый)"
                if let counts = score.nakedCountsAfter, rules.nakedPenaltyEvery > 1,
                   counts[seat] % rules.nakedPenaltyEvery == rules.nakedPenaltyEvery - 1 {
                    text += " — в следующий раз штраф \(number(-rules.nakedPenaltyPoints))"
                }
                notes.append(text)
            }
        }

        if score.potAfter > 0 && score.outcome != .hanging {
            notes.append(matchOver ? potBurnedText : "Висячие очки (\(score.potAfter)) переходят в следующую сдачу")
        }
        if reachedTarget && !matchOver {
            notes.append("\(nameList(leaders, names: names, humanSeat: humanSeat)): по \(top) — поровну, играется ещё одна сдача")
        }
        return notes
    }

    /// Итог партии без рода глагола: «Вы выиграли партию!» / «Победа: Саша». nil — партия идёт.
    public static func matchResult(_ match: Match, humanSeat: Int?) -> String? {
        guard let w = match.winner else { return nil }
        return w == humanSeat ? "Вы выиграли партию!" : "Победа: \(match.names[w])"
    }

    /// Короткая пометка для строки записи: Б, ВБ, 4×7 и т. п.
    public static func sheetMark(_ score: DealScore) -> String {
        switch score.outcome {
        case .made: return ""
        case .bait: return "Б"
        case .hanging: return "ВБ"
        case .tie: return "="
        case .allPassed: return "пас"
        case .fourSevens: return "4×7"
        }
    }

    // MARK: - Ход картой

    /// Почему игрок `seat` не может сейчас пойти картой `card`: учитывает масть хода,
    /// обязанность бить козырем и перебивать старшим. Пустая строка — ходить можно.
    public static func illegalCardReason(deal: Deal, seat: Int, card: Card) -> String {
        switch deal.phase {
        case .bidding: return "Сейчас идёт торговля"
        case .exchange: return "Сначала решите, менять ли козырную семёрку"
        case .finished: return "Сдача окончена"
        case .playing: break
        }
        guard seat == deal.turn else { return "Сейчас не ваш ход" }
        guard let trump = deal.trump, deal.hands.indices.contains(seat) else { return "Так сейчас нельзя" }
        let hand = deal.hands[seat]
        guard hand.contains(card) else { return "Этой карты нет на руке" }
        let trick = deal.currentTrick.cards
        switch PlayRules.violation(of: card, hand: hand, trick: trick, trump: trump, rules: deal.rules) {
        case nil:
            return ""
        // Значок масти стоит после двоеточия, без падежа: так фраза грамотна и на экране, и вслух
        // («нужно ходить в масть: бубны»), а не «в масть бубны».
        case .mustFollowSuit(let suit):
            return suit == trump
                ? "Зашли с козыря — ходите козырем: \(suit.symbol)"
                : "Нужно ходить в масть: \(suit.symbol)"
        case .mustTrump(let t):
            let led = trick.first?.suit
            return led.map { "\(suitGenitive($0).capitalizedFirst) нет — бейте козырем: \(t.symbol)" }
                ?? "Нужно бить козырем: \(t.symbol)"
        case .mustOvertrump(let over):
            return "Нужно перебить: козырь старше, чем \(over)"
        }
    }

    // MARK: - Словами для VoiceOver

    // На экране карты и масти пишутся значками («Т♥», «10-В-Д-К♣»), а VoiceOver читает их
    // как «Т, знак червей» или «десять дефис В дефис Д» — неразборчиво и долго.
    // Здесь те же тексты словами; экранные строки (и тесты на них) не меняются.

    /// Масть в родительном падеже: «пик», «треф», «бубен», «червей» — «дама червей».
    public static func suitGenitive(_ suit: Suit) -> String {
        switch suit {
        case .spades: return "пик"
        case .clubs: return "треф"
        case .diamonds: return "бубен"
        case .hearts: return "червей"
        }
    }

    /// Достоинство в родительном падеже — для «от десятки до короля».
    static func rankGenitive(_ rank: Rank) -> String {
        switch rank {
        case .seven: return "семёрки"
        case .eight: return "восьмёрки"
        case .nine: return "девятки"
        case .ten: return "десятки"
        case .jack: return "валета"
        case .queen: return "дамы"
        case .king: return "короля"
        case .ace: return "туза"
        }
    }

    /// Карта словами: «дама червей», «десятка пик».
    public static func spokenCard(_ card: Card) -> String {
        "\(card.rank.name) \(suitGenitive(card.suit))"
    }

    /// Комбинация словами, как её называют за столом: «полтинник от десятки до короля треф»
    /// (на экране — «полтинник 10-В-Д-К♣»).
    public static func spokenMeld(_ meld: Meld, rules: RuleSet) -> String {
        "\(meld.name(rules)) \(spokenRun(from: meld.low, to: meld.high, suit: meld.suit))"
    }

    /// «от десятки до короля треф».
    private static func spokenRun(from low: Rank, to high: Rank, suit: Suit) -> String {
        "от \(rankGenitive(low)) до \(rankGenitive(high)) \(suitGenitive(suit))"
    }

    /// Сообщение о событии словами — для объявления VoiceOver (на экране — `message`):
    /// «Саша играет, козырь черви», «Саша забирает туз червей за козырную семёрку».
    public static func spokenMessage(for event: DealEvent, names: [String], humanSeat: Int?, rules: RuleSet) -> String? {
        message(for: event, names: names, humanSeat: humanSeat, rules: rules).map(spoken)
    }

    /// То же с учётом партии после события (предупреждение о сдаче на обязах).
    public static func spokenMessage(for event: DealEvent, in match: Match, humanSeat: Int?) -> String? {
        message(for: event, in: match, humanSeat: humanSeat).map(spoken)
    }

    /// Любой текст с экрана словами — для сообщений внизу стола, реплик соперников,
    /// подписей панели хода и пояснений к итогам:
    /// «Т♥» → «туз червей», «10-В-Д-К♣» → «от десятки до короля треф»,
    /// «козырь ♥ черви» → «козырь черви» (название уже рядом — значок просто пропадает),
    /// «Беру ♦» → «Беру бубны». Остальной текст не меняется.
    public static func spoken(_ text: String) -> String {
        // «·» между частями VoiceOver читает как «точка» посреди фразы.
        let chars = Array(text.replacingOccurrences(of: " · ", with: ", "))
        var result = ""
        var i = 0
        while i < chars.count {
            // Карта начинается не посреди слова или числа: «110♥» — не десятка.
            let atWordStart = i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber)
            if atWordStart, let run = cardRun(chars, at: i), let first = run.ranks.first, let last = run.ranks.last {
                result += run.ranks.count > 1
                    ? spokenRun(from: first, to: last, suit: run.suit)
                    : spokenCard(Card(first, run.suit))
                i = run.end
                continue
            }
            if let suit = suitSymbol(chars[i]) {
                let name = Array(" " + suit.name)
                let named = i + name.count < chars.count && Array(chars[(i + 1)...(i + name.count)]) == name
                if named {
                    i += 2   // значок и пробел: дальше идёт само название
                } else {
                    result += suit.name
                    i += 1
                }
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// Достоинства через дефис и значок масти сразу за ними: «Т♥», «10-В-Д♣». nil — это не карта.
    private static func cardRun(_ chars: [Character], at start: Int) -> (ranks: [Rank], suit: Suit, end: Int)? {
        var ranks: [Rank] = []
        var i = start
        while let token = rankToken(chars, at: i) {
            ranks.append(token.rank)
            i += token.length
            guard i < chars.count, chars[i] == "-", rankToken(chars, at: i + 1) != nil else { break }
            i += 1
        }
        guard !ranks.isEmpty, i < chars.count, let suit = suitSymbol(chars[i]) else { return nil }
        return (ranks, suit, i + 1)
    }

    /// Обозначение достоинства в тексте: «10» — два знака, остальные («7», «В», «Т») — один.
    private static func rankToken(_ chars: [Character], at i: Int) -> (rank: Rank, length: Int)? {
        guard chars.indices.contains(i) else { return nil }
        if chars[i] == "1", chars.indices.contains(i + 1), chars[i + 1] == "0" { return (.ten, 2) }
        guard let rank = Rank.allCases.first(where: { $0 != .ten && $0.symbol == String(chars[i]) }) else { return nil }
        return (rank, 1)
    }

    /// Значок масти — и с селектором варианта («♥︎» для текстового вида — один символ).
    private static func suitSymbol(_ character: Character) -> Suit? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        return Suit.allCases.first { $0.symbol.unicodeScalars.first == scalar }
    }
}

extension String {
    /// Первая буква заглавная: «бубен» → «Бубен».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
