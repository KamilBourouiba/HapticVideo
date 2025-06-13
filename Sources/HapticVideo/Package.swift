// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "HaptickVideo",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "HaptickVideo",
            targets: ["HaptickVideo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/arthenica/ffmpeg-kit.git", from: "5.1.0"),
        .package(url: "https://github.com/AudioKit/AudioKit.git", from: "5.6.1")
    ],
    targets: [
        .target(
            name: "HaptickVideo",
            dependencies: [
                .product(name: "FFmpegKit", package: "ffmpeg-kit"),
                .product(name: "AudioKit", package: "AudioKit")
            ],
            path: "Sources/HaptickVideo"),
        .testTarget(
            name: "HaptickVideoTests",
            dependencies: ["HaptickVideo"],
            path: "Tests"),
    ],
    swiftLanguageVersions: [.v5]
) 