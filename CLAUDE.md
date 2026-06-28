# CLAUDE.md

> NOTE: `AGENTS.md` は `CLAUDE.md` から生成されるコピーです（タイトル行のみ異なる）。
> `CLAUDE.md` を編集し、`make docs-sync` を実行して同期してください（CI で同期を検証します）。

## ビルドコマンド

```bash
make setup           # 初回セットアップ: サブモジュール初期化 + Syphon.xcframework のビルド
make build           # ライブラリのビルド (swift build)
make test            # テスト実行 (swift test)
make clean           # ビルド成果物のクリーン
make check           # セットアップ状態の確認 (Syphon.xcframework, サブモジュール)
make llms-txt        # llms.txt の生成 (AI が読める API リファレンス)
make examples-index  # docs/ai/examples-index.{md,json} の生成
```

サンプルの実行:
```bash
cd Examples/Basics/Form/ShapePrimitives && swift build && swift run
```

AI 向けの詳細なデバッグ・拡張ノートは `docs/ai/README.md` を参照。

### 自動生成される AI 向けファイル

`llms.txt` と `docs/ai/examples-index.{md,json}` はチェックインされているが **自動生成物** であり、手で編集してはいけない。
入力は次のとおり:

| 出力 | 入力 |
|---|---|
| `llms.txt` | `Sources/**/*.swift`, `scripts/generate-llms-txt.py` |
| `docs/ai/examples-index.{md,json}` | `Examples/**`, `scripts/generate-examples-index.py` |

いずれかの入力を変更したら、push 前に再生成すること（`make llms-txt` または `make examples-index`）。
`make setup` が導入する pre-push フックがこれをチェックし、未再生成なら中断する。
CI もこのリポジトリからの PR に対して examples index を自動再生成し、セーフティネットとする。

ジェネレータは決定的でなければならない（壁時計のタイムスタンプを使わず、すべてのコレクションをソートする）— 非決定的だと自動修正ボットが毎回 push し続けることになる。

## アーキテクチャ概要

metaphor は Processing に着想を得た Swift + Metal のクリエイティブコーディングライブラリ。
宣言的なフレームベースのレンダリングを行う `Sketch` プロトコルを提供し、2D/3D 描画、GPU コンピュート、ポストプロセス、物理、オーディオなどを備える。
macOS（Apple Silicon）専用。

### モジュール構成

マルチターゲットの SPM アーキテクチャ。
`import metaphor`（アンブレラ。`@_exported import` で全モジュールを再エクスポート）するか、個別モジュールを import する:

- **Tier 1（Core 依存なし）**: MetaphorAudio, MetaphorNetwork, MetaphorPhysics, MetaphorML, MetaphorVideo
- **Tier 2（MetaphorCore に依存）**: MetaphorNoise, MetaphorMPS, MetaphorCoreImage, MetaphorRenderGraph, MetaphorSceneGraph

アンブレラターゲットはブリッジ拡張（`Sketch+AudioBridge.swift` など）を提供し、`import metaphor` のユーザーが `createAudioInput()`、`createOSCReceiver()`、`createPhysics2D()` などの便利メソッドを使えるようにする。

### 3 層 API アーキテクチャ

```
Sketch protocol extensions  ← ユーザー向け（_activeSketchContext 経由の Processing 風グローバル）
        ↓
   SketchContext             ← Sketch を Canvas2D/Canvas3D に橋渡し
        ↓
  Canvas2D / Canvas3D        ← 低レベルの Metal レンダリング
```

### レンダリングパイプライン

2 パス方式:

1. **オフスクリーンパス**: Compute フェーズ → MTLEvent バリア → Draw フェーズ → Shadow パス → RenderGraph → PostProcess → Export/Syphon
2. **Blit パス**: アスペクト比を保持して（レターボックス/ピラーボックス）オフスクリーンテクスチャを画面に blit する

これによりレンダリング解像度をウィンドウサイズから分離でき、固定解像度での Syphon 出力が可能になる。

### 主要な設計パターン

