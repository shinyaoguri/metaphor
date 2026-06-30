# 決定論レンダリング（Issue #70 / #71 への布石）

- **ステータス**: 設計提案（実装はフェーズ分割・チェックポイント付き）
- **対象 Issue**: #70（noLoop 2フレーム描画 + 次フレームシャドウ）、布石として #71（即時描画→コマンド記録）
- **Epic**: #75 P1「信頼できる観測」
- **最終更新**: 2026-06-30

## なぜ

AI協調ループ（Probe）の核心は「AIが自分の編集が意図通りの絵を出したか」を観測して検証することにある。
そのためにはレンダリングが**決定論的**——同一スケッチの snapshot が毎回一致し、`frameCount` が予測可能で、
影が現フレームのジオメトリと整合している——必要がある。現状には2つの非決定論ノイズが残る。

成功基準（Epic #75）: 観測の決定論性（同一スケッチの snapshot 一致）、AIループの往復時間短縮。

## 現状の正確な機構（コード検証済み 2026-06-30）

### 問題1: noLoop が2フレーム描画する

`noLoop()` 起動時、フレームを2回描画する。`frameCount`（[SketchContext.swift:285](../../Sources/MetaphorCore/Sketch/SketchContext.swift#L285) の `beginFrame` で `+1`）が **2** になり、初回 snapshot が非決定論的になる。

- **ウィンドウ起動**: [SketchRunner.swift:463-470](../../Sources/MetaphorCore/Sketch/SketchRunner.swift#L463-L470)
  1. `renderer.renderFrame()` — オフスクリーンのみ。`clearColorApplied == false` のため `background()` は全画面クワッドで背景を塗る（[Canvas2D+Background.swift:19-35](../../Sources/MetaphorCore/Drawing/Canvas2D+Background.swift#L19-L35)）。**この時点でオフスクリーンテクスチャは正しい背景を持つ**。
  2. `useExternalRenderLoop = false` にして `mtkView.draw()` → [`draw(in:)`](../../Sources/MetaphorCore/Core/MetaphorRenderer.swift#L989) が `renderFrame()` を**再実行**（frameCount=2）し、その後ブリット。2回目は `clearColorApplied == true`（[SketchContext.swift:311-312](../../Sources/MetaphorCore/Sketch/SketchContext.swift#L311-L312) の `markPendingClearColorApplied`）なので Metal の `loadAction=.clear` 最適化に切り替わる。
- **ライブ noLoop() 呼び出し**: [SketchRunner.swift handleNoLoop](../../Sources/MetaphorCore/Sketch/SketchRunner.swift#L443) が `mtkView.draw()` を2回。
- **ヘッドレス**: [SketchRunner.swift:488-489](../../Sources/MetaphorCore/Sketch/SketchRunner.swift#L488-L489) が `renderFrame()` を2回。

**本質**: 2回目の描画は「クワッドclear → loadAction clear への切り替え」のためだけに存在し、**スナップショットの正しさには不要**（1回目で背景は確定済み）。`blitToScreen` は `lastOutputTexture`（[MetaphorRenderer.swift:784,885](../../Sources/MetaphorCore/Core/MetaphorRenderer.swift#L784)）を読むため、再描画なしのブリットが可能。

### 問題2: 次フレームシャドウ（動く影が1フレーム遅延）

[`renderFrame()`](../../Sources/MetaphorCore/Core/MetaphorRenderer.swift#L795) のパス順:

```
onCompute → [main pass] onDraw → [shadow] onAfterDraw → RenderGraph → PostProcess → blit
            (854-859)              (862)
```

3D 描画（[Canvas3D.drawMesh](../../Sources/MetaphorCore/Drawing/Canvas3D.swift#L953)）は**2つのこと**を同時に行う:
1. `recordedDrawCalls` に**記録**（[Canvas3D.swift:960-973](../../Sources/MetaphorCore/Drawing/Canvas3D.swift#L960-L973)、`shadowMap != nil` のときのみ）。
2. 即座にメインパスへ**エンコード**（インスタンスバッチ/イミディエイト）。このとき `shadow.shadowTexture` をサンプルするが、その内容は**前フレーム N-1**（[Canvas3D.swift:1105](../../Sources/MetaphorCore/Drawing/Canvas3D.swift#L1105)）。

シャドウ深度パス（[Canvas3D.performShadowPass](../../Sources/MetaphorCore/Drawing/Canvas3D.swift#L355)、配線は [SketchRunner.swift:419-422](../../Sources/MetaphorCore/Sketch/SketchRunner.swift#L419-L422)）は `onAfterDraw` で `recordedDrawCalls` から shadow N を生成。**メイン（影を読む）がシャドウ生成（影を書く）より先**に走るため、動く影が常に1フレーム遅れる。静止スケッチでは N == N-1 なので2フレーム目で一致する。

## 設計判断（詳細は ADR-0002）

2つの問題は**独立**しており、リスクが大きく異なる。フェーズ分割し、高リスク部の前に設計チェックポイントを置く。

| 問題 | リスク | アプローチ |
|---|---|---|
| noLoop 2フレーム | 低 | 再描画なしブリットで単一フレーム化、`frameCount=1` |
| 次フレームシャドウ | 中〜高 | `recordedDrawCalls` を「記録／再生」に分離し、`記録→shadow→main(再生)` へ組み替え |

公開API（`noLoop()`, `box()`, `sphere()`, `directionalLight()`, `background()` 等）は**全フェーズで不変**。

## 実装フェーズ

### フェーズ1（低リスク・独立PR可）: noLoop 単一フレーム化

- **ウィンドウ起動** [SketchRunner.swift:463-470]: 2回目の `mtkView.draw()` の前に `useExternalRenderLoop = true` を設定し、`draw(in:)` が `renderFrame()` を再実行せずブリットのみ行うようにする。frameCount=1。
- **ヘッドレス** [SketchRunner.swift:488-489]: 2回目の `renderFrame()` を削除（1回目で背景確定済み）。
- **ライブ handleNoLoop** [SketchRunner.swift:443]: 2回目の `draw()` を再描画なしブリットへ。
- 視覚結果は不変（クワッドclear と loadAction clear は不透明背景で同一ピクセル）。
- ドローアブルサイズ未確定・オクルージョンの相互作用（[MetaphorRenderer.swift:995-1002](../../Sources/MetaphorCore/Core/MetaphorRenderer.swift#L995-L1002)）は既存の `hasBlittedOnce` ガードで担保。

### フェーズ2（チェックポイント）: 本ドキュメント + ADR-0002 のレビュー

フェーズ3着手前に必ずレビューを通す（Epic #75 / Issue #70 が明記する設計ゲート）。

### フェーズ3（中〜高リスク）: シャドウ同一フレーム化

`recordedDrawCalls` の記録は既存。これを「記録フェーズ／再生フェーズ」に明示分離する。

```
[記録] onDraw 内で 3D は recordedDrawCalls に記録のみ（メインパスへ即時エンコードしない）
[shadow] performShadowPass で shadow N を生成
[main 再生] recordedDrawCalls を shadow N でメインパスへエンコード
```

- `shadowMap == nil`（影オフ）のときは記録が走らないため、**現状の即時描画パスを維持**（リグレッションゼロ）。影オン時のみ再生パスに切り替える。
- これは #71「即時描画→コマンド記録」への前方互換な第一歩。当面 **2D は即時描画を維持**し、#71 で 2D もコマンド記録へ拡張する。

#### フェーズ3の最大リスク: 2D/3D 重ね順

現状 2D（`canvas`）と 3D（`canvas3D`）は呼び出し順に**同一エンコーダ**へ即時書き込みされる。3D メインパスを shadow 後に遅延すると、3D が常に全2Dの上に重なり、`background → box → text` のような重ね順が壊れる。

対策（実装時に実コードで重ね順の織り込みを精査して確定）:
- **案A（最小侵襲・推奨）**: `onDraw` を「3D記録 + 2D背景」と「2D前景」に二分。多くのスケッチが `background → 3D → 2Dオーバーレイ` パターンのため自然に吸収できる。
- **案B**: 2D も `recordedDrawCalls` 化（#71 本体の領域、本Issueでは見送り）。

## テスト

新規 `Tests/metaphorTests/DeterminismTests.swift`（Swift Testing `@Suite`）。GPU読み戻しヘルパー [`MetaphorRendererTests.readbackCenterPixel`](../../Tests/metaphorTests/MetaphorRendererTests.swift#L176) を再利用。

- フェーズ1: noLoop スケッチで `frameCount == 1`、初回フレームの中心ピクセルが背景色（青）と一致。
- フェーズ3: box を A→B に動かし、各フレームで影の境界が現フレームのジオメトリと整合。同一 noLoop スケッチの2回レンダリングで全ピクセル一致。
- 既存829テスト緑維持。フェーズ3では 2D/3D 混在スケッチの重ね順を重点回帰。Examples の代表スケッチ（3D + 2Dオーバーレイ）で目視 + snapshot 更新。

## 実装メモ（2026-06-30）

フェーズ1・フェーズ3とも実装・テスト済み（全849テスト緑）。

### フェーズ3 の実装結果（影オン経路のみ作動）

`MetaphorRenderer.renderFrame()` は `shadowDeferActive` が `true`（`canvas3D.shadowMap != nil`）のフレームでのみ次の経路を取る:

1. `onRecordFrame`: メインエンコーダ無しで `draw()` を実行。3D は `Canvas3D.recordedDrawCalls` に記録（即時エンコードせず）、2D は `Canvas2D.deferredDraws` にクロージャとして遅延、`background()` は `loadAction = .clear` に委ねてクワッドを描かない。
2. `onAfterDraw`: `performShadowPass` が記録済み3Dから影N（`shadow.shadowTexture`）を生成。
3. `onReplayMain`: **単一**のメインエンコーダで `Canvas3D.replayMainPass`（影Nをサンプル）→ `Canvas2D.replayForeground`（前景2D）の順に再生。

- 3D 再生は `isReplaying` フラグで `drawMesh` の記録ブロックをスキップし、既存のインスタンシング/イミディエイト経路をそのまま再利用（記録済みコールを `drawMesh` に再投入）。
- **レンダーパスは増えない**（3D・2D とも同一メインエンコーダで再生）。当初懸念したタイルフラッシュ増は発生しない。
- **影オフのスケッチは全経路で完全に無変更**（即時描画のまま）。846 既存テスト緑で実証。

主な変更: `Canvas3D.swift`（`isReplaying`/`replayMainPass`）、`Canvas2D.swift` + `Canvas2D+Clipping.swift` + `Canvas2D+Background.swift`（`isDeferring`/`deferredDraws`/`replayForeground`、background のクワッド抑制）、`SketchContext.swift`（`beginRecordingFrame`/`endRecordingFrame`/`replayDeferredMain`）、`MetaphorRenderer.swift`（`shadowDeferActive`/`onRecordFrame`/`onReplayMain` と `renderFrame` 分岐）、`SketchRunner.swift`/`SketchWindow.swift`（配線）。検証: `Tests/metaphorTests/DeterminismTests.swift`。

### 非目標 / 互換性の境界（既知の制限）

- **公開API・書き心地は不変**。`box()`/`text()`/`background()` 等の書き方は変わらない。
- **`background()` 以外の2Dを「3Dの背後」に意図して描いた場合、その2Dは3Dの前面に出る**（支配的パターン `background → 3D → オーバーレイ` は正しい）。3Dの間に2Dを挟む稀なスケッチのみ重ね順が変わる。完全な任意順序の保持は #71（2Dのコマンド記録化）の領域。
- **影オン時の massive 2D インスタンス描画（`circles(instances)` 等のオンザフライ即時パス）は記録経路で描画されない**（`Canvas2DMassive` は encoder 必須ガードで安全にスキップ）。massive 2D と影付き3Dの混在は稀。必要なら #71 で対応。
- 影オン時の 2D クリッピング（scissor）の途中変更は前景再生で失われうる（clipping + 影 + 2Dオーバーレイは稀）。

## #71 追補: 順序保持コマンドストリームへの統一（2026-06-30）

#70 が残した上記4つの制限（順序前面化・massive 非描画・clip 損失・クロージャ型）の根因は、**2D（`Canvas2D.deferredDraws`：クロージャ）と 3D（`Canvas3D.recordedDrawCalls`：型付き）が別ストアで、再生が `replayMainPass`（3D全部）→`replayForeground`（2D前景）の固定2段順** だったこと（[SketchContext.swift:307](../../Sources/MetaphorCore/Sketch/SketchContext.swift#L307)）。呼び出し順の情報がソースコード上にしか残らない。

#71 はこれを **呼び出し順を保持する単一コマンドストリーム** へ統一して根治する。設計判断の正典は [ADR-0003](../adr/0003-unified-command-stream.md)。要点:

- **2ストリーム + 単調 seq**: `SketchContext` がフレーム頭でリセットする単調 `seq` を払い出し（`nextDrawSeq()`、両 Canvas に `seqProvider` をクロージャ注入）、`DrawCall3D` に `seq` を追加、2D 遅延を明示コマンド型 `Deferred2DCommand` enum（`colorBatch`/`texturedBatch`/`instancedBatch`/`massiveCircles`/`setScissor`）へ昇格。再生時に 2D/3D を seq 昇順でマージし、隣接同種を run にグルーピングして単一メインパスへ交互再投入する。
- **深度セマンティクス**: 2D=`.always`（深度書かない）・3D=`.readWrite`・共有深度1枚。seq 昇順なら「背後 2D → 先に描画、後続 3D が深度付きで上に重なる／前面 2D は最後に上書き」が自然成立。追加レンダーパスは作らない（TBDR）。run グルーピングで状態切替コストと `instanceBatcher` バッチ効率を維持。**2D は深度を持たない挿入レイヤー**として扱う。
- **スコープ (a)**: main パス統一のみ。後段（RenderGraph/PostProcess/outputs）は既に線形決定論なので #71 対象外（完全決定論パイプライン=スコープ b は follow-up Epic）。
- **活性化は opt-in 段階拡大**: `defersMainPassForShadow` を `shouldRecordMainPass`（既定=影オン時のみ）へ一般化し、`METAPHOR_COMMAND_RECORD` 環境変数で影オフスケッチにも拡大可能。影オフ既定は即時経路をフォールバックに維持（回帰ゼロ）。単一分岐点（[renderFrame:871](../../Sources/MetaphorCore/Core/MetaphorRenderer.swift#L871)）でロールバック可。

PR 分割（各 PR 独立緑・850 維持）: 基盤型導入（配線据え置き）→ 2D 載せ替え（②③根治・挙動同値）→ seq interleave で順序統合（①根治）+ フラグ → クリーンアップ（④完了）。テストは順序ユニット（GPU 不要）+ 複数サンプル点ピクセル回帰（clip/massive/重ね順）+ 決定論 + 実機目視（`SceneGraphHybrid`/`CubesWithinCube`）。

## 参考

- ADR: [docs/adr/0002-deterministic-render-pipeline.md](../adr/0002-deterministic-render-pipeline.md)、[docs/adr/0003-unified-command-stream.md](../adr/0003-unified-command-stream.md)
- Issue #70（決定論化）、#71（コマンド記録）、Epic #75
- [CLAUDE.md](../../CLAUDE.md) レンダリング2パス構造の節
