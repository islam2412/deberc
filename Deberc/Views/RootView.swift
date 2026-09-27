import SwiftUI
import DebercKit

struct RootView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        ZStack {
            if store.isInGame {
                GameView()
                    .transition(.opacity)
            } else {
                MenuView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.isInGame)
    }
}

/// Главное меню.
struct MenuView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showRules = false
    @State private var showSettings = false
    @State private var confirmNewGame = false

    var body: some View {
        ZStack {
            FeltBackground()
            GeometryReader { geo in
                let isLarge = min(geo.size.width, geo.size.height) >= 600
                ScrollView {
                    menuContent(isLarge: isLarge)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height)
                }
                .dynamicTypeSize(isLarge ? max(dynamicTypeSize, .xxxLarge) : dynamicTypeSize)
            }
        }
        .sheet(isPresented: $showRules) {
            RulesView(rules: store.settings.rules)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .confirmationDialog("Начать новую партию?", isPresented: $confirmNewGame, titleVisibility: .visible) {
            Button("Начать новую", role: .destructive) { store.newGame() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текущая партия будет потеряна.")
        }
    }

    private func menuContent(isLarge: Bool) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)
            title(isLarge: isLarge)

            VStack(spacing: 14) {
                if store.canContinue {
                    Button {
                        store.continueGame()
                    } label: {
                        Label("Продолжить партию", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TableButtonStyle(prominent: true))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Игроков")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Picker("Игроков", selection: $store.settings.playerCount) {
                        Text("Вдвоём").tag(2)
                        Text("Втроём").tag(3)
                    }
                    .pickerStyle(.segmented)

                    Text("Сложность")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 6)
                    Picker("Сложность", selection: $store.settings.botLevel) {
                        ForEach(BotLevel.allCases, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.22)))

                Button {
                    if store.canContinue {
                        confirmNewGame = true
                    } else {
                        store.newGame()
                    }
                } label: {
                    Label("Новая партия", systemImage: "suit.spade.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TableButtonStyle(prominent: !store.canContinue))

                HStack(spacing: 12) {
                    Button {
                        showRules = true
                    } label: {
                        Label("Правила", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TableButtonStyle())

                    Button {
                        showSettings = true
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TableButtonStyle())
                }
            }
            .frame(maxWidth: isLarge ? 600 : 440)
            .padding(.horizontal, 24)

            Text("Партия до \(Narrator.pointsGenitive(store.settings.rules.targetScore))")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 24)
        }
    }

    private func title(isLarge: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("♠\u{FE0E}").foregroundStyle(.white)
                Text("♥\u{FE0E}").foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                Text("♣\u{FE0E}").foregroundStyle(.white)
                Text("♦\u{FE0E}").foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
            }
            .font(.system(size: isLarge ? 48 : 34))
            Text("Деберц")
                .font(.system(size: isLarge ? 84 : 56, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            Text("по нашим правилам")
                .font(.headline)
                .foregroundStyle(Theme.gold)
        }
    }
}
