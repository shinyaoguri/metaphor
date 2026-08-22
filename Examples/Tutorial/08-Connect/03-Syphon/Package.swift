// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SyphonShare",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
        // Syphon 出力は別パッケージ（metaphor 0.12 で本体から分離。ADR-0014）。
        // 自分のスケッチでは本体も url 依存にする: .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.12.0")
        .package(url: "https://github.com/shinyaoguri/metaphor-syphon.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "SyphonShare",
            dependencies: [
                .product(name: "metaphor", package: "metaphor"),
                .product(name: "MetaphorSyphon", package: "metaphor-syphon"),
            ],
            path: "SyphonShare"
        ),
    ]
)
