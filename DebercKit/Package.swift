// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DebercKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DebercKit", targets: ["DebercKit"]),
    ],
    targets: [
        .target(name: "DebercKit"),
        .testTarget(name: "DebercKitTests", dependencies: ["DebercKit"]),
    ]
)
