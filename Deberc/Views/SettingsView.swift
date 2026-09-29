import SwiftUI
import DebercKit

/// Настройки: «Игра» (темп, касания, вид, звук, имя) и отдельная страница «Правила партии».
/// Настройки игры действуют сразу — и в идущей партии; правила — с новой партии.
struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    /// Имя в поле. «Вы» по умолчанию показывается подсказкой, а не текстом, который надо стирать.
    @State private var nameDraft = ""
    @State private var nameLoaded = false

    /// Длина имени: длиннее не помещается на табличках и в столбцах записи.
    static let nameLimit = 12

    var body: some View {
        SheetContainer(title: "Настройки") {
            Form {
                gameSection
                lookSection
                soundSection
                nameSection
                rulesSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Игра

    private var gameSection: some View {
        Section {
            Picker(selection: $store.settings.speed) {
                ForEach(GameSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            } label: {
                SettingLabel(title: "Скорость игры", detail: "Как быстро ходят соперники и сколько лежит взятка")
            }
            Toggle(isOn: $store.settings.confirmCardTap) {
                SettingLabel(title: "Ход в два касания", detail: "Первое касание приподнимает карту, второе — ходит")
            }
            Toggle(isOn: $store.settings.showLivePoints) {
                SettingLabel(title: "Мои очки во время сдачи", detail: "Сколько взяток и очков у вас уже есть")
            }
        } header: {
            Text("Игра").formHeaderStyle()
        } footer: {
            Text("Действует сразу, и в идущей партии.").formHeaderStyle()
        }
        .screenRow()
    }

    private var lookSection: some View {
        Section {
            Toggle(isOn: $store.settings.largeCards) {
                SettingLabel(title: "Крупный режим", detail: "Крупнее карты, подписи и кнопки")
            }
            Toggle(isOn: $store.settings.fourColorDeck) {
                // Масти — под подписью, а не справа от неё: иначе «Четырёхцветная» переносится по слогам.
                VStack(alignment: .leading, spacing: 6) {
                    SettingLabel(title: "Четырёхцветная колода", detail: "У каждой масти свой цвет")
                    HStack(spacing: 3) {
                        ForEach(Suit.allCases, id: \.self) { suit in
                            SuitBadge(suit: suit, size: 22, fourColor: store.settings.fourColorDeck)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        } header: {
            Text("Вид").formHeaderStyle()
        }
        .screenRow()
    }

    private var soundSection: some View {
        Section {
            Toggle(isOn: $store.settings.soundEnabled) {
                SettingLabel(title: "Звуки", detail: "Тихо, не перебивает музыку; молчит в беззвучном режиме")
            }
            if !AppInfo.isPad {
                Toggle(isOn: $store.settings.hapticsEnabled) {
                    SettingLabel(title: "Вибрация", detail: "Лёгкий отклик на ход, взятку и ошибку")
                }
            }
        } header: {
            Text(AppInfo.isPad ? "Звук" : "Звук и вибрация").formHeaderStyle()
        }
        .screenRow()
    }

    private var nameSection: some View {
        Section {
            LabeledContent {
                TextField("Вы", text: $nameDraft)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onAppear(perform: loadName)
                    .onChange(of: nameDraft, perform: saveName)
            } label: {
                Text("Ваше имя")
            }
        } header: {
            Text("Вы").formHeaderStyle()
        } footer: {
            Text("Так вас подпишут в записи партии и в итогах — с новой партии. До \(SettingsView.nameLimit) букв.")
                .formHeaderStyle()
        }
        .screenRow()
    }

    private func loadName() {
        guard !nameLoaded else { return }
        nameLoaded = true
        let current = store.settings.playerName
        nameDraft = current == "Вы" ? "" : current
    }

    /// Обрезает имя до `nameLimit` и сохраняет; пустое поле — снова «Вы».
    private func saveName(_ value: String) {
        let limited = String(value.prefix(SettingsView.nameLimit))
        guard limited == value else {
            nameDraft = limited   // onChange сработает ещё раз и сохранит обрезанное
            return
        }
        let trimmed = limited.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty ? "Вы" : trimmed
        if store.settings.playerName != stored { store.settings.playerName = stored }
    }

    private var rulesSection: some View {
        Section {
            NavigationLink {
                RuleSettingsView()
            } label: {
                HStack {
                    SettingLabel(title: "Правила партии", detail: rulesSummary)
                    Spacer(minLength: 4)
                }
            }
        } header: {
            Text("Правила").formHeaderStyle()
        } footer: {
            Text("Соперников и их уровень выбирают в меню, перед новой партией.").formHeaderStyle()
        }
        .screenRow()
    }

    private var rulesSummary: String {
        let rules = store.settings.rules
        let target = "до \(Narrator.pointsGenitive(rules.targetScore))"
        return rules == .house ? "Наши, \(target)" : "Изменены, \(target)"
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: AppInfo.version)
            if store.match != nil {
                ProblemReportLink()
            }
        } header: {
            Text("О приложении").formHeaderStyle()
        } footer: {
            // Ссылка есть только при сохранённой партии — без неё и пояснять нечего.
            if store.match != nil {
                Text("«Сообщить о проблеме» готовит файл с партией и настройками — его можно отправить разработчику в Telegram или WhatsApp. Больше ничего не отправляется.")
                    .formHeaderStyle()
            }
        }
        .screenRow()
    }
}

/// Подпись настройки: название и пояснение мелко под ним.
struct SettingLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(Theme.tableText)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
