// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevHubCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DevHubCore", targets: ["DevHubCore"]),
        .executable(name: "devhub-scan", targets: ["devhub-scan"])
    ],
    targets: [
        .target(name: "DevHubCore", resources: [.process("Resources")]),
        .executableTarget(name: "devhub-scan", dependencies: ["DevHubCore"]),
        .testTarget(
            name: "DevHubCoreTests",
            dependencies: ["DevHubCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
