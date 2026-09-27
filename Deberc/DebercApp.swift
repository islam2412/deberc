import SwiftUI
import UIKit

@main
struct DebercApp: App {
    @StateObject private var store = GameStore()
    /// Фаза всего приложения (на iPad — сразу всех окон): активно, если на экране хоть одно окно.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .background { WindowMinimumSize(width: 480, height: 600) }
        }
        .onChange(of: scenePhase) { phase in
            // Не на экране (фон, пункт управления, звонок) — игра на паузе и сохраняется.
            store.setScenePhaseActive(phase == .active)
        }
    }
}

/// На iPad (iPadOS 17+: Stage Manager, окна iPadOS 26) не даёт сжать окно так,
/// что стол станет нечитаемым. На iPhone ничего не делает.
private struct WindowMinimumSize: UIViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.minimum = CGSize(width: width, height: height)
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.minimum = CGSize(width: width, height: height)
        view.apply()
    }

    final class Probe: UIView {
        var minimum = CGSize.zero

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard UIDevice.current.userInterfaceIdiom == .pad, let scene = window?.windowScene else { return }
            if #available(iOS 17, *) {
                scene.sizeRestrictions?.minimumSize = minimum
            }
        }
    }
}
