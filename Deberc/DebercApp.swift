import SwiftUI
import UIKit

@main
struct DebercApp: App {
    @StateObject private var store = GameStore()
    /// Фаза всего приложения (на iPad — сразу всех окон): активно, если на экране хоть одно окно.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if #available(iOS 17, *), LaunchOptions.current.zoomed {
                ZoomedCanvas {
                    RootView()
                        .environmentObject(store)
                }
            } else if #available(iOS 17, *), LaunchOptions.current.landscape {
                DemoLandscape {
                    RootView()
                        .environmentObject(store)
                }
            } else {
                RootView()
                    .environmentObject(store)
                    .background { WindowMinimumSize(width: 480, height: 600) }
            }
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

/// Проверка тесной раскладки (`-DebercZoom YES`): приложение раскладывается в ширину 320 pt,
/// как на iPhone с «Увеличенным» видом экрана, и растягивается на весь экран.
@available(iOS 17, *)
private struct ZoomedCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 320
            content()
                // Вырез и полоска «Домой» в пересчёте на 320 pt.
                .safeAreaPadding(EdgeInsets(top: 48, leading: 0, bottom: 28, trailing: 0))
                .frame(width: 320, height: geo.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }
}

/// Снимки iPad в альбомной ориентации (`-DebercOrientation landscape`, только демо-режим).
/// Симулятор сам не поворачивается, поэтому окно поворачивает приложение. В режиме
/// «Приложения в окнах» iPadOS 26 система этого не разрешает — тогда приложение раскладывается
/// в размер экрана, повёрнутого набок, и уменьшается до ширины окна (как `ZoomedCanvas`);
/// сверху и снизу остаются чёрные поля. Листы (sheet) система и тогда показывает в настоящем,
/// книжном окне — их раскладку так не проверить. На iPhone ничего не делает.
@available(iOS 17, *)
private struct DemoLandscape<Content: View>: View {
    @ViewBuilder let content: () -> Content
    /// Система не повернула окно — альбомный экран рисуем сами.
    @State private var emulated = false

    var body: some View {
        // Одно дерево на оба случая: при переходе к своему альбомному экрану приложение
        // не создаётся заново (иначе закрылся бы открытый демо-режимом лист).
        GeometryReader { geo in
            let long = max(geo.size.width, geo.size.height)
            let short = min(geo.size.width, geo.size.height)
            let scale = emulated ? geo.size.width / long : 1
            content()
                // Строка состояния и полоска «Домой» iPad в альбомной ориентации.
                .safeAreaPadding(emulated ? EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0) : EdgeInsets())
                .frame(width: emulated ? long : geo.size.width, height: emulated ? short : geo.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: emulated ? short * scale : geo.size.height, alignment: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { if emulated { Color.black } }
        .ignoresSafeArea(edges: emulated ? .all : [])
        .onAppear(perform: rotate)
    }

    private func rotate() {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let emulated = $emulated
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
            Diagnostics.log("Окно не повернулось (\(error.localizedDescription)) — альбомный экран рисуем сами")
            Task { @MainActor in emulated.wrappedValue = true }
        }
    }
}
