# ADR-0003: 即時描画を順序保持コマンド記録へ統一する（main パス 2D/3D の単一ストリーム化）

- **Status**: Accepted
- **Date**: 2026-06-30
- **Deciders**: PR #110 レビューで確定
- **PR / Commit**: ADR #110。実装 #111（seq 基盤）→ #112（2D コマンド化・宿題②③④）→ #113（seq interleave・宿題①）

## Context

AI 協調ループ（Probe）が「編集 → 再観測」で意図通りの絵を検証するには、レンダリングの決定論性が前提（Epic #75 P1 / Issue #71）。ADR-0002（#70）は決定論化の第一歩として **影オン時のみ作動する部分的コマンド記録** を導入した。しかし 2D（`Canvas2D`）と 3D（`Canvas3D`）は **別ストア・固定再生順** で記録される:

- 3D は `Canvas3D.recordedDrawCalls: [DrawCall3D]`（型付きスナップショット）に記録。
- 2D は `Canvas2D.deferredDraws: [(MTLRenderCommandEncoder) -> Void]`（クロージャ）に遅延。
- 再生は [`SketchContext.replayDeferredMain`](../../Sources/MetaphorCore/Sketch/SketchContext.swift#L307) が `canvas3D.replayMainPass` → `canvas.replayForeground` の **2段固定順**。

呼び出し順を保持する統一ストリームが存在しないため、ADR-0002 は4つの宿題を残した:

1. **順序前面化**: `background()` 以外の 2D を「3D の背後」に意図描画しても 3D の前面に出る（任意順序が保持されない）。
2. **massive 非描画**: 影オン時に `Canvas2DMassive`（`circles()` 等のオンザフライ即時パス）が記録経路で黙って捨てられる（`drawCircleInstances` の encoder 必須ガード、[Canvas2DMassive.swift:94](../../Sources/MetaphorCore/Drawing/Canvas2DMassive.swift#L94)）。
3. **clip 損失**: 2D の scissor/clip 途中変更（`beginClip`/`endClip`）が遅延ストリームに載らず、前景再生で失われる。
4. **クロージャ捕捉**: 2D 遅延がクロージャで型情報を持たず、検査・テスト・順序マージができない。

Probe の決定論観測を全スケッチへ広げるには、main パスを **呼び出し順を保持する単一コマンドストリーム** へ統一する必要がある。

制約: 公開 API 不変が目標。レンダラ中核は 850 テストの土台に影響するため高リスク。Issue #71 / Epic #75 が「着手前に設計チェックポイント必須」と明記（本 ADR がそのゲート）。

スコープの前提として、`renderFrame` 後段（RenderGraph.execute → PostProcess.apply → save/export/Syphon → plugin.post → commit、[MetaphorRenderer.swift:895-988](../../Sources/MetaphorCore/Core/MetaphorRenderer.swift#L895)）は既に **単一 commandBuffer 内で線形・決定論的にエンコード** されている。テクスチャを介した宣言的パイプラインで `frameToken` メモ化済み。

## Considered Options

### Option A: RenderGraph/PostProcess/outputs まで含む完全決定論パイプライン（スコープ b）
- Pros: 2D/3D に加え後段まで一貫したコマンド記録に乗り、理屈上は根治。
- Cons: 後段は既に線形決定論なので投資対効果が薄い。non-determinism があるとすればプラグイン（Syphon 等）や GPU タイミングで、main 記録化とは独立。main と後段を一度に書き換えると「850 テストの土台を一度に揺らす」（ADR-0002 Option A の轍）。リスク過大。

### Option B: #70 のまま、宿題を個別パッチで潰す
- Pros: 最小変更。
- Cons: 2D/3D が別ストア・固定再生順のままでは、宿題①（任意の重ね順保持）が **原理的に解けない**。massive/clip も場当たり対応になり、クロージャ型（宿題④）も残る。決定論観測を全スケッチへ広げられない。

### Option C（採用）: main パスを順序保持コマンドストリームに統一。影非依存に一般化しフラグで opt-in、影オフ既定は即時フォールバック維持
- 2D/3D を共通の単調シーケンス番号で記録し、再生時に seq 昇順でマージ → 単一メインパスへ交互再投入。
- 2D のクロージャを明示コマンド型 `Deferred2DCommand` enum へ昇格（宿題④）。massive/clip もコマンド化（宿題②③）。
- 活性化は `shouldRecordMainPass`（既定 = 影オン時のみ）に一般化し、`METAPHOR_COMMAND_RECORD` 環境変数で影オフスケッチにも opt-in 拡大可能にする。影オフ既定は従来の即時経路をフォールバックに残す。
- Pros: 宿題①〜④を根治。後段（既に決定論）を触らずリスクを main パスに局所化。影オフ既定は無変更で回帰ゼロ。スコープ (b) への前方互換。単一分岐点（`renderFrame` の `shadowDeferActive`）でいつでも旧経路へロールバック可。
- Cons: 順序保持により 2D/3D の重ね順が #70 と変わる箇所がある（影オン e2e の期待値更新・実機目視必須）。PR 数が増える。記録/再生の CPU オーバーヘッドが opt-in 拡大時に全スケッチへ及ぶ。深度あり 3D と深度なし 2D の交互合成セマンティクスを文書化する必要。

## Decision

Option C を採用する。決め手は「宿題①〜④を根治しつつ、変更を main パス・影オン経路に局所化し、影オフ既定を無変更に保てる（回帰ゼロ）」こと。後段の完全決定論（スコープ b）は既に達成済みの領域に投資することになり、リスクだけが増えるため follow-up Epic へ分離する。

具体（実装は段階導入。各 PR が独立して 850 緑を維持。#70 の #107 → #108 → #109 を踏襲）:

1. **基盤**: `SketchContext` に単調 seq 払い出し（`nextDrawSeq()`、フレーム頭でリセット）を置き、両 Canvas に `seqProvider` をクロージャ注入（Canvas は Context を直接知らず依存方向を保つ）。`DrawCall3D` に `seq` を追加。2D 遅延を `Deferred2DCommand` enum へ昇格。
2. **2D 載せ替え**: `flushColorVertices`/`flushTexturedVertices`/`flushInstancedBatch` のクロージャ append を enum case へ。`beginClip`/`endClip` を `setScissor` コマンド化（宿題③）。massive を遅延コマンド化（宿題②）。この段階では再生順は 3D → 2D のまま（挙動同値）。
3. **順序統合**: `replayDeferredMain` を「2D/3D を seq 昇順マージ → 隣接同種を run にグルーピング → 単一エンコーダへ交互再投入」へ書き換え（宿題①）。`defersMainPassForShadow` を `shouldRecordMainPass` に一般化し、`METAPHOR_COMMAND_RECORD` で opt-in 拡大。
4. **クリーンアップ**: 旧クロージャ依存を撤去（宿題④完了）。既定 ON 化判断は安定後（1.0 前は「影オン = 常時記録／影オフ = opt-in」据え置きを推奨）。

### 深度・順序のセマンティクス（実装の核心）

2D は `depthCompareFunction = .always`・深度書き込み無効（[Canvas2D.swift:388](../../Sources/MetaphorCore/Drawing/Canvas2D.swift#L388)）、3D は `.readWrite`（[Canvas3D.swift:267](../../Sources/MetaphorCore/Drawing/Canvas3D.swift#L267)）で、**共有深度テクスチャ1枚**（`TextureManager` の単一 `renderPassDescriptor`）を使う。再生を **seq 昇順** で行えば:

- 「3D 背後に置いた 2D」は先に描かれ、後続 3D が `.readWrite` で深度クリア値(1.0)に対しテストして **その上に重なる**（2D は深度を書かないので深度を汚さない）。
- 「前面 2D（オーバーレイ）」は 3D より後の seq なので最後に `.always` で上書き = 最前面。
- 3D 同士は seq に関係なく深度で正しく解決（現状維持）。
- これで `background → 3D → 2D` も `2D背景 → 3D → 2D前景` も任意順が成立する。**追加レンダーパスは作らない**（TBDR の tile メモリ温存。#70 と同じく単一メインパス）。

run グルーピング（隣接同種コマンドを区間化し、`setDepthStencilState`/`setRenderPipelineState` を run 単位で1回だけ設定）により、状態切替コストと `instanceBatcher` のバッチ効率を維持する。支配パターン（背景 → 3D 一括 → オーバーレイ）では 3D が 1 run になり現状と同等効率。

**2D は深度を持たない挿入レイヤー**である（2 つの 3D 群の間に挟んだ 2D は、後段 3D の深度比較には参加しない）。これは平面オーバーレイとして物理的に正しく、許容する。

## Consequences

### Positive

- 呼び出し順どおりの 2D/3D 合成（宿題①解消）。clip 途中変更の保持（③）。massive の記録（②）。型付きコマンド化で将来の検証性向上（④）。
- 公開 API・書き心地は不変。影オフ既定は即時経路のまま回帰ゼロ。
- 変更が main パス・影オン経路に局所化。単一分岐点でロールバック可。
- Probe の決定論観測を全スケッチへ広げる土台。スコープ (b) への前方互換。

### Negative / Trade-offs

- 順序保持により 2D/3D 重ね順が #70 と変わる箇所がある（影オン e2e の期待値更新が必要・実機目視必須）。
- 記録/再生の CPU オーバーヘッドが opt-in 拡大時に全スケッチへ及ぶ（影オフ既定では発生しない）。
- 半透明ブレンド順序は記述順厳密化の方向だが、3D 半透明の CPU ソートは引き続き行わない（明示ソートは別 Issue）。
- 深度あり 3D と深度なし 2D の交互合成セマンティクスを文書化・周知する必要。

### Follow-ups / 残課題

- スコープ (b): RenderGraph/PostProcess/outputs を含む完全決定論パイプライン（別 Epic）。
- `METAPHOR_COMMAND_RECORD` 既定 ON 化の判断（安定後）。
- 3D 半透明の深度ソート（別 Issue 推奨）。

## 実装結果（2026-06-30）

スコープ (a) を4 PR で段階導入し完了。宿題①〜④をすべて根治。各 PR は独立して全テスト緑を維持（850 → 860）。

- **#111（PR-1・基盤）**: `SketchContext` の単調 seq 払い出し（`nextDrawSeq`・フレーム頭リセット・両 Canvas へ `seqProvider` 注入）、`DrawCall3D.seq`、`Deferred2DCommand` enum と純粋な `DrawStreamMerge.mergeOrder`。配線据え置きで挙動不変。
- **#112（PR-2・2D コマンド化）**: 2D 遅延を `deferredDraws` クロージャ → `deferred2DCommands: [Deferred2DSlot]` へ昇格（**④**）。`emit`/`encode` で遅延/即時を振り分け。massive を `isDeferring` 対応（**②**）、clip を `setScissor` コマンド化（**③**）。再生順は 3D→2D のまま（挙動同値）。
- **#113（PR-3・順序統合）**: `replayDeferredMain` を `DrawStreamMerge.mergeOrder` による seq 昇順マージ + run グルーピングで交互再投入（**①**）。`replayMainPass` を `beginReplay`/`replayRecordedRange`/`endReplay` に分解。`shouldRecordMainPass`（= `shadowMap != nil || commandRecordEnabled`）へ一般化し `METAPHOR_COMMAND_RECORD` で opt-in。
- **#114（PR-4・仕上げ）**: 冗長になった `defersMainPassForShadow` を撤去し `shouldRecordMainPass` に一本化。本 ADR / 設計ドキュメントを実装完了として確定。

### 設計上の発見

2D はバッチをフレーム末尾まで遅延フラッシュするため、素朴に flush 時点で seq を採ると呼び出し順と逆転する（先に書いた 2D が後の 3D より大きい seq を得る）。**3D 記録の直前に 2D 保留バッチを flush（`Canvas3D.flushPending2D` フック）して seq を「この 3D より前」に確定**することで、flush が正しいインターリーブ点で起き呼び出し順が保たれる。

### 既知の制限（2026-07-02 追記・#152）

記録フレームで取り残されていた経路（2D `image()`/`text()`、3D `beginShape`/`endShape`・`dynamicMesh`、フレーム途中の `background()`）は #152 で記録経路に対応済み。ただし以下は未対応の制限として残る:

- **カメラ・ライトのフレーム内変更は再生時に再現されない。** `DrawCall3D` はカメラ・投影・ライトのスナップショットを持たず、`replayRecordedRange` は**フレーム末尾**の状態を全コールに適用する。即時経路は「呼び出し時点の状態」を保証するため、draw() の途中で `camera()` / ライトを切り替えるスケッチは影オン（または `METAPHOR_COMMAND_RECORD=1`）時のみ挙動が変わる。回避策: フレーム内でカメラ・ライトを固定するか、影をオフにする。根治には `DrawCall3D` へのカメラ/ライトスナップショット（seq 付き）追加が必要（follow-up）。
- 記録経路の 3D `beginShape`/`dynamicMesh` は毎フレーム一時 `Mesh` を生成する（記録モード時のみのコスト）。

### 活性化方針（確定）

1.0 前は **影オン = 常時記録／影オフ = `METAPHOR_COMMAND_RECORD` opt-in** で据え置く（影オフ既定は即時経路＝回帰ゼロ）。既定 ON 化は安定後に判断（follow-up）。`renderFrame` の `shadowDeferActive` 単一分岐点で旧経路へロールバック可能。

## References

- 設計ドキュメント: [docs/design/deterministic-rendering.md](../design/deterministic-rendering.md)（#71 追補）
- 先行 ADR: [docs/adr/0002-deterministic-render-pipeline.md](0002-deterministic-render-pipeline.md)
- `Sources/MetaphorCore/Sketch/SketchContext.swift:279,307`（beginFrame / replayDeferredMain）
- `Sources/MetaphorCore/Drawing/Canvas2D.swift:388,521,650`（深度 disabled / replayForeground / flushInstancedBatch）
- `Sources/MetaphorCore/Drawing/Canvas2D+Clipping.swift:18,54,85`（clip / flush 群）
- `Sources/MetaphorCore/Drawing/Canvas2DMassive.swift:94`（massive 即時パス）
- `Sources/MetaphorCore/Drawing/Canvas3D.swift:267,381,1008`（深度 readWrite / replayMainPass / drawMesh）
- `Sources/MetaphorCore/Drawing/ShadowMap.swift:19`（DrawCall3D）
- `Sources/MetaphorCore/Core/MetaphorRenderer.swift:871`（活性化分岐・ロールバック点）
- Issue #71、Epic #75
