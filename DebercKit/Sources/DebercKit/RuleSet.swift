import Foundation

/// Все настраиваемые правила. Значения по умолчанию — «домашние» правила,
/// согласованные с папой (см. RULES.md в корне репозитория).
public struct RuleSet: Codable, Equatable, Sendable {

    /// Кто может поменять козырную семёрку на открытую карту.
    public enum SevenExchange: String, Codable, CaseIterable, Sendable {
        case anyPlayer, bidderOnly, off
    }

    /// Кто делает первый ход в сдаче.
    public enum FirstLead: String, Codable, CaseIterable, Sendable {
        case afterDealer, bidder
    }

    /// Кто сдаёт следующую сдачу.
    public enum DealerRotation: String, Codable, CaseIterable, Sendable {
        /// Следующий по кругу.
        case nextPlayer
        /// Выигравший прошлую сдачу (если победителя нет — следующий по кругу).
        case dealWinner
    }

    /// Как сравнивать равные по виду комбинации.
    public enum MeldOrder: String, Codable, CaseIterable, Sendable {
        /// Сначала длиннее, потом старшая карта, потом козырная.
        case longerFirst
        /// Сначала стоимость (полтинник старше терца), потом старшая карта, потом козырная.
        case valueThenTopCard
    }

    /// Нужно ли взять взятку, чтобы записать комбинации.
    public enum CombosNeedTrick: String, Codable, CaseIterable, Sendable {
        case none, bellaOnly, all
    }

    /// Обязанность перебивать козырь.
    public enum Overtrump: String, Codable, CaseIterable, Sendable {
        /// Бить козырем обязательно, но любым.
        case never
        /// Перебивать старшим — только когда зашли с козыря.
        case trumpLeadOnly
        /// Перебивать старшим всегда, когда во взятке уже есть козырь.
        case always
    }

    /// Что происходит с очками играющего при байте.
    public enum BaitTransfer: String, Codable, CaseIterable, Sendable {
        /// Уходят сопернику.
        case toOpponent
        /// Сгорают.
        case burn
    }

    /// Кому уходят очки при байте в игре втроём.
    public enum BaitRecipient: String, Codable, CaseIterable, Sendable {
        /// Сопернику, у которого в сдаче больше очков (при равенстве — пополам).
        case leadingOpponent
        /// Всегда пополам.
        case splitHalf
    }

    /// Сколько должен набрать играющий при игре втроём.
    public enum BidderMustBeat: String, Codable, CaseIterable, Sendable {
        case eachOpponent, opponentsCombined
    }

    /// Ничья между играющим и соперником.
    public enum TieRule: String, Codable, CaseIterable, Sendable {
        case hangingBait, bait, eachKeeps
    }

    /// Четыре семёрки на руках.
    public enum FourSevens: String, Codable, CaseIterable, Sendable {
        case bonusAndRedeal, redeal, off
    }

    /// Когда показывают нижнюю карту колоды.
    public enum BottomCard: String, Codable, CaseIterable, Sendable {
        case afterPrikup, afterDeal, hidden
    }

    // MARK: Партия
    public var targetScore = 701

    // MARK: Торговля
    /// После скольких пересдач подряд (все пас) наступают «обязы». 0 — обязов нет.
    public var forcedDealAfterRedeals = 2
    public var sevenExchange = SevenExchange.anyPlayer
    public var firstLead = FirstLead.afterDealer
    public var dealerRotation = DealerRotation.nextPlayer
    public var fourSevens = FourSevens.bonusAndRedeal
    public var fourSevensBonus = 100
    /// Считаются ли 4 семёрки после прикупа (до первого хода).
    public var fourSevensAfterPrikup = true
    /// Пересдача из-за 4 семёрок не сбрасывает счёт пересдач до «обязов»:
    /// если это были обязы, следующая сдача — снова обязы (у нового сдающего).
    /// Если выключено — после 4 семёрок счёт пересдач начинается заново.
    public var fourSevensKeepsForcedStreak = true
    public var bottomCard = BottomCard.afterPrikup

    // MARK: Комбинации
    public var terzPoints = 20
    public var fiftyPoints = 50
    /// 5 и больше карт подряд — «сотня» (100). Если выключено — это тоже полтинник.
    public var hundredForFive = false
    public var bellaPoints = 20
    /// Король и дама бэлы могут одновременно входить в терц или полтинник.
    /// Если выключено — у игрока с бэлой эти две карты в последовательностях не считаются.
    public var bellaInMelds = true
    public var meldOrder = MeldOrder.longerFirst
    public var combosNeedTrick = CombosNeedTrick.all

