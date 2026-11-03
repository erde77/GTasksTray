// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GTasksTray",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "GTasksTray"),
        .testTarget(name: "GTasksTrayTests", dependencies: ["GTasksTray"])
    ]
)
