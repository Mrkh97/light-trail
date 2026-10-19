// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LightTrail",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LightTrail", path: "Sources/LightTrail"),
    ]
)
