import SwiftUI
import DebercKit

/// «Запись» партии — как на бумаге: столбцы игроков, строка на сдачу, в клетке — итог
/// после сдачи и мелко изменение. У играющего — масть козыря, при байте «Б», при висячем «ВБ»;
/// «Г» — голый, штраф — красным. Новая сдача сверху. Над таблицей — сколько осталось до цели,
/// висячие очки и сколько до штрафа за байты и голых.
///
/// Работает без `GameStore` в окружении: открывается и со стола, и из итогов, и с экрана конца партии.
struct ScoreSheetView: View {
    let match: Match
    let humanSeat: Int

    init(match: Match, humanSeat: Int) {
        self.match = match
        self.humanSeat = humanSeat
    }

    private var seats: SeatNames { SeatNames(names: match.names, humanSeat: humanSeat) }
    private var n: Int { match.playerCount }
    private var numberWidth: CGFloat { 34 }

    var body: some View {
        SheetContainer(title: "Запись партии", sizing: .page) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    overview
                        .padding(.bottom, 18)
                    Section {
                        if match.history.isEmpty {
                            emptyRow
                        } else {
                            ForEach(Array(match.history.reversed().enumerated()), id: \.offset) { index, score in
                                row(score, index: index)
                            }
                        }
                        paperBottom
                    } header: {
                        columnHeader
                    }
                    legend
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Над таблицей

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("До \(match.rules.targetScore)")
                .font(.headline)
                .foregroundStyle(Theme.tableText)
            MatchProgressList(totals: match.totals, target: match.rules.targetScore, seats: seats)
            if match.pot > 0 {
                // Запись открывают и после конца партии — тогда висячие уже сгорели.
                Label(match.isOver
                      ? "Висячие \(Narrator.points(match.pot)) не разыграны — партия окончена, они сгорели"
                      : "Висят \(Narrator.points(match.pot)) — достанутся тому, кто наберёт больше всех в следующей сдаче",
                      systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.tableSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let penalties = penaltyLines
            if !penalties.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Штрафы")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.tableText)
                    ForEach(penalties, id: \.self) { line in
                        SummaryNoteLine(text: line,
                                 systemImage: line.contains("следующий") ? "exclamationmark.triangle.fill" : "circle.fill",
                                 tint: line.contains("следующий") ? Theme.gold : Theme.tableSecondaryText)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
    }

    /// «Вы: байтов 2 — следующий со штрафом −100».
    private var penaltyLines: [String] {
        let rules = match.rules
        var lines: [String] = []
        for seat in 0 ..< n {
            var parts: [String] = []
            let baits = match.baitCounts[seat]
            if baits > 0 {
                var text = "байтов \(baits)"
                if rules.baitPenaltyEvery > 1 && baits % rules.baitPenaltyEvery == rules.baitPenaltyEvery - 1 {
                    text += " — следующий со штрафом \(Narrator.number(-rules.baitPenaltyPoints))"
                } else if rules.baitPenaltyEvery == 1 {
                    text += " — каждый со штрафом"
                }
                parts.append(text)
            }
            let naked = match.nakedCounts[seat]
            if naked > 0 {
                var text = "голый \(RuPlural.count(naked, "раз", "раза", "раз"))"
                if rules.nakedPenaltyEvery > 1 && naked % rules.nakedPenaltyEvery == rules.nakedPenaltyEvery - 1 {
                    text += " — следующий со штрафом \(Narrator.number(-rules.nakedPenaltyPoints))"
                }
                parts.append(text)
            }
            if !parts.isEmpty {
                lines.append("\(seats.column(seat)): " + parts.joined(separator: "; "))
            }
        }
        return lines
    }

    // MARK: - Бумага

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("№")
                .frame(width: numberWidth, alignment: .leading)
                .foregroundStyle(ScreenStyle.inkSecondary)
            ForEach(0 ..< n, id: \.self) { seat in
                HStack(spacing: 5) {
                    if let persona = seats.persona(seat) {
                        Text(persona.avatar)
                            .font(.system(size: 15))
                            .accessibilityHidden(true)
                    }
                    Text(seats.column(seat))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(ScreenStyle.ink)
            }
        }
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            UnevenTopRectangle(radius: 14)
                .fill(ScreenStyle.paper))
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Rectangle().fill(ScreenStyle.inkRed.opacity(0.55)).frame(height: 1)
                Rectangle().fill(ScreenStyle.inkRed.opacity(0.55)).frame(height: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ score: DealScore, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(score.number)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(ScreenStyle.inkSecondary)
                .frame(width: numberWidth, alignment: .leading)
            if score.outcome == .allPassed {
                Text("все пас — пересдача")
                    .font(.footnote.italic())
                    .foregroundStyle(ScreenStyle.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(0 ..< n, id: \.self) { seat in
                    cell(score, seat: seat)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, score.outcome == .allPassed ? 6 : 8)
        .background(index.isMultiple(of: 2) ? ScreenStyle.paper : ScreenStyle.paperAlt)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ScreenStyle.paperRule).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRow(score))
    }

    private func cell(_ score: DealScore, seat: Int) -> some View {
        let change = score.change[seat]
        return VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 4) {
                marks(score, seat: seat)
                Text(Narrator.number(score.totalsAfter[seat]))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ScreenStyle.ink)
            }
            Text(Narrator.signed(change))
                .font(.caption.monospacedDigit())
                .foregroundStyle(ScreenStyle.inkChange(change))
            if score.penalties[seat] != 0 {
                Text("штраф \(Narrator.number(score.penalties[seat]))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ScreenStyle.inkRed)
            }
        }
    }

