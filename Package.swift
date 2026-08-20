// swift-tools-version:6.0
import PackageDescription

#if os(macOS)
let appTargets: [Target] = [
    .executableTarget(
        name: "PoolBar",
        dependencies: ["PoolBarCore"],
        path: "Sources/PoolBar",
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
]
#else
// Linux Cloud Agent / CI can compile PoolBarCore + tests. The menu bar
// executable imports SwiftUI and is macOS-only.
let appTargets: [Target] = []
#endif

let package = Package(
    name: "PoolBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PoolBarCore",
            path: "Sources/PoolBarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ] + appTargets + [
        .testTarget(
            name: "PoolBarTests",
            dependencies: ["PoolBarCore"],
            path: "Tests/PoolBarTests"
        )
    ]
)
