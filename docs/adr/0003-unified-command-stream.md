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
- ~~`METAPHOR_COMMAND_RECORD` 既定 ON 化の判断（安定後）。~~ → **本 ADR の Amendment（2026-08-02, #327）で決着**。
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

- ~~カメラ・ライトのフレーム内変更は再生時に再現されない~~ → **#201 で解消**（2026-07-02）。`DrawCall3D` が呼び出し時点のカメラ/投影/ライトのスナップショット（`RenderStateSnapshot3D`、状態が変わらない間はコール間で参照共有）を保持し、再生時に復元する。スナップショット境界ではインスタンスバッチを確定してから状態を切り替える。なお**シャドウマップ自体**（ライト空間行列）はフレームごとに 1 枚で、フレーム末尾のディレクショナルライトに基づく点は従来どおり。
- 記録経路の 3D `beginShape`/`dynamicMesh` は毎フレーム一時 `Mesh` を生成する（記録モード時のみのコスト）。

### 活性化方針（確定）

1.0 前は **影オン = 常時記録／影オフ = `METAPHOR_COMMAND_RECORD` opt-in** で据え置く（影オフ既定は即時経路＝回帰ゼロ）。既定 ON 化は安定後に判断（follow-up）。`renderFrame` の `shadowDeferActive` 単一分岐点で旧経路へロールバック可能。

## Amendment（2026-08-02, Issue #327）— 既定 ON 化の判断【ドラフト・レビュー用】

> **ステータス: 未確定（ユーザーレビュー待ち）**。実測と選択肢はここに確定させたが、
> Decision の採否は未承認。承認後にこの注記を削除し Accepted 相当として確定する。

**ユーザーが判断すべき点**:

1. **Option B（見送り＝現行の活性化方針を 1.0 の確定仕様として凍結）を採るか**（本ドラフトの推奨。決め手は「既定 ON が `loadPixels()` の Processing 互換を全スケッチで失わせる」ことの実測確認）。
2. `METAPHOR_COMMAND_RECORD` を **1.0 以降も公式な opt-in として残すか**（残す前提で書いた。撤去するなら deprecation ウィンドウが別途必要）。
3. 再評価（このウィンドウを再び開く）の条件を後述の 2 つに固定してよいか。

### 1. 実測: 記録 ON のオーバーヘッド

計測条件: Apple Silicon / `-c release` / 1280×720 オフスクリーン / ウォームアップ 30 フレーム後の 200 フレーム平均 / ON・OFF を入れ替えて 2 回ずつ測り速い方を採用（`renderFrame()` の壁時計。トリプルバッファのセマフォを含むため実質のフレーム所要時間）。`METAPHOR_PERF_TESTS` ゲートと同種の使い捨てベンチで測定（コミットしていない）。

| シーン | OFF (ms/f) | ON (ms/f) | 差 | 比 |
|---|---:|---:|---:|---:|
| `background()` のみ | 0.084 | 0.104 | +0.020 | +24% |
| 2D `rect` ×2000（同一スタイル＝1 バッチ） | 0.218 | 0.221 | +0.004 | +2% |
| 2D `rect` ×2000（毎回 stroke/strokeWeight 変更＝バッチ切れ） | 4.996 | 5.264 | +0.268 | +5% |
| 3D `box` ×500 | 0.156 | 0.264 | +0.108 | +69% |
| 3D `box` ×2000 | 0.557 | 0.999 | +0.442 | +79% |
| 3D `beginShape3D` ×200（記録時のみ一時 `Mesh` 生成） | 0.148 | 0.673 | +0.525 | +354% |
| 混在 3D×200 + 2D×1000 | 0.180 | 0.225 | +0.045 | +25% |
| massive `circles()` ×50000 | 0.949 | 0.949 | ±0.000 | ±0% |

単位コストに直すと **記録された 3D ドローコール 1 件あたり ≈ 0.22 µs**、**遅延 2D コマンド 1 件あたり ≈ 0.13 µs**、**記録経路の `beginShape3D` 1 図形あたり ≈ 2.6 µs**（一時 `Mesh` 生成が支配的）。バッチに畳まれる 2D と GPU インスタンシング（massive）は記録してもコマンド数が増えないため実質ゼロ。

**メモリ**: 定常状態の `phys_footprint` ドリフトは ON/OFF とも ±0.0MB（200 フレーム）。`recordedDrawCalls` / `deferred2DCommands` は `removeAll(keepingCapacity:)` で再利用されるため周回増加はない。ピークは 1 フレームぶんの記録量に比例し、記録されたコマンドが持つ `Mesh`／`MTLTexture` 参照がフレーム末尾まで生存する（`beginShape3D` 系は毎フレーム新規 `Mesh`）。

