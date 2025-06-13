// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "HapticVideo",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "HapticVideo",
            targets: ["HapticVideo"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HapticVideo",
            dependencies: [],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]),
        .testTarget(
            name: "HapticVideoTests",
            dependencies: ["HapticVideo"]),
    ]
) 