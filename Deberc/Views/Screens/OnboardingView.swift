import SwiftUI
import DebercKit

/// Приветствие при первом запуске — одна страница: что это за игра, крупный режим, подсказки
/// и как вас называть. «Играть» (всегда внизу экрана) — сразу за стол, «Выбрать соперников» — в меню.
struct OnboardingView: View {
    @EnvironmentObject private var store: GameStore
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        GeometryReader { screen in
            let large = min(screen.size.width, screen.size.height) >= 600
            let width: CGFloat = large ? 600 : 480
            // «Играть» не прокручивается — он внизу всегда; страница прокручивается над ним.
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 22) {
                            Spacer(minLength: 12)
                            BrandMark(large: large, compact: true, showsTagline: false)
                            intro
                            // Крупный режим — сразу под приветствием: кому мелко, увидит его без прокрутки.
                            largeModeToggle
                            hints
                            nameField
                            Spacer(minLength: 28)
                        }
                        .frame(maxWidth: width)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .bottomFade()
                }
                buttons
                    .frame(maxWidth: width)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    // Кнопкам — вся нужная им высота (крупный шрифт на узком экране — в две-три строки),
                    // странице — остаток. Без этого VStack делит экран пополам и сжимает кнопки.
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
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
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Деберц \(RulesText.housePhrase): партия до \(store.settings.rules.targetScore), обязы, байты и штрафы уже настроены.")
                .font(.body)
                .foregroundStyle(Theme.tableSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 16) {
            HintRow(icon: "hand.tap",
                    text: "Коснитесь карты — она приподнимется, коснитесь ещё раз — сходите. Или просто бросьте карту пальцем вверх, к центру стола.")
            HintRow(icon: "hand.point.up.left",
                    text: "Подержите палец на карте — она покажется крупно. Хода при этом не будет.")
            HintRow(icon: "line.3.horizontal.circle",
                    text: "В меню стола — запись партии, правила, совет, отмена хода и настройки.")
            HintRow(icon: "slider.horizontal.3",
                    text: "Любое правило можно поменять: Настройки → Правила партии.")
            HintRow(icon: "star.fill",
                    text: "Золотая звёздочка на карте — козырь, золотое свечение — картой можно ходить. Масть вверху справа — козырь сдачи.")
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

    /// Крупный режим — главная настройка для тех, кому мелко: предлагаем сразу, а не прячем
    /// в Настройках → Вид. Переключатель пишет прямо в настройки, поэтому текст этой страницы
    /// и образец карт меняются на глазах — видно, что получится.
    private var largeModeToggle: some View {
        let large = store.settings.largeCards
        return VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.settings.largeCards) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Крупный режим")
                        .font(.headline)
                        .foregroundStyle(Theme.tableText)
                    Text("Крупнее подписи, кнопки и значки на картах — легче читать и попадать пальцем. "
                         + "Можно поменять в Настройках → Вид.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tableSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.gold)
            HStack(spacing: -(large ? 16 : 12)) {
                ForEach([Card(.ace, .hearts), Card(.ten, .spades), Card(.king, .diamonds)], id: \.self) { card in
                    CardView(card: card, width: large ? 60 : 44, largeIndex: large)
                }
            }
            .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.2), value: large)
        .screenPanel()
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                finish(startGame: true)
            } label: {
                buttonLabel(store.canContinue ? "Продолжить партию" : "Играть", systemImage: "play.fill")
            }
            .buttonStyle(TableButtonStyle(prominent: true))
            .accessibilityHint(store.canContinue ? "Вернуться к сохранённой партии" : "Партия вдвоём с соперником-любителем")

            Button {
                finish(startGame: false)
            } label: {
                buttonLabel("Выбрать соперников", systemImage: "person.2")
            }
            .buttonStyle(TableButtonStyle())
        }
    }

    /// Со значком — если надпись помещается в строку. Крупный шрифт на узком экране — без значка:
    /// так слова переносятся целиком («Продолжить / партию»), а не по слогам, и кнопка ниже.
    private func buttonLabel(_ title: String, systemImage: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Text(title)
        }
        .frame(maxWidth: .infinity)
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