**読み方**: 60fps の予算 16.7ms に対し、最も重い測定でも **+0.44〜0.53 ms（予算の 2.6〜3.2%）**。絶対値は小さい。一方で **3D 主体のスケッチでは CPU 側の描画投入コストがほぼ倍**になる（相対 +69〜79%）。この計測はオフスクリーンで GPU 負荷が軽いため相対値が誇張されており、実シーンでの相対影響はこれより小さい。

### 2. 実測: 出力の同一性（ゴールデン基盤 #330 の全画素比較）

ADR-0003 執筆時には存在しなかった全画素比較基盤（#330 / PR #366）で、**同一スケッチを記録 OFF / ON で描いて全画素比較**した（128×128、7 シーン: 2D 図形・ブレンドモード・Blinn-Phong・PBR・3D+2D オーバーレイ・2D/3D/2D 交互・テキスト）。

- **3 フレーム描画後: 7 シーンすべて 1 ビットも違わない**（`differingPixels = 0`）。OFF↔OFF・ON↔ON の対照比較も同一で、比較自体の再現性も確認済み。
- **1 フレームのみ描画: 上端 1 行 + 左端 1 列（255/16384 px = 1.56%）だけ違う**。ON 側が背景色そのもの、OFF 側がその約 50%。原因は `Canvas2D.background()` の「**初回フレームだけ clear 最適化をスキップして全画面クワッドを描く**」経路（[Canvas2D+Background.swift:37-44](../../Sources/MetaphorCore/Drawing/Canvas2D+Background.swift#L37)）で、そのクワッドがキャンバス縁の画素を半分しか覆わないため。記録経路は同一フレーム内で `loadAction = .clear` を効かせられるのでこの穴を通らない。

つまり **定常フレームの見た目は経路に依存しない**（順序統合が仕様どおり働いている裏づけ）。差が出るのは初回フレームだけで、しかも**記録経路の方が正しい**（背景色ちょうどになる）。この初回フレーム縁の欠けは既定 ON 化とは独立した既存不具合であり、単一フレームキャプチャの品質（`noLoop` / Probe snapshot / 1 フレーム目の `save()`）に効くため別 Issue とする。

### 3. 実測: `loadPixels()` との相互作用（決定的な材料）

`draw()` の途中で `rect()` → `loadPixels()` し、中心画素を読む最小スケッチで確認した:

| | 読めた値 | 意味 |
|---|---|---|
| 記録 OFF（現行既定） | `(255, 0, 0)` | 直前に描いた赤 = **Processing 互換**（W1-7 / #326 / PR #370 の到達点） |
| 記録 ON | `(0, 0, 0)` | 同一フレームの描画が読めない（直近コミット済みフレームへフォールバック + 初回警告） |

原因は構造的で回避策がない。記録経路では `draw()` が「メインエンコーダを持たない記録パス」として先に走るため、`loadPixels()` 時点でエンコード済みの描画が存在せず、**メインパスを分割して読み戻す**という #326 の同期設計が成立しない（ADR-0005 Amendment 2026-08-02 の既知の制限 (b) に明記済み）。

したがって **既定 ON にすると、W1-7 が達成したばかりの Processing 互換な `loadPixels()` が全スケッチで失われる**。これは W1 の中で 2 つの宿題が正面衝突していることを意味する。

### Considered Options

#### Option A: 既定 ON（`METAPHOR_COMMAND_RECORD` opt-in を撤廃し常時記録）

- Pros: 影の有無で描画意味論が変わらなくなる（現在は「影オンなら 2D を 3D の背後に置ける／影オフなら置けない」という説明しづらい非対称がある）。経路が 1 本になりテスト・ゴールデン・デバッグの対象が半減。初回フレームの縁欠けが消える。#71 のシリアライズ一般化やスコープ (b) へ進むときの前提が単純になる。
- Cons: **`loadPixels()` の Processing 互換が全スケッチで失われる**（§3。W1-7 の成果を W1-8 が取り消す）。3D 主体スケッチで CPU 描画投入コストがほぼ倍（絶対値は +0.1〜0.5 ms/frame）。全利用者が「使っていない機能」のコストを払う。単一分岐点によるロールバック手段が実質失われ、即時経路が死にコード化して腐る。

#### Option B（推奨）: 見送り — 現行の活性化方針を 1.0 の確定仕様として凍結

- Pros: `loadPixels()` の Processing 互換を守れる。既定経路のコストが増えない。順序保持が必要な利用者・AI 協調ループは `METAPHOR_COMMAND_RECORD=1` で今すぐ opt-in でき、**得られる機能に差はない**（既定値の違いだけ）。単一分岐点が生きたまま残り、将来 ON にする道も塞がない（挙動変更であって API 破壊ではないので 1.0 後でも minor で可能）。
- Cons: 影の有無で 2D/3D の重ね順の自由度が変わる非対称が 1.0 に残る（doc で明示する）。記録経路が「影オンと opt-in でしか通らない」ため、通常利用で踏まれず回帰に気付きにくい（→ ゴールデン基盤での ON/OFF パリティ常設テストで補う）。

#### Option C: 段階的 — 既定 ON にしつつ `loadPixels()` 使用時だけ即時経路へ自動フォールバック

- Pros: 両取りに見える。
- Cons: 同じ API が「呼んだか呼ばないか」でフレーム構造ごと切り替わり、性能と描画順序に説明不能な崖ができる。`loadPixels()` は `draw()` の途中で条件分岐の先にも書けるため、フレームごとに経路が揺れて決定論の保証が壊れる（`loadPixels()` を呼ぶ前に記録するか即時描画するかを、呼ばれる前に決められない）。1.0 で凍結する仕様としては複雑すぎる。**却下**。

### Decision（ドラフト）

**Option B を採用する。** 決め手は「既定 ON で新たに得られるものが『影オフでも 2D を 3D の背後に置ける』**だけ**であり、それは既に opt-in で得られる」のに対し、「代償の `loadPixels()` 非互換は全利用者に及び、同じ v0.8.x ウィンドウで達成した W1-7 を打ち消す」という非対称である。実測 CPU コスト（+0.1〜0.5 ms/frame）は単体なら許容範囲だが、機能上の利得がゼロである以上、それを全利用者に課す理由がない。

1.0 の確定仕様として以下を凍結する:

1. **活性化条件は `shadowMap != nil || commandRecordEnabled`**（`Canvas3D.shouldRecordMainPass`）。影オフ既定は即時経路。
2. **`METAPHOR_COMMAND_RECORD=1` は 1.0 以降も公式な opt-in として維持する**。ただしこれは実験・検証用のスイッチであり、**`CONTRACT.md` の環境変数契約には含めない**（metaphor-cli は設定しておらず、クロスリポの結合点ではない）。現状どこにも文書化されていないため `DEVELOPMENT.md` の環境変数表に載せる。
3. **影オン／opt-in と影オフ既定で、定常フレームの描画結果は同一である**（§2 で実測）。これを ADR の保証として宣言し、ゴールデン基盤に ON/OFF パリティの常設テストを置いて守る。

**再評価の条件**（このウィンドウを再び開いてよい状況。どちらかが満たされたら再検討する）:

- (a) 記録経路でも `loadPixels()` の同一フレーム readback が成立する実装ができたとき（例: 記録→再生のうち**再生パス**を分割する。再生時点ではエンコード済みなので理屈上は可能）。§3 の唯一のブロッカーが消える。
- (b) #71 のシリアライズ一般化やスコープ (b)（RenderGraph/PostProcess を含む完全決定論パイプライン）が、既定 ON を前提として要求するとき。

1.0 後に既定 ON へ倒すことは**ソース互換を壊さない**（public API は不変で、変わるのは既定の実行経路と `loadPixels()` の観測内容）。ただし利用者から見た挙動変更であり CHANGELOG での明示と minor bump を要する。

### Consequences

- ADR-0003「活性化方針（確定）」節の「既定 ON 化は安定後に判断（follow-up）」は本 Amendment で**決着済み**となる。Follow-ups の該当項目もクローズ。
- 影の有無で 2D/3D の重ね順の自由度が変わる非対称が 1.0 の仕様として残る。`docs/ai/README.md` と Sketch 層 doc に「2D を 3D の背後に置きたい場合は影を有効にするか `METAPHOR_COMMAND_RECORD=1`」を明記する（別 PR）。
- 別 Issue とするもの:
  - 影オフの**初回フレーム**で `background()` の縁 1px が半輝度になる（§2。単一フレーム capture の品質に効く）。
  - 記録 ON/OFF の**全画素パリティ常設テスト**（ゴールデン基盤 #330 の上に。定常フレームで bit-identical を守る回帰ガード）。
  - `METAPHOR_COMMAND_RECORD` を `DEVELOPMENT.md` の環境変数表へ追記。

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
- Amendment（2026-08-02）関連: Issue #327（本判断）、Epic #314 / [v1-release-plan.md](../design/v1-release-plan.md) W1-8、
  Issue #326 / PR #370（`loadPixels()` の Processing 互換 = §3 のブロッカー）、
  ADR-0005 Amendment 2026-08-02（記録経路でパス分割不能であることの明記）、
  Issue #330 / PR #366（ゴールデン全画素比較基盤 = §2 の計測手段）
