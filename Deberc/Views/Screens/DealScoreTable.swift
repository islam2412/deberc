import SwiftUI
import DebercKit

/// Таблица итога сдачи: взятки, очки за карты, комбинации, бэла, набрано, висячие, штрафы, записано.
/// Столбец играющего подписан золотом со значком козыря; «Записано» — зелёным/красным.
struct DealScoreTable: View {
    let score: DealScore
    let seats: SeatNames

    private var n: Int { score.change.count }

    var body: some View {
        // Втроём на узком экране с крупным текстом подписи строк не должны ломаться переносами —
        // тогда таблица мельче.
        ViewThatFits(in: .horizontal) {
            table(font: .body, spacing: 14)
            table(font: .callout, spacing: 10)
            table(font: .footnote, spacing: 8, compact: true)
        }
        .foregroundStyle(Theme.tableText)
    }

    /// `compact` — самый тесный вариант: имена и «Записано» тоже мельче.
    private func table(font: Font, spacing: CGFloat, compact: Bool = false) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: spacing, verticalSpacing: 7) {
            header(compact: compact)
            rule
            if score.wasPlayed {
                playedRows
            } else if score.bonus.contains(where: { $0 != 0 }) {
                valueRow("Бонус", score.bonus, signed: true)
            }
            rule
            writtenRow(compact: compact)
        }
        .font(font.monospacedDigit())
    }

    // MARK: - Строки

    private func header(compact: Bool) -> some View {
        GridRow {
            Color.clear
                .frame(width: 1, height: 1)
                .gridCellUnsizedAxes([.horizontal, .vertical])
            ForEach(0 ..< n, id: \.self) { seat in
                headerCell(seat, compact: compact)
            }
        }
    }

    private func headerCell(_ seat: Int, compact: Bool) -> some View {
        let isBidder = score.wasPlayed && score.bidder == seat
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if isBidder, let trump = score.trump {
                    SuitBadge(suit: trump, size: compact ? 15 : 18)
                }
                Text(seats.column(seat))
                    .font((compact ? Font.footnote : Font.subheadline).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isBidder ? Theme.gold : Theme.tableText)
            }
            if isBidder {
                Text(score.forced ? "обязы" : "играет")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isBidder ? "\(seats.column(seat)), играет" : seats.column(seat))
    }

    private var rule: some View {
        Divider()
            .overlay(Color.white.opacity(0.25))
            .gridCellUnsizedAxes(.horizontal)
    }

    @ViewBuilder
    private var playedRows: some View {
        valueRow("Взятки", score.tricksTaken)
        valueRow("За карты", score.cardPoints)
        if score.meldPoints.contains(where: { $0 != 0 }) || score.burnedMeldSeat != nil {
            valueRow("Комбинации", score.meldPoints)
        }
        if score.bellaPoints.contains(where: { $0 != 0 }) || score.burnedBellaSeat != nil {
            valueRow("Бэла", score.bellaPoints)
        }
        valueRow("Набрано", score.raw, bold: true)
        if score.potAwarded.contains(where: { $0 != 0 }) {
            valueRow("Висячие", score.potAwarded, signed: true)
        }
        if score.penalties.contains(where: { $0 != 0 }) {
            valueRow("Штраф", score.penalties, signed: true, colored: true)
        }
    }

    private func writtenRow(compact: Bool) -> some View {
        GridRow {
            Text("Записано")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.tableSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .gridColumnAlignment(.leading)
            ForEach(0 ..< n, id: \.self) { seat in
                writtenCell(seat, compact: compact)
            }
        }
    }

    private func writtenCell(_ seat: Int, compact: Bool) -> some View {
        let value = score.change[seat]
        let mark = score.bidder == seat ? Narrator.sheetMark(score) : ""
        return HStack(spacing: 4) {
            if score.wasPlayed && !mark.isEmpty && mark != "=" {
                ScoreMarkBadge(text: mark)
            }
            Text(Narrator.signed(value))
                .font((compact ? Font.headline : Font.title3).weight(.bold).monospacedDigit())
                .foregroundStyle(ScreenStyle.change(value))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seats.column(seat)): записано \(Narrator.signed(value))\(spokenMark(mark))")
    }

    private func spokenMark(_ mark: String) -> String {
        switch mark {
        case "Б": return ", байт"
        case "ВБ": return ", висячий байт"
        default: return ""
        }
    }

    private func valueRow(_ title: String, _ values: [Int], signed: Bool = false, bold: Bool = false,
                          colored: Bool = false) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(Theme.tableSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .gridColumnAlignment(.leading)
            ForEach(0 ..< n, id: \.self) { seat in
                let value = values.indices.contains(seat) ? values[seat] : 0
                Text(signed ? Narrator.signed(value) : Narrator.number(value))
                    .fontWeight(bold ? .bold : .regular)
                    .foregroundStyle(colored ? ScreenStyle.change(value) : Theme.tableText)
                    .accessibilityLabel("\(title), \(seats.column(seat)): \(signed ? Narrator.signed(value) : Narrator.number(value))")
            }
        }
    }
}

/// «Счёт партии»: у каждого — итог, полоска до цели и сколько осталось.
struct MatchProgressList: View {
    let totals: [Int]
    let target: Int
    let seats: SeatNames
    /// Места в нужном порядке (по умолчанию — по порядку мест).
    var order: [Int]? = nil

    var body: some View {
        let top = totals.max() ?? 0
        let seatsInOrder = order ?? Array(totals.indices)
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(seatsInOrder, id: \.self) { seat in
                let total = totals[seat]
                let leading = total == top && total > 0
                GridRow {
                    Text(seats.column(seat))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.tableText)
                    GoalProgressBar(value: total, target: target,
                                      tint: leading ? Theme.gold : Theme.tableSecondaryText.opacity(0.8))
                        .frame(minWidth: 50, maxWidth: .infinity)
                    Text(Narrator.number(total))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(leading ? Theme.gold : Theme.tableText)
                        .gridColumnAlignment(.trailing)
                    Text(remaining(total, seat: seat))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.tableSecondaryText)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }

    /// Сколько осталось до цели партии, а у дошедшего до неё — «дошли» (вы), «дошёл» или «дошла».
    private func remaining(_ total: Int, seat: Int) -> String {
        let left = target - total
        if left > 0 { return "ещё \(left)" }
        if seat == seats.humanSeat { return "дошли" }
        return seats.persona(seat)?.feminine == true ? "дошла" : "дошёл"
    }
}
