// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Prwatch",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "PrwatchCore"),
        .executableTarget(name: "PrwatchApp", dependencies: ["PrwatchCore"]),
        .executableTarget(name: "prwatch", dependencies: ["PrwatchCore"]),
        .testTarget(name: "PrwatchCoreTests", dependencies: ["PrwatchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
