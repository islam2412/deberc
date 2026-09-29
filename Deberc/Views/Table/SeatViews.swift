import SwiftUI
import DebercKit

// Места за столом в раскладке. Сами карты (веер рубашек, стопка взяток) рисует слой карт
// поверх — здесь только рамки нужного размера, которые сообщают ему свои кадры.

/// Место под веер рубашек соперника.
struct FanSlot: View {
    let seat: Int
    let metrics: TableMetrics

    var body: some View {
        let size = metrics.fanSlotSize
        Color.clear
            .frame(width: size.width, height: size.height)
            .tableSlot(.fan(seat))
            .accessibilityHidden(true)
    }
}

/// Место под стопку взяток. Касание показывает последнюю взятку стола (кто бы её ни взял).
struct PileSlot: View {
    let seat: Int
    /// Чья стопка — для VoiceOver (втроём две стопки соперников иначе звучали бы одинаково); nil — ваша.
    let owner: String?
    let tricks: Int
    let metrics: TableMetrics
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        let size = metrics.pileSlotSize
        // Рамка — по размеру стопки (по ней лежат карты слоя), а зона касания — не меньше 44 pt:
        // в стопку 32–38 pt высотой пальцем не попасть. Поля вокруг рамки не меняют раскладку.
        let padX = max(0, (44 - size.width) / 2)
        let padY = max(0, (44 - size.height) / 2)
        Color.clear
            .frame(width: size.width, height: size.height)
            .tableSlot(.pile(seat))
            .padding(.horizontal, padX)
            .padding(.vertical, padY)
            .contentShape(Rectangle())
            .onTapGesture {
                if enabled { onTap() }
            }
            .accessibilityElement()
            .accessibilityLabel(spokenLabel)
            .accessibilityHint(enabled ? "Показать последнюю взятку стола" : "")
            .accessibilityAddTraits(enabled ? .isButton : [])
            .padding(.horizontal, -padX)
            .padding(.vertical, -padY)
    }

    private var spokenLabel: String {
        guard let owner else {
            return tricks > 0 ? "Ваши взятки: \(tricks)" : "Ваших взяток пока нет"
        }
        return tricks > 0 ? "\(owner): взяток \(tricks)" : "\(owner): взяток пока нет"
    }
}

/// Соперник втроём на узком экране: плашка, под ней веер и стопка.
struct SeatStack: View {
    let info: SeatInfo
    let metrics: TableMetrics
    let commands: TableCommands
    let canShowLastTrick: Bool
    /// Левый соперник (иначе — правый): веер ближе к краю, стопка — к центру.
    let leading: Bool

    var body: some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: metrics.spacing) {
            SeatPlate(info: info, avatarSize: metrics.avatarSize, maxWidth: metrics.roomy ? 320 : 210,
                      onTap: { commands.showPersona(info.seat) })
                .tableSlot(.seat(info.seat))
            HStack(spacing: 8) {
                if leading {
                    FanSlot(seat: info.seat, metrics: metrics)
                    pile
                } else {
                    pile
                    FanSlot(seat: info.seat, metrics: metrics)
                }
            }
        }
    }

    private var pile: some View {
        PileSlot(seat: info.seat, owner: info.name, tricks: info.tricks, metrics: metrics,
                 enabled: canShowLastTrick, onTap: commands.showLastTrick)
    }
}

/// Соперник втроём на широком экране: колонка сбоку от центра.
struct SeatColumn: View {
    let info: SeatInfo
    let metrics: TableMetrics
    let commands: TableCommands
    let canShowLastTrick: Bool

