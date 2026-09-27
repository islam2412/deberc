import Foundation

/// Русские тексты для событий и итогов — чтобы интерфейс оставался простым.
public enum Narrator {

    /// Имя в начале фразы: «Саша», а для себя — «Вы».
    public static func name(_ seat: Int, names: [String], humanSeat: Int?) -> String {
        seat == humanSeat ? "Вы" : names[seat]
    }

    /// «до 701 очка», «до 500 очков».
    public static func pointsGenitive(_ n: Int) -> String {
        let last = abs(n) % 10, lastTwo = abs(n) % 100
        return last == 1 && lastTwo != 11 ? "\(n) очка" : "\(n) очков"
    }

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

    /// Пояснения к итогам сдачи: штрафы, висячие очки и т. п.
    public static func outcomeNotes(_ score: DealScore, names: [String], humanSeat: Int?, rules: RuleSet) -> [String] {
        var notes: [String] = []
        let n = score.change.count
        switch score.outcome {
        case .bait:
            if rules.baitTransfer == .toOpponent, let b = score.bidder {
                let receivers = (0..<n).filter { $0 != b && score.written[$0] > score.raw[$0] }
                let list = receivers.map { name($0, names: names, humanSeat: humanSeat) }.joined(separator: " и ")
                if !list.isEmpty {
                    notes.append("Очки играющего (\(score.raw[b])) получает: \(list)")
                }
            } else {
                notes.append("Очки играющего сгорают")
            }
        case .hanging:
            notes.append("\(score.potAdded) очк. висят — их заберёт выигравший следующую сдачу")
        case .fourSevens:
            if let s = score.fourSevensSeat, score.bonus[s] > 0 {
                notes.append("\(name(s, names: names, humanSeat: humanSeat)): +\(score.bonus[s]) за четыре семёрки")
            }
        default:
            break
        }
        for seat in 0..<n where score.potAwarded[seat] > 0 {
            notes.append("\(name(seat, names: names, humanSeat: humanSeat)): +\(score.potAwarded[seat]) висячих очков")
        }
        for seat in 0..<n {
            let who = name(seat, names: names, humanSeat: humanSeat)
            if score.baitPenalty[seat] {
                notes.append("\(who): штраф −\(rules.baitPenaltyPoints) за \(rules.baitPenaltyEvery)-й байт")
            }
            if score.nakedPenalty[seat] {
                notes.append("\(who): штраф −\(rules.nakedPenaltyPoints) — голый \(rules.nakedPenaltyEvery)-й раз")
            } else if score.naked[seat] {
                notes.append("\(who): голый (без взяток)")
            }
        }
        if score.potAfter > 0 && score.outcome != .hanging {
            notes.append("Висят \(score.potAfter) очк.")
        }
        return notes
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
}
