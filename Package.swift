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
    dependencies: [],
    targets: [
        .target(
            name: "LoomCore",
            dependencies: [],
            path: "Loom",
            exclude: ["App", "UI"],
            sources: ["Core", "Providers"]
        ),
        .executableTarget(
            name: "Loom",
            dependencies: ["LoomCore"],
            path: "Loom",
            exclude: ["Core", "Providers"],
            sources: ["App", "UI"]
        ),
        .testTarget(
            name: "LoomCoreTests",
            dependencies: ["LoomCore"],
            path: "Tests/LoomCoreTests"
        )
    ]
)
