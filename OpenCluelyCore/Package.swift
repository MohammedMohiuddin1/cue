// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenCluelyCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenCluelyCore", targets: ["OpenCluelyCore"]),
    ],
    targets: [
        .target(name: "OpenCluelyCore"),
        .testTarget(
            name: "OpenCluelyCoreTests",
            dependencies: ["OpenCluelyCore"]
        ),
    ]
)
