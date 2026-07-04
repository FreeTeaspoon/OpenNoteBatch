// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenNoteBatch",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "OpenNoteBatch", targets: ["OpenNoteBatch"])
    ],
    targets: [
        .executableTarget(
            name: "OpenNoteBatch",
            path: "Sources/OpenNoteBatch"
        ),
        .testTarget(
            name: "OpenNoteBatchTests",
            dependencies: ["OpenNoteBatch"],
            path: "Tests/OpenNoteBatchTests"
        )
    ]
)
