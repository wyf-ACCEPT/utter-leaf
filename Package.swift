// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UtterLeaf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "UtterLeaf", targets: ["UtterLeaf"])],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "UtterLeafCore", dependencies: ["CZlib"]),
        .executableTarget(name: "UtterLeaf", dependencies: ["UtterLeafCore"]),
        .testTarget(name: "UtterLeafCoreTests", dependencies: ["UtterLeafCore", "UtterLeaf"])
    ],
    swiftLanguageModes: [.v5]
)
