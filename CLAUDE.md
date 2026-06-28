# CLAUDE.md

このファイルは Claude Code (claude.ai/code) と Claude Agent SDK が本リポジトリで作業するときの起点です。
詳細は `docs/` と各専用ドキュメントに委譲し、ここはコンセプト・地図・規約に徹します。

## プロジェクト概要

metaphor は Processing 由来の発想を持つクリエイティブコーディングライブラリです。Swift + Metal の上に、宣言的・フレームベースで描画する `Sketch` プロトコルを提供します。2D/3D 描画、GPU compute、ポストプロセス、物理、音声を備えます。

- **対象**: macOS 14.0+ / Apple Silicon 専用
- **言語**: Swift 5.10+
- **形態**: マルチターゲット SwiftPM ライブラリ（`shinyaoguri/metaphor`）

## モジュール構成

`import metaphor`（アンブレラ。全モジュールを `@_exported import` で再エクスポート）か、個別モジュールを import します。

- **Tier 1（Core 非依存）**: MetaphorAudio / MetaphorNetwork / MetaphorPhysics / MetaphorML / MetaphorVideo
- **Tier 2（MetaphorCore 依存）**: MetaphorNoise / MetaphorMPS / MetaphorCoreImage / MetaphorRenderGraph / MetaphorSceneGraph

アンブレラターゲット `Sources/metaphor/` はブリッジ拡張（`Sketch+AudioBridge.swift` 等）を持ち、`import metaphor` 利用者に `createAudioInput()` / `createOSCReceiver()` / `createPhysics2D()` などの便利メソッドを提供します。

## ビルド・開発コマンド

```bash
make setup    # 初回: サブモジュール初期化 + Syphon.xcframework ビルド
make build    # swift build
make test     # swift test
make check    # セットアップ状態を確認（Syphon.xcframework / submodules）
make llms-txt # llms.txt（AI 向け API リファレンス）を生成
```

example の実行（各 example は独立した SwiftPM パッケージ）:

```bash
cd Examples/Basics/Form/ShapePrimitives && swift build && swift run
```

セットアップ・全コマンド・トラブルシュートの詳細は [DEVELOPMENT.md](DEVELOPMENT.md) を参照。

### 自動生成される AI 向けファイル

`llms.txt` と `docs/ai/examples-index.{md,json}` はチェックインされていますが **生成物** です。手で編集しないこと。入力を変えたら push 前に再生成します。

| 出力 | 入力 |
|---|---|
| `llms.txt` | `Sources/**/*.swift`, `scripts/generate-llms-txt.py` |
| `docs/ai/examples-index.{md,json}` | `Examples/**`, `scripts/generate-examples-index.py` |

`make setup` が入れる pre-push フックが陳腐化を検出して push を中断します（CI も safety net として再生成）。生成器は決定的であること（全コレクションをソート）——非決定的出力は auto-fix bot が毎回 push する原因になります。

## アーキテクチャ

3 層の API 構造:

```
Sketch protocol extensions  ← ユーザー向け（_activeSketchContext 経由の Processing 風グローバル）
        ↓
   SketchContext             ← Sketch を Canvas2D/Canvas3D へ橋渡し
        ↓
  Canvas2D / Canvas3D        ← 低レベル Metal レンダリング
```

レンダリングは 2 パス。**オフスクリーンパス**（compute → MTLEvent バリア → draw → shadow → RenderGraph → PostProcess → Export/Syphon）の後、**ブリットパス**でアスペクト比を保ってオフスクリーンテクスチャを画面へ転送（レターボックス/ピラーボックス）。これによりレンダリング解像度とウィンドウサイズを分離し、固定解像度 Syphon 出力を可能にします。

主要な設計パターン（GPU インスタンシング、トリプルバッファリング、PBR/Blinn-Phong 切替、シャドウマッピング、シェーダーホットリロード、compute→render の MTLEvent 同期、`MetaphorPlugin` ライフサイクルフック等）と、実装の詳細・デバッグ・拡張ノートは [docs/ai/README.md](docs/ai/README.md) を参照。

### API クイックマップ（機能 → 実装ファイル）

API シグネチャは `llms.txt` にありますが、**どのファイルが実装するか**は載っていません。編集箇所を引くための地図:

- **2D 図形・変換**（circle, rect, line, arc, bezier, push/pop）: `Sketch+Shapes.swift`
- **3D**（box, sphere, camera, perspective, lights, material, pbr）: `Sketch+3D.swift`
- **スタイル**（fill, stroke, strokeWeight, blendMode, tint）: `Sketch+Style.swift`
- **画像・テキスト・書き出し**（loadImage, text, save, beginVideoRecord）: `Sketch+Image.swift`
- **ピクセル**（loadPixels, updatePixels）: `Sketch+Pixels.swift`
- **compute・particles・postFX・GIF・orbitControl**: `Sketch+Advanced.swift`
- **ブリッジ**（audio/video/physics/network/noise/scene/render graph）: `Sketch+*Bridge.swift`
- **Probe（AI）**（probe, MetaphorProbePlugin）: `Sketch+Probe.swift`
- **スタンドアロン noise()**: `Noise.swift`

