# metaphor

[![Release](https://img.shields.io/github/v/release/shinyaoguri/metaphor?label=version)](https://github.com/shinyaoguri/metaphor/releases/latest)
[![CI](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml/badge.svg)](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![License MIT](https://img.shields.io/github/license/shinyaoguri/metaphor)](LICENSE)

`metaphor` は、Processing にインスパイアされた Swift + Metal クリエイティブコーディングライブラリです。

Processing の `setup()` / `draw()` の軽さを保ちながら、Metal による 2D/3D 描画、GPU compute、ポストエフェクト、音声、映像、OSC/MIDI、Core ML、レイトレーシング、Syphon 出力まで扱えることを目指しています。

## Quick Start

まず `metaphor` コマンドを入れます。これは新しいスケッチ作成や更新を扱うためのCLIです。

```bash
curl -fsSL https://raw.githubusercontent.com/shinyaoguri/metaphor-cli/main/scripts/install.sh | bash
```

将来的には Homebrew からもインストールできるようにする予定です。

```bash
brew install shinyaoguri/tap/metaphor
```

`~/.local/bin` が `PATH` に入っていない場合:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

スケッチを作って実行します。

```bash
mkdir -p ~/Repos
cd ~/Repos
metaphor new MySketch
cd MySketch
metaphor run
```

生成される `App.swift` は通常の Swift コードです。

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720, title: "MySketch")
    }

    func draw() {
        background(0.04, 0.05, 0.07)
        fill(1.0, 0.35, 0.18)
        circle(mouseX, mouseY, 96)
    }
}
```

## Templates

`metaphor new` はテンプレートを選べます。

```bash
metaphor examples
metaphor new MyScene --template 3d
metaphor new LiveSet --template live
metaphor new ShaderLab --template shader
```

現在のテンプレート:

- `2d` - 最小の2Dスケッチ
- `3d` - カメラ、ライト、3Dプリミティブ
- `shader` - カスタムMetalポストエフェクト
- `live` - GUI、OSC、MIDI、Performance HUD
- `audio-reactive` - マイク入力とFFT解析
- `raytracing` - Metal ray tracing starter scene
- `syphon` - Syphon出力向け固定解像度スケッチ

## Requirements

- Apple Silicon Mac
- macOS 14.0+
- Xcode 15.0+
- Swift 5.10+

## CLI Commands

```bash
metaphor new <name>
metaphor run
metaphor update
metaphor doctor
metaphor examples
metaphor version
```

よく使うもの:

```bash
metaphor doctor          # Swift / Xcode / template環境を確認
metaphor update          # CLIとライブラリの更新確認
metaphor update self     # metaphor-cli本体を更新
metaphor update library  # 現在のスケッチのmetaphor依存を更新
```

## Manual SwiftPM Setup

CLIを使わずに、通常のSwift Packageとして追加することもできます。

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.4"),
]
```

ターゲットには `metaphor` product を追加します。

```swift
.executableTarget(
    name: "MySketch",
    dependencies: [
        .product(name: "metaphor", package: "metaphor")
    ]
)
```

ただし、はじめて使う場合は `metaphor-cli` による `metaphor new` を推奨します。`Package.swift`、テンプレート、リソースディレクトリ、更新導線が最初から揃います。

## Examples

[Examples/](Examples/) には Processing examples の移植や、metaphor 独自機能のサンプルがあります。

```bash
cd Examples/Samples/RayTracing
swift run
```

## For Library Developers

`metaphor` 本体の開発、Syphon.xcframework の扱い、テスト、リリース手順は [DEVELOPMENT.md](DEVELOPMENT.md) に分けています。

## Acknowledgements

[Examples/](Examples/) ディレクトリの多くのサンプルは、
Casey Reas、Ben Fry、Daniel Shiffman による
[Processing](https://processing.org/) サンプルスケッチ（public domain）の Swift/Metal 移植です。
個別の帰属情報は各ファイルのヘッダーコメントを参照してください。

- Processing: https://processing.org/
- Processing examples: https://github.com/processing/processing-examples
