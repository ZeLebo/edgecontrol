// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeControl",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EdgeControl", targets: ["EdgeControl"])],
    targets: [
        .executableTarget(name: "EdgeControl"),
        .testTarget(name: "EdgeControlTests", dependencies: ["EdgeControl"]),
    ]
)
