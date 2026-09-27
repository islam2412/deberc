import Foundation
import DebercKit

enum GameSpeed: String, Codable, CaseIterable, Identifiable {
    case slow, normal, fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: return "Медленно"
        case .normal: return "Обычно"
        case .fast: return "Быстро"
        }
    }

    /// Пауза перед ходом компьютера.
    var botDelay: Duration {
        switch self {
        case .slow: return .milliseconds(1200)
        case .normal: return .milliseconds(750)
        case .fast: return .milliseconds(350)
        }
    }

    /// Сколько показывать собранную взятку.
    var trickPause: Duration {
        switch self {
        case .slow: return .milliseconds(1800)
        case .normal: return .milliseconds(1200)
        case .fast: return .milliseconds(650)
        }
    }

    /// Сколько показывать сообщение.
    var bannerTime: Duration {
        switch self {
        case .slow: return .milliseconds(2600)
        case .normal: return .milliseconds(2000)
        case .fast: return .milliseconds(1400)
        }
    }
}

struct AppSettings: Codable, Equatable {
    var rules = RuleSet.house
    var botLevel = BotLevel.medium
    var speed = GameSpeed.normal
    var playerName = "Вы"
    var botNames = ["Саша", "Миша"]
    /// Первое касание выбирает карту, второе — ходит.
    var confirmCardTap = true
    var playerCount = 2

    init() {}

    enum CodingKeys: String, CodingKey {
        case rules, botLevel, speed, playerName, botNames, confirmCardTap, playerCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        rules = (try? c.decodeIfPresent(RuleSet.self, forKey: .rules)) ?? d.rules
        botLevel = (try? c.decodeIfPresent(BotLevel.self, forKey: .botLevel)) ?? d.botLevel
        speed = (try? c.decodeIfPresent(GameSpeed.self, forKey: .speed)) ?? d.speed
        playerName = (try? c.decodeIfPresent(String.self, forKey: .playerName)) ?? d.playerName
        botNames = (try? c.decodeIfPresent([String].self, forKey: .botNames)) ?? d.botNames
        confirmCardTap = (try? c.decodeIfPresent(Bool.self, forKey: .confirmCardTap)) ?? d.confirmCardTap
        playerCount = (try? c.decodeIfPresent(Int.self, forKey: .playerCount)) ?? d.playerCount
        if !(2...3).contains(playerCount) { playerCount = 2 }
        while botNames.count < 2 { botNames.append("Бот \(botNames.count + 1)") }
    }
}