    var body: some View {
        VStack(spacing: 12) {
            SeatPlate(info: info, avatarSize: metrics.avatarSize, maxWidth: metrics.sideSeatWidth,
                      onTap: { commands.showPersona(info.seat) })
                .tableSlot(.seat(info.seat))
            FanSlot(seat: info.seat, metrics: metrics)
            PileSlot(seat: info.seat, owner: info.name, tricks: info.tricks, metrics: metrics,
                     enabled: canShowLastTrick, onTap: commands.showLastTrick)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

/// Своё место над рукой: счёт, прогресс, «сдаёте»/«играете», свои комбинации,
/// взятки и очки в сдаче, стопка взяток.
struct HumanStrip: View {
    @EnvironmentObject private var store: GameStore

    struct Live: Equatable {
        var tricks: Int
        var points: Int
    }

    let info: SeatInfo
    let live: Live?
    let metrics: TableMetrics
    let commands: TableCommands
    let canShowLastTrick: Bool

    var body: some View {
        // Место делится по приоритетам: сначала очки в сдаче — но лишь то, что остаётся за самым узким
        // вариантом плашки (счёт виден всегда); потом плашка выбирает вариант под остаток; комбинации — последними.
        // Тесно (узкий экран, крупный текст, вы сдаёте) — плашка теряет полоску прогресса, «сдаёте» становится
        // маленькой меткой, пропадает аватар; очки в сдаче — одной строкой или совсем. Стопка — всегда.
        // У каждой части последний вариант заведомо помещается, поэтому полоса не выходит за края экрана.
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                scorePlate(showsProgress: true, avatar: true, dealerWord: true)
                scorePlate(showsProgress: false, avatar: true, dealerWord: true)
                scorePlate(showsProgress: false, avatar: true, dealerWord: false)
                scorePlate(showsProgress: false, avatar: false, dealerWord: false)
            }
            .layoutPriority(2)
            if !info.declarations.isEmpty {
                ViewThatFits(in: .horizontal) {
                    DeclarationRow(items: info.declarations, rules: info.rules, tileHeight: metrics.tileHeight)
                    DeclarationRow(items: info.declarations, rules: info.rules, tileHeight: metrics.tileHeight,
                                   compact: true)
                    Color.clear.frame(width: 0, height: 0)
                }
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
            if let live {
                ViewThatFits(in: .horizontal) {
                    liveBlock(live, compact: false)
                    liveBlock(live, compact: true)
                    Color.clear.frame(width: 0, height: 0)
                }
                .layoutPriority(3)
            }
            PileSlot(seat: info.seat, owner: nil, tricks: info.tricks, metrics: metrics,
                     enabled: canShowLastTrick, onTap: commands.showLastTrick)
        }
        .frame(maxWidth: stripWidth)
        .padding(.horizontal, metrics.gutter)
        .frame(minHeight: metrics.roomy ? 50 : 40)
        .transaction { $0.animation = nil }
    }

    private var stripWidth: CGFloat { metrics.roomy ? 1100 : .infinity }

    /// Аватар, «Вы», счёт, прогресс, «сдаёте»; масть козыря у играющего — значком на углу, как у соперников.
    /// `dealerWord` — «сдаёте» подписью размера текста; иначе — маленькой меткой постоянного размера.
    private func scorePlate(showsProgress: Bool, avatar: Bool, dealerWord: Bool) -> some View {
        HStack(spacing: 8) {
            if avatar {
                HumanAvatarView(name: store.settings.playerName, size: metrics.roomy ? 34 : 28)
                    .overlay(Circle().strokeBorder(info.isActive ? Theme.gold : Color.clear, lineWidth: 2))
            }
            Text("Вы")
                .font(Theme.Typography.seatName)
                .foregroundStyle(info.isActive ? Theme.gold : Theme.tableText)
                .fixedSize()
            Text(TableText.number(info.score))
                .font(Theme.Typography.score)
                .foregroundStyle(Theme.tableText)
                .contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
            if showsProgress {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressTrack(fraction: info.progress, width: metrics.roomy ? 60 : 40)
                    MarksLabel(info: info)
                }
            } else {
                MarksLabel(info: info)
            }
            if info.isDealer {
                // Мелкая метка — 12 pt, как у соперников на аватаре (не мельче: кто сдаёт, важно).
                DealerTag(text: "сдаёте", fontSize: dealerWord ? nil : 12)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .tableSurface(cornerRadius: 14, highlighted: info.isActive)
        .overlay(alignment: .topTrailing) {
            if info.isBidder, let trump = info.trump {
                SuitBadge(suit: trump, size: 22)
                    .offset(x: 8, y: -8)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .tableSlot(.seat(info.seat))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Вы")
        .accessibilityValue(info.spokenValue)
    }

    /// Взятки и очки в сдаче; `compact` — одной строкой, только очки (число взяток — и на стопке).
    private func liveBlock(_ live: Live, compact: Bool) -> some View {
        let tricks = "\(live.tricks) \(TableText.plural(live.tricks, "взятка", "взятки", "взяток"))"
        let points = "\(live.points) \(TableText.plural(live.points, "очко", "очка", "очков"))"
        return VStack(alignment: .trailing, spacing: 0) {
            if !compact {
                Text(tricks)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
            Text(points)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.gold)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("В этой сдаче: \(tricks), \(points)")
    }
}
