import SwiftUI
import DebercKit

/// Праздничный «дождь» из мастей для победы в партии: ~44 значка за 4 секунды, потом тишина.
/// С «Уменьшением движения» не показывается (решает вызывающий).
struct ConfettiView: View {
    private let pieces: [ConfettiPiece]
    private let duration: Double = 4.2
    @State private var start = Date()
    @State private var finished = false

    init(count: Int = 44, seed: UInt64 = 0xDEB_E4C) {
        var rng = SplitMix64(seed: seed)
        pieces = (0 ..< count).map { _ in ConfettiPiece(rng: &rng) }
    }

    var body: some View {
        // Контуры мастей размером 1×1 с центром в нуле — готовятся заранее, в холсте только заливка.
        let shapes = ConfettiView.unitPaths()
        Group {
            if !finished {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(start)
                        for piece in pieces {
                            if let path = shapes[piece.suit] {
                                piece.draw(path, in: &context, size: size, time: t, duration: duration)
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(for: .seconds(duration + 0.2))
            finished = true
        }
    }
}

extension ConfettiView {
    static func unitPaths() -> [Suit: Path] {
        var result: [Suit: Path] = [:]
        for suit in Suit.allCases {
            result[suit] = SuitShape(suit: suit).path(in: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
        }
        return result
    }
}

/// Один значок конфетти: откуда падает, как качается и вращается.
struct ConfettiPiece {
    let x: Double
    let delay: Double
    let speed: Double
    let sway: Double
    let swayRate: Double
    let phase: Double
    let spin: Double
    let size: Double
    let suit: Suit
    let color: Color

    init(rng: inout SplitMix64) {
        func unit() -> Double { Double(rng.next() % 10_000) / 10_000 }
        x = unit()
        delay = unit() * 1.4
        speed = 0.28 + unit() * 0.22
        sway = 10 + unit() * 26
        swayRate = 1.5 + unit() * 2.5
        phase = unit() * 6.28
        spin = (unit() - 0.5) * 5
        size = 14 + unit() * 16
        suit = Suit.allCases[Int(rng.next() % 4)]
        let palette: [Color] = [Theme.gold, Theme.goldLight, Theme.ivory, Color(red: 0.95, green: 0.33, blue: 0.36)]
        color = suit.isRed ? palette[3] : palette[Int(rng.next() % 3)]
    }

    /// `unitPath` — контур масти 1×1 с центром в нуле.
    func draw(_ unitPath: Path, in context: inout GraphicsContext, size canvas: CGSize, time: Double, duration: Double) {
        let t = time - delay
        guard t > 0 else { return }
        let fall = t * speed * Double(canvas.height)
        let y = -size + fall
        guard y < Double(canvas.height) + size else { return }
        let px = x * Double(canvas.width) + sin(t * swayRate + phase) * sway
        let fade = min(1, max(0, (duration - time) / 0.8))
        var local = context
        local.opacity = fade
        local.translateBy(x: px, y: y)
        local.rotate(by: .radians(t * spin + phase))
        local.scaleBy(x: size, y: size)
        local.fill(unitPath, with: .color(color))
    }
}
