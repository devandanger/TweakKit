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
        ),
        .library(
            name: "TweakKitServer",
            targets: ["TweakKitServer"]
        ),
        .library(
            name: "TweakKitMCP",
            targets: ["TweakKitMCP"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Building42/Telegraph.git", from: "0.28.0")
    ],
    targets: [
        .target(
            name: "TweakKitCore",
            path: "Sources/TweakKitCore"
        ),
        .target(
            name: "TweakKitServer",
            dependencies: [
                "TweakKitCore",
                "TweakKitNetworking",
                .product(name: "Telegraph", package: "Telegraph")
            ],
            path: "Sources/TweakKitServer"
        ),
        .target(
            name: "TweakKitMCP",
            dependencies: [
                "TweakKitCore",
                "TweakKitNetworking",
                .product(name: "Telegraph", package: "Telegraph")
            ],
            path: "Sources/TweakKitMCP"
        ),
        .target(
            name: "TweakKitNetworking",
            path: "Sources/TweakKitNetworking"
        ),
        .testTarget(
            name: "TweakKitCoreTests",
            dependencies: ["TweakKitCore"],
            path: "Tests/TweakKitCoreTests"
        ),
        .testTarget(
            name: "TweakKitServerTests",
            dependencies: ["TweakKitServer"],
            path: "Tests/TweakKitServerTests"
        ),
        .testTarget(
            name: "TweakKitMCPTests",
            dependencies: ["TweakKitMCP"],
            path: "Tests/TweakKitMCPTests"
        )
    ]
)
