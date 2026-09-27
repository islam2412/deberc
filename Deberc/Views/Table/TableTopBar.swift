import SwiftUI
import DebercKit

/// Что стол может попросить у экрана: открыть лист, выйти.
struct TableCommands {
    var showScoreSheet: () -> Void = {}
    var showRules: () -> Void = {}
    var showSettings: () -> Void = {}
    var showLastTrick: () -> Void = {}
    var leave: () -> Void = {}
}

/// Верхняя полоса стола: меню, колода с открытой и нижней картой, цель партии, козырь.
struct TableTopBar: View {
    @EnvironmentObject private var store: GameStore
    let match: Match
    let deal: Deal
    let metrics: TableMetrics
    let commands: TableCommands

    var body: some View {
        HStack(spacing: 8) {
            TableMenuButton(commands: commands, inSummary: false, size: menuSize)
            deckSlot
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                MatchInfoBadge(target: match.rules.targetScore, pot: match.pot,
                               redeals: deal.forced ? 0 : match.allPassStreak,
                               forcedAfter: match.rules.forcedDealAfterRedeals)
                Color.clear.frame(width: 0, height: 0)
            }
            trumpBadge
        }
        .padding(.horizontal, metrics.gutter)
        .frame(height: metrics.topBarHeight)
    }

    private var menuSize: CGFloat { metrics.roomy ? 50 : 44 }

    /// Место для колоды: карты рисует слой карт, здесь — только рамка и подпись «низ».
    private var deckSlot: some View {
        let size = metrics.deckSlotSize
        return HStack(spacing: 6) {
            Color.clear
                .frame(width: size.width, height: size.height)
                .tableSlot(.deck)
            if deal.bottomCardVisible, deal.bottomCard != nil {
                Text("низ")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.tableSecondaryText)
                    .fixedSize()
                Color.clear
                    .frame(width: metrics.miniCardWidth, height: size.height)
                    .tableSlot(.bottom)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deckDescription)
    }

    private var deckDescription: String {
        var parts = ["Открытая карта: \(CardView.spokenName(deal.openCard))"]
        if deal.bottomCardVisible, let bottom = deal.bottomCard {
            parts.append("нижняя карта: \(CardView.spokenName(bottom))")
        }
        return parts.joined(separator: ", ")
    }

    private var trumpBadge: some View {
        let round: Int?
        if case .bidding(let r) = deal.phase {
            round = r
        } else if deal.allPassed {
            round = 0
        } else {
            round = nil
        }
        return ViewThatFits(in: .horizontal) {
            TrumpBadge(trump: deal.trump, detail: trumpDetail, biddingRound: round, height: metrics.topBarHeight)
            TrumpBadge(trump: deal.trump, detail: nil, biddingRound: round, height: metrics.topBarHeight)
        }
    }

    private var trumpDetail: String? {
        guard let bidder = deal.bidder else { return nil }
        let who = bidder == store.humanSeat ? "Вы играете" : "играет \(store.displayName(for: bidder))"
        return deal.forced ? "обязы · " + who : who
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
