// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReshimaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReshimaCore",
            targets: ["ReshimaCore"]
        )
    ],
    targets: [
        .target(
            name: "ReshimaCore",
            path: "ios/Reshima/Models"
        ),
        .testTarget(
            name: "ReshimaTests",
            dependencies: ["ReshimaCore"],
            path: "ios/ReshimaTests"
        )
    ]
)