    // MARK: Ход
    public var mustTrump = true
    public var overtrump = Overtrump.never
    /// Правило «перебивать» по-настоящему: без обязанности бить козырем перебивать тоже не нужно
    /// (так и написано в правилах; сам выбор в настройках при этом сохраняется).
    public var effectiveOvertrump: Overtrump { mustTrump ? overtrump : .never }

    // MARK: Подсчёт
    public var baitTransfer = BaitTransfer.toOpponent
    public var baitRecipient = BaitRecipient.leadingOpponent
    public var bidderMustBeat = BidderMustBeat.eachOpponent
    public var tieRule = TieRule.hangingBait

    // MARK: Штрафы
    /// Штраф за каждый N-й байт в партии. 0 — нет штрафа.
    public var baitPenaltyEvery = 3
    public var baitPenaltyPoints = 100
    public var hangingCountsAsBait = false
    /// Штраф за каждый N-й раз «голым» (ни одной взятки). 0 — нет штрафа.
    public var nakedPenaltyEvery = 2
    public var nakedPenaltyPoints = 100

    public init() {}

    /// Домашние правила по умолчанию.
    public static let house = RuleSet()

    enum CodingKeys: String, CodingKey {
        case targetScore, forcedDealAfterRedeals, sevenExchange, firstLead, dealerRotation
        case fourSevens, fourSevensBonus, fourSevensAfterPrikup, fourSevensKeepsForcedStreak, bottomCard
        case terzPoints, fiftyPoints, hundredForFive, bellaPoints, bellaInMelds, meldOrder, combosNeedTrick
        case mustTrump, overtrump
        case baitTransfer, baitRecipient, bidderMustBeat, tieRule
        case baitPenaltyEvery, baitPenaltyPoints, hangingCountsAsBait, nakedPenaltyEvery, nakedPenaltyPoints
    }

    /// Терпимое к старым сохранениям чтение: отсутствующие или неизвестные значения
    /// заменяются значениями по умолчанию, лишние ключи пропускаются.
    /// Новое поле правил добавлять сюда же, в `CodingKeys` и в этот инициализатор.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RuleSet()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        targetScore = value(.targetScore, d.targetScore)
        forcedDealAfterRedeals = value(.forcedDealAfterRedeals, d.forcedDealAfterRedeals)
        sevenExchange = value(.sevenExchange, d.sevenExchange)
        firstLead = value(.firstLead, d.firstLead)
        dealerRotation = value(.dealerRotation, d.dealerRotation)
        fourSevens = value(.fourSevens, d.fourSevens)
        fourSevensBonus = value(.fourSevensBonus, d.fourSevensBonus)
        fourSevensAfterPrikup = value(.fourSevensAfterPrikup, d.fourSevensAfterPrikup)
        fourSevensKeepsForcedStreak = value(.fourSevensKeepsForcedStreak, d.fourSevensKeepsForcedStreak)
        bottomCard = value(.bottomCard, d.bottomCard)
        terzPoints = value(.terzPoints, d.terzPoints)
        fiftyPoints = value(.fiftyPoints, d.fiftyPoints)
        hundredForFive = value(.hundredForFive, d.hundredForFive)
        bellaPoints = value(.bellaPoints, d.bellaPoints)
        bellaInMelds = value(.bellaInMelds, d.bellaInMelds)
        meldOrder = value(.meldOrder, d.meldOrder)
        combosNeedTrick = value(.combosNeedTrick, d.combosNeedTrick)
        mustTrump = value(.mustTrump, d.mustTrump)
        overtrump = value(.overtrump, d.overtrump)
        baitTransfer = value(.baitTransfer, d.baitTransfer)
        baitRecipient = value(.baitRecipient, d.baitRecipient)
        bidderMustBeat = value(.bidderMustBeat, d.bidderMustBeat)
        tieRule = value(.tieRule, d.tieRule)
        baitPenaltyEvery = value(.baitPenaltyEvery, d.baitPenaltyEvery)
        baitPenaltyPoints = value(.baitPenaltyPoints, d.baitPenaltyPoints)
        hangingCountsAsBait = value(.hangingCountsAsBait, d.hangingCountsAsBait)
        nakedPenaltyEvery = value(.nakedPenaltyEvery, d.nakedPenaltyEvery)
        nakedPenaltyPoints = value(.nakedPenaltyPoints, d.nakedPenaltyPoints)
    }
}
