import Foundation

/// Статистика человека за все доигранные партии. Хранится приложением отдельно от партии;
/// читается терпимо: отсутствующие поля — нули, лишние ключи пропускаются.
public struct PlayerStats: Codable, Equatable, Sendable {

    /// Сыграно и выиграно партий.
    public struct Record: Codable, Equatable, Sendable {
        public var played: Int
        public var won: Int

        public init(played: Int = 0, won: Int = 0) {
            self.played = played
            self.won = won
        }

        public var lost: Int { max(0, played - won) }

        /// Доля побед 0…1 (nil — партий ещё не было).
        public var winRate: Double? { played > 0 ? Double(won) / Double(played) : nil }

        /// Процент побед, округлённый: 0…100 (nil — партий ещё не было).
        public var winPercent: Int? { winRate.map { Int(($0 * 100).rounded()) } }

        mutating func add(won didWin: Bool) {
            played += 1
            if didWin { won += 1 }
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            played = max(0, (try? c.decodeIfPresent(Int.self, forKey: .played)) ?? 0)
            won = min(played, max(0, (try? c.decodeIfPresent(Int.self, forKey: .won)) ?? 0))
        }
    }

    /// Все партии.
    public var total: Record
    /// По уровню соперников; ключ — `BotLevel.rawValue` (что передало приложение).
    public var byLevel: [String: Record]
    /// Против каждого соперника; ключ — `Persona.id`.
    public var byPersona: [String: Record]
    /// Текущая серия: > 0 — побед подряд, < 0 — поражений подряд.
    public var currentStreak: Int
    /// Лучшая серия побед.
    public var bestStreak: Int
    /// Сдач, где вы назначали козырь (сыгранных, без пересдач).
    public var dealsAsBidder: Int
    /// Из них сделано (набрали больше соперников).
    public var dealsMade: Int
    /// Из них байтов (включая висячие).
    public var baits: Int
    /// Лучший счёт человека в конце партии.
    public var bestMatchScore: Int
    /// Метка последней записанной партии — чтобы одну партию не записать дважды.
    public var lastRecordedMatch: String?

    public init() {
        total = Record()
        byLevel = [:]
        byPersona = [:]
        currentStreak = 0
        bestStreak = 0
        dealsAsBidder = 0
        dealsMade = 0
        baits = 0
        bestMatchScore = 0
        lastRecordedMatch = nil
    }

    /// Доля сделанных сдач среди тех, где вы играли (nil — ещё не играли).
    public var madeRate: Double? {
        dealsAsBidder > 0 ? Double(dealsMade) / Double(dealsAsBidder) : nil
    }

    /// Записать доигранную партию. Вызывать один раз, когда `match.isOver`;
    /// повторный вызов для той же партии ничего не меняет.
    /// - Parameters:
    ///   - humanSeat: место человека.
    ///   - personaIDs: id соперников этой партии (по одному на каждого).
    ///   - levelKey: уровень соперников (`BotLevel.rawValue`), nil — не записывать по уровням.
    /// - Returns: true, если партия записана.
    @discardableResult
    public mutating func record(match: Match, humanSeat: Int, personaIDs: [String], levelKey: String?) -> Bool {
        guard let winner = match.winner, match.totals.indices.contains(humanSeat) else { return false }
        let signature = PlayerStats.signature(of: match)
        guard signature != lastRecordedMatch else { return false }
        lastRecordedMatch = signature

        let won = winner == humanSeat
        total.add(won: won)
        if let levelKey {
            byLevel[levelKey, default: Record()].add(won: won)
        }
        for id in Set(personaIDs) {
            byPersona[id, default: Record()].add(won: won)
        }
        if won {
            currentStreak = currentStreak > 0 ? currentStreak + 1 : 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            currentStreak = currentStreak < 0 ? currentStreak - 1 : -1
        }
        for score in match.history where score.wasPlayed && score.bidder == humanSeat {
            dealsAsBidder += 1
            switch score.outcome {
            case .made: dealsMade += 1
            case .bait, .hanging: baits += 1
            default: break
            }
        }
        bestMatchScore = max(bestMatchScore, match.totals[humanSeat])
        return true
    }

    /// Метка партии: состояние генератора в конце партии и итоговый счёт.
    static func signature(of match: Match) -> String {
        "\(match.rng.state)-\(match.dealCount)-" + match.totals.map(String.init).joined(separator: ",")
    }

    enum CodingKeys: String, CodingKey {
        case total, byLevel, byPersona, currentStreak, bestStreak
        case dealsAsBidder, dealsMade, baits, bestMatchScore, lastRecordedMatch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        total = value(.total, Record())
        byLevel = value(.byLevel, [:])
        byPersona = value(.byPersona, [:])
        currentStreak = value(.currentStreak, 0)
        bestStreak = max(0, value(.bestStreak, 0))
        dealsAsBidder = max(0, value(.dealsAsBidder, 0))
        dealsMade = max(0, value(.dealsMade, 0))
        baits = max(0, value(.baits, 0))
        bestMatchScore = value(.bestMatchScore, 0)
        lastRecordedMatch = try? c.decodeIfPresent(String.self, forKey: .lastRecordedMatch)
    }
}
