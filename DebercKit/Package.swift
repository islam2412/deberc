// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DebercKit",
    platforms: [
        // Совпадает с IPHONEOS_DEPLOYMENT_TARGET приложения: iPhone 8/X и новее.
        .iOS("16.4"),
        // macOS 13.3 — ровесник iOS 16.4: `swift test` на Mac ловит API новее минимальной iOS.
        .macOS("13.3"),
    ],
    products: [
        .library(name: "DebercKit", targets: ["DebercKit"]),
    ],
    targets: [
        // Веса сети «чутья» (tools/belief) — belief.bin, см. `BeliefNet`.
        .target(name: "DebercKit", resources: [.process("Resources")]),
        .testTarget(name: "DebercKitTests", dependencies: ["DebercKit"]),
    ]
)
