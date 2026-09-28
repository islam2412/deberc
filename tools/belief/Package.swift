// swift-tools-version: 5.9
import PackageDescription

// Данные для сети «чутья» (у кого какая карта): боты играют партии, с каждого места
// записывается, что видно со стола, и где на самом деле невидимые карты.
let package = Package(
    name: "BeliefTools",
    platforms: [.macOS("13.3")],
    dependencies: [.package(path: "../../DebercKit")],
    targets: [
        .executableTarget(name: "BeliefGen", dependencies: [.product(name: "DebercKit", package: "DebercKit")]),
    ]
)
