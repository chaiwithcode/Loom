// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Loom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LoomCore",
            targets: ["LoomCore"]
        ),
        .executable(
            name: "Loom",
            targets: ["Loom"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .target(
            name: "LoomCore",
            dependencies: [],
            path: "Loom",
            exclude: ["App", "UI", "Update"],
            sources: ["Core", "Providers"]
        ),
        .executableTarget(
            name: "Loom",
            dependencies: [
                "LoomCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Loom",
            exclude: ["Core", "Providers"],
            sources: ["App", "UI", "Update"]
        ),
        .testTarget(
            name: "LoomCoreTests",
            dependencies: ["LoomCore"],
            path: "Tests/LoomCoreTests"
        ),
        .testTarget(
            name: "LoomRegressionTests",
            dependencies: ["LoomCore"],
            path: "Tests/LoomRegressionTests"
        )
    ]
)