- **GPU インスタンシング**: Canvas2D/Canvas3D は連続する同一形状の描画を `InstanceBatcher<T>` で自動バッチ化する
- **トリプルバッファ GPU バッファ**: 頂点・インスタンス・`GrowableGPUBuffer` はセマフォ値 3 を使う
- **デュアルパイプライン**: テクスチャなし（positionNormalColor）+ テクスチャあり（positionNormalUV）。それぞれにインスタンシング版がある
- **PBR + Blinn-Phong**: Material3D は `usePBR` フラグに応じて自動切り替え（単一シェーダ・条件分岐）
- **シャドウマッピング**: DrawCall の記録 → 深度のみの shadow パス → PCF 3x3 フィルタリング
- **シェーダのホットリロード**: ShaderLibrary は CustomMaterial/CustomPostEffect 向けに MSL のランタイム再読み込みをサポート
- **Compute→Render 同期**: compute パスと render パスの間の明示的バリアに `MTLEvent` を使う
- **RenderLoopMode**: DisplayLink（デフォルト）または Syphon/export 用の DispatchSourceTimer
- **プラグインプロトコル**: `MetaphorPlugin` がライフサイクルフック（onBeforeRender, onAfterRender, onResize など）を提供する

### Syphon フレームワークの扱い

- **ローカル開発**: Package.swift は `Frameworks/Syphon.xcframework` が存在すればそれを使う（`make setup` がビルド）
- **SPM ユーザー**: GitHub Releases からビルド済み XCFramework のダウンロードにフォールバックする

### API クイックマップ

API シグネチャは `llms.txt`（`make llms-txt` で自動生成）を参照。
llms.txt は全関数を列挙するが **どのファイルが実装しているか** は載せていない — ここでは機能領域をソースに対応づけ、どこを編集すればよいか分かるようにする:

- **2D 図形・変換**（circle, rect, line, arc, bezier, push/pop）: `Sketch+Shapes.swift`
- **3D**（box, sphere, camera, perspective, lights, material, pbr）: `Sketch+3D.swift`
- **スタイル**（fill, stroke, strokeWeight, blendMode, tint）: `Sketch+Style.swift`
- **画像・テキスト・書き出し**（loadImage, text, save, beginVideoRecord）: `Sketch+Image.swift`
- **ピクセル**（loadPixels, updatePixels）: `Sketch+Pixels.swift`
- **コンピュート・パーティクル・postFX・GIF・orbitControl**: `Sketch+Advanced.swift`
- **ブリッジ**（audio/video/physics/network/noise/scene/render graph）: `Sketch+AudioBridge.swift`, `Sketch+VideoBridge.swift`, `Sketch+PhysicsBridge.swift`, `Sketch+NetworkBridge.swift`, `Sketch+NoiseBridge.swift`, `Sketch+SceneGraphBridge.swift`, `Sketch+RenderGraphBridge.swift`
- **Probe（AI）**（probe, MetaphorProbePlugin）: `Sketch+Probe.swift`
- **noise() 単体**: `Noise.swift`

## AI Probe

`MetaphorProbePlugin` を有効化するとスケッチが「いま見えている画像」と「内部状態」を AI エージェントに渡せる。

- 有効化: 環境変数 `METAPHOR_PROBE=1` で自動登録、または `SketchConfig(plugins: [PluginFactory { MetaphorProbePlugin() }])` で明示登録。
- リクエスト: AI 側が `.metaphor/probe/request.json` を `{"id":"snap-1","label":"baseline"}` で書き込む。
  次フレームで処理される（id を変えるたびに 1 回だけ走る）。
- 出力: `.metaphor/probe/current/frame.png` と `frame.json`。
  書き込みは `.tmp` 経由の atomic rename。
- スキーマ: `frame.json` は `schemaVersion: 3`（`stats`=平均色/輝度/内容率・領域、`customTypes`=`probe()` 値の型タグ）。
  完全なスキーマは [CONTRACT.md](CONTRACT.md)。
- 連続フレーム観測: `request.json` に `frames`（採取枚数）/ `every`（ストライド）を指定すると、単一フレームの代わりに `.metaphor/probe/current/sequence/`（`frame.NNNN.{png,json}` + `contact_sheet.png` + `sequence.json` manifest）へ連続フレーム列を書き出す（PR #90、`ProbeSequenceManifest.swift` / `ProbeRequest.swift`）。
  MCP の `capture_sequence` ツールとしての露出は metaphor-cli 側で今後。
- 状態の申告: スケッチの `draw()` の中で `probe("particles.count", n)` のように呼ぶ。
  プラグイン未登録時は no-op。
- 警告: 32x32 サンプルで色分散を測り、blank フレームを `frame.json.warnings` に出す。
- 通常時はリクエストファイルの mtime を見るだけなのでホットパスは触らない。
- サンプル: `Examples/Samples/ProbeSnapshot`

## Cross-Repo Contract (metaphor ⇄ metaphor-cli)

