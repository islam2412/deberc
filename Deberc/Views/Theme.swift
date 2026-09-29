import SwiftUI
import DebercKit

/// Визуальный язык игры: сукно, золото, цвета мастей, плашки, типографика стола.
///
/// Контраст (WCAG 2.x) проверен на самом светлом месте сукна (`feltCenter`):
/// `tableText` 6.6:1, `tableSecondaryText` 5.3:1, `gold` 4.9:1, красная масть на карте 5.6:1,
/// текст на золотой кнопке 13:1. Масти в тексте на сукне и тёмных плашках (`tableSuitColor`) — 3:1 и выше
/// на самом светлом месте сукна и 6:1 на плашке (норма для графики 3:1); для мелких меток лучше `SuitBadge`.
enum Theme {
    // MARK: Сукно

    /// Центр стола (самое светлое место).
    static let feltCenter = rgb(0x17663D)
    static let feltMid = rgb(0x0F4A2B)
    /// Край стола.
    static let feltEdge = rgb(0x06301B)

    // MARK: Текст и акценты на столе

    /// Основной текст на сукне и плашках (кремово-белый).
    static let tableText = rgb(0xFFF8EC)
    /// Второстепенный текст на сукне: сплошной цвет вместо белого с прозрачностью, ≥ 4.5:1.
    static let tableSecondaryText = rgb(0xD3E5D9)
    /// Золото: активный игрок, «Ваш ход», главная кнопка, обводки. Годится и для мелкого текста на сукне.
    static let gold = rgb(0xFFD45C)
    /// Светлое золото — верх градиента главной кнопки.
    static let goldLight = rgb(0xFFE08A)
    /// Насыщенное золото — заливка орнаментов на картах.
    static let goldFill = rgb(0xE3B23C)
    /// Тёмное золото — контуры орнаментов на слоновой кости.
    static let goldDeep = rgb(0xB07F1F)
    /// Текст на золоте (13:1).
    static let onGold = rgb(0x1A1206)

    /// Фон плашек (табло, баннер, реплики) поверх сукна.
    static let panel = rgb(0x04140B).opacity(0.62)
    /// Тонкая светлая кромка плашек.
    static let panelStroke = Color.white.opacity(0.16)

    // MARK: Карты

    /// Лицо карты — слоновая кость с лёгким затенением книзу.
    static let ivory = rgb(0xFFFDF7)
    static let ivoryShade = rgb(0xF4EEDF)
    static let red = rgb(0xCC1224)
    static let black = rgb(0x141414)
    /// Бубны в четырёхцветной колоде.
    static let blue = rgb(0x0059C7)
    /// Трефы в четырёхцветной колоде.
    static let green = rgb(0x007A33)
    /// Рубашка (бордо).
    static let backLight = rgb(0x7E1222)
    static let backDark = rgb(0x480812)
    /// Тон затемнения недопустимых карт — глубокий зелёный сукна, а не серый.
    static let dimTint = rgb(0x041E11)

    /// Цвет масти на лице карты. Четырёхцветная колода: ♠ чёрный, ♥ красный, ♦ синий, ♣ зелёный.
    static func suitColor(_ suit: Suit, fourColor: Bool) -> Color {
        switch suit {
        case .spades: return black
        case .hearts: return red
        case .diamonds: return fourColor ? blue : red
        case .clubs: return fourColor ? green : black
        }
    }

    /// Цвет масти в тексте прямо на сукне или на тёмной плашке (сообщения, подписи):
    /// черви и бубны — красные, пики и трефы — светлые, как «чёрные» масти на тёмном.
    /// Для самых важных меток лучше `SuitBadge` — масть настоящим цветом на светлой плашке.
    static func tableSuitColor(_ suit: Suit, fourColor: Bool) -> Color {
        switch suit {
        case .spades: return tableText
        case .hearts: return rgb(0xFF8C8C)
        case .diamonds: return fourColor ? rgb(0x8CC2FF) : rgb(0xFF8C8C)
        case .clubs: return fourColor ? rgb(0x8FE3AE) : tableText
        }
    }

