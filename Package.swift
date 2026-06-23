// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RogerThatCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "RogerThatCore", targets: ["RogerThatCore"]),
    ],
    targets: [
        .target(
            name: "RogerThatCore",
            path: "Sources/RogerThatCore"
        ),
        .testTarget(
            name: "RogerThatCoreTests",
            dependencies: ["RogerThatCore"],
            path: "Tests/RogerThatCoreTests"
        ),
    ]
)
