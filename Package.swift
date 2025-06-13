// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "HAPTICKAnalyzer",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "HAPTICKAnalyzer",
            targets: ["HAPTICKAnalyzer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/arthenica/ffmpeg-kit.git", from: "5.1.0"),
        .package(url: "https://github.com/AudioKit/AudioKit.git", from: "5.6.1")
    ],
    targets: [
        .target(
            name: "HAPTICKAnalyzer",
            dependencies: [
                .product(name: "FFmpegKit", package: "ffmpeg-kit"),
                .product(name: "AudioKit", package: "AudioKit")
            ],
            path: "Sources"),
        .testTarget(
            name: "HAPTICKAnalyzerTests",
            dependencies: ["HAPTICKAnalyzer"],
            path: "Tests"),
    ],
    swiftLanguageVersions: [.v5]
) 