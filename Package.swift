// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WhisperFlowCore"),
        .executableTarget(name: "WhisperFlow", dependencies: ["WhisperFlowCore"]),
        .testTarget(name: "WhisperFlowTests", dependencies: ["WhisperFlowCore"]),
    ]
)
