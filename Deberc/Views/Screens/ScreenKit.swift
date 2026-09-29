import SwiftUI
import UIKit
import DebercKit

// Общие детали экранов вне стола: меню, листы (настройки, правила, запись, статистика),
// итоги сдачи и конец партии. Цвета и кнопки — из Theme.swift; здесь только то,
// что нужно экранам: цвета «плюс/минус», бумага записи, крупные переключатели, аватары.

/// Цвета экранов поверх сукна.
enum ScreenStyle {
    /// Плюс в счёте (на тёмном фоне, 9:1).
    static let positive = Color(red: 0.49, green: 0.89, blue: 0.63)
    /// Минус в счёте (на тёмном фоне, 6:1).
    static let negative = Color(red: 1.0, green: 0.55, blue: 0.55)
    /// Фон строк в листах (настройки, статистика) — темнее сукна.
    static let row = Color.black.opacity(0.26)
    /// Фон карточки итогов сдачи и конца партии.
    static let cardTop = Color(red: 0.055, green: 0.23, blue: 0.14)
    static let cardBottom = Color(red: 0.03, green: 0.14, blue: 0.085)

    // Бумага «записи»: слоновая кость и чернила.
    static let paper = Theme.ivory
    static let paperAlt = Color(red: 0.975, green: 0.96, blue: 0.925)
    static let paperRule = Color(red: 0.78, green: 0.83, blue: 0.9)
    static let ink = Color(red: 0.11, green: 0.15, blue: 0.27)
    static let inkSecondary = Color(red: 0.36, green: 0.39, blue: 0.45)
    static let inkRed = Color(red: 0.74, green: 0.07, blue: 0.14)
    static let inkGreen = Color(red: 0.1, green: 0.45, blue: 0.24)

    /// Цвет изменения счёта: плюс — зелёный, ноль — приглушённый, минус — красный.
    static func change(_ value: Int) -> Color {
        if value > 0 { return positive }
        if value < 0 { return negative }
        return Theme.tableSecondaryText
    }

    /// То же для бумаги.
    static func inkChange(_ value: Int) -> Color {
        if value > 0 { return inkGreen }
        if value < 0 { return inkRed }
        return inkSecondary
    }

    /// Фон карточек поверх затемнённого стола.
    static var cardFill: LinearGradient {
        LinearGradient(colors: [cardTop, cardBottom], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Размер текста

/// Сколько места у экрана: на iPad текст крупнее, но с потолком, чтобы раскладка не ломалась.
enum TextScale {
    /// Полноэкранные экраны (меню, приветствие, конец партии).
    case screen
    /// Листы (настройки, правила, запись, статистика).
    case sheet
}

private struct AdaptiveTextSize: ViewModifier {
    let scale: TextScale
    @EnvironmentObject private var store: GameStore

    @ViewBuilder
    func body(content: Content) -> some View {
        let large = store.settings.largeCards
        if UIDevice.current.userInterfaceIdiom == .pad {
            switch scale {
            case .screen:
                content.dynamicTypeSize(DynamicTypeSize.xxxLarge ... DynamicTypeSize.accessibility3)
            case .sheet:
                content.dynamicTypeSize((large ? DynamicTypeSize.xxxLarge : DynamicTypeSize.xxLarge) ... DynamicTypeSize.accessibility3)
            }
        } else if large {
            content.dynamicTypeSize(DynamicTypeSize.xLarge ... DynamicTypeSize.accessibility3)
        } else {
            content.dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }
}

/// То же без обращения к магазину — для листов, которые могут открыться откуда угодно.
/// Крупный режим берётся из окружения (`tableLargeControls` ставит RootView и стол).
private struct PlainTextSize: ViewModifier {
    let scale: TextScale
    @Environment(\.tableLargeControls) private var large

    @ViewBuilder
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            switch scale {
            case .screen:
                content.dynamicTypeSize(DynamicTypeSize.xxxLarge ... DynamicTypeSize.accessibility3)
            case .sheet:
                content.dynamicTypeSize((large ? DynamicTypeSize.xxxLarge : DynamicTypeSize.xxLarge) ... DynamicTypeSize.accessibility3)
            }
        } else if large {
            content.dynamicTypeSize(DynamicTypeSize.xLarge ... DynamicTypeSize.accessibility3)
        } else {
            content.dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }
}

extension View {
    /// Размер текста экрана: на iPad крупнее, с учётом крупного режима из настроек. Нужен `GameStore` в окружении.
    func adaptiveTextSize(_ scale: TextScale) -> some View {
        modifier(AdaptiveTextSize(scale: scale))
    }

    /// Размер текста без `GameStore` (для листов): крупный режим — из окружения.
    func plainTextSize(_ scale: TextScale) -> some View {
        modifier(PlainTextSize(scale: scale))
    }
}

// MARK: - Листы

/// Как лист раскрывается на iPad (iOS 18+); на iPhone — всегда во весь экран снизу.
enum SheetSizing {
    case form, page
}

extension View {
    /// Размер листа на iPad: запись и правила — страницей пошире, остальное — формой.
    @ViewBuilder
    func sheetSizing(_ sizing: SheetSizing) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            switch sizing {
            case .form: self.presentationSizing(.form)
            case .page: self.presentationSizing(.page)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Фон листов: то же сукно, только спокойнее — без виньетки.
struct SheetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.feltMid, Theme.feltEdge], startPoint: .top, endPoint: .bottom)
            FeltBackground(vignette: false).opacity(0.55)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Низ прокручиваемого списка затухает: итоги не обрываются посреди строки, и видно, что дальше
    /// есть ещё. Снизу у содержимого должен быть отступ не меньше `height` — тогда в самом конце
    /// прокрутки затухает только пустое место.
    func bottomFade(_ height: CGFloat = 24) -> some View {
        mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            })
    }
}

