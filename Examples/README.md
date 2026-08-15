# Examples

Processing 公式サンプルの Swift / Metal 移植と、metaphor 独自機能のサンプル集です。各サンプルは**独立した SwiftPM パッケージ**で、そのディレクトリに入って `swift run` するだけで動きます。

```bash
cd Basics/Form/ShapePrimitives
swift run
```

## カテゴリ

| カテゴリ | 内容 |
|---|---|
| [Basics/](Basics/) | Processing 標準サンプルの移植。Form / Color / Image / Lights / Math / Transform / Input / Typography など基礎トピック別 |
| [Topics/](Topics/) | 応用トピック別。Curves / Shaders / Simulate / Motion / Fractals and L-Systems / Cellular Automata / GUI / Drawing など |
| [Demos/](Demos/) | パフォーマンス系デモ（GPU パーティクル、インスタンシング比較など） |
| [Samples/](Samples/) | metaphor 独自機能。RayTracing / SceneGraph / Syphon / Plugins / ProbeSnapshot（AI 観測） |
| [ML/](ML/) | Core ML / Vision 連携（顔検出、スタイル変換、画像分類、人物セグメンテーション） |
| [Plugins/](Plugins/) | `MetaphorPlugin` による拡張のサンプル |

## 探し方

- **はじめて metaphor を使う** → [docs/tutorial/](../docs/tutorial/)。順に読んで作品を作れるようになるための読み物（日本語。<!-- tutorial-status: ja-status -->第 1 部〜第 10 部を公開中<!-- /tutorial-status -->）。Examples を掘るのはその後で構いません。
- **順番に学ぶ** → [LEARNING_PATH.md](LEARNING_PATH.md)（英語）。285 本の索引ではなく、難度タグを使ったカテゴリ別の推奨順路（代表 3〜5 本 x 各カテゴリ）です。
- **やりたいことから探す** → [docs/ai/examples-index.md](../docs/ai/examples-index.md)。全サンプルをタグ・難度つきで索引化しています（AI エージェントは MCP の `api_reference` ツールでも同じ索引を引けます）。
- **Processing のサンプル名で探す** → `Basics/` / `Topics/` は Processing 公式サンプルとほぼ同じ階層・名前です。多くのサンプルに元の `.pde` とスクリーンショット `.png` が同梱されています。

## サンプルの構成

各サンプルディレクトリの典型的な中身:

```text
ShapePrimitives/
├── Package.swift        # 独立した SwiftPM パッケージ
├── Sources/…/App.swift  # スケッチ本体
├── ShapePrimitives.pde  # 元になった Processing スケッチ（移植の場合）
├── ShapePrimitives.json # メタデータ（説明・タグ・status）
└── ShapePrimitives.png  # 実行結果画像
```

メタデータの `status` は `supported`（動作する参照実装）/ `partial` / `stub` / `obsolete` のいずれかで、索引と CI のビルドゲートに使われます。

## 実行結果画像（`<Name>.png`）

出所が 2 つあり、台帳 [docs/ai/examples-shots.json](../docs/ai/examples-shots.json) の `origin` で区別します。

- **`processing`** — Processing 原典から移植初日に持ち込んだ 162 枚。metaphor が描いた絵ではないので、**実装と食い違っていることがあります**（実測は [#501](https://github.com/shinyaoguri/metaphor/issues/501) のコメント）。撮影時のソースが分からないため鮮度判定の対象外です
- **`captured`** — `make example-shots` が Probe のヘッドレス実行で撮ったもの。撮影時のソースの指紋を持ち、`--check` が「コードを変えたのに画像が古い」を検出します

```bash
make example-shots                       # 画像がまだ無い example を撮る
make example-shots ARGS="--check"        # 鮮度だけ調べる（撮影しない）
make example-shots ARGS="--compare --only Examples/Basics/Form"  # 原典と並べて見比べる
```

画像は**手で置かないでください**（撮影は生成物で、台帳と対になっています）。撮影には GPU が要るのでローカルで実行します。

撮り方の例外は 2 種類の申告で表します。

- **`no-capture.txt`**（パッケージ直下、理由を 1 行）— 実行環境に依存して絵が決まらないもの（カメラ・外部動画・他アプリの映像入力）、実行可能ターゲットを持たないプラグイン本体、**実装の不具合で絵にならないもの**。最後のものは理由に Issue 番号を書き、直ったらファイルごと消して撮ります
- **`probe-input.jsonl`**（同、JSON Lines の入力台本）— マウス・キーボードの入力が無いと題意が出ないもの。描画ループが回ったのを確かめてから**台本を stdin へ流し、そのうえで撮ります**。書式は[チュートリアルの規約](../docs/tutorial/README.md)（「入力が要る節」）と同じ（`{"t":"mouseMove","x":320,"y":180}` と `{"wait": ミリ秒}`、`//` で意図を書ける）

台本があるものは「撮らない申告」ではなく**こう撮る**という指定です。待ち時間は台本の `wait` が持つので `settle` は使いません。`noLoop()` のスケッチとは両立しない（起動後に置いたリクエストを処理する機会が来ない）ので、両方あると撮影はエラーになります。

待ち時間（描画ループが回ってから撮るまでの秒数、既定 1.5）が合わない example は [docs/ai/examples-shots.config.json](../docs/ai/examples-shots.config.json) に個別に書きます。台帳は生成物なので、手書きの例外はこちらに置きます。

## 新しいサンプルを追加する

既存のレイアウト `{Category}/{Subcategory}/{Name}/` に従い、自己完結した SwiftPM パッケージとして追加してください。追加・変更後は索引の再生成が必要です（生成物を手で編集しないこと）:

```bash
make examples-index
```

## Acknowledgements

`Basics/` と `Topics/` の多くは、Casey Reas、Ben Fry、Daniel Shiffman による [Processing](https://processing.org/) サンプルスケッチ（public domain）の移植です。個別の帰属情報は各ファイルのヘッダーコメントを参照してください。
