// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BubbleTaxBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BubbleTaxBar", targets: ["BubbleTaxBar"])],
    targets: [
        .target(name: "BubbleTaxBarCore"),
        .executableTarget(name: "BubbleTaxBar", dependencies: ["BubbleTaxBarCore"], resources: [.copy("Resources/collector.py"), .copy("Resources/live_usage.py"), .copy("Resources/claude_statusline.py"), .copy("Resources/Personas")]),
        .testTarget(name: "BubbleTaxBarCoreTests", dependencies: ["BubbleTaxBarCore"])
    ]
)
