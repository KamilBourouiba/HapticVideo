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
    dependencies: [
        .package(url: "https://github.com/apple/swift-avfoundation.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-accelerate.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "HapticVideo",
            dependencies: [
                .product(name: "AVFoundation", package: "swift-avfoundation"),
                .product(name: "Accelerate", package: "swift-accelerate")
            ]),
        .testTarget(
            name: "HapticVideoTests",
            dependencies: ["HapticVideo"]),
    ]
) 