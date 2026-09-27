import SwiftUI
import DebercKit

/// Итоги сдачи (и партии, если она закончилась).
struct DealSummaryView: View {
    @EnvironmentObject private var store: GameStore
    let match: Match
    /// Сколько места по высоте есть на экране.
    let maxHeight: CGFloat
    var maxWidth: CGFloat = 560

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let score = match.history.last {
                    header(score)
                    if [.made, .bait, .hanging, .tie].contains(score.outcome) {
                        detailsGrid(score)
                    } else {
                        totalsGrid(score)
                    }
                    notes(score)
                }
                if match.isOver {
                    gameOver
                } else {
                    Button("Следующая сдача") { store.startNextDeal() }
                        .buttonStyle(TableButtonStyle(prominent: true))
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: maxWidth, maxHeight: max(240, maxHeight))
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.07, green: 0.16, blue: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.gold.opacity(0.5), lineWidth: 1)
        )
        .foregroundStyle(.white)
        .padding(16)
    }

    private func name(_ seat: Int) -> String {
        seat == store.humanSeat ? "Вы" : match.names[seat]
    }

    private func header(_ score: DealScore) -> some View {
        VStack(spacing: 4) {
            Text(headerSubtitle(score))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Text(Narrator.outcomeTitle(score, names: match.names, humanSeat: store.humanSeat))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
        }
    }

    private func headerSubtitle(_ score: DealScore) -> String {
        var text = "Сдача \(score.number)"
        if let trump = score.trump, let bidder = score.bidder {
            text += " · играет \(name(bidder)) \(trump.glyph)"
            if score.forced { text += " (обязы)" }
        }
        return text
    }

    private func detailsGrid(_ score: DealScore) -> some View {
        let n = match.playerCount
        return Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(0..<n, id: \.self) { seat in
                    Text(name(seat))
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
            }
            Divider().overlay(Color.white.opacity(0.3))
            valueRow("Взятки", score.tricksTaken)
            valueRow("Карты", score.cardPoints)
            if score.meldPoints.contains(where: { $0 != 0 }) {
                valueRow("Комбинации", score.meldPoints)
            }
            if score.bellaPoints.contains(where: { $0 != 0 }) {
                valueRow("Бэла", score.bellaPoints)
            }
            valueRow("Набрано", score.raw, bold: true)
            Divider().overlay(Color.white.opacity(0.3))
            valueRow("Записано", score.change, signed: true, bold: true)
            valueRow("Счёт", score.totalsAfter, bold: true)
        }
        .font(.body.monospacedDigit())
    }

    private func totalsGrid(_ score: DealScore) -> some View {
        let n = match.playerCount
        return Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(0..<n, id: \.self) { seat in
                    Text(name(seat)).font(.subheadline.bold()).lineLimit(1)
                }
            }
            valueRow("Записано", score.change, signed: true)
            valueRow("Счёт", score.totalsAfter, bold: true)
        }
        .font(.body.monospacedDigit())
    }

    private func valueRow(_ title: String, _ values: [Int], signed: Bool = false, bold: Bool = false) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.white.opacity(0.8))
                .gridColumnAlignment(.leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(signed && value > 0 ? "+\(value)" : "\(value)")
                    .fontWeight(bold ? .bold : .regular)
            }
        }
    }

    @ViewBuilder
    private func notes(_ score: DealScore) -> some View {
        let lines = Narrator.outcomeNotes(score, names: match.names, humanSeat: store.humanSeat, rules: match.rules)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var gameOver: some View {
        if let winner = match.winner {
            VStack(spacing: 10) {
                Text(winner == store.humanSeat ? "🏆 Вы выиграли партию!" : "Партию выиграл(а) \(match.names[winner])")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Новая партия") { store.newGame() }
                        .buttonStyle(TableButtonStyle(prominent: true))
                    Button("В меню") { store.leaveGame() }
                        .buttonStyle(TableButtonStyle())
                }
            }
            .padding(.top, 6)
        }
    }
}
