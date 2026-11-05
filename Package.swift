// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SpotPen",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "SpotPen",
            targets: ["SpotPen"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SpotPen",
            dependencies: [],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["SpotPen"],
            path: "Tests/AppTests"
        )
    ]
)
