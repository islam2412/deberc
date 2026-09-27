import SwiftUI
import DebercKit

/// Приветствие при первом запуске — одна страница: что это за игра, три подсказки,
/// как вас называть. «Играть» — сразу за стол, «Выбрать соперников» — в меню.
struct OnboardingView: View {
    @EnvironmentObject private var store: GameStore
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let large = min(geo.size.width, geo.size.height) >= 600
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 12)
                    BrandMark(large: large, compact: true, showsTagline: false)
                    intro
                    hints
                    nameField
                    buttons
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: large ? 600 : 480)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(FeltBackground())
        .adaptiveTextSize(.screen)
        .onAppear {
            let current = store.settings.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            name = current == "Вы" ? "" : current
        }
    }

    private var intro: some View {
        VStack(spacing: 8) {
            Text("Добро пожаловать!")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.tableText)
                .accessibilityAddTraits(.isHeader)
            Text("Деберц по вашим домашним правилам: партия до 701, обязы, байты и штрафы уже настроены.")
                .font(.body)
                .foregroundStyle(Theme.tableSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 16) {
            HintRow(icon: "hand.tap",
                    text: "Коснитесь карты — она приподнимется. Коснитесь ещё раз или смахните вверх — сходите.")
            HintRow(icon: "line.3.horizontal.circle",
                    text: "В меню стола — запись партии, правила, подсказка, отмена хода и настройки.")
            HintRow(icon: "slider.horizontal.3",
                    text: "Любое правило можно поменять: Настройки → Правила партии.")
            HintRow(icon: "star.fill",
                    text: "Золотая звёздочка на карте — козырь, золотое свечение — картой можно ходить.")
        }
        .screenPanel()
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Как вас называть?")
                .font(.headline)
                .foregroundStyle(Theme.tableText)
            TextField("Например, Папа", text: $name)
                .font(.title3)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { nameFocused = false }
                .onChange(of: name) { value in
                    if value.count > SettingsView.nameLimit {
                        name = String(value.prefix(SettingsView.nameLimit))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(nameFocused ? Theme.gold : Theme.panelStroke, lineWidth: nameFocused ? 2 : 1))
                .foregroundStyle(Theme.tableText)
            Text("Так вас подпишут в записи партии и в итогах. Можно оставить пустым — будет «Вы».")
                .font(.footnote)
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                finish(startGame: true)
            } label: {
                Label(store.canContinue ? "Продолжить партию" : "Играть", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle(prominent: true))
            .accessibilityHint(store.canContinue ? "Вернуться к сохранённой партии" : "Партия вдвоём с соперником-любителем")

            Button {
                finish(startGame: false)
            } label: {
                Label("Выбрать соперников", systemImage: "person.2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle())
        }
    }

    private func finish(startGame: Bool) {
        nameFocused = false
        var settings = store.settings
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.playerName = trimmed.isEmpty ? "Вы" : String(trimmed.prefix(SettingsView.nameLimit))
        settings.hasSeenOnboarding = true
        store.settings = settings
        if store.requestedScreen == "onboarding" { store.requestedScreen = nil }
        if startGame {
            // Сохранённая (в том числе из прошлой версии) партия не должна пропасть молча.
            if store.canContinue { store.continueGame() } else { store.newGame() }
        }
    }
}

/// Подсказка приветствия: значок и текст.
private struct HintRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.gold)
                .frame(width: 34)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.tableText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
