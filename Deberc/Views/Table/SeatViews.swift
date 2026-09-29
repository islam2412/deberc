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

/// Место под стопку взяток. Касание показывает последнюю взятку.
struct PileSlot: View {
    let seat: Int
    let tricks: Int
    let metrics: TableMetrics
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        let size = metrics.pileSlotSize
        Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if enabled { onTap() }
            }
            .tableSlot(.pile(seat))
            .accessibilityElement()
            .accessibilityLabel(tricks > 0 ? "Взяток: \(tricks)" : "Взяток пока нет")
            .accessibilityHint(enabled ? "Показать последнюю взятку" : "")
            .accessibilityAddTraits(enabled ? .isButton : [])
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
        PileSlot(seat: info.seat, tricks: info.tricks, metrics: metrics,
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
            PileSlot(seat: info.seat, tricks: info.tricks, metrics: metrics,
                     enabled: canShowLastTrick, onTap: commands.showLastTrick)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

/// Своё место над рукой: счёт, прогресс, «сдаёте»/«играете», свои комбинации,
/// взятки и очки в сдаче, стопка взяток.
struct HumanStrip: View {
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
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                scorePlate(showsProgress: true)
                scorePlate(showsProgress: false)
            }
            .layoutPriority(2)
            if !info.declarations.isEmpty {
                ViewThatFits(in: .horizontal) {
                    DeclarationRow(items: info.declarations, rules: info.rules, tileHeight: tileHeight)
                    DeclarationRow(items: info.declarations, rules: info.rules, tileHeight: tileHeight, compact: true)
                    Color.clear.frame(width: 0, height: 0)
                }
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
            if let live {
                liveBlock(live)
            }
            PileSlot(seat: info.seat, tricks: info.tricks, metrics: metrics,
                     enabled: canShowLastTrick, onTap: commands.showLastTrick)
        }
        .frame(maxWidth: stripWidth)
        .padding(.horizontal, metrics.gutter)
        .frame(minHeight: metrics.roomy ? 50 : 40)
        .transaction { $0.animation = nil }
    }

    private var tileHeight: CGFloat { metrics.roomy ? 30 : 24 }
    private var stripWidth: CGFloat { metrics.roomy ? 1100 : .infinity }

    /// «Вы», счёт, прогресс, «сдаёте»; масть козыря у играющего — значком на углу, как у соперников.
    private func scorePlate(showsProgress: Bool) -> some View {
        HStack(spacing: 8) {
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
                DealerTag(text: "сдаёте")
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

    private func liveBlock(_ live: Live) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(live.tricks) \(TableText.plural(live.tricks, "взятка", "взятки", "взяток"))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.tableSecondaryText)
            Text("\(live.points) \(TableText.plural(live.points, "очко", "очка", "очков"))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.gold)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("В этой сдаче: \(live.tricks) \(TableText.plural(live.tricks, "взятка", "взятки", "взяток")), \(live.points) \(TableText.plural(live.points, "очко", "очка", "очков"))")
    }
}
