import SwiftUI
import DebercKit

/// «Запись» — история сдач партии.
struct ScoreSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let match: Match
    let humanSeat: Int

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "Счёт", values: match.totals.map { "\($0)" }, bold: true)
                    if match.pot > 0 {
                        Text("Висят \(match.pot) очк. — достанутся выигравшему следующую сдачу")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    row(title: "", values: (0..<match.playerCount).map(name), bold: true)
                }

                Section("Сдачи") {
                    ForEach(match.history.reversed(), id: \.number) { score in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(caption(score))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            row(title: "\(score.number)",
                                values: score.change.map { $0 > 0 ? "+\($0)" : "\($0)" },
                                bold: false)
                            row(title: "",
                                values: score.totalsAfter.map { "\($0)" },
                                bold: true)
                        }
                    }
                }

                Section("Штрафы в партии") {
                    ForEach(0..<match.playerCount, id: \.self) { seat in
                        HStack {
                            Text(name(seat))
                            Spacer()
                            Text("байтов: \(match.baitCounts[seat]) · голый: \(match.nakedCounts[seat])")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Запись партии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func name(_ seat: Int) -> String {
        seat == humanSeat ? "Вы" : match.names[seat]
    }

    private func caption(_ score: DealScore) -> String {
        var parts: [String] = []
        if let bidder = score.bidder, let trump = score.trump {
            parts.append("играет \(name(bidder)) \(trump.glyph)")
            if score.forced { parts.append("обязы") }
        }
        let mark = Narrator.sheetMark(score)
        switch score.outcome {
        case .made: break
        case .bait: parts.append("байт (\(mark))")
        case .hanging: parts.append("висячий байт (\(mark))")
        case .tie: parts.append("ничья")
        case .allPassed: parts.append("все пас")
        case .fourSevens: parts.append("4 семёрки")
        }
        for seat in 0..<score.change.count {
            if score.baitPenalty[seat] { parts.append("\(name(seat)): штраф за байты") }
            if score.nakedPenalty[seat] { parts.append("\(name(seat)): штраф за голого") }
        }
        return parts.joined(separator: " · ")
    }

    private func row(title: String, values: [String], bold: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(.secondary)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .fontWeight(bold ? .semibold : .regular)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
