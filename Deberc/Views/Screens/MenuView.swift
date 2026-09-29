import SwiftUI
import DebercKit

/// Главное меню.
///
/// Сверху заставка; если партия идёт — карточка «Продолжить» со счётом, сдачей и соперниками.
/// Ниже — «Новая партия»: сколько игроков, кто соперники (по отдельности, с аватарами),
/// быстрый выбор уровня с пояснением. Внизу — правила, статистика, настройки.
/// На iPad в альбомной ориентации — две колонки.
struct MenuView: View {
    @EnvironmentObject private var store: GameStore
    @State private var sheet: MenuSheet?
    @State private var confirmNewGame = false
    /// Партия идёт — выбор новой партии свёрнут, пока его не попросят.
    @State private var newGameExpanded = false
    /// Значок плитки «Правила / Статистика / Настройки» растёт вместе со шрифтом.
    @ScaledMetric(relativeTo: .title2) private var tileIcon: CGFloat = 28

    enum MenuSheet: String, Identifiable {
        case rules, settings, stats, firstOpponent, secondOpponent
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geo in
            let large = min(geo.size.width, geo.size.height) >= 600
            let wide = geo.size.width > geo.size.height && geo.size.width >= 900
            let short = geo.size.height < 900
            ScrollView {
                Group {
                    if wide {
                        wideLayout(large: large)
                    } else {
                        tallLayout(large: large, short: short, height: geo.size.height)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(FeltBackground())
        .adaptiveTextSize(.screen)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environmentObject(store)
        }
        .alert("Начать новую партию?", isPresented: $confirmNewGame) {
            Button("Начать новую", role: .destructive) { store.newGame() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(lostGameText)
        }
        .onAppear(perform: openRequestedScreen)
    }

    // MARK: - Раскладка

    /// На невысоком экране (iPhone SE, «Увеличенный» вид) у заставки нет подзаголовка, а при идущей
    /// партии — и веера, отступы плотнее: тогда плитки «Правила / Статистика / Настройки» видны
    /// без прокрутки. На самом низком (SE с «Увеличенным» видом) при идущей партии заставки нет вовсе —
    /// заголовок там карточка «Партия идёт».
    private func tallLayout(large: Bool, short: Bool, height: CGFloat) -> some View {
        let tight = height < 700
        return VStack(spacing: tight ? 14 : 20) {
            Spacer(minLength: tight ? 8 : 16)
            if height >= 600 || !store.canContinue {
                BrandMark(large: large, compact: short && !large,
                          showsFan: height >= 740 || !store.canContinue,
                          showsTagline: height >= 740)
            }
            panels(spacing: tight ? 12 : 16)
            footer
            Spacer(minLength: tight ? 8 : 16)
        }
        .frame(maxWidth: large ? 620 : 480)
        .padding(.horizontal, 20)
    }

    private func wideLayout(large: Bool) -> some View {
        HStack(alignment: .center, spacing: 48) {
            VStack(spacing: 24) {
                BrandMark(large: large)
                footer
            }
            .frame(maxWidth: 420)
            VStack(spacing: 20) {
                Spacer(minLength: 16)
                panels(spacing: 16)
                Spacer(minLength: 16)
            }
            .frame(maxWidth: 560)
        }
        .padding(.horizontal, 32)
    }

    private func panels(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            if let problem = store.loadProblem {
                loadProblemBanner(problem)
            }
            if store.canContinue, let match = store.match {
                ContinueCard(match: match) { store.continueGame() }
            }
            if store.canContinue && !newGameExpanded {
                collapsedNewGame
            } else {
                newGamePanel
            }
            secondaryButtons
        }
    }

    // MARK: - Партию не удалось прочитать

    private func loadProblemBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(text)
                    .foregroundStyle(Theme.tableText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.gold)
            }
            .font(.subheadline)
            Button("Понятно") { store.loadProblem = nil }
                .buttonStyle(TableButtonStyle())
        }
        .screenPanel(highlighted: true)
    }

    // MARK: - Новая партия

    /// Свёрнутая «Новая партия» при идущей партии: кто соперники, и кнопка развернуть выбор.
    private var collapsedNewGame: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { newGameExpanded = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "suit.spade.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Новая партия…")
                        .font(.headline)
                        .foregroundStyle(Theme.tableText)
                    // «Втроём · Нина и Миша» в строку, а если тесно — в две, но без переносов посреди имени.
                    ViewThatFits(in: .horizontal) {
                        Text(newGameNames.isEmpty ? newGameCount : "\(newGameCount) · \(newGameNames)")
                            .lineLimit(1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(newGameCount)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            if !newGameNames.isEmpty {
                                Text(newGameNames)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.tableSecondaryText)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tableSurface(cornerRadius: 22, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Выбрать соперников и начать новую партию")
    }

    /// «Вдвоём» / «Втроём».
    private var newGameCount: String {
        store.settings.playerCount == 3 ? "Втроём" : "Вдвоём"
    }

    /// «Саша» / «Нина и Миша».
    private var newGameNames: String {
        store.settings.activeOpponentIDs.compactMap { Persona.byID($0)?.name }.joined(separator: " и ")
    }

    private var newGamePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Новая партия")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.tableText)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 8) {
                caption("Игроков")
                ChoiceRow(title: "Игроков",
                          options: [ChoiceOption(2, "Вдвоём"), ChoiceOption(3, "Втроём")],
                          selected: store.settings.playerCount) { count in
                    store.settings.playerCount = count
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                caption(store.settings.playerCount == 2 ? "Соперник" : "Соперники")
                ForEach(0 ..< max(1, store.settings.playerCount - 1), id: \.self) { slot in
                    opponentButton(slot)
                }
            }

            levelPicker

            if let advice = LevelAdvice.forMenu(stats: store.stats, selected: selectedLevel) {
                adviceRow(advice)
            }

            if store.canContinue {
                Text("Соперники, уровень и правила — для новой партии. Идущая партия доигрывается как была.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if store.canContinue {
                    confirmNewGame = true
                } else {
                    store.newGame()
                }
            } label: {
                Label(store.canContinue ? "Начать новую партию" : "Начать партию", systemImage: "suit.spade.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle(prominent: !store.canContinue))
        }
        .screenPanel()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.tableSecondaryText)
            .accessibilityHidden(true)
    }

    private func opponent(_ slot: Int) -> Persona? {
        let ids = store.settings.opponentIDs
        return ids.indices.contains(slot) ? Persona.byID(ids[slot]) : nil
    }

    @ViewBuilder
    private func opponentButton(_ slot: Int) -> some View {
        if let persona = opponent(slot) {
            let style = persona.style.title(feminine: persona.feminine)
            Button {
                sheet = slot == 0 ? .firstOpponent : .secondOpponent
            } label: {
                HStack(spacing: 12) {
                    PersonaAvatarView(persona: persona, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(persona.name)
                            .font(.headline)
                            .foregroundStyle(Theme.tableText)
                        HStack(spacing: 6) {
                            LevelStarsView(level: persona.level)
                            Text("\(persona.level.title) · \(style)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.tableSecondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 6)
                    Text("Сменить")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.24)))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Соперник: \(persona.name), \(persona.level.title), \(style)")
            .accessibilityHint("Выбрать другого соперника")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// Общий уровень выбранных соперников (nil — разного уровня).
    private var selectedLevel: BotLevel? {
        let levels = Set(store.settings.activeOpponentIDs.compactMap { Persona.byID($0)?.level })
        return levels.count == 1 ? levels.first : nil
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Уровень")
            ChoiceRow(title: "Уровень соперников",
                      options: BotLevel.allCases.map { ChoiceOption($0, $0.title) },
                      selected: selectedLevel) { level in
                chooseLevel(level)
            }
            Text(selectedLevel?.subtitle ?? "Соперники разного уровня — выбраны по отдельности.")
                .font(.footnote)
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Быстрый выбор уровня: подбирает соперников этого уровня.
    private func chooseLevel(_ level: BotLevel) {
        var settings = store.settings
        settings.difficulty = level
        settings.opponentIDs = AppSettings.defaultOpponentIDs(for: level)
        if settings != store.settings {
            store.settings = settings
        }
    }

    private func adviceRow(_ advice: LevelAdvice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(advice.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.tableText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(advice.buttonTitle) { chooseLevel(advice.level) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    // MARK: - Второстепенное

    /// Плитки равной ширины. Подписи у всех одним кеглем: не помещаются словом целиком — все мельче.
    private var secondaryButtons: some View {
        ViewThatFits(in: .horizontal) {
            tiles(font: nil)
            tiles(font: .subheadline.weight(.semibold))
        }
    }

    /// `font` — nil: кегль из стиля плитки.
    private func tiles(font: Font?) -> some View {
        EqualWidthHStack(spacing: 10) {
            tile("Правила", icon: "book", sheet: .rules, font: font)
            tile("Статистика", icon: "chart.bar", sheet: .stats, font: font)
            tile("Настройки", icon: "gearshape", sheet: .settings, font: font)
        }
    }

    private func tile(_ title: String, icon: String, sheet target: MenuSheet, font: Font?) -> some View {
        Button {
            sheet = target
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(height: tileIcon)
                    .accessibilityHidden(true)
                if let font {
                    // Запасной кегль тоже не влез («Увеличенный» вид и крупный режим) — лучше мельче,
                    // чем «Статисти…».
                    Text(title)
                        .font(font)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(title)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(title)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(footerText)
                .font(.footnote)
                .foregroundStyle(Theme.tableSecondaryText)
                .multilineTextAlignment(.center)
            // В сборке из App Store ссылка — только в Настройках → О приложении.
            if store.match != nil && AppInfo.isTestBuild {
                ProblemReportLink()
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
        }
    }

    private var footerText: String {
        let rules = store.settings.rules
        let kind = rules == .house ? RulesText.housePhrase : "правила изменены в настройках"
        return "Новая партия — до \(Narrator.pointsGenitive(rules.targetScore)), \(kind)"
    }

    // MARK: - Листы

    @ViewBuilder
    private func sheetContent(_ sheet: MenuSheet) -> some View {
        switch sheet {
        case .rules:
            if store.canContinue, let match = store.match {
                RulesView(rules: match.rules, newGameRules: store.settings.rules)
            } else {
                RulesView(rules: store.settings.rules)
            }
        case .settings:
            SettingsView()
        case .stats:
            StatsView()
        case .firstOpponent:
            OpponentPickerView(slot: 0)
        case .secondOpponent:
            OpponentPickerView(slot: 1)
        }
    }

    private var lostGameText: String {
        guard let match = store.match else { return "Текущая партия будет потеряна." }
        let score = match.totals.map { Narrator.number($0) }.joined(separator: " : ")
        return "Текущая партия (счёт \(score)) будет потеряна."
    }

    /// Экран из аргумента запуска `-DebercScreen` (скриншоты, проверка в CI).
    private func openRequestedScreen() {
        switch store.requestedScreen {
        case "settings"?: sheet = .settings
        case "rules"?: sheet = .rules
        case "stats"?: sheet = .stats
        case "opponents"?: sheet = .firstOpponent
        default: return
        }
        store.requestedScreen = nil
    }
}

/// Карточка идущей партии: сдача, счёт каждого с полоской до цели, «Продолжить».
struct ContinueCard: View {
    @EnvironmentObject private var store: GameStore
    let match: Match
    let onContinue: () -> Void

    /// Номер сдачи: идущей или только что сыгранной.
    private var dealNumber: Int { max(1, match.dealCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Заголовок и сдача — в строку, а если тесно — друг под другом (без переносов по словам).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 8)
                    dealLine
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    dealLine
                }
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 10) {
                ForEach(0 ..< match.playerCount, id: \.self) { seat in
                    playerRow(seat)
                }
            }
            Button(action: onContinue) {
                // Всегда в одну строку: тесно — без значка, ещё теснее — короче.
                ViewThatFits(in: .horizontal) {
                    Label("Продолжить партию", systemImage: "play.fill")
                    Text("Продолжить партию")
                    Label("Продолжить", systemImage: "play.fill")
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Продолжить партию")
            .buttonStyle(TableButtonStyle(prominent: true))
        }
        .screenPanel(highlighted: true)
    }

    private var title: some View {
        Text("Партия идёт")
            .font(.title2.weight(.bold))
            .foregroundStyle(Theme.tableText)
            .lineLimit(1)
    }

    private var dealLine: some View {
        Text("сдача \(dealNumber) · до \(match.rules.targetScore)")
            .font(.subheadline)
            .foregroundStyle(Theme.tableSecondaryText)
            .lineLimit(1)
    }

    private func playerRow(_ seat: Int) -> some View {
        let total = match.totals[seat]
        let top = match.totals.max() ?? 0
        let leading = total == top && total > 0
        let persona = store.persona(for: seat)
        return HStack(spacing: 10) {
            PlayerAvatarView(persona: persona, humanName: store.settings.playerName, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(store.displayName(for: seat))
                        .font(.headline)
                        .foregroundStyle(Theme.tableText)
                    if let persona {
                        LevelStarsView(level: persona.level, size: 9)
                    }
                    Spacer(minLength: 6)
                    Text(Narrator.number(total))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(leading ? Theme.gold : Theme.tableText)
                }
                GoalProgressBar(value: total, target: match.rules.targetScore,
                                  tint: leading ? Theme.gold : Theme.tableSecondaryText.opacity(0.8))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.displayName(for: seat)): \(Narrator.points(total))")
    }
}
