import SwiftUI
import DebercKit

/// Статистика: победы, серии, как вы играете сдачи, успехи по уровням и против каждого соперника.
struct StatsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var confirmReset = false

    private var stats: PlayerStats { store.stats }

    var body: some View {
        SheetContainer(title: "Статистика", sizing: .page) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stats.total.played == 0 {
                        emptyState
                    } else {
                        headline
                        tiles
                        biddingCard
                        levelsCard
                        opponentsCard
                        resetButton
                    }
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .alert("Стереть статистику?", isPresented: $confirmReset) {
            Button("Стереть", role: .destructive) { store.resetStats() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Победы, серии и счёт с соперниками начнутся с нуля. Идущая партия не пострадает.")
        }
    }

    // MARK: - Пусто

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            Text("Пока пусто")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.tableText)
            Text("Доиграйте первую партию до конца — здесь появятся победы, серии и счёт с каждым соперником.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Главное

    private var headline: some View {
        let total = stats.total
        return VStack(alignment: .leading, spacing: 6) {
            // Одной строкой: «Побед: 12 из 30 · 40 %» на узком экране чуть мельче, но без переноса.
            Text("Побед: \(total.won) из \(total.played) · \(percent(total.won, total.played))")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.tableText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GoalProgressBar(value: total.won, target: max(1, total.played), height: 10)
            Text(streakText)
                .font(.headline)
                .foregroundStyle(stats.currentStreak > 0 ? Theme.gold : Theme.tableSecondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var streakText: String {
        let streak = stats.currentStreak
        if streak > 0 { return "Сейчас \(RuPlural.count(streak, "победа", "победы", "побед")) подряд" }
        if streak < 0 { return "Сейчас \(RuPlural.count(-streak, "поражение", "поражения", "поражений")) подряд" }
        return "Серии пока нет"
    }

    /// Доля побед и число партий — уже в заголовке; плитки — рекорды.
    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(value: "\(stats.bestStreak)", title: "лучшая серия")
            StatTile(value: "\(stats.bestMatchScore)", title: "лучший счёт")
        }
    }

    private var biddingCard: some View {
        StatsCard(title: "Когда играете вы") {
            if stats.dealsAsBidder == 0 {
                Text("Вы ещё не назначали козырь в доигранных партиях.")
                    .foregroundStyle(Theme.tableSecondaryText)
            } else {
                StatsRow(title: "Назначали козырь", value: RuPlural.count(stats.dealsAsBidder, "раз", "раза", "раз"))
                StatsRow(title: "Сделали игру",
                         value: "\(stats.dealsMade) из \(stats.dealsAsBidder) (\(percent(stats.dealsMade, stats.dealsAsBidder)))")
                StatsRow(title: "Байтов", value: "\(stats.baits)")
            }
        }
    }

    private var levelsCard: some View {
        StatsCard(title: "По уровню соперников") {
            let rows = BotLevel.allCases.filter { (stats.byLevel[$0.rawValue]?.played ?? 0) > 0 }
            if rows.isEmpty {
                Text("Партии с соперниками разного уровня сюда не попадают.")
                    .foregroundStyle(Theme.tableSecondaryText)
            } else {
                ForEach(rows, id: \.self) { level in
                    let record = stats.byLevel[level.rawValue] ?? PlayerStats.Record()
                    RecordRow(title: level.title, record: record) {
                        LevelStarsView(level: level, size: 10)
                    }
                }
            }
        }
    }

    private var opponentsCard: some View {
        StatsCard(title: "Против соперников") {
            let rows = Persona.all.filter { (stats.byPersona[$0.id]?.played ?? 0) > 0 }
            if rows.isEmpty {
                Text("Здесь будет счёт с каждым соперником.")
                    .foregroundStyle(Theme.tableSecondaryText)
            } else {
                ForEach(rows) { persona in
                    let record = stats.byPersona[persona.id] ?? PlayerStats.Record()
                    RecordRow(title: persona.name, record: record) {
                        PersonaAvatarView(persona: persona, size: 30)
                    }
                }
            }
        }
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            confirmReset = true
        } label: {
            Label("Стереть статистику", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(TableButtonStyle())
        .padding(.top, 8)
    }

    private func percent(_ part: Int, _ whole: Int) -> String {
        guard whole > 0 else { return "—" }
        // Узкий неразрывный пробел: «33 %» не разрывается и не слипается.
        return "\(Int((Double(part) * 100 / Double(whole)).rounded()))\u{202F}%"
    }
}

/// Плитка с крупным числом.
private struct StatTile: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.tableSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .tableSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

/// Карточка раздела статистики.
private struct StatsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .font(.body)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
    }
}

/// Строка «название — значение».
private struct StatsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.tableText)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.tableText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Строка с победами и полоской доли побед.
private struct RecordRow<Leading: View>: View {
    let title: String
    let record: PlayerStats.Record
    let leading: Leading

    init(title: String, record: PlayerStats.Record, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.record = record
        self.leading = leading()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                leading
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.tableText)
                Spacer(minLength: 8)
                Text("\(record.won) из \(record.played)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.tableText)
            }
            GoalProgressBar(value: record.won, target: max(1, record.played), height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): побед \(record.won) из \(record.played)")
    }
}