/// Оболочка листа: заголовок, кнопка «Готово», фон сукна, золотые акценты, крупный текст на iPad.
struct SheetContainer<Content: View>: View {
    let title: String
    let sizing: SheetSizing
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(title: String, sizing: SheetSizing = .form, @ViewBuilder content: () -> Content) {
        self.title = title
        self.sizing = sizing
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .background(SheetBackground())
        }
        .tint(Theme.gold)
        .environment(\.colorScheme, .dark)
        .plainTextSize(.sheet)
        .sheetSizing(sizing)
    }
}

extension View {
    /// Строки формы на сукне: тёмная подложка вместо системной серой.
    func screenRow() -> some View {
        listRowBackground(ScreenStyle.row)
    }

    /// Плашка экрана (меню, приветствие): стекло/матовая подложка с отступами.
    func screenPanel(highlighted: Bool = false) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tableSurface(cornerRadius: 22, highlighted: highlighted)
    }

    /// Заголовок раздела формы — обычным регистром и светлым цветом.
    func formHeaderStyle() -> some View {
        textCase(nil)
            .foregroundStyle(Theme.tableSecondaryText)
    }
}

// MARK: - Выбор из нескольких вариантов

/// Вариант для `ChoiceRow`.
struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// Крупный переключатель вместо сегментного: шрифт растёт вместе с Dynamic Type,
/// выбранный вариант — золотой. Не помещается в строку — переносится в две колонки или столбик.
struct ChoiceRow<Value: Hashable>: View {
    let title: String
    let options: [ChoiceOption<Value>]
    /// nil — ничего не выбрано (например, соперники разного уровня).
    let selected: Value?
    let onSelect: (Value) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(options) { option in chip(option) }
            }
            VStack(spacing: 8) {
                ForEach(pairs.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        ForEach(pairs[index]) { option in chip(option) }
                    }
                }
            }
            VStack(spacing: 8) {
                ForEach(options) { option in chip(option) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var pairs: [[ChoiceOption<Value>]] {
        stride(from: 0, to: options.count, by: 2).map { start in
            Array(options[start ..< min(start + 2, options.count)])
        }
    }

    private func chip(_ option: ChoiceOption<Value>) -> some View {
        let isOn = option.value == selected
        return Button {
            onSelect(option.value)
        } label: {
            Text(option.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChipButtonStyle(selected: isOn))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Кнопка-«фишка» для `ChoiceRow`: выбранная — золотая, остальные — тёмные.
struct ChipButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipButtonBody(configuration: configuration, selected: selected)
    }
}

private struct ChipButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool

    @Environment(\.tableLargeControls) private var large
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(large ? Font.title3.weight(.semibold) : Font.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: large ? 54 : 46)
            .foregroundStyle(selected ? Theme.onGold : Theme.tableText)
            .background(fill(shape))
            .overlay(shape.strokeBorder(stroke, lineWidth: 1))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var stroke: Color {
        if selected { return Theme.goldDeep.opacity(0.7) }
        return contrast == .increased ? Color.white.opacity(0.6) : Theme.panelStroke
    }

    @ViewBuilder
    private func fill(_ shape: RoundedRectangle) -> some View {
        if selected {
            shape.fill(LinearGradient(colors: [Theme.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
        } else {
            shape.fill(Color.black.opacity(contrast == .increased ? 0.45 : 0.28))
        }
    }
}

/// Плитка «значок над подписью» — для второстепенных кнопок меню.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileButtonBody(configuration: configuration)
    }
}

private struct TileButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.tableLargeControls) private var large

    var body: some View {
        configuration.label
            .font(large ? Font.headline : Font.subheadline.weight(.semibold))
            .foregroundStyle(Theme.tableText)
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: large ? 76 : 66)
            .tableSurface(cornerRadius: 16, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Игроки

/// Аватар персонажа: портрет (или эмодзи) на круге его цвета — так же, как за столом (`SeatAvatar`).
struct PersonaAvatarView: View {
    let persona: Persona
    var size: CGFloat = 40

    var body: some View {
        let tint = Theme.seatTint(persona.tint)
        ZStack {
            if let portrait = CardArt.avatarImageName(persona) {
                PortraitImage(name: portrait, size: size)
            } else {
                Text(persona.avatar)
                    .font(.system(size: size * 0.54))
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                                 startPoint: .top, endPoint: .bottom)))
        .overlay(Circle().strokeBorder(Theme.ivory.opacity(0.75), lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

/// Портрет персонажа, вписанный в круг аватара.
struct PortraitImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

/// Аватар человека: золотой круг с первой буквой имени (или значком, если имя не задано).
struct HumanAvatarView: View {
    let name: String
    var size: CGFloat = 40

    private var initial: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, trimmed != "Вы" else { return nil }
        return String(first).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.goldLight, Theme.goldFill], startPoint: .top, endPoint: .bottom))
            if let initial {
                Text(initial)
                    .font(.system(size: size * 0.48, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.onGold)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Theme.onGold)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Theme.goldDeep.opacity(0.6), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Аватар места за столом: персонаж или человек.
struct PlayerAvatarView: View {
    let persona: Persona?
    let humanName: String
    var size: CGFloat = 40

    var body: some View {
        if let persona {
            PersonaAvatarView(persona: persona, size: size)
        } else {
            HumanAvatarView(name: humanName, size: size)
        }
    }
}

/// Уровень звёздами: ★☆☆☆ — Новичок … ★★★★ — Мастер.
struct LevelStarsView: View {
    let level: BotLevel
    var size: CGFloat = 11

    private var filled: Int {
        (BotLevel.allCases.firstIndex(of: level) ?? 0) + 1
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< BotLevel.allCases.count, id: \.self) { index in
                Image(systemName: index < filled ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.gold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("уровень \(level.title)")
    }
}

/// Полоска «сколько набрано до цели партии».
struct GoalProgressBar: View {
    let value: Int
    let target: Int
    var tint: Color = Theme.gold
    var track: Color = Color.white.opacity(0.14)
    var height: CGFloat = 6

    private var fraction: CGFloat {
        guard target > 0, value > 0 else { return 0 }
        return CGFloat(min(value, target)) / CGFloat(target)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if fraction > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(height, geo.size.width * fraction))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Маленькая плашка-пометка: «Б», «ВБ», «играет».
struct ScoreMarkBadge: View {
    let text: String
    var color: Color = ScreenStyle.negative
    var textColor: Color = Theme.onGold

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(textColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
    }
}

// MARK: - Тексты

/// Русские окончания: 1 победа, 2 победы, 5 побед.
enum RuPlural {
    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n) % 100
        let b = a % 10
        if (11...14).contains(a) { return many }
        if b == 1 { return one }
        if (2...4).contains(b) { return few }
        return many
    }

    /// «3 победы», «5 партий».
    static func count(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(n) \(form(n, one, few, many))"
    }
}

/// Версия приложения: «1.0 (260927.1805)».
enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    @MainActor
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Почта разработчика для отзывов и сообщений о проблемах (её же видно в App Store).
    static let supportEmail = "islamytchaev@gmail.com"

    /// Письмо разработчику с темой «Деберц» (в адресе — URL-кодировкой).
    static let supportURL = URL(string: "mailto:\(supportEmail)?subject=%D0%94%D0%B5%D0%B1%D0%B5%D1%80%D1%86")!

    /// Сборка для проверки: из Xcode или из TestFlight (у неё «песочный» чек App Store).
    /// Только в ней «Отправить сдачу» стоит прямо в итогах и в меню — родным, которые проверяют
    /// игру, так удобнее. Покупателю из App Store эта ссылка непонятна, ему она — в Настройках.
    static let isTestBuild: Bool = {
        #if DEBUG
        return true
        #elseif targetEnvironment(simulator)
        // Скриншоты для App Store снимаются на симуляторе с Release-сборкой — там ссылки быть не должно.
        return false
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
}

/// Имена мест для итогов, записи и конца партии.
struct SeatNames {
    let names: [String]
    let humanSeat: Int

    /// Короткое имя для столбца: у человека — его имя из партии, если он его задал, иначе «Вы».
    func column(_ seat: Int) -> String {
        guard names.indices.contains(seat) else { return "" }
        if seat == humanSeat {
            let own = names[seat].trimmingCharacters(in: .whitespacesAndNewlines)
            return own.isEmpty ? "Вы" : own
        }
        return names[seat]
    }

    /// Для фраз: «Вы» у человека, имя — у соперника.
    func speaker(_ seat: Int) -> String {
        seat == humanSeat ? "Вы" : (names.indices.contains(seat) ? names[seat] : "")
    }

    /// Персонаж по имени места (имена ботов в партии совпадают с именами персонажей).
    func persona(_ seat: Int) -> Persona? {
        guard seat != humanSeat, names.indices.contains(seat) else { return nil }
        return Persona.all.first { $0.name == names[seat] }
    }
}

// MARK: - Пауза игры

private struct PausesGame: ViewModifier {
    let isPresented: Bool
    @EnvironmentObject private var store: GameStore

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { presented in
            if store.isOverlayPresented != presented {
                store.isOverlayPresented = presented
            }
        }
    }
}

extension View {
    /// Пока открыт лист или диалог (`isPresented`), игра стоит на паузе (`store.isOverlayPresented`).
    func pausesGame(while isPresented: Bool) -> some View {
        modifier(PausesGame(isPresented: isPresented))
    }
}
