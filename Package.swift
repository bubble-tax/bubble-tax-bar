// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubRIP",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SubRIP", targets: ["SubRIP"])],
    targets: [
        .target(name: "SubRIPCore"),
        .executableTarget(name: "SubRIP", dependencies: ["SubRIPCore"], resources: [.copy("Resources/collector.py")]),
        .testTarget(name: "SubRIPCoreTests", dependencies: ["SubRIPCore"])
    ]
)
