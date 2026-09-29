import SwiftUI
import DebercKit

/// Что стол может попросить у экрана: открыть лист, выйти.
struct TableCommands {
    var showScoreSheet: () -> Void = {}
    var showRules: () -> Void = {}
    var showSettings: () -> Void = {}
    var showLastTrick: () -> Void = {}
    /// Карточка соперника на месте (характер, уровень, счёт против него).
    var showPersona: (Int) -> Void = { _ in }
    /// Меню стола (≡).
    var showMenu: () -> Void = {}
    var leave: () -> Void = {}
}

/// Верхняя полоса стола: меню и козырь; вдвоём между ними — соперник, под ним его карты и взятки.
/// Колода лежит на столе у левого края, номер сдачи и цель партии — вертикальной надписью
/// у правого (`TableDecorations`); висячие очки и пересдачи — золотом под козырем (`PotChip`).
struct TableTopBar: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let match: Match
    let deal: Deal
    let metrics: TableMetrics
    let commands: TableCommands
    /// Соперник вдвоём (втроём соперники сидят строкой ниже).
    var opponent: SeatInfo? = nil
    var canShowLastTrick = false

    /// Только что назначили козырь — индикатор ненадолго вспыхивает.
    @State private var trumpFlash = false

    var body: some View {
        Group {
            if let opponent {
                // Одна полоса или две — решено заранее по ширине окна и размеру текста (`opponentInTopBar`),
                // а не по нынешнему счёту: полоса не перескакивает посреди партии. В одной полосе плашка
                // сама убирает звёзды и полоску прогресса, если счёт длинный.
                if metrics.opponentInTopBar {
                    topRow(opponent)
                } else {
                    VStack(spacing: metrics.spacing) {
                        barRow
                        OpponentCluster(info: opponent, metrics: metrics, commands: commands,
                                        canShowLastTrick: canShowLastTrick)
                    }
                }
            } else {
                barRow
            }
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.top, metrics.topPadding)
        // Смена варианта раскладки (козырь стал шире) — сразу, без затухания:
        // иначе на миг видны пустые стеклянные рамки.
        .transaction { $0.animation = nil }
        .onChange(of: deal.trump) { trump in
            guard trump != nil, !reduceMotion else { return }
            trumpFlash = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                trumpFlash = false
            }
        }
    }

    /// Вдвоём: меню, соперник, справа — козырь и под ним висячие очки (место есть: плашка с веером выше козыря).
    /// Козырь и меню — по своему размеру, всё сжатие достаётся плашке соперника.
    private func topRow(_ opponent: SeatInfo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            menuButton
            Spacer(minLength: 0)
            OpponentCluster(info: opponent, metrics: metrics, commands: commands,
                            canShowLastTrick: canShowLastTrick)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                trumpBadge(detail: nil)
                    .fixedSize()
                potChip
            }
        }
    }

    /// Меню — и козырь справа (висячие очки — рядом с ним).
    private var barRow: some View {
        HStack(spacing: 8) {
            menuButton
            Spacer(minLength: 4)
            potChip
            ViewThatFits(in: .horizontal) {
                trumpBadge(detail: trumpDetail)
                trumpBadge(detail: nil)
                trumpBadge(detail: nil, compact: true)
            }
        }
        .frame(height: metrics.topBarHeight)
    }

    private var menuButton: some View {
        TableMenuButton(commands: commands, size: menuSize)
    }

    private var menuSize: CGFloat { metrics.roomy ? 50 : 44 }

    /// На iPad в альбомной ориентации висячие очки — в панели справа.
    @ViewBuilder
    private var potChip: some View {
        if !metrics.wide, let text = PotChip.text(pot: match.pot, redeals: redeals,
                                                   forcedAfter: match.rules.forcedDealAfterRedeals) {
            PotChip(text: text)
        }
    }

    /// Пересдачи подряд до обязов — пока идёт торговля: когда козырь взят (или сдача на обязах),
    /// обязов из этой серии уже не будет.
    private var redeals: Int { deal.forced || deal.trump != nil ? 0 : match.allPassStreak }

    private func trumpBadge(detail: String?, compact: Bool = false) -> some View {
        let round: Int?
        if case .bidding(let r) = deal.phase {
            round = r
        } else if deal.allPassed {
            round = 0
        } else {
            round = nil
        }
        return TrumpBadge(trump: deal.trump, detail: detail, biddingRound: round,
                          height: metrics.topBarHeight, compact: compact, forced: deal.forced)
            .scaleEffect(trumpFlash ? 1.1 : 1, anchor: .trailing)
            .shadow(color: Theme.gold.opacity(trumpFlash ? 0.75 : 0), radius: trumpFlash ? 10 : 0)
            .animation(trumpFlash ? .spring(response: 0.3, dampingFraction: 0.55) : .easeOut(duration: 0.45),
                       value: trumpFlash)
            .accessibilityValue(matchSpoken)
    }

    private var trumpDetail: String? {
        guard let bidder = deal.bidder else { return nil }
        let who = bidder == store.humanSeat ? "Вы играете" : "играет \(store.displayName(for: bidder))"
        return deal.forced ? "обязы · " + who : who
    }

    /// Номер сдачи, цель партии, висячие очки и пересдачи до обязов — для VoiceOver
    /// (на экране — вертикальная надпись у края стола и золотая строка под козырем).
    private var matchSpoken: String {
        var parts = ["сдача \(max(1, match.dealCount))", "партия до \(match.rules.targetScore)"]
        if match.pot > 0 {
            parts.append("висят \(match.pot) \(TableText.plural(match.pot, "очко", "очка", "очков"))")
        }
        let forcedAfter = match.rules.forcedDealAfterRedeals
        if redeals > 0 && forcedAfter > 0 {
            parts.append("пересдач \(redeals) из \(forcedAfter), дальше обязы")
        }
        return parts.joined(separator: ", ")
    }
}

