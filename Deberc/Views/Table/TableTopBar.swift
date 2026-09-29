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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let match: Match
    let deal: Deal
    let metrics: TableMetrics
    let commands: TableCommands

    /// Только что назначили козырь — индикатор ненадолго вспыхивает.
    @State private var trumpFlash = false

    var body: some View {
        HStack(spacing: 8) {
            TableMenuButton(commands: commands, inSummary: false, size: menuSize)
            deckSlot
            Spacer(minLength: 4)
            // Главное справа — козырь словом; цель партии и кто играет — если помещаются.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    matchInfo
                    trumpBadge(detail: trumpDetail)
                }
                HStack(spacing: 8) {
                    matchInfo
                    trumpBadge(detail: nil)
                }
                trumpBadge(detail: nil)
                trumpBadge(detail: nil, compact: true)
            }
            .scaleEffect(trumpFlash ? 1.1 : 1, anchor: .trailing)
            .shadow(color: Theme.gold.opacity(trumpFlash ? 0.75 : 0), radius: trumpFlash ? 10 : 0)
        }
        .padding(.horizontal, metrics.gutter)
        .frame(height: metrics.topBarHeight)
        .onChange(of: deal.trump) { trump in
            guard trump != nil, !reduceMotion else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { trumpFlash = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                withAnimation(.easeOut(duration: 0.45)) { trumpFlash = false }
            }
        }
    }

    private var matchInfo: some View {
        MatchInfoBadge(target: match.rules.targetScore, pot: match.pot,
                       redeals: deal.forced ? 0 : match.allPassStreak,
                       forcedAfter: match.rules.forcedDealAfterRedeals)
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
                // Подпись «низ» слой карт кладёт прямо на карту: рядом с ней места нет — оно нужно козырю справа.
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