`metaphor-cli`（別リポジトリ `shinyaoguri/metaphor-cli`）はこのリポジトリを Swift ライブラリとしては依存していないが、**ランタイム/バイナリの暗黙の契約** で結合している（環境変数・stdin JSON Lines 入力・Probe ファイル・Syphon の Release pin）。
完全な一覧と変更ルールは **[CONTRACT.md](CONTRACT.md)** を参照。

**重要（エージェント向け）**: 以下に触れる変更は `metaphor` 単体では完結しない。
必ず `metaphor-cli` 側も同時に更新し、両リポジトリの `CONTRACT.md` を揃え、`./scripts/check-contract.sh` が緑であることを確認すること。
片方だけ作業中ならもう片方に対応 PR/Issue を必ず立てる。

- 環境変数 `METAPHOR_VIEWER` / `METAPHOR_SYPHON_NAME` / `METAPHOR_FPS` / `METAPHOR_PROBE`（`SketchRunner.swift`）
- stdin 入力イベントのキー/値（`InputInjectionPlugin.swift`：`mouseDown` 等）
- Probe のパス/スキーマ（`MetaphorProbeConfig.swift` / `ProbeFrameMetadata.swift`）
- Syphon.xcframework の Release 発行（`release.yml`、cli の `Package.swift` が pin）

CI は `scripts/check-contract.sh` で契約トークンの消失を検知する。

## 規約

- macOS 14.0+（Apple Silicon）、Swift 5.10+
- XCTest ではなく Swift Testing フレームワーク（`@Suite`, `@Test`）を使う
- 新しいサンプルは既存のディレクトリ構造に従う: `Examples/{Category}/{Subcategory}/{Name}/`
- 各サンプルは独自の `Package.swift` を持つ独立した SPM パッケージ

## ブランチ運用（GitHub Flow）

- **`main`** — 唯一の長命ブランチでありデフォルトブランチ。
  すべての作業は PR を通じてここに戻る。
  ruleset で保護: PR 必須、`build-and-test` のパス必須、直 push 禁止（削除 / non-fast-forward もブロック）、**squash のみ**。
- `main` から切る feature ブランチは短命で、マージ時に自動削除される。
- CI は `push: main`、`pull_request: main`、`workflow_dispatch` で発火する（Release ワークフローは workflow_dispatch 経由で `release/<tag>` ブランチ上で CI に再入する）。

### リリース

リリースは別ブランチではなく PR の `release:*` ラベル（`release:patch` / `release:minor` / `release:major`）で駆動する — ラベル付き PR を（squash で）マージすると **Release** ワークフローが metaphor と metaphor-cli の両方をタグ付け・公開する。
ラベルなしの PR はリリース **しない**。
完全な手順・手動 `workflow_dispatch` 入力・バージョン bump 操作は **[docs/releasing.md](docs/releasing.md)** を参照。

### ブランチを切るタイミング（Claude デフォルト）

**非自明な** 作業（新機能、1〜2 行を超えるバグ修正、リファクタ、複数コミットになるもの）には `main` からブランチを切る。
`main` へ直接 push しない — ruleset がブロックする。

### 命名

カテゴリ接頭辞付きの kebab-case を使う:
- `feature/<short-name>` — 新しい public API、新モジュール、新サンプル
- `fix/<short-name>` — バグ修正
- `refactor/<short-name>` — API 変更のない内部リファクタ
- `chore/<short-name>` — ツール、CI、ビルドスクリプト
- `docs/<short-name>` — ドキュメントのみ
- `release/<tag>` — Release ワークフロー専用。再利用しない

### 標準フロー

```bash
git checkout -b feature/<name>          # main から; 上の命名を参照
gh pr create --base main                # リリースするなら --label release:minor を付ける
gh pr merge --squash --delete-branch    # squash のみ・ブランチ自動削除
```

一般的な git の作法（Conventional Commits、1 コミット 1 論点、push は頼まれたときだけ）はグローバル CLAUDE.md にあり、ここでは繰り返さない。

### Claude 向けの注意

- **マージ・push はユーザーの明示的な指示があるまで実行しない。**
  PR を作ったら CI とレビューを待ち、`gh pr merge` は指示を受けてから叩く。
  `git push` の可否も都度ユーザーに確認する（グローバル CLAUDE.md の git 安全則に準拠）。
- すべての PR は `main` を対象とする。
  リリースは PR の `release:*` ラベルで駆動される。
- squash マージのみ許可 — PR のタイトル/本文に最終コミットメッセージを 1 つだけきちんと書く。
  ブランチ上の各コミットメッセージは使い捨て。
- マージ後は `main` に戻って pull する。
  ローカルブランチは `git fetch -p` で掃除する。
