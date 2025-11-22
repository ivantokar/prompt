// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CLIKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CLIKit",
            targets: ["CLIKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "CLIKit",
            dependencies: [
                .product(name: "Rainbow", package: "Rainbow")
            ],
            path: "Sources/CLIKit"
        ),
        .testTarget(
            name: "CLIKitTests",
            dependencies: ["CLIKit"],
            path: "Tests/CLIKitTests"
        )
    ]
)