## ドキュメント階層（真実の在処）

- **CLAUDE.md（本ファイル）**: 玄関口 / コンセプト / 地図 / 規約
- **[DEVELOPMENT.md](DEVELOPMENT.md)**: ライブラリ本体開発者向けのセットアップ・コマンド
- **`llms.txt`**: 公開 API シグネチャ（生成物）
- **[docs/ai/README.md](docs/ai/README.md)**: 実装デバッグ・拡張ノート。スケッチ作者向けは `docs/ai/for-sketch-authors.md` と `docs/ai/examples-index.md`
- **[CONTRACT.md](CONTRACT.md)**: metaphor ⇄ metaphor-cli のクロスリポジトリ契約
- **[docs/adr/](docs/adr/)**: 設計判断の蓄積（Architecture Decision Records）
- **[docs/design/](docs/design/)**: 進行中プロジェクトの設計ドキュメント
- **[docs/releasing.md](docs/releasing.md)**: リリース手順

仕様の根拠は `docs/adr/`、コードの触り方は本ファイルと `docs/ai/`、API は `llms.txt` が真実の在処です。

## AI Probe

`MetaphorProbePlugin` を有効化すると、スケッチが「いま見えている画像」と「内部状態」を AI エージェントへ渡せます。

- **有効化**: 環境変数 `METAPHOR_PROBE=1` で自動登録、または `SketchConfig(plugins: [PluginFactory { MetaphorProbePlugin() }])`。
- **やり取り**: AI が `.metaphor/probe/request.json` を書き、次フレームで処理。出力は `.metaphor/probe/current/frame.{png,json}`（`.tmp` 経由のアトミックリネーム）。
- **状態報告**: スケッチの `draw()` 内で `probe("particles.count", n)`（未登録時は no-op）。
- 複数フレーム取得（`frames`/`every`）やスキーマ（`frame.json` は `schemaVersion: 3`）の詳細は [CONTRACT.md](CONTRACT.md) を参照。例: `Examples/Samples/ProbeSnapshot`。

## クロスリポジトリ契約（metaphor ⇄ metaphor-cli）

`metaphor-cli`（別リポジトリ `shinyaoguri/metaphor-cli`）は本リポジトリを Swift ライブラリとして依存しませんが、**実行時/バイナリ契約**（環境変数、stdin JSON Lines 入力、Probe ファイル、Syphon Release pin）で結合しています。

**重要（エージェント向け）**: 以下に触れる変更は metaphor 単独で完了できません。常に metaphor-cli を同時更新し、両リポの `CONTRACT.md` を揃え、`./scripts/check-contract.sh` が green であることを確認してください。片方のみで作業する場合は、もう片方に対応する PR/Issue を立てること。対象・変更ルールの全体は **[CONTRACT.md](CONTRACT.md)** を参照。

## 規約

- Swift Testing フレームワーク（`@Suite`, `@Test`）を使う。XCTest は使わない。
- 新しい example は既存のレイアウト `Examples/{Category}/{Subcategory}/{Name}/` に従い、各々が自己完結した SwiftPM パッケージ。

## ブランチ運用（GitHub Flow）

- **`main`** が唯一の長命ブランチかつデフォルト。すべての作業は PR 経由で main へ戻る。ルールセットで保護（PR 必須、`build-and-test` 必須、直接 push 不可、**squash のみ**）。
- 非自明な作業（新機能、1〜2 行を超える修正、リファクタ、複数コミットに跨る変更）は main からブランチを切る。命名は kebab-case + カテゴリ接頭辞（`feature/` `fix/` `refactor/` `chore/` `docs/`）。`release/<tag>` は Release ワークフロー予約。

```bash
git checkout -b feature/<name>          # main から
gh pr create --base main                # リリースは --label release:minor 等を付与
gh pr merge --squash --delete-branch    # squash のみ、ブランチ自動削除
```

リリースは PR の `release:*` ラベル駆動（手順は [docs/releasing.md](docs/releasing.md)）。一般的な git 規約（Conventional Commits、1 コミット 1 関心、push は依頼時のみ）はグローバル CLAUDE.md にあり、ここでは繰り返しません。

### Claude への注記

- **ユーザーが明示するまで merge / push しない。** PR を開いたら CI とレビューを待ち、指示があってはじめて `gh pr merge`。`git push` も毎回確認する。
- squash merge のみ。PR タイトル/本文に最終コミットメッセージを 1 本きれいに書く（ブランチ上の各コミットは使い捨て）。
- merge 後は main に戻って pull し、`git fetch -p` でローカルブランチを掃除する。
