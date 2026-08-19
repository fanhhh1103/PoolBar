// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PoolBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PoolBarCore",
            path: "Sources/PoolBarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PoolBar",
            dependencies: ["PoolBarCore"],
            path: "Sources/PoolBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PoolBarTests",
            dependencies: ["PoolBarCore"],
            path: "Tests/PoolBarTests"
        )
    ]
)