    @ViewBuilder
    private func marks(_ score: DealScore, seat: Int) -> some View {
        HStack(spacing: 3) {
            if score.bidder == seat && score.wasPlayed, let trump = score.trump {
                SuitBadge(suit: trump, size: 17)
                let mark = Narrator.sheetMark(score)
                if mark == "Б" || mark == "ВБ" {
                    InkMark(text: mark, color: ScreenStyle.inkRed)
                }
            }
            if score.outcome == .fourSevens && score.fourSevensSeat == seat {
                InkMark(text: "4×7", color: ScreenStyle.inkGreen)
            }
            if score.naked[seat] {
                InkMark(text: "Г", color: ScreenStyle.inkSecondary)
            }
        }
    }

    private var emptyRow: some View {
        Text("Сдач пока не было")
            .font(.subheadline)
            .foregroundStyle(ScreenStyle.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(ScreenStyle.paper)
    }

    private var paperBottom: some View {
        UnevenBottomRectangle(radius: 14)
            .fill(ScreenStyle.paper)
            .frame(height: 12)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Значок масти — кто играл и какой козырь. Б — байт, ВБ — висячий байт, Г — голый (ни одной взятки), 4×7 — четыре семёрки.")
            Text("В клетке крупно — счёт после сдачи, мелко — сколько записано за сдачу.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.tableSecondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - VoiceOver

    private func spokenRow(_ score: DealScore) -> String {
        var parts = ["Сдача \(score.number)"]
        if score.outcome == .allPassed {
            parts.append("все пас, пересдача")
            return parts.joined(separator: ", ")
        }
        if score.wasPlayed, let bidder = score.bidder, let trump = score.trump {
            parts.append("играет \(seats.column(bidder)), козырь \(trump.name)")
        }
        switch score.outcome {
        case .bait: parts.append("байт")
        case .hanging: parts.append("висячий байт")
        case .tie: parts.append("ничья")
        case .fourSevens: parts.append("четыре семёрки")
        default: break
        }
        for seat in 0 ..< n {
            parts.append("\(seats.column(seat)) \(Narrator.signed(score.change[seat])), итого \(score.totalsAfter[seat])")
        }
        return parts.joined(separator: ", ")
    }
}

/// Пометка «чернилами»: Б, ВБ, Г.
private struct InkMark: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 3)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1))
    }
}

/// Прямоугольник со скруглёнными только верхними углами (iOS 16: без UnevenRoundedRectangle).
struct UnevenTopRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// То же — скруглены только нижние углы.
struct UnevenBottomRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}
