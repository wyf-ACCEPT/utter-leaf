// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UtterLeafHostSupport",
    platforms: [.iOS(.v16)],
    products: [.library(name: "KeyboardKitHostPlugin", targets: ["KeyboardKitHostPlugin"])],
    targets: [
        .binaryTarget(
            name: "KeyboardKitHostPlugin",
            path: "Artifacts/KeyboardKitHostPlugin.xcframework"
        )
    ]
)
