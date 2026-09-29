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
    var leave: () -> Void = {}
}

/// Верхняя полоса стола: меню и козырь; вдвоём между ними — соперник, под ним его карты и взятки.
/// Колода лежит на столе у левого края, цель партии и висячие очки — вертикальной надписью
/// у правого (`TableDecorations`).
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
                // Соперник — в одной полосе с меню и козырем (тесно — без звёзд уровня); иначе — строкой ниже.
                ViewThatFits(in: .horizontal) {
                    topRow(opponent, stars: true)
                    topRow(opponent, stars: false)
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
        // Смена варианта раскладки (козырь стал шире, соперник переехал) — сразу, без затухания:
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

    private func topRow(_ opponent: SeatInfo, stars: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            menuButton
            Spacer(minLength: 0)
            OpponentCluster(info: opponent, metrics: metrics, commands: commands,
                            canShowLastTrick: canShowLastTrick, showsStars: stars)
            Spacer(minLength: 0)
            trumpBadge(detail: nil)
        }
    }

    /// Меню — и козырь справа.
    private var barRow: some View {
        HStack(spacing: 8) {
            menuButton
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                trumpBadge(detail: trumpDetail)
                trumpBadge(detail: nil)
                trumpBadge(detail: nil, compact: true)
            }
        }
        .frame(height: metrics.topBarHeight)
    }

    private var menuButton: some View {
        TableMenuButton(commands: commands, inSummary: false, size: menuSize)
    }

    private var menuSize: CGFloat { metrics.roomy ? 50 : 44 }

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
                          height: metrics.topBarHeight, compact: compact)
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

    /// Цель партии и висячие очки — для VoiceOver (на экране — вертикальная надпись у края стола).
    private var matchSpoken: String {
        var text = "партия до \(match.rules.targetScore)"
        if match.pot > 0 { text += ", висят \(match.pot) \(TableText.plural(match.pot, "очко", "очка", "очков"))" }
        return text
    }
}

/// Соперник вдвоём: плашка, под ней — его карты рубашкой и стопка взяток.
struct OpponentCluster: View {
    let info: SeatInfo
    let metrics: TableMetrics
    let commands: TableCommands
    let canShowLastTrick: Bool
    var showsStars = true

    var body: some View {
        VStack(spacing: 4) {
            SeatPlate(info: info, avatarSize: metrics.avatarSize, maxWidth: metrics.roomy ? 320 : 230,
                      showsStars: showsStars, onTap: { commands.showPersona(info.seat) })
                .tableSlot(.seat(info.seat))
            // Веер — ровно под плашкой, стопка взяток — справа от него (в ширину полосы не входит).
            FanSlot(seat: info.seat, metrics: metrics)
                .overlay(alignment: .trailing) {
                    PileSlot(seat: info.seat, tricks: info.tricks, metrics: metrics,
                             enabled: canShowLastTrick, onTap: commands.showLastTrick)
                        .offset(x: metrics.pileSlotSize.width + 8)
                }
        }
    }
}

/// Кнопка меню стола (≡). Та же кнопка лежит поверх окна итогов, чтобы между сдачами
/// можно было открыть запись, настройки или выйти.
struct TableMenuButton: View {
    @EnvironmentObject private var store: GameStore
    let commands: TableCommands
    let inSummary: Bool
    var size: CGFloat = 44

    var body: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Theme.tableText)
                .frame(width: size, height: size)
                .tableSurface(cornerRadius: size / 2, interactive: true)
                .contentShape(Circle())
        }
        .accessibilityLabel("Меню")
    }

    @ViewBuilder
    private var menuContent: some View {
        Section {
            Button(action: commands.showScoreSheet) {
                Label("Запись партии", systemImage: "list.number")
            }
            if store.lastTrick != nil {
                Button(action: commands.showLastTrick) {
                    Label("Последняя взятка", systemImage: "eye")
                }
            }
            Button(action: commands.showRules) {
                Label("Правила", systemImage: "book")
            }
        }
        if !inSummary && (store.isHumanTurn || store.canUndo) {
            Section {
                if store.isHumanTurn {
                    Button {
                        store.showHint()
                    } label: {
                        Label("Подсказка", systemImage: "lightbulb")
                    }
                }
                if store.canUndo {
                    Button {
                        store.undo()
                    } label: {
                        Label("Отменить ход", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        Section("Быстрые настройки") {
            Picker(selection: $store.settings.speed) {
                ForEach(GameSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            } label: {
                Label("Скорость: \(store.settings.speed.title.lowercased())", systemImage: "speedometer")
            }
            .pickerStyle(.menu)
            Toggle(isOn: $store.settings.confirmCardTap) {
                Label("Ход двойным касанием", systemImage: "hand.tap")
            }
            Picker(selection: $store.settings.autoPlay) {
                ForEach(AutoPlay.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("Автоход: \(store.settings.autoPlay.title.lowercased())", systemImage: "wand.and.stars")
            }
            .pickerStyle(.menu)
            Toggle(isOn: $store.settings.soundEnabled) {
                Label("Звук", systemImage: "speaker.wave.2")
            }
            // На iPad вибрации нет — как и в настройках.
            if !AppInfo.isPad {
                Toggle(isOn: $store.settings.hapticsEnabled) {
                    Label("Вибрация", systemImage: "iphone.radiowaves.left.and.right")
                }
            }
            Button(action: commands.showSettings) {
                Label("Все настройки…", systemImage: "gearshape")
            }
        }
        Section {
            Button(action: commands.leave) {
                Label("Выйти в меню", systemImage: "house")
            }
        }
    }
}
