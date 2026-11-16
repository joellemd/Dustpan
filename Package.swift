// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dustpan",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DustpanCore", targets: ["DustpanCore"]),
        .executable(name: "Dustpan", targets: ["DustpanApp"]),
    ],
    targets: [
        .target(
            name: "DustpanCore",
            resources: [.copy("Rules")]
        ),
        .executableTarget(
            name: "DustpanApp",
            dependencies: ["DustpanCore"]
        ),
        .testTarget(
            name: "DustpanCoreTests",
            dependencies: ["DustpanCore"]
        ),
    ]
)