    /// Светлый оттенок масти: поле картинки, диск туза.
    static func suitTint(_ suit: Suit, fourColor: Bool) -> Color {
        switch suit {
        case .spades: return rgb(0xECEEF2)
        case .hearts: return rgb(0xFBEAEA)
        case .diamonds: return fourColor ? rgb(0xE8F0FB) : rgb(0xFBEAEA)
        case .clubs: return fourColor ? rgb(0xE7F4EC) : rgb(0xECEEF2)
        }
    }

    /// Приглушённый цвет масти: полосы «перевязи» на картинках.
    static func suitSoft(_ suit: Suit, fourColor: Bool) -> Color {
        switch suit {
        case .spades: return rgb(0x93A3BE)
        case .hearts: return rgb(0xEE9AA3)
        case .diamonds: return fourColor ? rgb(0x8DB4EA) : rgb(0xEE9AA3)
        case .clubs: return fourColor ? rgb(0x86C9A0) : rgb(0x93A3BE)
        }
    }

    // MARK: Игроки

    /// Восемь цветов аватаров (индекс — `Persona.tint`). Без зелёных: на сукне они терялись бы.
    static let seatTints: [Color] = [
        rgb(0xE8665A), // коралл
        rgb(0x5AA9E6), // небесный
        rgb(0xF2A541), // янтарь
        rgb(0x9B7FE6), // фиалка
        rgb(0x3FBFAD), // бирюза
        rgb(0xE27AA8), // роза
        rgb(0x9DAABD), // сталь
        rgb(0xCDB38A), // песок
    ]

    /// Цвет аватара по индексу (любое целое, берётся по модулю).
    static func seatTint(_ index: Int) -> Color {
        let n = seatTints.count
        return seatTints[((index % n) + n) % n]
    }

    // MARK: Типографика стола

    /// Минимальные размеры для стола: подписи ≥ 13 pt, имена 17 pt, счёт 22 pt.
    /// Всё — стили Dynamic Type, поэтому растёт вместе с системным размером текста.
    enum Typography {
        /// Мелкие подписи («козырь», «низ»): 13 pt.
        static let caption = Font.footnote.weight(.semibold)
        /// Вторичные строки («Ходит Саша…»): 15 pt.
        static let label = Font.subheadline.weight(.semibold)
        /// Имена игроков: 17 pt.
        static let seatName = Font.headline
        /// Счёт: 22 pt, цифры одинаковой ширины.
        static let score = Font.title2.weight(.bold).monospacedDigit()
        /// Баннер и кнопки: 17 pt.
        static let banner = Font.headline
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

extension Suit {
    /// Символ масти, который всегда рисуется текстом, а не эмодзи.
    var glyph: String { symbol + "\u{FE0E}" }
}

// MARK: - Сукно

/// Зелёное сукно: радиальный градиент, фактура ткани и виньетка по краям.
struct FeltBackground: View {
    var vignette = true

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let longSide = max(size.width, size.height)
            let shortSide = min(size.width, size.height)
            ZStack {
                RadialGradient(
                    colors: [Theme.feltCenter, Theme.feltMid, Theme.feltEdge],
                    center: UnitPoint(x: 0.5, y: 0.45),
                    startRadius: 0,
                    endRadius: max(longSide * 0.75, 1))
                if let texture = FeltTexture.image {
                    Image(decorative: texture, scale: FeltTexture.scale)
                        .resizable(resizingMode: .tile)
                }
                if vignette {
                    RadialGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.36)],
                        center: .center,
                        startRadius: shortSide * 0.35,
                        endRadius: max(longSide * 0.85, shortSide * 0.35 + 1))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Фактура сукна: мелкое зерно и едва заметные нити, генерируется один раз.
/// Прозрачная картинка поверх градиента — без режимов наложения, дёшево для GPU.
enum FeltTexture {
    static let scale: CGFloat = 2
    static let image: CGImage? = make(size: 256)

