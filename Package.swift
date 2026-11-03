// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GTasksTray",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "GTasksTray", resources: [.process("Resources")]),
        .testTarget(name: "GTasksTrayTests", dependencies: ["GTasksTray"])
    ]
)
