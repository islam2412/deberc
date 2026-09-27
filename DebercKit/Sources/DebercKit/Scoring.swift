import Foundation

/// Итог сдачи — строка в «записи».
public struct DealScore: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// Играющий набрал больше соперников.
        case made
        /// Байт: играющий набрал меньше.
        case bait
        /// Висячий байт: ничья, очки играющего «висят».
        case hanging
        /// Ничья, каждый записал свои очки.
        case tie
        /// Все спасовали — пересдача.
        case allPassed
        /// 4 семёрки — бонус и пересдача.
        case fourSevens
    }

    public var number: Int
    public var dealer: Int
    public var outcome: Outcome
    public var bidder: Int?
    public var trump: Suit?
    public var forced: Bool
    public var cardPoints: [Int]
    public var tricksTaken: [Int]
    public var meldPoints: [Int]
    public var bellaPoints: [Int]
    /// Сумма очков в сдаче до байта.
    public var raw: [Int]
    /// Записанные очки за сдачу (с учётом байта).
    public var written: [Int]
    /// Получено висячих очков из прошлых сдач.
    public var potAwarded: [Int]
    /// Очки, повисшие в этой сдаче.
    public var potAdded: Int
    public var potAfter: Int
    /// Штрафы (отрицательные числа).
    public var penalties: [Int]
    public var baitPenalty: [Bool]
    public var nakedPenalty: [Bool]
    public var naked: [Bool]
    public var bonus: [Int]
    public var fourSevensSeat: Int?
    /// Итоговое изменение счёта.
    public var change: [Int]
    public var totalsAfter: [Int]
}

/// Итог розыгрыша сдачи, посчитанный по правилам (без номера и итогов партии).
public struct Settlement: Equatable, Sendable {
    public var outcome: DealScore.Outcome
    public var meldPoints: [Int]
    public var bellaPoints: [Int]
    public var raw: [Int]
    public var written: [Int]
    public var potAwarded: [Int]
    public var potAdded: Int
    public var potAfter: Int
    public var penalties: [Int]
    public var baitPenalty: [Bool]
    public var nakedPenalty: [Bool]
    public var naked: [Bool]
    public var baitCountsAfter: [Int]
    public var nakedCountsAfter: [Int]

    public var change: [Int] {
        (0..<raw.count).map { written[$0] + potAwarded[$0] + penalties[$0] }
    }
}

public enum Scoring {

    /// Подсчёт сыгранной сдачи.
    /// - Parameters:
    ///   - cardPoints: очки за карты во взятках, включая 10 за последнюю взятку.
    ///   - tricksTaken: число взятых взяток.
    ///   - declarations: объявленные комбинации.
    ///   - bidder: играющий (назначивший козырь).
    ///   - priority: порядок игроков начиная со следующего после сдающего.
    ///   - pot: висячие очки из прошлых сдач.
    public static func settle(
        cardPoints: [Int],
        tricksTaken: [Int],
        declarations: Declarations?,
        bidder: Int,
        priority: [Int],
        rules: RuleSet,
        pot: Int,
        baitCounts: [Int],
        nakedCounts: [Int]
    ) -> Settlement {
        let n = cardPoints.count
        var meldPoints = [Int](repeating: 0, count: n)
        var bellaPoints = [Int](repeating: 0, count: n)

        if let decl = declarations {
            if let w = decl.meldWinner, rules.combosNeedTrick != .all || tricksTaken[w] > 0 {
                meldPoints[w] = decl.meldPoints(for: w, rules: rules)
            }
            if let b = decl.bellaSeat, rules.combosNeedTrick == .none || tricksTaken[b] > 0 {
                bellaPoints[b] = rules.bellaPoints
            }
        }

        let raw = (0..<n).map { cardPoints[$0] + meldPoints[$0] + bellaPoints[$0] }
        let opponents = priority.filter { $0 != bidder }
        let opponentMax = opponents.map { raw[$0] }.max() ?? 0
        let threshold: Int
        if rules.bidderMustBeat == .opponentsCombined && n == 3 {
            threshold = opponents.reduce(0) { $0 + raw[$1] }
        } else {
            threshold = opponentMax
        }

        let b = raw[bidder]
        var outcome: DealScore.Outcome
        if b > threshold {
            outcome = .made
        } else if b < threshold {
            outcome = .bait
        } else {
            switch rules.tieRule {
            case .hangingBait: outcome = .hanging
            case .bait: outcome = .bait
            case .eachKeeps: outcome = .tie
            }
        }

        var written = raw
        var potAdded = 0
        switch outcome {
        case .made, .tie, .allPassed, .fourSevens:
            break
        case .bait:
            written[bidder] = 0
            if rules.baitTransfer == .toOpponent {
                let recipients: [Int]
                if rules.baitRecipient == .splitHalf {
                    recipients = opponents
                } else {
                    recipients = opponents.filter { raw[$0] == opponentMax }
                }
                let share = b / recipients.count
                var remainder = b % recipients.count
                for seat in recipients {
                    written[seat] += share
                    if remainder > 0 {
                        written[seat] += 1
                        remainder -= 1
                    }
                }
            }
        case .hanging:
            written[bidder] = 0
            potAdded = b
        }

        // Висячие очки прошлых сдач забирает тот, кто набрал в этой сдаче больше всех.
        var potAwarded = [Int](repeating: 0, count: n)
        var potAfter = pot
        if pot > 0 && outcome != .hanging {
            let top = raw.max() ?? 0
            let leaders = (0..<n).filter { raw[$0] == top }
            if leaders.count == 1 {
                potAwarded[leaders[0]] = pot
                potAfter = 0
            }
        }
        potAfter += potAdded

        var penalties = [Int](repeating: 0, count: n)
        var baitPenalty = [Bool](repeating: false, count: n)
        var nakedPenalty = [Bool](repeating: false, count: n)
        var baitCountsAfter = baitCounts
        var nakedCountsAfter = nakedCounts

        if outcome == .bait || (outcome == .hanging && rules.hangingCountsAsBait) {
            baitCountsAfter[bidder] += 1
            if rules.baitPenaltyEvery > 0 && baitCountsAfter[bidder] % rules.baitPenaltyEvery == 0 {
                penalties[bidder] -= rules.baitPenaltyPoints
                baitPenalty[bidder] = true
            }
        }

        let naked = tricksTaken.map { $0 == 0 }
        for seat in 0..<n where naked[seat] {
            nakedCountsAfter[seat] += 1
            if rules.nakedPenaltyEvery > 0 && nakedCountsAfter[seat] % rules.nakedPenaltyEvery == 0 {
                penalties[seat] -= rules.nakedPenaltyPoints
                nakedPenalty[seat] = true
            }
        }

        return Settlement(
            outcome: outcome,
            meldPoints: meldPoints,
            bellaPoints: bellaPoints,
            raw: raw,
            written: written,
            potAwarded: potAwarded,
            potAdded: potAdded,
            potAfter: potAfter,
            penalties: penalties,
            baitPenalty: baitPenalty,
            nakedPenalty: nakedPenalty,
            naked: naked,
            baitCountsAfter: baitCountsAfter,
            nakedCountsAfter: nakedCountsAfter
        )
    }
}
