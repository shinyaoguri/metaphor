# CLAUDE.md

このファイルは Claude Code (claude.ai/code) と Claude Agent SDK が本リポジトリで作業するときの起点です。
詳細は `docs/` と各専用ドキュメントに委譲し、ここはコンセプト・地図・規約に徹します。

## プロジェクト概要

metaphor は Processing 由来の発想を持つクリエイティブコーディングライブラリです。Swift + Metal の上に、宣言的・フレームベースで描画する `Sketch` プロトコルを提供します。2D/3D 描画、GPU compute、ポストプロセス、物理、音声を備えます。

- **対象**: macOS 14.0+ / Apple Silicon 専用
- **言語**: Swift 5.10+（最小サポート = Xcode 15.4。per-PR CI の `build-swift-5-10` ジョブが旧ツールチェーンでのビルドを検証 — 新 SDK 限定シンボルの混入はここで捕まる）
- **形態**: マルチターゲット SwiftPM ライブラリ（`shinyaoguri/metaphor`）

## モジュール構成

`import metaphor`（アンブレラ。全モジュールを `@_exported import` で再エクスポート）か、個別モジュールを import します。

- **Tier 1（Core 非依存）**: MetaphorAudio / MetaphorNetwork / MetaphorPhysics / MetaphorML / MetaphorVideo
- **Tier 2（MetaphorCore 依存）**: MetaphorNoise / MetaphorMPS / MetaphorCoreImage / MetaphorRenderGraph / MetaphorSceneGraph / MetaphorSyphon

Syphon 出力は `MetaphorSyphon` が持ち、`Syphon` binaryTarget もこのターゲットだけ。`MetaphorCore` は Syphon 非依存で、出力は `MetaphorOutputRegistry` 経由（`import metaphor` なら自動登録により従来どおり `config.syphon` が使えます）。

アンブレラターゲット `Sources/metaphor/` はブリッジ拡張（`Sketch+AudioBridge.swift` 等）を持ち、`import metaphor` 利用者に `createAudioInput()` / `createOSCReceiver()` / `createPhysics2D()` などの便利メソッドを提供します。

## ビルド・開発コマンド

```bash
make setup    # 初回: サブモジュール初期化 + Syphon.xcframework ビルド
make build    # swift build
make test     # swift test
make ci-check # CI と同条件（-Xswiftc -warnings-as-errors）で build + test — push 前に通す
make check    # セットアップ状態を確認（Syphon.xcframework / submodules）
make llms-txt # llms.txt（AI 向け API リファレンス）を生成
```

example の実行（各 example は独立した SwiftPM パッケージ）:

```bash
cd Examples/Basics/Form/ShapePrimitives && swift build && swift run
```

セットアップ・全コマンド・トラブルシュートの詳細は [DEVELOPMENT.md](DEVELOPMENT.md) を参照。

### 自動生成される AI 向けファイル

`llms.txt` / `docs/ai/examples-index.{md,json}` / `Sources/MetaphorCore/Shaders/ShaderSources/*.txt` は生成物です。手で編集せず、入力を変えたら push 前に再生成します（pre-push フックと CI が陳腐化を検出、llms.txt はセッション終了時の Stop hook でも自動再生成）。入力と再生成コマンドの対応表は [DEVELOPMENT.md](DEVELOPMENT.md) の「生成物の管理」、Sources 編集時は metaphor-contrib:generated-artifacts スキルが手順を案内します。

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
- **ブリッジ**（audio/video/physics/network/noise/scene/render graph）: `Sketch+AudioBridge.swift`, `Sketch+VideoBridge.swift`, `Sketch+PhysicsBridge.swift`, `Sketch+NetworkBridge.swift`, `Sketch+NoiseBridge.swift`, `Sketch+SceneGraphBridge.swift`, `Sketch+RenderGraphBridge.swift`
- **Probe（AI）**（probe, MetaphorProbePlugin）: `Sketch+Probe.swift`
- **Parameter Store**（`@Param`, params, ParameterPlugin, `gui.params()`）: `Parameters/*.swift`, `Sketch+Params.swift`, `UI/ParameterGUI+Params.swift`
- **スタンドアロン noise()**: `Noise.swift`

## ドキュメント階層（真実の在処）

読者別の入口・ディレクトリ構成・「どれが正か」の一覧は [docs/README.md](docs/README.md) が正本です。本ファイルは玄関口 / コンセプト / 地図 / 規約に徹します。エージェントが最頻で参照するのは次の 4 つ:

