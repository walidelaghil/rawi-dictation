// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rawi",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RawiCore"),
        .executableTarget(name: "Rawi", dependencies: ["RawiCore"]),
        .testTarget(name: "RawiTests", dependencies: ["RawiCore"]),
    ]
)
