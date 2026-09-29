import SwiftUI

/// Ряд кнопок одинаковой ширины: «Новая партия» и «Запись», «Запись» и «В меню».
///
/// Своя ширина ряда (её спрашивает `ViewThatFits`) — самая широкая кнопка × число кнопок:
/// ряд «помещается», только если каждая кнопка получит место для надписи целиком.
/// На экране ширину ряда делят поровну, и короткая кнопка не отдаёт место длинной.
struct EqualWidthHStack: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let n = CGFloat(subviews.count)
        let gaps = spacing * (n - 1)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? widest * n + gaps
        let cell = max(0, (width - gaps) / n)
        let height = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: cell, height: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let n = CGFloat(subviews.count)
        let cell = max(0, (bounds.width - spacing * (n - 1)) / n)
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: cell, height: bounds.height))
            x += cell + spacing
        }
    }
}
