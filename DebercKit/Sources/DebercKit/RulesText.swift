import Foundation

/// Текст правил, собранный из текущих настроек. Из него же собирается RULES.md
/// (часть между маркерами `<!-- generated:start -->` и `<!-- generated:end -->`).
public enum RulesText {

    /// Как называется набор правил по умолчанию (`RuleSet.house`). Одно имя на всё приложение —
    /// в меню, приветствии, настройках и при «Поделиться»: незнакомому игроку «наши» и «ваши»
    /// ничего не говорят, а «домашние правила» — понятный набор, который можно поменять.
    public static let houseTitle = "Домашние правила"

    /// То же в подписях вида «Деберц по домашним правилам».
    public static let housePhrase = "по домашним правилам"

    public struct Section: Sendable, Equatable {
        public let title: String
        public let items: [String]
    }

    /// «раз» / «раза»: «2 раза», «5 раз», «22 раза».
    static func timesWord(_ n: Int) -> String {
        let last = n % 10, lastTwo = n % 100
        return (2...4).contains(last) && !(12...14).contains(lastTwo) ? "раза" : "раз"
    }

    public static func sections(for r: RuleSet) -> [Section] {
        var result: [Section] = []

        result.append(Section(title: "Игроки и колода", items: [
            "Играют вдвоём или втроём, каждый сам за себя. Партия — до \(Narrator.pointsGenitive(r.targetScore)).",
            "Втроём сдают, торгуются и ходят по часовой стрелке: следующий — тот, кто сидит слева.",
            "Колода из 32 карт: от семёрки до туза.",
            "Козыри от старшего: валет — 20, девятка — 14, туз — 11, десятка — 10, король — 4, дама — 3, восьмёрка и семёрка — 0.",
            "Остальные масти: туз — 11, десятка — 10, король — 4, дама — 3, валет — 2, девятка, восьмёрка и семёрка — 0.",
            "За последнюю взятку — ещё 10 очков.",
        ]))

        var deal: [String] = [
            "Каждому сдают по 6 карт (по 3 за раз), следующая карта открывается — она предлагает козырь.",
            "1-й круг начинает следующий после сдающего: «беру» (козырь — масть открытой карты) или «пас».",
            "Если все спасовали — 2-й круг: можно назвать любую другую масть или сказать «пас».",
            "Если все спасовали и во 2-м круге — пересдача, сдаёт следующий.",
        ]
        if r.forcedDealAfterRedeals == 1 {
            deal.append("Обязы: если все спасовали и была пересдача, в следующей сдаче торговли нет — сдающий играет сам, козырь — масть открытой карты.")
        } else if r.forcedDealAfterRedeals > 1 {
            let n = r.forcedDealAfterRedeals
            deal.append("Обязы: если пересдача была \(n) \(timesWord(n)) подряд, в следующей сдаче торговли нет — сдающий играет сам, козырь — масть открытой карты.")
        }
        deal.append("Кто назначил козырь — «играющий», остальные — его соперники.")
        var prikup = "Затем каждому добирают ещё по 3 карты — у всех по 9."
        switch r.bottomCard {
        case .afterPrikup: prikup += " После этого открывают нижнюю карту колоды (только для информации)."
        case .afterDeal: prikup += " Нижнюю карту колоды показывают сразу после раздачи."
        case .hidden: break
        }
        deal.append(prikup)
        switch r.sevenExchange {
        case .anyPlayer:
            deal.append("Если козырь — масть открытой карты, любой игрок с козырной семёркой может до первого хода поменять её на открытую карту.")
        case .bidderOnly:
            deal.append("Если козырь — масть открытой карты, играющий с козырной семёркой может до первого хода поменять её на открытую карту.")
        case .off:
            break
        }
        if r.fourSevens != .off {
            let when = r.fourSevensAfterPrikup ? " (сразу или после добора, до первого хода)" : " (при раздаче)"
            let what = r.fourSevens == .bonusAndRedeal ? "+\(Narrator.points(r.fourSevensBonus)) и пересдача" : "пересдача"
            deal.append("Четыре семёрки на руках\(when): \(what). Следующую сдачу сдаёт следующий по кругу.")
            if r.forcedDealAfterRedeals > 0 {
                deal.append(r.fourSevensKeepsForcedStreak
                    ? "Пересдача из-за четырёх семёрок не меняет счёт пересдач до обязов: если это были обязы, следующая сдача — снова обязы, у нового сдающего."
                    : "Пересдача из-за четырёх семёрок начинает счёт пересдач до обязов заново.")
            }
        }
        switch r.dealerRotation {
        case .nextPlayer: deal.append("Сдают по очереди, по кругу.")
        case .dealWinner: deal.append("Следующую сдачу сдаёт тот, кто выиграл прошлую (набрал в ней больше всех); если такого нет — следующий по кругу.")
        }
        result.append(Section(title: "Раздача и козырь", items: deal))

        var melds = [
            "Терц — 3 карты одной масти подряд: \(r.terzPoints).",
        ]
        if r.hundredForFive {
            melds.append("Полтинник — 4 карты подряд: \(r.fiftyPoints). Сотня — 5 и больше: 100.")
        } else {
            melds.append("Полтинник — 4 и больше карт подряд: \(r.fiftyPoints).")
        }
        melds.append("Порядок для комбинаций: 7-8-9-10-В-Д-К-Т. Одна карта — только в одной последовательности.")
        melds.append(r.bellaInMelds
            ? "Бэла — король и дама козырей: \(r.bellaPoints). Король и дама из бэлы могут входить и в терц."
            : "Бэла — король и дама козырей: \(r.bellaPoints). Король и дама из бэлы в терц и полтинник не входят.")
        let tieBreak = "затем козырная, затем — кто раньше ходит. Он пишет все свои, у остальных они сгорают."
        switch r.meldOrder {
        case .longerFirst:
            melds.append("Терцы и полтинники записывает только один игрок — у кого старшая комбинация: длиннее, при равной длине — со старшей картой выше, \(tieBreak)")
        case .valueThenTopCard:
            melds.append("Терцы и полтинники записывает только один игрок — у кого старшая комбинация: полтинник старше терца, при равных — со старшей картой выше, \(tieBreak)")
        }
        switch r.combosNeedTrick {
        case .all:
            melds.append("Все комбинации, включая бэлу, засчитываются, только если взята хотя бы одна взятка. Если у записывающего взяток нет — его комбинации сгорают, а младшие комбинации других всё равно не пишутся.")
        case .bellaOnly:
            melds.append("Бэла засчитывается, только если взята хотя бы одна взятка.")
        case .none:
            break
        }
        melds.append("Комбинации приложение объявляет само: перед первым ходом показывает, чьи терцы и полтинники старше, а бэлу — когда её хозяин кладёт короля или даму козырей.")
        result.append(Section(title: "Комбинации", items: melds))

        var play = [
            "Первым ходит \(r.firstLead == .afterDealer ? "следующий после сдающего" : "играющий").",
        ]
        var obligations = "Ходить в масть обязательно."
        if r.mustTrump {
            switch r.overtrump {
            case .never: obligations += " Нет масти — обязательно бить козырем (любым, перебивать старшим не нужно)."
            case .trumpLeadOnly: obligations += " Нет масти — обязательно бить козырем. На ход с козыря нужно класть козырь старше, если он есть."
            case .always: obligations += " Нет масти — обязательно бить козырем, и старше уже лежащего козыря, если есть."
            }
            obligations += " Нет козырей — любую карту."
        } else {
            obligations += " Нет масти — можно положить любую карту."
        }
        play.append(obligations)
        play.append("Взятку берёт старший козырь, а без козырей — старшая карта масти, с которой зашли. Взявший ходит следующим.")
        result.append(Section(title: "Розыгрыш", items: play))

        var scoring = [
            "Очки за сдачу = карты во взятках + 10 за последнюю взятку + комбинации.",
            r.bidderMustBeat == .eachOpponent
                ? "Играющий должен набрать больше каждого из соперников."
                : "Играющий должен набрать больше, чем соперники вместе.",
            "Набрал больше — каждый записывает свои очки.",
        ]
        var bait = "Байт — набрал меньше: играющий пишет 0"
        if r.baitTransfer == .toOpponent {
            bait += ", а все его очки (с комбинациями) уходят сопернику."
            if r.baitRecipient == .leadingOpponent {
                bait += " Втроём — тому, у кого в сдаче больше очков; если у соперников поровну — пополам."
            } else {
                bait += " Втроём — пополам обоим соперникам."
            }
            bait += " При дележе пополам лишнее очко получает тот, кто раньше ходит."
        } else {
            bait += ", его очки сгорают."
        }
        scoring.append(bait)
        switch r.tieRule {
        case .hangingBait:
            scoring.append("Висячий байт — ничья: соперники пишут свои очки, а очки играющего «висят» и достаются тому, кто наберёт больше всех в следующей сдаче. Если и там ничья — висят дальше.")
        case .bait:
            scoring.append("Ничья считается байтом.")
        case .eachKeeps:
            scoring.append("При ничьей каждый записывает свои очки.")
        }
        result.append(Section(title: "Подсчёт", items: scoring))

        var penalties: [String] = []
        if r.baitPenaltyEvery > 0 {
            var text = "Каждый \(r.baitPenaltyEvery)-й байт за партию — минус \(r.baitPenaltyPoints)."
            text += r.hangingCountsAsBait ? " Висячий байт тоже считается." : " Висячий байт не считается."
            if r.forcedDealAfterRedeals > 0 { text += " Байт на обязах считается как обычный." }
            penalties.append(text)
        }
        if r.nakedPenaltyEvery > 0 {
            if r.nakedPenaltyEvery == 1 {
                penalties.append("Голый (ни одной взятки за сдачу) — минус \(r.nakedPenaltyPoints).")
            } else {
                penalties.append("Голый (ни одной взятки за сдачу): каждый \(r.nakedPenaltyEvery)-й раз за партию, не обязательно подряд, — минус \(r.nakedPenaltyPoints).")
            }
        }
        if penalties.isEmpty { penalties.append("Штрафов нет.") }
        result.append(Section(title: "Штрафы", items: penalties))

        var end = [
            "Как только после сдачи у кого-то \(r.targetScore) или больше — партия окончена. Досрочно, не доиграв сдачу, «Партию!» не объявляют.",
            "Если перешли сразу двое — побеждает тот, у кого больше. При равенстве играется ещё одна сдача.",
        ]
        if r.tieRule == .hangingBait {
            end.append("Висячие очки, не разыгранные до конца партии, сгорают.")
        }
        result.append(Section(title: "Конец партии", items: end))

        let levels = BotLevel.allCases.map(\.title).joined(separator: ", ")
        let styles = BotStyle.allCases.map { $0.title.lowercased() }.joined(separator: ", ")
        result.append(Section(title: "Компьютер-соперник", items: [
            "Компьютер видит только свои карты и то, что открыто на столе: ваших карт и прикупа он не знает.",
            "Карты тасуются честно и одинаково на всех уровнях; уровень соперника во время партии сам не меняется.",
            "Уровни от слабого к сильному: \(levels). Характер соперника (\(styles)) меняет манеру торговли, а не силу игры.",
        ]))
        return result
    }

    /// Разделы правил в формате Markdown (без заголовка) — генерируемая часть RULES.md.
    public static func markdownBody(for rules: RuleSet) -> String {
        var text = ""
        for (index, section) in sections(for: rules).enumerated() {
            if index > 0 { text += "\n" }
            text += "## \(section.title)\n\n"
            for item in section.items { text += "- \(item)\n" }
        }
        return text
    }

    /// Текст правил в формате Markdown.
    public static func markdown(for rules: RuleSet, title: String = "Деберц — наши правила") -> String {
        "# \(title)\n\n" + markdownBody(for: rules)
    }
}
