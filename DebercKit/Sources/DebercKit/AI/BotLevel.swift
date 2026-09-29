import Foundation

/// Уровень игры компьютерного соперника. Лестница откалибрована дубликатным турниром
/// (см. BotExperiments): каждый следующий уровень вдвоём выигрывает у предыдущего
/// заметно больше половины партий.
public enum BotLevel: String, Codable, CaseIterable, Sendable, Comparable {
    case novice, amateur, expert, master

    /// «Новичок», «Любитель», «Знаток», «Мастер».
    public var title: String {
        switch self {
        case .novice: return "Новичок"
        case .amateur: return "Любитель"
        case .expert: return "Знаток"
        case .master: return "Мастер"
        }
    }

    /// Одна строка: чем уровень отличается.
    public var subtitle: String {
        switch self {
        case .novice: return "Торгуется на глаз, забывает вышедшие карты"
        case .amateur: return "Играет разумно, но просчитывает немногое"
        case .expert: return "Считает карты и редко ошибается"
        case .master: return "Просчитывает расклады до конца — сильнейший"
        }
    }

    /// Порядковый номер: 0 — Новичок … 3 — Мастер.
    public var rank: Int {
        switch self {
        case .novice: return 0
        case .amateur: return 1
        case .expert: return 2
        case .master: return 3
        }
    }

    public static func < (lhs: BotLevel, rhs: BotLevel) -> Bool { lhs.rank < rhs.rank }

    /// Терпимый разбор строки: понимает и старые значения ("easy", "medium", "hard").
    /// Неизвестное значение — «Любитель».
    public init(tolerant raw: String) {
        switch raw.lowercased() {
        case "novice", "easy": self = .novice
        case "amateur", "medium": self = .amateur
        case "expert", "hard", "strong": self = .expert
        case "master": self = .master
        default: self = .amateur
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self.init(tolerant: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Характер торговли. Меняет пороги «беру/играю» — сила при этом почти не меняется
/// (проверено турниром), меняется только манера.
public enum BotStyle: String, Codable, CaseIterable, Sendable {
    case cautious, balanced, bold

    /// «Осторожный», «Ровный», «Рисковый» — мужской род, как у слова «характер».
    public var title: String { title(feminine: false) }

    /// Манера в роде персонажа: «Вера — Мастер · Осторожная», «Борис — Мастер · Ровный».
    /// Уровни («Новичок», «Мастер») — существительные общего рода, им род не нужен.
    public func title(feminine: Bool) -> String {
        switch self {
        case .cautious: return feminine ? "Осторожная" : "Осторожный"
        case .balanced: return feminine ? "Ровная" : "Ровный"
        case .bold: return feminine ? "Рисковая" : "Рисковый"
        }
    }

    /// Коротко о манере.
    public var subtitle: String {
        switch self {
        case .cautious: return "Берёт игру только с хорошей картой"
        case .balanced: return "Торгуется по расчёту"
        case .bold: return "Охотно берёт игру и на средней карте"
        }
    }

    /// Сдвиг порога «беру» в 1-м круге и «играю» во 2-м (в очках ожидаемого итога сдачи).
    var takeShift: Double {
        switch self {
        case .cautious: return 5
        case .balanced: return 0
        case .bold: return -5
        }
    }

    var nameShift: Double {
        switch self {
        case .cautious: return 4
        case .balanced: return 0
        case .bold: return -6
        }
    }

    /// Сдвиг логита при торговле «на глаз» (у Новичка).
    var feelShift: Double {
        switch self {
        case .cautious: return -0.6
        case .balanced: return 0
        case .bold: return 0.6
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = BotStyle(rawValue: raw) ?? .balanced
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
