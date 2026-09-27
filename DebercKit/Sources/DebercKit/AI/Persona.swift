import Foundation

/// Персонаж-соперник: имя, аватар, уровень и манера торговли.
public struct Persona: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Короткое русское имя.
    public let name: String
    /// Один эмодзи.
    public let avatar: String
    /// Индекс цвета в `Theme.seatTints` (0…7).
    public let tint: Int
    public let level: BotLevel
    public let style: BotStyle
    /// Одна фраза о характере игры.
    public let bio: String
    /// Женское имя — для согласования глаголов («выиграла»).
    public let feminine: Bool

    public init(id: String, name: String, avatar: String, tint: Int, level: BotLevel, style: BotStyle,
                bio: String, feminine: Bool = false) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.tint = tint
        self.level = level
        self.style = style
        self.bio = bio
        self.feminine = feminine
    }

    enum CodingKeys: String, CodingKey {
        case id, name, avatar, tint, level, style, bio, feminine
    }

    /// Терпимое чтение: недостающие поля берутся из встроенного персонажа с тем же id.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = (try? c.decode(String.self, forKey: .id)) ?? "sasha"
        let base = Persona.byID(id) ?? Persona.all[2]
        self.id = id
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? base.name
        avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar)) ?? base.avatar
        tint = (try? c.decodeIfPresent(Int.self, forKey: .tint)) ?? base.tint
        level = (try? c.decodeIfPresent(BotLevel.self, forKey: .level)) ?? base.level
        style = (try? c.decodeIfPresent(BotStyle.self, forKey: .style)) ?? base.style
        bio = (try? c.decodeIfPresent(String.self, forKey: .bio)) ?? base.bio
        feminine = (try? c.decodeIfPresent(Bool.self, forKey: .feminine)) ?? base.feminine
    }

    // MARK: - Встроенные персонажи

    /// 8 персонажей: по 2 на каждый уровень, у пары — разная манера.
    public static let all: [Persona] = [
        Persona(id: "lesha", name: "Лёша", avatar: "🐣", tint: 0, level: .novice, style: .bold,
                bio: "Только учится и любит рискнуть"),
        Persona(id: "katya", name: "Катя", avatar: "🦔", tint: 1, level: .novice, style: .cautious,
                bio: "Играет недавно и берёт игру с опаской", feminine: true),
        Persona(id: "sasha", name: "Саша", avatar: "🐻", tint: 2, level: .amateur, style: .balanced,
                bio: "Играет по выходным — спокойно и ровно"),
        Persona(id: "olya", name: "Оля", avatar: "🦊", tint: 3, level: .amateur, style: .bold,
                bio: "Азартная: берёт игру и на средней карте", feminine: true),
        Persona(id: "nina", name: "Нина", avatar: "🐱", tint: 4, level: .expert, style: .cautious,
                bio: "Считает карты и зря не рискует", feminine: true),
        Persona(id: "misha", name: "Миша", avatar: "🐺", tint: 5, level: .expert, style: .bold,
                bio: "Помнит вышедшие карты и любит смелую игру"),
        Persona(id: "boris", name: "Борис", avatar: "🦉", tint: 6, level: .master, style: .balanced,
                bio: "Просчитывает концовку до последней взятки"),
        Persona(id: "vera", name: "Вера", avatar: "🦅", tint: 7, level: .master, style: .cautious,
                bio: "Видит расклад наперёд и почти не ошибается", feminine: true),
    ]

    public static func byID(_ id: String) -> Persona? {
        all.first { $0.id == id }
    }

    /// Соперники для быстрого выбора уровня: `count` персонажей этого уровня
    /// (если нужно больше — добираются с соседнего уровня).
    public static func defaults(level: BotLevel, count: Int) -> [Persona] {
        guard count > 0 else { return [] }
        // Сначала персонажи этого уровня («ровный» — первым), затем — ближайших уровней.
        let ranked = all.enumerated().sorted { a, b in
            func key(_ p: Persona, _ index: Int) -> (Int, Int, Int) {
                (abs(p.level.rank - level.rank), p.style == .balanced ? 0 : 1, index)
            }
            return key(a.element, a.offset) < key(b.element, b.offset)
        }
        return Array(ranked.prefix(count).map(\.element))
    }

    // MARK: - Реплики

    /// Реплика при торговле, в характере персонажа («Пас», «Беру ♥», «Рискну: ♠»…).
    /// Вариант выбирается по самой заявке, поэтому фраза не «мигает» при перерисовке.
    public func phrase(for bid: Bid) -> String {
        phrase(for: bid, variant: 0)
    }

    /// То же с дополнительным разнообразием (например, по номеру сдачи).
    public func phrase(for bid: Bid, variant: Int) -> String {
        let s = bid.suit?.symbol ?? ""
        let options: [String]
        switch bid.kind {
        case .pass:
            switch (style, bid.round) {
            case (.bold, 1): options = ["Пас", "Не в этот раз", "Пас, пока"]
            case (.bold, _): options = ["Пас", "Не моя сдача", "Пропущу"]
            case (.cautious, 1): options = ["Пас", "Пожалуй, пас", "Воздержусь"]
            case (.cautious, _): options = ["Пас", "Лучше пас", "Воздержусь"]
            case (_, 1): options = ["Пас", "Пас", "Пропускаю"]
            default: options = ["Пас", "Тоже пас", "Пас"]
            }
        case .take:
            switch style {
            case .bold: options = ["Беру \(s)!", "Рискну: \(s)", "Беру, \(s)!"]
            case .cautious: options = ["Беру \(s)", "Пожалуй, беру \(s)", "Ладно, беру \(s)"]
            case .balanced: options = ["Беру \(s)", "Беру \(s)", "Беру, \(s)"]
            }
        case .name:
            switch style {
            case .bold: options = ["Играю \(s)!", "Рискну: \(s)", "Козырь \(s)!"]
            case .cautious: options = ["Играю \(s)", "Пожалуй, \(s)", "Попробую \(s)"]
            case .balanced: options = ["Играю \(s)", "Козырь \(s)", "Играю \(s)"]
            }
        case .forced:
            switch style {
            case .bold: options = ["Обязы \(s) — сыграем!", "Обязы \(s)", "Обязы \(s), поехали"]
            case .cautious: options = ["Обязы \(s)…", "Обязы \(s)", "Что ж, обязы \(s)"]
            case .balanced: options = ["Обязы \(s)", "Обязы \(s)", "Играю на обязах \(s)"]
            }
        }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        for x in [bid.seat, bid.round, bid.suit?.rawValue ?? 7, variant] {
            h = (h ^ UInt64(bitPattern: Int64(x))) &* 0x0000_0100_0000_01B3
        }
        return options[Int(h % UInt64(options.count))]
    }
}