- **`llms.txt`**: 公開 API シグネチャ（生成物）
- **[docs/ai/README.md](docs/ai/README.md)**: 実装デバッグ・拡張ノート
- **[docs/adr/](docs/adr/)**: 設計判断の根拠
- **[CONTRACT.md](CONTRACT.md)**: metaphor ⇄ metaphor-cli の契約

**ユーザー影響のある変更を入れたら [CHANGELOG.md](CHANGELOG.md) ではなく [`changelog.d/`](changelog.d/README.md) に 1 ファイル置く**（`<slug>.<category>.md`。破壊的変更は `.breaking.md`）。リリース時に集約・昇格され、どちらも空のままだとリリースが中断します。

## AI Probe

`MetaphorProbePlugin`（環境変数 `METAPHOR_PROBE=1` で自動登録）を有効化すると、実行中スケッチの「いま見えている画像」と「内部状態」を AI エージェントへ渡せます。wire format・複数フレーム取得・スキーマの詳細は [CONTRACT.md](CONTRACT.md)、例は `Examples/Samples/ProbeSnapshot`。

## クロスリポジトリ契約（metaphor ⇄ metaphor-cli）

`metaphor-cli`（別リポジトリ `shinyaoguri/metaphor-cli`）とは実行時/バイナリ契約（環境変数、stdin JSON Lines 入力、Probe ファイル、Syphon Release pin）で結合しています。**契約対象に触れる変更は metaphor 単独で完了できません** — 常に metaphor-cli 側と揃えます。対象・変更ルールは [CONTRACT.md](CONTRACT.md) が正本で、契約ファイルに触れると metaphor-contrib:cross-repo-contract スキルが手順を案内します。

## 規約

- Swift Testing フレームワーク（`@Suite`, `@Test`）を使う。XCTest は使わない。
- 新しい example は既存のレイアウト `Examples/{Category}/{Subcategory}/{Name}/` に従い、各々が自己完結した SwiftPM パッケージ（[Examples/README.md](Examples/README.md) 参照）。追加後は `make examples-index` で索引を再生成。

## ブランチ運用（GitHub Flow）

- `main` が唯一の長命ブランチかつデフォルト。すべての作業は PR 経由で main へ戻る。ルールセットで保護（PR 必須、集約ゲート `ci-gate` 必須、直接 push 不可、**squash のみ**）。
- `release/<tag>` は Release ワークフロー予約。リリースは PR の `release:*` ラベル駆動（手順は [docs/releasing.md](docs/releasing.md)）。
- ブランチ命名・Conventional Commits・1 コミット 1 関心などの一般的な git 規約はグローバル CLAUDE.md にあり、ここでは繰り返しません。

### Claude への注記

- push / merge の判断基準（丁寧なコミットログと PR 本文・green なら指示を待たず merge・不可逆操作のみ事前確認）はグローバル CLAUDE.md に従う。
- squash merge のみ。PR タイトル/本文に最終コミットメッセージを 1 本きれいに書く（ブランチ上の各コミットは使い捨て）。
- merge は `gh pr merge --squash --auto` で手離れさせる（CI green で自動 merge され、BEHIND でも追随不要 — [docs/releasing.md](docs/releasing.md) の "Merging PRs"）。CI を watch して手動 merge する運用はしない。
- 描画結果が変わる PR には before/after 画像を PR 本文に載せる（手順は [DEVELOPMENT.md](DEVELOPMENT.md) の「PR に見た目の証跡を載せる」）。
- 並行してエージェント/PR を走らせるときの合流点ルール: 同時 in-flight PR は 3 本程度まで / 同じファイル群（特に Sources 全域・生成物）を触るタスク同士は直列に / Sources 系と docs 系を混ぜてバッチを組む / 生成物が conflict したら `git merge origin/main` 後に再生成すれば常に正。
- merge 後は main に戻って pull し、`git fetch -p` でローカルブランチを掃除する。

### 気付きは Issue へ

本題以外のバグ・ドキュメント不備・改善アイデアはその場で直さず、気軽に Issue を起票する（手順は metaphor-contrib:quick-issue スキル）。CLI 側の事象は `shinyaoguri/metaphor-cli` へ、両リポに跨るものは両方に立てて相互リンクします（[CONTRACT.md](CONTRACT.md) 参照）。
