# metaphor

[![Release](https://img.shields.io/github/v/release/shinyaoguri/metaphor?label=version)](https://github.com/shinyaoguri/metaphor/releases/latest)
[![CI](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml/badge.svg)](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![License MIT](https://img.shields.io/github/license/shinyaoguri/metaphor)](LICENSE)

`metaphor` は、**AI と人間が同じ実行中の作品を観測・操作・反復できる、Apple ネイティブのクリエイティブコーディング・ランタイム**です。

Processing 譲りの `setup()` / `draw()` を入口に、Metal で作品を成立させ、**Probe + ライブビューア + ローカル MCP** の三点で「AI が"いま見えている絵"と内部状態を見ながら直す」観測ループを回せます。差別化は Swift/Metal そのものではなく、この観測ループにあります。

書き味はそのまま、高速な 2D / 3D 描画、GPU compute、ポストエフェクト、音声・映像、OSC / MIDI、Core ML、レイトレーシング、Syphon 出力までを、ひと続きの API で扱えます。

```swift
import metaphor

@main
final class Hello: Sketch {
    var config: SketchConfig { SketchConfig(width: 800, height: 600) }

    func draw() {
        background(13)
        fill(255, 102, 51)
        circle(mouseX, mouseY, 120)
    }
}
```

## Metaphorの特徴

- **中心はこれ ― AI が「いま見えている絵」を見ながら作れる。** Probe がフレーム画像と内部状態をファイルに書き出し、`metaphor mcp` がそれを MCP ツール（`snapshot` / `input` / `build_status` / `api_reference`）として AI エージェントに渡します。AI が **観測 → 編集 → 再観測 → 検証** のループを自分で回せる。差別化は Swift/Metal そのものではなく、この **Probe + ライブビューア + ローカル MCP** の三点セットにあります（[AI と協調する](#ai-と協調する観測--操作--反復)）。
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

## 開発スタイル

metaphor は **人力だけでも、AI と一緒でも** 使えます。スタイルは「誰が書くか（人力 / AI / 協調）」×「ツール（`metaphor` CLI を使う / SwiftPM だけ）」で決まります。中でも **「AI と協調する」行 ― AI が動作中のスケッチを観測しながら直すモード ― が metaphor 固有の使い方**です。

| | CLI を使う（`metaphor` コマンド） | CLI を使わない（SwiftPM だけ） |
|---|---|---|
| **人力で書く** | `metaphor new` → `metaphor run` / `metaphor watch`（ライブリロード）。最短で始められる。 | `.package(url:)` で依存に追加して `swift run`。Xcode や既存プロジェクトに組み込みたいとき。 |
| **AI に書かせる** | 上記に加え、AI が `llms.txt` を参照してコード生成。`metaphor run` で確認。 | `llms.txt` を AI に渡してコード生成し、`swift run` / Xcode で確認。 |
| **AI と協調する**<br>（AI が動作中のスケッチを観測） | `metaphor mcp` を登録すると AI が `snapshot` で**結果を見ながら**反復。`metaphor watch` を足せば人間も同じ実体を共有。 | **✗ 観測ループは不可。** `snapshot` は CLI（`metaphor mcp`）が提供するため、AI はコード生成までに留まる。 |

要点:

- **最短で始める** → CLI（`metaphor new` / `run`）。[Quick Start](#quick-start)
- **AI に「いま見えている絵」を観測させる**にはCLIが要る。`metaphor mcp` が Probe を MCP 化する。[AI と協調する](#ai-と協調する観測--操作--反復)
- **CLI なしでもライブラリは完全に使える。** AI には `llms.txt` を渡せばよい。[SwiftPM パッケージとして組み込む](#swiftpm-パッケージとして組み込む) / [AI による開発支援](#ai-による開発支援)

## AI と協調する（観測 → 操作 → 反復）

metaphor は、AI エージェントが実行中のスケッチを観測しながら開発できるよう設計されています。一般的な LLM はソースコードしか参照できませんが、metaphor では `metaphor mcp` を AI クライアント（Claude Code / Cursor など）に MCP サーバとして登録すると、エージェントが **レンダリング結果の画像と内部状態** を取得し、再ビルドの結果まで確認しながら「観測 → 編集 → 再観測 → 検証」を自律的に反復できます。

| ツール | 役割 |
|---|---|
| `snapshot` | 現在フレームの画像（PNG）と内部状態（`frameCount` / `time` / `probe()` 値 / 色・領域統計 / 警告）を返す |
| `input` | 実行中のスケッチへマウス・キー入力を送る |
| `build_status` | 直近の `swift build` の成否とエラーを返す |
| `api_reference` | 依存先 metaphor の API ドキュメント（作法ガイド / 全 API / サンプル索引）を返す。新しい API を使う前に参照する |

さらに、人間が VSCode で `metaphor watch` を起動しておくと、AI の `metaphor mcp` は **同じ実行中スケッチにアタッチ**して観測します（共有セッション）。人間はライブビューア窓で見ながら編集し、AI はファイル編集と `snapshot` で協調できます。

この観測の仕組み自体は metaphor 本体の機能（**Probe** プラグイン）です。内部状態を AI に渡すには `draw()` 内で `probe("count", n)` のように申告します（[`Examples/Samples/ProbeSnapshot`](Examples/Samples/ProbeSnapshot)）。

- **セットアップ手順**（`claude mcp add` / `.mcp.json`）・共有セッション・プロセス構成 → **[metaphor-cli の「AI と協調する」](https://github.com/shinyaoguri/metaphor-cli#ai-と協調する)**
- **設計** → [docs/design/ai-mcp-server.md](docs/design/ai-mcp-server.md) / [docs/design/shared-session.md](docs/design/shared-session.md)
- **AI に metaphor 流のコードを書かせる**静的コンテキスト（`llms.txt` 等） → [AI による開発支援](#ai-による開発支援)

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

> `metaphor` コマンド（インストールの他の方法・全コマンド・テンプレート）は **[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli)** が提供します。CLI を使わずライブラリだけを使う場合は [SwiftPM パッケージとして組み込む](#swiftpm-パッケージとして組み込む) を参照してください。

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
        background(13)
        fill(255, 102, 51)
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

// --- スタイル（色は既定で 0〜255。Processing と同じ。colorMode で変更可）
background(r, g, b)
fill(r, g, b);  fill(gray)
stroke(r, g, b); strokeWeight(2)
noFill();  noStroke()
blendMode(.additive)

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

## CLI

`metaphor` コマンドは新規作成・実行・ライブリロード・AI 連携をまとめて提供します。

```bash
metaphor new <name>   # テンプレートから新しいスケッチを作成（2d / 3d / shader / live / audio-reactive / raytracing / syphon）
metaphor run          # 現在のスケッチを実行（解決・ビルド・表示）
metaphor watch        # 編集を監視し、ライブビューア窓を保ったまま再ビルド差し替え
metaphor mcp          # AI エージェント向け MCP サーバ（snapshot / input / build_status / api_reference）
metaphor doctor       # 環境チェック
metaphor update       # CLI / ライブラリの更新
```

全コマンド・テンプレート・インストール方法の詳細は **[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli)** を参照してください。

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

[AI と協調する](#ai-と協調する観測--操作--反復) が **動いているスケッチを観測して回すループ**だとすれば、こちらは **AI に metaphor 流のコードを書かせる**ための静的コンテキストです。`metaphor` は Claude Code / Cursor / Copilot などの LLM ベースのコーディングアシスタントと一緒に使うことを前提に作られています。何をどう書けばいいかを AI が把握しやすいように、以下のものを同梱しています。

- **[`llms-sketch.txt`](llms-sketch.txt)** — スケッチ作者向けの短い AI コンテキスト。`setup()` / `draw()` の書き方、よく使う API、避けるべき重い処理を素早く共有できます。
- **[`llms.txt`](llms.txt)** — リポジトリ直下に、API 全体を 1 ファイルにまとめた LLM 向けリファレンスがあります。Quick Start、関数シグネチャ、3 層 API アーキテクチャの解説、サンプルコードを含み、**AI のコンテキストに丸ごと貼り付けるだけ** で metaphor の流儀に沿ったコードを書かせられます。`make llms-txt` でソースから再生成できます。
- **[`docs/ai/`](docs/ai/)** — Examples 索引、スケッチ作者向けガイド、用途別プロンプト、インストール形態ごとの効き方をまとめています。
  - [`docs/ai/for-sketch-authors.md`](docs/ai/for-sketch-authors.md) — AI と一緒にスケッチを書くためのガイド
  - [`docs/ai/install-scenarios.md`](docs/ai/install-scenarios.md) — SwiftPM / CLI / ローカル checkout 別の効き方
  - [`docs/ai/prompts/`](docs/ai/prompts/) — 用途別（audio-reactive、shader など）プロンプトテンプレート
- **[`CLAUDE.md`](CLAUDE.md)** — このライブラリ自体を AI と保守・拡張するためのプロジェクトインストラクションです。`metaphor new` で生成されるスケッチには、制作意図を共有するための `AGENTS.md` と `PROJECT_BRIEF.md` が入ります。
- **使い方の目安**
  - 自分のスケッチで AI に書かせるとき：`llms.txt` をチャットに貼る、または Cursor / Claude Code でリポジトリごと参照に入れる
  - 「Processing でいうところの○○を metaphor でやって」と聞ける粒度の API ドキュメントが揃っているので、Processing / p5.js / openFrameworks の知識をそのまま AI 経由で持ち込めます

## 他ツールとの比較

`metaphor` の立ち位置はひとことで言うと **「Processing の書き味 × Apple Silicon ネイティブ × AI が観測・操作・反復できる」**。macOS に振り切ることで、Web やゲームエンジン、ノードベース VJ ツールの中間に空いていた場所を、**AI と協調できるコードファーストのランタイム**として埋めることを目指しています。

- **vs Processing / p5.js** — `setup` / `draw` の書き味は同じ。代わりに Metal ネイティブの GPU compute、PBR、Core ML、100 万粒子といった重い処理に踏み込めます。クロスプラットフォーム（Win / Linux / ブラウザ）が必要なら向こうが有利。
- **vs openFrameworks** — Swift と SPM で依存解決とビルドが速く、Metal が第一級。代わりに Win / Linux 対応や C++ addon の蓄積は openFrameworks に分があります。
- **vs Unity** — コード中心で `App.swift` 1 ファイルから即起動、ライセンス料なし。フル機能のゲーム開発、全プラットフォーム展開、エディタ GUI が必要なら Unity。
- **vs TouchDesigner** — git で version control できるコードベース、AI 開発フローと相性が良い。ノードベースで即興・非プログラマと協業するなら TouchDesigner。

**選ぶべきとき**: **AI と協調して作品を作りたい（AI が動作中の絵を観測しながら反復）** / macOS で動く作品を作りたい / Apple Silicon の性能（Metal・Core ML・MPS・Syphon）を引き出したい / Syphon・OSC・MIDI を使ったライブパフォーマンスを組みたい。

**向かないとき**: Windows・Linux・モバイル・Web ターゲット / ノードベースの即興 / フル機能のゲーム開発。

## Requirements

- Apple Silicon Mac
- macOS 14.0+
- Xcode 15.0+ / Swift 5.10+

## Troubleshooting

- **`make build` が失敗する / Syphon.xcframework が無い** — 初回は `make setup` を実行して
  サブモジュール初期化と Syphon.xcframework のビルドを済ませてください。状態は `make check`
  で確認できます。
- **ライブビューア（`metaphor watch`）が真っ黒** — CLI 側の事象です。
  [metaphor-cli の Troubleshooting](https://github.com/shinyaoguri/metaphor-cli#troubleshooting)
  を参照してください。
- **AI から「いま見えている絵」を観測できない** — `metaphor watch`（共有セッション）が動いて
  いるか、`metaphor mcp` を同じディレクトリで実行しているかを確認してください。
- **`llms.txt` が古い / CI で stale と言われる** — public API を変更したら `make llms-txt` を
  実行してコミットしてください（pre-push フックと CI が鮮度を検証します）。

## SwiftPM パッケージとして組み込む

CLI（Homebrew / ダイレクトインストーラ / ソースビルド）の各インストール方法は **[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli#install)** にまとめています。

CLI を使わず、`metaphor` を通常の Swift Package として依存に追加することもできます。

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.3.0"),
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
