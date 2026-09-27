import Foundation

/// Текст правил, собранный из текущих настроек.
public enum RulesText {

    public struct Section: Sendable, Equatable {
        public let title: String
        public let items: [String]
    }

    public static func sections(for r: RuleSet) -> [Section] {
        var result: [Section] = []

        result.append(Section(title: "Игроки и колода", items: [
            "Играют вдвоём или втроём, каждый сам за себя. Партия — до \(Narrator.pointsGenitive(r.targetScore)).",
            "Колода из 32 карт: от семёрки до туза.",
            "Козыри от старшего: валет — 20, девятка — 14, туз — 11, десятка — 10, король — 4, дама — 3, восьмёрка и семёрка — 0.",
            "Остальные масти: туз — 11, десятка — 10, король — 4, дама — 3, валет — 2, девятка, восьмёрка и семёрка — 0.",
            "За последнюю взятку — ещё 10 очков.",
        ]))

        var deal: [String] = [
            "Каждому сдают по 6 карт (по 3 за раз), следующая карта открывается — она предлагает козырь.",
            "1-й круг начинает следующий после сдающего: «беру» (козырь — масть открытой карты) или «пас».",
            "Если все спасовали — 2-й круг: можно назвать любую другую масть или сказать «пас».",
        ]
        if r.forcedDealAfterRedeals > 0 {
            deal.append("Если все спасовали и во 2-м круге — пересдача, сдаёт следующий.")
            deal.append("Обязы: если пересдача была \(r.forcedDealAfterRedeals) раза подряд, в следующей сдаче торговли нет — сдающий играет сам, козырь — масть открытой карты.")
        } else {
            deal.append("Если все спасовали и во 2-м круге — пересдача, сдаёт следующий.")
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
        switch r.fourSevens {
        case .bonusAndRedeal:
            deal.append("Четыре семёрки на руках\(r.fourSevensAfterPrikup ? " (сразу или после добора, до первого хода)" : " (при раздаче)"): +\(r.fourSevensBonus) очков и пересдача.")
        case .redeal:
            deal.append("Четыре семёрки на руках\(r.fourSevensAfterPrikup ? " (сразу или после добора, до первого хода)" : " (при раздаче)"): пересдача.")
        case .off:
            break
        }
        switch r.dealerRotation {
        case .nextPlayer: deal.append("Сдают по очереди, по кругу.")
        case .dealWinner: deal.append("Следующую сдачу сдаёт тот, кто выиграл прошлую.")
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
        melds.append("Бэла — король и дама козырей: \(r.bellaPoints). Король и дама из бэлы могут входить и в терц.")
        switch r.meldOrder {
        case .longerFirst:
            melds.append("Терцы и полтинники записывает только один игрок — у кого старшая комбинация: длиннее, при равной длине — со старшей картой выше, затем козырная, затем — кто раньше ходит. Он пишет все свои, у остальных они сгорают.")
        case .valueThenTopCard:
            melds.append("Терцы и полтинники записывает только один игрок — у кого старшая комбинация: полтинник старше терца, при равных — со старшей картой выше, затем козырная, затем — кто раньше ходит. Он пишет все свои, у остальных они сгорают.")
        }
        switch r.combosNeedTrick {
        case .all: melds.append("Все комбинации, включая бэлу, засчитываются, только если взята хотя бы одна взятка.")
        case .bellaOnly: melds.append("Бэла засчитывается, только если взята хотя бы одна взятка.")
        case .none: break
        }
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
        } else {
            bait += ", его очки сгорают."
        }
        scoring.append(bait)
        switch r.tieRule {
        case .hangingBait:
            scoring.append("Висячий байт — ничья: соперники пишут свои очки, а очки играющего «висят» и достаются тому, кто наберёт больше всех в следующей сдаче.")
        case .bait:
            scoring.append("Ничья считается байтом.")
        case .eachKeeps:
            scoring.append("При ничьей каждый записывает свои очки.")
        }
        result.append(Section(title: "Подсчёт", items: scoring))

        var penalties: [String] = []
        if r.baitPenaltyEvery > 0 {
            penalties.append("Каждый \(r.baitPenaltyEvery)-й байт за партию — минус \(r.baitPenaltyPoints)."
                + (r.hangingCountsAsBait ? " Висячий байт тоже считается." : " Висячий байт не считается."))
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

        result.append(Section(title: "Конец партии", items: [
            "Как только после сдачи у кого-то \(r.targetScore) или больше — партия окончена.",
            "Если перешли сразу двое — побеждает тот, у кого больше. При равенстве играется ещё одна сдача.",
        ]))
        return result
    }

    /// Текст правил в формате Markdown.
    public static func markdown(for rules: RuleSet, title: String = "Деберц — наши правила") -> String {
        var text = "# \(title)\n"
        for section in sections(for: rules) {
            text += "\n## \(section.title)\n\n"
            for item in section.items { text += "- \(item)\n" }
        }
        return text
    }
}
