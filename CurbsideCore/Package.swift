// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CurbsideCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CurbsideCore", targets: ["CurbsideCore"]),
        .executable(name: "replay", targets: ["replay"]),
    ],
    targets: [
        .target(name: "CurbsideCore"),
        .executableTarget(name: "replay", dependencies: ["CurbsideCore"]),
        .testTarget(name: "CurbsideCoreTests", dependencies: ["CurbsideCore"]),
    ]
)
