# metaphor

[![Release](https://img.shields.io/github/v/release/shinyaoguri/metaphor?label=version)](https://github.com/shinyaoguri/metaphor/releases/latest)
[![CI](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml/badge.svg)](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![License MIT](https://img.shields.io/github/license/shinyaoguri/metaphor)](LICENSE)

`metaphor` は Processing にインスパイアされた、Swift + Metal のクリエイティブコーディングライブラリです。

`setup()` と `draw()` を書くだけのシンプルな書き味のまま、Metal による高速な 2D / 3D 描画、GPU compute、ポストエフェクト、音声・映像、OSC / MIDI、Core ML、レイトレーシング、Syphon 出力までをひと続きで扱えます。

```swift
import metaphor

@main
final class Hello: Sketch {
    var config: SketchConfig { SketchConfig(width: 800, height: 600) }

    func draw() {
        background(0.05)
        fill(1.0, 0.4, 0.2)
        circle(mouseX, mouseY, 120)
    }
}
```

## Metaphorの特徴

- **Processing の書き味のまま、Metal の速度。** `circle` を並べて書くだけで、Canvas2D / Canvas3D が同じ形状の連続描画を **GPU インスタンシングに自動バッチ** します。10,000 個の円でも CPU 行列計算ゼロ、draw call 1 回。100 万粒子の GPU パーティクルも、`createParticleSystem` 1 行で動きます。
- **2D と 3D が同じ語彙で書ける。** `fill` / `stroke` / `push` / `pop` / `translate` / `rotate` が 2D でも 3D でも同じ感覚で使えます。
- **Apple のグラフィックスフレームワーク全部入り。** Metal / MetalPerformanceShaders（レイトレーシング含む）/ Core ML & Vision / Core Image / AVFoundation / GameplayKit Noise / Syphon / Core MIDI が、1 枚の `Sketch` から呼べる統一 API でラップされています。
- **シェーダーホットリロード。** カスタム MSL を実行中に差し替え可能。`CustomMaterial` / `CustomPostEffect` を `.metal` ファイルから読み込めば、保存するたびに即座に反映されます。
- **ライブ / VJ をそのまま想定。** Syphon 出力、OSC / MIDI 入出力、即時 GUI、Performance HUD、シーン全体の RenderGraph、オービットカメラが標準装備。`live` テンプレートで全部入りスケッチが 1 コマンドで生まれます。
- **作品の書き出しまで完結。** 動画 / GIF / 静止画エクスポートに加えて、オフライン決定論レンダリング（フレームインデックスベースの時間）に対応。リアルタイムで書いたスケッチを、そのまま fixed-FPS の高解像度動画に焼き出せます。

## できること

| 領域 | 主な機能 |
|---|---|
| 2D 描画 | プリミティブ、パス、凹多角形（穴あり）、テキスト、画像、ブレンドモード |
| 3D 描画 | プリミティブ / 自作メッシュ / OBJ・USDZ・ABC ローダー、カメラ、ライト（PBR + Blinn-Phong）、シャドウマップ |
| GPU compute | カスタム MSL カーネル、indirect draw、100万粒子の GPU パーティクル |
| Post-process | bloom、blur、edge detect、カスタム MSL シェーダー、FBO フィードバック |
| 音声 | マイク入力、FFT、ビート検出、サウンドファイル再生 |
| 映像 | カメラ入力、動画再生、動画 / GIF エクスポート |
| 入力 | OSC、MIDI 入出力、マウス、キー、オービットカメラ |
| ML | Core ML、Vision（分類 / 検出 / ポーズ / セグメント / OCR / 顔 など） |
| 高度な機能 | RenderGraph、SceneGraph、2D 物理、Syphon 出力、MPS レイトレーシング |

## Quick Start

`metaphor` CLI を Homebrew でインストールします。

```bash
brew install shinyaoguri/tap/metaphor
```

新しいスケッチを作って実行します。

```bash
metaphor new MySketch
cd MySketch
metaphor run
```

`metaphor run` がパッケージ解決とビルド、ウィンドウ表示までまとめてやってくれます。これだけで始められます。

> Homebrew が使えない環境や手動セットアップは [別のインストール方法](#別のインストール方法) を参照してください。

## はじめてのスケッチ

`metaphor new` が生成する `App.swift` は、Processing と同じ「`setup` で初期化、`draw` を毎フレーム呼ぶ」モデルになっています。

```swift
import metaphor

@main
final class MySketch: Sketch {
    // ウィンドウサイズや title などの設定
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720, title: "MySketch")
    }

    // 起動時に1回だけ呼ばれる
    func setup() {
        // 初期化
    }

    // 毎フレーム呼ばれる
    func draw() {
        background(0.05)
        fill(1.0, 0.4, 0.2)
        circle(mouseX, mouseY, 96)
    }
}
```

### ライフサイクル

| メソッド | 呼ばれるタイミング |
|---|---|
| `setup()` | 起動時に1回 |
| `compute()` | 毎フレーム、`draw` の前（GPU compute 用） |
| `draw()` | 毎フレーム |
| `mousePressed()` / `mouseDragged()` / `mouseScrolled()` など | マウスイベント |
| `keyPressed()` / `keyReleased()` | キーボードイベント |

`noLoop()` で 1 フレームだけ描画して停止、`loop()` で再開、`frameRate(n)` で FPS を指定できます。

### よく使う関数

```swift
// --- 2D shapes
circle(x, y, diameter)
rect(x, y, w, h)
ellipse(x, y, w, h)
line(x1, y1, x2, y2)
triangle(x1, y1, x2, y2, x3, y3)
arc(x, y, w, h, start, stop)
text("hello", x, y)

// --- 3D shapes
box(size)
sphere(radius)
plane(w, h)
cylinder(radius: 0.5, height: 1)
torus(ringRadius: 0.5, tubeRadius: 0.2)

// --- スタイル
background(r, g, b)
fill(r, g, b);  fill(gray)
stroke(r, g, b); strokeWeight(2)
noFill();  noStroke()
blendMode(.add)

// --- 変換（push/pop でスタック）
push()
translate(x, y);  translate(x, y, z)
rotate(angle);    rotateX(a); rotateY(a); rotateZ(a)
scale(s)
pop()

// --- 状態 / ユーティリティ
mouseX, mouseY, frameCount, deltaTime, width, height
random(0, 1);  noise(x, y);  map(v, 0, 1, 100, 200)
```

API 全体は [`llms.txt`](llms.txt) で確認できます（`make llms-txt` で再生成）。

## Templates

`metaphor new` には用途別のテンプレートがあります。

```bash
metaphor new MyScene  --template 3d
metaphor new LiveSet  --template live
metaphor new ShaderLab --template shader
```

| テンプレート | 内容 |
|---|---|
| `2d`（既定） | 最小の 2D スケッチ |
| `3d` | カメラ、ライト、3D プリミティブ |
| `shader` | カスタム Metal ポストエフェクト |
| `live` | GUI、OSC、MIDI、Performance HUD 入り |
| `audio-reactive` | マイク入力と FFT 解析 |
| `raytracing` | Metal レイトレーシングのスターター |
| `syphon` | Syphon 出力向けの固定解像度スケッチ |

## CLI

```bash
metaphor new <name>      # 新しいスケッチを作成
metaphor run             # 現在のスケッチを実行
metaphor doctor          # 環境チェック
metaphor update          # CLI / ライブラリの更新
metaphor examples        # サンプル / テンプレート一覧
metaphor version
```

CLI 本体の更新は Homebrew 経由で行います。

```bash
brew upgrade metaphor          # CLI 本体の更新
metaphor update library        # 現在のスケッチの metaphor 依存を更新
```

## Examples

[Examples/](Examples/) には、Processing 公式サンプルの Swift / Metal 移植と、metaphor 独自機能のサンプルが揃っています。

```bash
cd Examples/Basics/Form/ShapePrimitives
swift run
```

カテゴリ:

- [Basics/](Examples/Basics/) — Processing 標準サンプルの移植（Form / Color / Image / Lights / Math / Transform …）
- [Topics/](Examples/Topics/) — Curves / Shaders / Simulate / GUI などトピック別
- [Demos/](Examples/Demos/) — パフォーマンス系デモ
- [Samples/](Examples/Samples/) — RayTracing / SceneGraph / Syphon / Plugins
- [ML/](Examples/ML/) — Vision / CoreML 連携

## AI による開発支援

`metaphor` は Claude Code / Cursor / Copilot などの LLM ベースのコーディングアシスタントと一緒に使うことを前提に作られています。何をどう書けばいいかを AI が把握しやすいように、以下のものを同梱しています。

- **[`llms.txt`](llms.txt)** — リポジトリ直下に、API 全体を 1 ファイルにまとめた LLM 向けリファレンスがあります。Quick Start、関数シグネチャ、3 層 API アーキテクチャの解説、サンプルコードを含み、**AI のコンテキストに丸ごと貼り付けるだけ** で metaphor の流儀に沿ったコードを書かせられます。`make llms-txt` でソースから再生成できます。
- **[`CLAUDE.md`](CLAUDE.md)** — Claude Code 向けのプロジェクトインストラクション。アーキテクチャ概要、ブランチ運用、リリース手順、API クイックマップが書かれていて、リポジトリを Claude Code で開けばこのプロジェクトの作法を踏まえて作業してもらえます。`metaphor new` で生成されるスケッチにも、簡易版の `CLAUDE.md` テンプレートが入っています。
- **使い方の目安**
  - 自分のスケッチで AI に書かせるとき：`llms.txt` をチャットに貼る、または Cursor / Claude Code でリポジトリごと参照に入れる
  - 「Processing でいうところの○○を metaphor でやって」と聞ける粒度の API ドキュメントが揃っているので、Processing / p5.js / openFrameworks の知識をそのまま AI 経由で持ち込めます

## 他ツールとの比較

`metaphor` の立ち位置をひとことで言うと、**macOS で完結する、現代的で高性能な creative coding スタック** です。Processing の書き味、Apple Silicon ネイティブの性能、AI フレンドリーな開発体験を 1 つに束ねていて、Web も、ゲームエンジンも、ノードベース VJ ツールも兼ねません。代わりに、その中間に空いていたスペースを埋めることを目指しています。

| 項目 | metaphor | Processing | p5.js | openFrameworks | Unity | TouchDesigner |
|---|---|---|---|---|---|---|
| 言語 | Swift | Java | JavaScript | C++ | C# | Python + ノード |
| プラットフォーム | macOS のみ | Win / Mac / Linux | ブラウザ | Win / Mac / Linux | 全プラットフォーム | Win / Mac |
| GPU | Metal ネイティブ | OpenGL | WebGL | OpenGL | DX / Metal / Vulkan | DX / OpenGL |
| GPU compute | あり（MSL） | 限定的 | WebGPU 限定 | 限定的 | あり | あり |
| 反復速度 | 速い | 速い | 即時 | 中 | 遅い | 速い |
| コード中心度 | 高 | 高 | 高 | 高 | 中（GUI 多） | 低（ノード） |
| ライセンス | MIT | LGPL | LGPL | MIT | 商用（制限あり） | 商用（無料枠あり） |
| エコシステム | 小（新しい） | 大 | 大 | 大 | 巨大 | 中 |
| ライブ / VJ | Syphon・OSC・MIDI 標準装備 | ライブラリ次第 | 弱め | 強い | 重い | 最強 |

### vs Processing (Java)

- **共通**: `setup` / `draw` のシンプルな書き味、creative coder 向け API、Examples 移植が豊富
- **metaphor の利点**: Metal ネイティブ性能、GPU compute、PBR + シャドウマップ、100万粒子、Core ML / Vision 統合、Swift の型安全性
- **Processing の利点**: クロスプラットフォーム（Win / Linux）、20 年以上の教材とコミュニティ、初学者向けリソースの厚み、Android / WebGL モード

### vs p5.js

- **共通**: 現代的な書き味、Examples ベースで学べる、creative coder の文化を共有
- **metaphor の利点**: ネイティブ性能、Metal compute、Core ML、動画 / GIF エクスポート、Syphon、ヘビーな 3D / ML を扱える
- **p5.js の利点**: ブラウザだけで動く、URL で作品を共有できる、ゼロインストール、Web エコシステム全体に乗れる

### vs openFrameworks (C++)

- **共通**: ネイティブ性能、フル 3D / GPU、ライブパフォーマンスやインスタレーション用途
- **metaphor の利点**: Swift の安全性とビルド速度、SPM による依存解決、Metal 第一級、AI フレンドリーな API ドキュメント（`llms.txt`）、CLI による `metaphor new` / `run` の即時導線
- **openFrameworks の利点**: クロスプラットフォーム、addon エコシステムの規模、長年の研究・インスタレーション実績、C++ で他の native ライブラリと直結

### vs Unity

- **共通**: 3D、GPU、パーティクル、物理、Audio などカバー範囲が広い
- **metaphor の利点**: コード中心で起動 / 反復が速い、ライブラリとして組み込める、`App.swift` 1 ファイルから始められる、ライセンス料なし、巨大エディタ不要
- **Unity の利点**: 全プラットフォーム対応、Asset Store、ゲーム / VR / AR の総合エンジン、エディタ GUI でのオーサリング、ノンコーダーとの協業

### vs TouchDesigner

- **共通**: ライブパフォーマンス / インスタレーション用途、Syphon、OSC、MIDI
- **metaphor の利点**: コードとして git で version control できる、Swift で型安全、ライセンス料なし、AI / コードベース開発フローと相性が良い
- **TouchDesigner の利点**: ノードベースで非プログラマでも使える、リアルタイムフィードバックの即時性、長年蓄積された VJ / 演出ノウハウ、GPU TOP / CHOP の即興性

### metaphor を選ぶべきとき

- macOS で動く creative coding 作品 / アプリを作りたい
- Processing / p5.js の手軽さは欲しいが、GPU compute や ML や 100 万粒子にも踏み込みたい
- Apple Silicon の性能（Metal、Core ML、MPS、Syphon）を素直に引き出したい
- AI コーディングアシスタント（Claude Code / Cursor）と一緒に開発したい
- Syphon 出力や OSC / MIDI を使ったライブパフォーマンス / VJ を組みたい

### metaphor が向かないとき

- Windows / Linux / モバイル / Web ターゲット → Processing / openFrameworks / p5.js / Unity
- ノードベースの即興 / 非プログラマとの共同作業 → TouchDesigner
- フル機能のゲーム開発 → Unity / Unreal
- 既存の Processing 教材・コミュニティに密着したい → Processing
- ブラウザ上で作品を公開・共有したい → p5.js

## Requirements

- Apple Silicon Mac
- macOS 14.0+
- Xcode 15.0+ / Swift 5.10+

## 別のインストール方法

### ダイレクトインストーラ

Homebrew を使わない場合、シェルスクリプトで CLI を入れられます。

```bash
curl -fsSL https://raw.githubusercontent.com/shinyaoguri/metaphor-cli/main/scripts/install.sh | bash
```

このとき `~/.local/bin` を `PATH` に通してください。

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

以前にダイレクトインストーラで入れた `~/.local/bin/metaphor` が残っていると、Homebrew 版より先に実行されることがあります。Homebrew に切り替える場合は削除してください。

```bash
rm -f ~/.local/bin/metaphor
```

### CLI を使わずに SwiftPM パッケージとして組み込む

通常の Swift Package として依存に追加することもできます。

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.4"),
]
```

ターゲット側:

```swift
.executableTarget(
    name: "MySketch",
    dependencies: [.product(name: "metaphor", package: "metaphor")]
)
```

ただし、はじめて使う場合は `metaphor new` を推奨します。`Package.swift`、テンプレート、リソースディレクトリ、更新導線が最初から揃います。

## ライブラリ本体の開発

`metaphor` 本体の開発、Syphon.xcframework の取り扱い、テスト、リリース手順は [DEVELOPMENT.md](DEVELOPMENT.md) にまとめています。

## Acknowledgements

[Examples/](Examples/) ディレクトリの多くのサンプルは、
Casey Reas、Ben Fry、Daniel Shiffman による
[Processing](https://processing.org/) サンプルスケッチ（public domain）の Swift / Metal 移植です。
個別の帰属情報は各ファイルのヘッダーコメントを参照してください。

- Processing: https://processing.org/
- Processing examples: https://github.com/processing/processing-examples