    private static func make(size n: Int) -> CGImage? {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            // SplitMix64: детерминированно, чтобы фактура не «мигала» между запусками.
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(1 << 53)
        }
        // Лёгкая неровность нитей по строкам и столбцам.
        let rows = (0..<n).map { _ in next() * 2 - 1 }
        let columns = (0..<n).map { _ in next() * 2 - 1 }
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let grain = (next() * 2 - 1) * 0.75 + rows[y] * 0.15 + columns[x] * 0.10
                let alpha = min(1, abs(grain)) * 0.075
                let a = UInt8(max(0, min(255, (alpha * 255).rounded())))
                let i = (y * n + x) * 4
                // Премультиплицированный RGBA: светлое зерно — белое, тёмное — чёрное.
                let v: UInt8 = grain > 0 ? a : 0
                bytes[i] = v
                bytes[i + 1] = v
                bytes[i + 2] = v
                bytes[i + 3] = a
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: n, height: n,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Плашки и кнопки

private struct TableLargeControlsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Крупный режим для кнопок стола (`TableButtonStyle`): выше, крупнее шрифт.
    var tableLargeControls: Bool {
        get { self[TableLargeControlsKey.self] }
        set { self[TableLargeControlsKey.self] = newValue }
    }
}

/// Поверхность плашки в духе iOS 26: на iOS 26 — настоящее «жидкое стекло»,
/// раньше — тёмный `ultraThinMaterial` с тонкой светлой кромкой.
struct TableSurface: ViewModifier {
    var cornerRadius: CGFloat = 14
    var interactive = false
    var highlighted = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var increased: Bool { contrast == .increased }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // У стекла своя световая кромка — добавляем обводку, только если она что-то значит.
            content
                .glassEffect(.regular.tint(Color.black.opacity(increased ? 0.5 : 0.28)).interactive(interactive),
                             in: shape)
                .overlay(glassBorder(shape))
        } else {
            fallback(content, shape: shape)
        }
        #else
        fallback(content, shape: shape)
        #endif
    }

    private func fallback(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Theme.panel.opacity(increased ? 1 : 0.8))
                }
                .environment(\.colorScheme, .dark)
            }
            .overlay(border(shape))
    }

    @ViewBuilder
    private func glassBorder(_ shape: RoundedRectangle) -> some View {
        if highlighted {
            shape.strokeBorder(Theme.gold, lineWidth: 2)
        } else if increased {
            shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        if highlighted {
            shape.strokeBorder(Theme.gold, lineWidth: 2)
        } else {
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(increased ? 0.6 : 0.3),
                                        Color.white.opacity(increased ? 0.35 : 0.08)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
    }
}

extension View {
    /// Фон плашки стола (табло, баннер, индикатор козыря): стекло на iOS 26, матовая подложка раньше.
    func tableSurface(cornerRadius: CGFloat = 14, interactive: Bool = false, highlighted: Bool = false) -> some View {
        modifier(TableSurface(cornerRadius: cornerRadius, interactive: interactive, highlighted: highlighted))
    }
}

/// Кнопка в стиле стола. Главная (`prominent`) — непрозрачное золото ради контраста,
/// обычная — стеклянная плашка. Крупный режим — `large` или `.environment(\.tableLargeControls, true)`.
struct TableButtonStyle: ButtonStyle {
    var prominent = false
    /// nil — брать из окружения (`tableLargeControls`).
    var large: Bool? = nil
    /// Кнопка-значок (подсказка, отмена): узкие поля, чтобы в тесном ряду словам на других кнопках хватило места.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        TableButtonBody(configuration: configuration, prominent: prominent, large: large, compact: compact)
    }
}

private struct TableButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let large: Bool?
    let compact: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.tableLargeControls) private var largeFromEnvironment

    var body: some View {
        let isLarge = large ?? largeFromEnvironment
        let radius: CGFloat = isLarge ? 16 : 14
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let label = configuration.label
            .font(isLarge ? Font.title3.weight(.semibold) : Font.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, isLarge ? 14 : 12)
            .frame(minHeight: isLarge ? 60 : 48)
            .foregroundStyle(prominent ? Theme.onGold : Theme.tableText)
            .contentShape(shape)

        Group {
            if prominent {
                label
                    .background(
                        shape.fill(LinearGradient(colors: [Theme.goldLight, Theme.gold, Theme.goldFill],
                                                  startPoint: .top, endPoint: .bottom)))
                    .overlay(shape.strokeBorder(Theme.goldDeep.opacity(contrast == .increased ? 1 : 0.55),
                                                lineWidth: contrast == .increased ? 2 : 1))
                    .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            } else {
                label.tableSurface(cornerRadius: radius, interactive: true)
            }
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
