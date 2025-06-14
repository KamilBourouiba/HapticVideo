// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "HapticVideo",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
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
            path: "Sources/HapticVideo",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]),
    ],
    swiftLanguageVersions: [.v5]
) 