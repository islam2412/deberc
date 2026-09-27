import SwiftUI
import DebercKit

/// Что на экране: приветствие при первом запуске, меню или стол; поверх стола —
/// экран конца партии. Здесь же задаются вид карт и крупный режим для всего приложения.
///
/// Экраны из аргумента запуска `-DebercScreen` открывают сами экраны: меню — настройки,
/// правила и статистику, стол — запись партии; итоги и конец партии готовит магазин,
/// приветствие показывается само (`hasSeenOnboarding == false`).
struct RootView: View {
    @EnvironmentObject private var store: GameStore

    /// Партия окончена, итоги открыты — праздник или «Партия окончена» во весь экран.
    private var showsMatchOver: Bool {
        store.isInGame && store.showDealSummary && (store.match?.isOver ?? false)
    }

    var body: some View {
        ZStack {
            if !store.settings.hasSeenOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else if store.isInGame {
                GameView()
                    .accessibilityHidden(showsMatchOver)
                    .transition(.opacity)
                if showsMatchOver, let match = store.match {
                    MatchOverView(match: match)
                        .transition(.opacity)
                        .zIndex(1)
                }
            } else {
                MenuView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.isInGame)
        .animation(.easeInOut(duration: 0.4), value: showsMatchOver)
        .animation(.easeInOut(duration: 0.3), value: store.settings.hasSeenOnboarding)
        .cardAppearance(fourColor: store.settings.fourColorDeck, largeIndex: store.settings.largeCards)
        .environment(\.tableLargeControls, store.settings.largeCards)
    }
}
