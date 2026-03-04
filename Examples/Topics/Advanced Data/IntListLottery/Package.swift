// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "IntListLottery",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "IntListLottery",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "IntListLottery"
        ),
    ]
)
