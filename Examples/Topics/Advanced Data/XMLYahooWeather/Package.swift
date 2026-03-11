// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "XMLYahooWeather",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "XMLYahooWeather",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "XMLYahooWeather"
        ),
    ]
)
