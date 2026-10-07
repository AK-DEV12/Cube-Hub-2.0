// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CubeHub",
    platforms: [.macOS("15.0")],
    targets: [
        .target(name: "CubeHubCore"),
        .executableTarget(name: "CubeHub", dependencies: ["CubeHubCore"]),
        .testTarget(name: "CubeHubCoreTests", dependencies: ["CubeHubCore"]),
    ]
)
