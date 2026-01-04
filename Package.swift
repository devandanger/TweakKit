// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TweakKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "TweakKitCore",
            targets: ["TweakKitCore"]
        )
    ],
    targets: [
        .target(
            name: "TweakKitCore",
            path: "Sources/TweakKitCore"
        ),
        .testTarget(
            name: "TweakKitCoreTests",
            dependencies: ["TweakKitCore"],
            path: "Tests/TweakKitCoreTests"
        )
    ]
)
