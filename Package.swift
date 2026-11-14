// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayblockCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DayblockCore", targets: ["DayblockCore"]),
        .executable(name: "dayblock-cli", targets: ["dayblock-cli"]),
    ],
    targets: [
        .target(name: "DayblockCore"),
        .executableTarget(name: "dayblock-cli", dependencies: ["DayblockCore"]),
        .testTarget(name: "DayblockCoreTests", dependencies: ["DayblockCore"]),
    ]
)
