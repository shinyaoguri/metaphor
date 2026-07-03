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
└── ShapePrimitives.png  # スクリーンショット
```

メタデータの `status` は `supported`（動作する参照実装）/ `partial` / `stub` / `obsolete` のいずれかで、索引と CI のビルドゲートに使われます。

## 新しいサンプルを追加する

既存のレイアウト `{Category}/{Subcategory}/{Name}/` に従い、自己完結した SwiftPM パッケージとして追加してください。追加・変更後は索引の再生成が必要です（生成物を手で編集しないこと）:

```bash
make examples-index
```

## Acknowledgements

`Basics/` と `Topics/` の多くは、Casey Reas、Ben Fry、Daniel Shiffman による [Processing](https://processing.org/) サンプルスケッチ（public domain）の移植です。個別の帰属情報は各ファイルのヘッダーコメントを参照してください。