/// Соперник вдвоём: плашка, под ней — его карты рубашкой и стопка взяток.
struct OpponentCluster: View {
    let info: SeatInfo
    let metrics: TableMetrics
    let commands: TableCommands
    let canShowLastTrick: Bool

    var body: some View {
        VStack(spacing: 4) {
            SeatPlate(info: info, avatarSize: metrics.avatarSize, maxWidth: metrics.roomy ? 320 : 230,
                      onTap: { commands.showPersona(info.seat) })
                .tableSlot(.seat(info.seat))
            // Веер — ровно под плашкой, стопка взяток — слева от него (в ширину полосы не входит):
            // слева под кнопкой меню пусто, а справа под козырем стоят висячие очки и пересдачи.
            FanSlot(seat: info.seat, metrics: metrics)
                .overlay(alignment: .leading) {
                    PileSlot(seat: info.seat, owner: info.name, tricks: info.tricks, metrics: metrics,
                             enabled: canShowLastTrick, onTap: commands.showLastTrick)
                        .offset(x: -(metrics.pileSlotSize.width + 8))
                }
        }
    }
}

/// Кнопка меню стола (≡): открывает меню стола (`TableMenuPanel`). Та же кнопка лежит поверх окна итогов,
/// чтобы между сдачами можно было открыть запись, настройки или выйти.
struct TableMenuButton: View {
    let commands: TableCommands
    var size: CGFloat = 44

    var body: some View {
        Button(action: commands.showMenu) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Theme.tableText)
                .frame(width: size, height: size)
                .tableSurface(cornerRadius: size / 2, interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Меню")
    }
}

/// Меню стола — своей карточкой, а не системным меню: пока она открыта, игра стоит на паузе
/// (у системного меню нет события «открылось», и соперники ходили, пока человек читал пункты),
/// а крупные строки легче читать и нажимать. Быстрых настроек — только звук и вибрация:
/// скорость, автоход и прочее меняются в настройках, где у каждого пункта есть пояснение.
struct TableMenuPanel: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.tableLargeControls) private var large
    let commands: TableCommands
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            // Не помещается по высоте (маленький экран, крупный текст) — прокручивается.
            ViewThatFits(in: .vertical) {
                items
                ScrollView(showsIndicators: false) {
                    items
                }
            }
            .frame(maxWidth: 400)
            .modalCard(cornerRadius: 26)
            .padding(16)
            .modalPanelAccessibility(onClose: onClose)
        }
    }

    private var items: some View {
        VStack(spacing: 10) {
            Text("Меню")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.tableText)
                .accessibilityAddTraits(.isHeader)
            item("Запись партии", icon: "list.number", perform: commands.showScoreSheet)
            if store.lastTrick != nil {
                item("Последняя взятка", icon: "eye", perform: commands.showLastTrick)
            }
            item("Правила", icon: "book", perform: commands.showRules)
            if !store.showDealSummary {
                if store.isHumanTurn {
                    item("Подсказка", icon: "lightbulb") { store.showHint() }
                }
                if store.canUndo {
                    item("Отменить ход", icon: "arrow.uturn.backward") { store.undo() }
                }
            }
            toggle("Звук", icon: "speaker.wave.2", isOn: $store.settings.soundEnabled)
            // На iPad вибрации нет — как и в настройках.
            if !AppInfo.isPad {
                toggle("Вибрация", icon: "iphone.radiowaves.left.and.right", isOn: $store.settings.hapticsEnabled)
            }
            item("Все настройки…", icon: "gearshape", perform: commands.showSettings)
            item("Выйти в меню", icon: "house", perform: commands.leave)
            // Игра стоит, пока открыто меню, — главная кнопка говорит, что будет дальше.
            Button(action: onClose) {
                Text(store.showDealSummary ? "Закрыть" : "Продолжить игру")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle(prominent: true))
            .padding(.top, 4)
        }
        .padding(20)
    }

    /// Пункт меню: сначала меню закрывается, потом открывается лист (игра остаётся на паузе — лист тоже пауза).
    private func item(_ title: String, icon: String, perform action: @escaping () -> Void) -> some View {
        Button {
            onClose()
            action()
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TableButtonStyle())
    }

    private func toggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon)
                .font(large ? Font.title3.weight(.semibold) : Font.headline)
                .foregroundStyle(Theme.tableText)
        }
        .tint(Theme.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: large ? 60 : 48)
        .tableSurface(cornerRadius: large ? 16 : 14)
    }
}
