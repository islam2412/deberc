import Foundation
import DebercKit

/// Честная подсказка об уровне: только совет, уровень сам не меняется, тасовка — та же.
///
/// Предлагает соперников посильнее после серии побед (или хорошего процента на уровне)
/// и попроще — после серии поражений. Никогда посреди партии.
struct LevelAdvice: Equatable {
    let level: BotLevel
    let text: String
    let buttonTitle: String
    /// true — предложение посильнее, false — попроще.
    let isStepUp: Bool

    /// После доигранной партии: `stats` уже с этой партией, `opponents` — соперники партии.
    static func afterMatch(stats: PlayerStats, opponents: [Persona], humanWon: Bool) -> LevelAdvice? {
        guard let top = opponents.map(\.level).max() else { return nil }
        let record = stats.byLevel[top.rawValue]
        let played = record?.played ?? 0
        let won = record?.won ?? 0
        if humanWon, let next = step(from: top, by: 1) {
            let streak = stats.currentStreak
            let strongRate = played >= 5 && won * 4 >= played * 3
            if streak >= 3 || strongRate {
                // Название уровня — в кавычках и после слова «уровень»: «против «Любитель»» не по-русски.
                let reason = streak >= 3
                    ? "\(RuPlural.count(streak, "победа", "победы", "побед")) подряд"
                    : "\(RuPlural.count(won, "победа", "победы", "побед")) из \(played) на уровне «\(top.title)»"
                return LevelAdvice(
                    level: next,
                    text: "\(reason) — похоже, вы сильнее. Попробуете соперников уровня «\(next.title)»?",
                    buttonTitle: "Играть на уровне «\(next.title)»",
                    isStepUp: true)
            }
        }
        if !humanWon, stats.currentStreak <= -3, let previous = step(from: top, by: -1) {
            let losses = -stats.currentStreak
            return LevelAdvice(
                level: previous,
                text: "\(RuPlural.count(losses, "поражение", "поражения", "поражений")) подряд. Можно сыграть с соперниками попроще — уровня «\(previous.title)».",
                buttonTitle: "Играть на уровне «\(previous.title)»",
                isStepUp: false)
        }
        return nil
    }

    /// В меню: выбранный уровень давно даётся легко.
    static func forMenu(stats: PlayerStats, selected: BotLevel?) -> LevelAdvice? {
        guard let selected, let next = step(from: selected, by: 1),
              let record = stats.byLevel[selected.rawValue] else { return nil }
        guard record.played >= 5, record.won * 4 >= record.played * 3, stats.currentStreak >= 2 else { return nil }
        return LevelAdvice(
            level: next,
            text: "На уровне «\(selected.title)» у вас \(RuPlural.count(record.won, "победа", "победы", "побед")) из \(record.played). Может, попробовать «\(next.title)»?",
            buttonTitle: "Выбрать уровень «\(next.title)»",
            isStepUp: true)
    }

    private static func step(from level: BotLevel, by delta: Int) -> BotLevel? {
        let all = BotLevel.allCases
        guard let index = all.firstIndex(of: level) else { return nil }
        let target = index + delta
        return all.indices.contains(target) ? all[target] : nil
    }
}
