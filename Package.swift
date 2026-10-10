// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BubbleTaxBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BubbleTaxBar", targets: ["BubbleTaxBar"])],
    targets: [
        .target(name: "BubbleTaxBarCore"),
        .executableTarget(name: "BubbleTaxBar", dependencies: ["BubbleTaxBarCore"], exclude: ["Resources/collector_entry.py", "Resources/__pycache__"], resources: [.copy("Resources/collector.py"), .copy("Resources/live_usage.py"), .copy("Resources/claude_statusline.py"), .copy("Resources/Personas"), .copy("Resources/AppIcon.icns")]),
        .testTarget(name: "BubbleTaxBarCoreTests", dependencies: ["BubbleTaxBarCore"]),
        .testTarget(name: "BubbleTaxBarCollectorTests", dependencies: ["BubbleTaxBar"])
    ]
)
