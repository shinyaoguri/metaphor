# ADR-0005: Sketch 層 API の一貫性規則を定める（2D/3D 適用規則・エラー報告規約・doc 正本）

- **Status**: Accepted
- **Date**: 2026-07-02
- **Deciders**: PR で確定（Issue #151）
- **PR / Commit**: 本 PR

## Context

API/Sketch 層レビュー（Issue #151）で、個別のバグではなく**設計規則の不在**に起因する一貫性問題が見つかった:

1. **2D/3D 適用規則が場当たり的**: 「両方に効く」= `fill`/`stroke`/`pushMatrix`/`scale(s)`、「2D 専用」= `blendMode`/`rotate`/`translate(x,y)`/`strokeWeight`/`scale(sx,sy)`。同じ変換ファミリ内で作用先が変わり推測不能で、Processing（P3D では全部効く）経験者を誤誘導する。
2. **spurious optional**: `createCapture`/`tween`/`gui`/`orbitCamera` は `Optional` を返すが、転送先は非オプショナルまたは fatalError であり nil 経路が存在しない。
3. **create*/make* 二重 API**: Audio/Physics/RenderGraph ブリッジは検証なし `create*` と throws `make*` が並存し、他モジュールは `create*` のみ。自動 start の有無（`createCapture` は自動、`createAudioInput` は手動）も不統一。
4. **doc の 3 層複製**: 同一 API の doc が Sketch 層と SketchContext 層で食い違い、llms.txt（= AI 生成コードの品質）に直結するドリフト源になっている。

破壊的変更を含み得るため、方針を先に確定して段階適用する。

## Considered Options

### 2D/3D 適用規則

- **Option A: Processing P3D の意味論に寄せる**（`translate`/`rotate`/`blendMode` 等を 2D/3D 両方に適用）
  - Pros: Processing 経験者の期待どおり。「どの API がどちらに効くか」の暗記が不要。
  - Cons: 既存スケッチの描画結果が変わる破壊的変更。2D と 3D で意味が異なる API（`blendMode` のパイプライン切替コスト等）の統一は実装コストが高い。
- **Option B: `canvas`/`canvas3D` 明示アクセスへ誘導**（Sketch 層は 2D 専用と割り切り、3D は明示）
  - Pros: 非破壊。適用先が常に明示的。
  - Cons: `box()`/`sphere()` 等の 3D API が既に Sketch 層にあるため一貫しない。Processing 風の手軽さを損なう。
- **Option C: 現状の割り当てを規範化して doc に明記**（変換系は段階的に P3D 意味論へ）
  - Pros: 非破壊で今すぐ実行可能。誤誘導は doc で解消。将来 A へ進む余地を残す。
  - Cons: 規則自体の場当たり性は残る。

### エラー報告規約

- **Option A: すべて throws に統一** — Cons: `draw()` 内の全描画呼び出しに try が付き Processing 風の手軽さが崩壊。
- **Option B: すべて warning + no-op** — Cons: リソース生成の失敗（回復判断が必要）まで黙殺される。
- **Option C: 層で分ける** — 実行時描画 = 受け口検証 + `metaphorWarning` + 安全なフォールバック（no-op/クランプ）、リソース生成・初期化 = typed throws（既存 Invariants と一致）。

### doc 正本の置き場

- **Option A: Sketch 層を正本にする**（ユーザーが最初に触る層。llms.txt も Sketch 層 API を晒す）
- **Option B: SketchContext 層を正本にする**（実装に近い） — Cons: llms.txt の主要面と乖離。

## Decision

1. **2D/3D 適用規則**: Option C を採用。現状の割り当て（下表）を規範とし、**両層の doc に「2D のみ」「2D/3D 両方」を明記**する。変換ファミリ（`translate`/`rotate`/`scale`）の P3D 意味論への統一は 1.0 前の破壊的変更ウィンドウで再評価する（follow-up）。

   | 適用先 | API |
   |---|---|
   | 2D/3D 両方 | `fill` / `stroke` / `noFill` / `noStroke` / `pushMatrix` / `popMatrix` / `scale(s)`（均一） |
   | 2D のみ | `blendMode` / `rotate(a)` / `translate(x,y)` / `strokeWeight` / `scale(sx,sy)` / `push()`・`pop()`（スタイル込み） |
   | 3D のみ | `translate(x,y,z)` / `rotateX/Y/Z` / `camera` / `lights` / `material` 系 |

2. **エラー報告規約**: Option C を採用（実行時描画 = warning + フォールバック、生成系 = typed throws）。`Sketch.context` 未初期化は fatalError（プログラミングエラー）、`probe()` は無言 no-op（観測は本体挙動を変えない）、`pixels` は空バッファ。#150 で受け口検証を統一済み。

3. **doc 正本**: Option A（Sketch 層）。mode 依存の解釈（`ellipseMode`/`rectMode`/`imageMode`）は Sketch 層 doc に明記し、SketchContext 層は「転送のみ」の簡潔なコメントに寄せる（段階適用）。

4. **create*/make* 二重 API**: `create*` に検証を統合し `make*` は deprecated を経て廃止する。**破壊的変更のため minor リリースで deprecation → 次の minor で削除**（follow-up Issue を起票して実施）。自動 start の有無は各 `create*` の doc に必ず明記する。

5. **spurious optional**: 戻り値型の変更（`Tween<T>?` → `Tween<T>` 等）は `if let` 利用者を壊すため deprecation フェーズで実施。当面は **doc を実挙動（常に非 nil）に合わせる**（本 PR で実施）。

6. **`loadPixels()` の意味論**: Processing の `loadPixels()` は「現在の描画結果を CPU に読み戻す」だが、現行実装は readback しない別物。リネーム（`createPixelLayer` 等）ではなく **readback 実装で Processing 互換に寄せる**方針とする（`Graphics.toImage().loadPixels()` の順序保証は #158 で実装済み。メインキャンバスへの適用は follow-up）。

## Consequences

- 非破壊分（doc 是正・`loadModel` の `normalize:` 公開・`onCaptureOutput` 上書き警告・2D `curve()` の実装ファイル移動）は本 PR で適用。
- 破壊的変更（make* 廃止・optional 除去・変換系の P3D 意味論）は 1.0 前の deprecation ウィンドウで別 Issue として実施。
- 新 API 追加時は本 ADR の規約（適用先の doc 明記・エラー規約・Sketch 層正本）に従う。

## Amendment（2026-07-03, Issue #221）

事後レビューで判明した、本 ADR の記述と実装・運用のずれを是正する。

### 1. Decision 4 の deprecation ウィンドウは守られなかった（記録）

Decision 4 は「minor リリースで deprecation → 次の minor で削除」と定めたが、実際には
deprecation（#203, フェーズ 2）と削除（#210, フェーズ 3）が同日に main へ入り、
**どちらも v0.5.0 が初出リリース**になった。deprecation を含む状態のリリースは一度も
公開されておらず、v0.4.0 利用者から見ると `make*` は警告期間なしで消えている。

v0.5.0 は撤回しない（0.x の破壊的変更として許容し、移行ガイドは #210 に記載済み）。
今後の deprecation は「**deprecation を含む minor を公開してから**、次の minor で削除する」
——つまりウィンドウの単位は PR やフェーズではなく **公開されたリリース** であることを
ここで再確認する。

### 2. Decision 2「生成系 = typed throws」の適用範囲の明確化

Decision 2 の「リソース生成・初期化 = typed throws」は **モジュール層のイニシャライザ**
（`SourcePass.init` / `AudioAnalyzer.init` 等）に適用する。**Sketch 層ブリッジの `create*`**
は Processing 風の手軽さを優先し、「受け口検証 + `metaphorWarning` + 安全なフォールバック
（生成不能なら nil）」とする——これは #203 が実装し #210 の移行ガイド
（「throws が必要な利用者は各モジュールのイニシャライザを直接呼ぶ」）が案内した規約の明文化であり、
`Sketch+RenderGraphBridge.swift` が生成エラーを warning + nil に変換するのは本規約どおりの挙動である。

## Amendment（2026-08-02, Issue #326）— Decision 6 の完了記録

Decision 6「readback 実装で Processing 互換に寄せる」の follow-up（メインキャンバスへの適用）が
2 段階で完了した。到達した意味論と、そのために選んだ同期設計を確定事項として記録する。

1. **#202 / #205（v0.5.0）**: `loadPixels()` がカラーテクスチャを `pixels` へ読み戻すようになった。
   ただし読めるのは「前フレーム末尾までにコミットされた内容」で、同じ `draw()` 内の先行描画は
   含まれなかった（未コミットのため）。
2. **#326**: `draw()` 途中の呼び出しで**呼び出し時点の内容**が読めるようになり、Processing と
   同じ意味論になった。オフスクリーンのカラーテクスチャはレンダーパスが終わるまで確定しない
   （MSAA のリゾルブはエンコーダ終了時）ため、**メインパスを分割する**以外に手段はない。
   採った設計は「保留バッチを flush → エンコーダを閉じる → 読み戻し blit を**フレーム自身の
   コマンドバッファに相乗り**させて commit → 完了待ち → `loadAction = .load` の継続パスで描画を
   再開し、両 Canvas のエンコーダを差し替える」。

   - **代替案「フレーム開始時点のテクスチャで足りる」は却下**。`background()` 直後の
     `loadPixels()` が前フレームを返してしまい、Processing 移行者の期待と最も食い違う典型
     パターンが直らないため。
   - **コストの局所化**: 分割は `loadPixels()` を呼んだフレームだけで起きる。呼ばないスケッチは
     エンコーダ生成もコマンドバッファも従来どおり 1 つで、追加コストはゼロ。
   - **既知の制限（意図的）**: (a) 継続パスはデプスをクリアする（元パスの depth storeAction が
     `.dontCare` のため保存できない）→ 分割をまたいだ 3D 同士は深度比較されない。2D は深度
     テストを使わないので影響なし。(b) 影オン経路（#70）は `draw()` が記録パスとして先に走り、
     その時点では何もエンコードされていないため分割不能 → 直近のコミット済みフレームへ
     フォールバックし、初回のみ警告する。

## Amendment（2026-08-02, Issue #323）— typed throws は延期し「エラー型の統一」で代替する

### 背景: Decision 2 の「typed throws」は現在の最小サポートでは書けない

Decision 2（および 2026-07-03 Amendment の 2）は「リソース生成・初期化 = typed throws」と
定めているが、**typed throws（`throws(E)`、SE-0413）は Swift 6.0 の言語機能**であり、
本リポジトリの最小サポートである **Swift 5.10（Xcode 15.4）ではパースできない**。
最小サポートは per-PR CI の必須チェック `build-swift-5-10`（Issue #332 で必須へ昇格）が
`swift build --target metaphor` で守っている。つまり `throws(MetaphorError)` を書いた時点で
必須チェックが落ち、main へ入れられない。

検証（手元の Swift 6.3.3 で実測）:

- `#if hasFeature(TypedThrows)` は `true`、`#if compiler(>=6.0)` も `true`、一方
  `-swift-version 5` を付けた状態で `#if swift(>=6.0)` は `false`。
  → typed throws を塞いでいるのは**言語モードではなくコンパイラのバージョン**であり、
  `swift-tools-version: 5.10` のままでも Swift 6 コンパイラでなら書ける。裏を返すと
  Swift 5.10 コンパイラでは書けない。そもそも `hasFeature(TypedThrows)` という検出手段が
  存在すること自体が、この機能が全バージョンで使えるわけではないことを意味する。
- 非活性な `#if` ブロックはパースされない（`#if compiler(>=99.0)` の中に壊れたトークン列を
  置いてもコンパイルが通ることを確認）。つまり `#if` による分岐は**構文上は成立する**。

その上で、**公開 API のシグネチャをツールチェーンで分岐させる案は却下**する。

- 同じライブラリのバージョンが、5.10 利用者には `throws`、6.0 利用者には
  `throws(MetaphorError)` として見える。typed throws を前提に `catch` を網羅的に書いた
  利用者コードが 5.10 ではコンパイルできず、**サポート範囲内でソース互換が割れる**。
- 対象は生成系だけで 50 件超。`#if` は宣言の途中（`throws` 節だけ）には置けないため、
  分岐のたびに**宣言と本体がまるごと二重化**する。
- `llms.txt` は `swift-symbolgraph-extract` の出力から作る（`scripts/generate-llms-txt.py`）。
  シンボルグラフは**生成したツールチェーンが選んだ枝しか含まない**ため、公開 API の正本が
  「生成に使った Swift のバージョン」に依存してしまう。手元・CI は Swift 6 系なので
  `throws(MetaphorError)` と書かれた llms.txt が出るが、5.10 利用者が実際にコンパイルする
  シグネチャは `throws` で、**ドキュメントと実物が食い違う**。

### 決定

1. **typed throws の適用は Swift 5.10 サポート終了まで延期**する。Decision 2 の「typed throws」
   は、それまでは**規約（何を投げるか）** として運用し、構文としては強制しない。
2. 代替として **「エラー型の統一」** を先に完遂する。`throws` と宣言した public API は
   **そのモジュールのエラー型だけ**を投げ、Metal / Foundation / MetalKit / AVFoundation /
   Network の生 `NSError` を素通りさせない。下層の原因はケースの `detail` / `underlying` に保存する。
3. すべての public throwing API の doc に **`- Throws:` で具体的なケース**を明記する。
   typed throws の実利（呼び出し側がどう `catch` すればよいか予見できる）の大半はここで得られる。
4. Swift 最小サポートを 6.0 以上へ上げる際、`throws` → `throws(E)` を**機械的に**適用する。
   エラー型が既に単一化されているため、その変更は**シグネチャ以外の挙動を変えない**
   （2 は typed throws 化の前提条件であり、遠回りではない）。

### 帰結

- `MetaphorError` に、素通りを塞ぐためのケースを追加した:
  `shaderSourceLoadFailed(path:detail:)` / `ImageFailure.loadFailed(source:detail:)` /
  `MeshFailure.loadFailed(path:detail:)` / `ExportFailure.fileWriteFailed(path:detail:)`。
  既に定義されていたが未使用だった `pipelineCreationFailed(name:underlying:)` を
  `PipelineFactory` で使うようにした。
- 独立モジュール側も同様に補った: `SoundFileError.loadFailed(path:detail:)` /
  `AudioAnalyzerError.engineStartFailed(detail:)` /
  `OSCReceiverError.listenerCreationFailed(port:detail:)`。
- **breaking**: 従来これらの経路で `NSError`（`NSCocoaErrorDomain` / `MTLLibraryErrorDomain` 等）を
  具体型で `catch` していた利用者コードは、`MetaphorError` を見るように変える必要がある。
  0.x の破壊的変更として許容する。
- エラー契約は `Sources/MetaphorCore/Core/MetaphorError.swift` の「エラー契約」節が正本。
  回帰は `Tests/metaphorTests/ErrorTests.swift` の `ErrorContractTests` などが凍結する。

## Amendment（ドラフト・2026-08-02, Issue #325）— 変換ファミリの P3D 意味論統一の判断

> **状態: ドラフト（ユーザーレビュー待ち）。** Decision 1 が「1.0 前の破壊的変更ウィンドウで
> 再評価する」と宣言した follow-up の結論案であり、確定していない。

### ユーザーが判断すべき点（3 行）

1. **Option A（`translate(x,y)` / `rotate(a)` / `scale(sx,sy)` を 3D にも効かせる）を実施してよいか** — 実測では実装 3 行・既存テストの赤 0・ゴールデン 6/6 差分 0 で、いま壊れている 11 examples が直る。
2. A を採るとき、**`shearX/Y` と `applyMatrix(float3x3)` も同時に 3D へ流すか**、`translate`/`rotate`/`scale` の 3 本に限るか（§6）。
3. **逆方向（3D 変換 API が 2D 描画に効く）は A では直らない**（`RotateXY` / `Explode` の 2 例）。1.0 では「直らないもの」として doc に明記して残すか、別 Epic を立てるか（§3）。

**推奨: Option A を実施する。** 以下はその根拠の実測記録。

### 1. 前提の訂正: 2D と 3D の座標系は既に一致している

ADR-0005 執筆時の Option A の Cons は「既存スケッチの描画結果が変わる破壊的変更」だったが、
再評価の過程で**前提が違っていた**ことが分かった。`Canvas3D.begin()` は毎フレーム
Processing P3D と同型の既定カメラへリセットする（[Canvas3D.swift:421-431](../../Sources/MetaphorCore/Drawing/Canvas3D.swift#L421)）:

```swift
let defaultZ = (height / 2) / tan(Canvas3D.defaultFov / 2)   // defaultFov = π/3
self.cameraEye    = SIMD3(width / 2, height / 2, defaultZ)
self.cameraCenter = SIMD3(width / 2, height / 2, 0)
```

つまり **3D のワールド座標はピクセル座標そのもの**（左上原点・y 下向き。y 下向きは
`computeViewProjection()` の `flipY` が担保）。`translate(x, y)` を 3D へ流すことは
「単位の異なる 2 空間を混線させる」ことではなく、**同じ空間に同じ量を足す**ことである。

実測（`128×128` オフスクリーン、フレームバッファの重心で比較）:

| 描いたもの | 重心 |
|---|---|
| 2D `rect(32-8, 24-8, 16, 16)` | (32.0, 24.0) |
| 3D `translate(32, 24, 0)` + `box(16)` | (32.0, 24.0) |

x/y とも 3px 以内で一致する。**2D と 3D は同じピクセル空間を共有している**。

この事実は Processing 移行ガイド（#336 / PR #377、マージ済み）の裏取りでも独立に確認されている
——既定カメラは Processing の P3D 既定と数値まで一致し、`box(100)` は 100 ピクセル、
`Examples/Basics/Form/Primitives3D` は元 `.pde` の座標値をそのまま使って正しく描けている。
**「P3D スケッチの座標が無変換で移植できる」という互換性は既に成立しており、
そこから外れているのは変換 API の適用先だけ**、というのが現在地である。

（注記: `screenPosition(x,y,z)` だけが y を反転して返すことは別 Issue #378 で扱う。）

### 1-b. 実装は既に部分的に P3D 寄りで、ADR-0005 の表の方が実装より遅れている

「現状の割り当て」として Decision 1 の表が書いていることは、**もはや実装と一致していない**（#379）:

| API | ADR-0005 の表 | 実装（[SketchContext+Transform.swift:50-77](../../Sources/MetaphorCore/Sketch/SketchContext+Transform.swift#L50)・`SketchContext+3D.swift:339-351`） |
|---|---|---|
| `push()` / `pop()` | 2D のみ | **2D/3D 両方**（`canvas.push()` + `canvas3D.pushState()`） |
| `pushStyle()` / `popStyle()` | 表に無い | **2D/3D 両方**（「片方だけ保存すると 2D と 3D のスタイルが黙って乖離する」というコメント付き） |
| `resetMatrix()` | 表に無い | **2D/3D 両方** |

しかも shipped example `Examples/Basics/Form/Primitives3D` は `push()`/`pop()` が 3D にも効く
実装挙動に依存しており（3D の `translate`/`rotateY`/`box` を `push()`/`pop()` で囲んでいる）、
その再現テスト（`Graphics3DTests` の "Primitives3D exact reproduction"）も同じ挙動を前提にしている。
つまり **metaphor は「Sketch 層の変換系を 2D/3D 両方へ効かせる」方向へ既に半歩踏み出しており、
残っているのが `translate`/`rotate`/`scale` の 3 本**という状態である。

この帰結は 2 つ:

- **Option C（見送り）を採っても「何もしない」では済まない**。#379 の表の是正が前提になり、
  そこで「`push`/`pop` は両方に効くが、その中で使う `translate(x,y)` は 2D にしか効かない」という
  説明を 1.0 の確定仕様として書くことになる。
- **Option A の実装コスト見積もりが下がる**。スタック（`push`/`pop`/`pushMatrix`/`popMatrix`）が
  既に両 Canvas を保存・復元しているため、変換の適用先を広げても**囲みの対称性は最初から取れている**。
  A で新規に必要なのは適用の 3 行だけで、スタック側の整合を取る作業は発生しない。

### 2. 実測: 現状の意味論は「壊れているまま黙っている」

2D 変換が 3D に効かないため、Processing 移植の最頻出イディオム
`translate(width/2, height/2)` → 3D 描画は、**3D 側だけが中央寄せされずワールド原点
（= ピクセル空間の左上）に描かれ、大半が画面外へ切れる**。

実測（`128×128`、`translate(64, 32)` 後に `box(20)` を描いたときの重心）:

| 意味論 | 重心 | 意味 |
|---|---|---|
| 現状（2D のみ） | **(7.0, 7.0)** | 左上に張り付き、ボックスの大半が画面外 |
| 統一後 | **(63.5, 29.9)** | 作者が書いたとおりの位置 |

Examples 278 本の全数調査（`grep` + 目視）:

| 区分 | 本数 | 統一後に起きること |
|---|---:|---|
| 3D 描画 + 2 引数 `translate(x, y)` | **11** | 3D の位置決めが**意図どおりに直る**（現在は左上に張り付き） |
| 3D 描画 + 1 引数 `rotate(a)` | **0** | — |
| 3D 描画 + 2 引数 `scale(sx, sy)` | **0**（`scale(sx,sy)` は Examples 全体で使用ゼロ） | — |
| 3D 変換の下で 2D 描画（逆方向） | 2 | **直らない**（§3） |
| 3D + 2D HUD（HUD 側は無変換） | 5 | 変化なし |

該当 11 本: `Topics/Geometry/{Icosahedra, NoiseSphere, ShapeTransform, Vertices}` /
`Topics/Textures/{TextureCylinder, TextureQuad}` / `Topics/Shaders/{EdgeFilter, ToonShading}` /
`Demos/Graphics/Patch` / `Demos/Performance/{Esfera, StaticParticlesImmediate}`。

いずれも Processing からの移植で、`translate(width/2, height/2)` が効く前提で書かれている。
**これらは「統一で壊れる」のではなく「統一しないと壊れたまま」である**——この点が
ADR-0005 執筆時の想定（= 動いているスケッチが壊れる）と逆であり、判断の軸が変わる。

移行ガイド（PR #377）は現状を正しく記述しているが、その記述が
「a ported `P3D` sketch that wraps a 3D object in `translate(x, y)` will not move it —
write `translate(x, y, 0)`」という**回避策の案内**になっている。座標系まで P3D 互換なのに
変換 API だけ書き換えを強いる、という状態を 1.0 の仕様として選ぶかどうかが本判断である。

`Demos/Graphics/Patch` は現状の非対称が最も分かりやすく出ている例で、
`translate(width/2, height/2)`（効かない）と `scale(0.9)`（**均一スケールなので既に 3D へ効く**）が
隣り合っている。同じ変換ファミリの中で作用先が割れていることが、コード上で目視できる。

### 3. 限界: A は P3D の「半分」であり、残り半分は構造的に到達不能

Processing P3D は**単一のレンダラ**で、`rect()` も 3D ジオメトリとして同じ行列スタックを通る。
metaphor は 2D と 3D で**別のパイプライン**を持つ:

- `Canvas2D` の変換は `float3x3` のアフィンで、頂点は CPU 側で変換してピクセル空間の
  オルソ投影へ書き込む（[Canvas2DVertexWriter.swift:49](../../Sources/MetaphorCore/Drawing/Canvas2DVertexWriter.swift#L49)）。深度もパースもない。
- `rotateX` / `rotateY` は `float3x3` では**表現できない**。したがって「3D 変換 API を 2D 描画にも効かせる」
  逆方向は、2D プリミティブを 3D パイプラインで描く（= P3D レンダラを新設する）以外に手段がない。

結果、以下の 2 例は Option A では直らない:

- `Examples/Basics/Transform/RotateXY` — `translate(w/2,h/2,0)` + `rotateX/rotateY` で `rect()` を回す
  Processing 本家の移植。現状は 3D 変換が `rect` に効かず、静止した矩形が左上に描かれるだけ。
- `Examples/Topics/Image Processing/Explode` — 画素セルを `translate(x, y, z)` で押し出して `rect()` を描く。

**A を採る場合、この非対称（2D 変換 API は両方に効く / 3D 変換 API は 3D だけ）が 1.0 に残る。**
現状の非対称（引数の数で作用先が決まる）より説明しやすいかは判断が要る。上の 2 例は
「P3D レンダラがないとできないこと」として doc に明記し、examples 側を 3D API で書き直すのが
現実的な着地になる。

### 4. 実測: 実装コストと回帰

試作ブランチ [`spike/p3d-transform-semantics`](https://github.com/shinyaoguri/metaphor/tree/spike/p3d-transform-semantics)（コミット `ed22fd0`）で実装して測った。
**判断材料であり、そのまま merge する成果物ではない**（採用する場合の実装 PR の土台にはできる）。

差分は `SketchContext` の 3 メソッドに 1 行ずつ:

```swift
public func translate(_ x: Float, _ y: Float) { canvas.translate(x, y);   canvas3D.translate(x, y, 0) }
public func rotate(_ angle: Float)           { canvas.rotate(angle);     canvas3D.rotateZ(angle) }
public func scale(_ sx: Float, _ sy: Float)  { canvas.scale(sx, sy);     canvas3D.scale(sx, sy, 1) }
```

`rotate(a)` → `rotateZ(a)` は符号規約まで一致する（`Canvas2D.rotate` の 3x3 と
`float4x4(rotationZ:)` の左上 2x2 が同一）。試作テストで行列同値を確認済み。

| 測定項目 | 結果 |
|---|---|
| `swift test` | **1221 / 1221 緑**（既存 1214 + 試作 7）。**既存テストの赤は 0** |
| ゴールデン 6 シーン | **6/6 が差分ピクセル 0**（`maxChannelDiff=0`, `differingPixels=0/16384`） |
| 試作テストの有効性 | 変更を戻すと 7 本中 **5 本が赤**（新しい意味論を実際に固定している） |
| 実装規模 | 実装 3 行 + doc コメント 4 箇所 + `llms.txt` 再生成 |

ゴールデンが 1 画素も動かないのは、6 シーンのうち 3D を含む 3 つが**すべて 3 引数 `translate` を
使っており、2 引数 `translate` を使うシーンが存在しない**ため。裏を返すと**ゴールデンは
この変更に対する検出力を持っていない**——採用する場合は「2D 変換 + 3D 描画」のシーンを
ゴールデンに追加してから実装するのが筋（W2-2 の追補）。

**既存テストの赤が 0 であることは「安全」ではなく「未固定」の証拠**でもある。ADR-0005
Decision 1 の規範表は、どのテストにも凍結されていない。

### 5. Considered Options

#### Option A（推奨）: 変換ファミリのみ P3D 意味論へ統一

`translate(x,y)` / `rotate(a)` / `scale(sx,sy)` を 2D・3D 双方へ適用する。

- **Pros**: 座標系が既に一致しているので実装 3 行（§1, §4）。壊れている 11 examples が直る（§2）。
  ADR-0007 の原則（Sketch 層 = Processing 互換最大化）に素直に従う——`translate`/`rotate`/`scale` は
  Processing 語彙そのもので、P3D では 2D 変換 API が 3D にも効く。`pushMatrix`/`popMatrix`/`push`/`pop` は
  **既に**両方を保存・復元するため、囲まれた変換は 3D へ漏れない（試作テストで確認）。
  「引数の数で作用先が変わる」という暗記事項が消える。
- **Cons**: 破壊的変更（0.x として許容範囲だが CHANGELOG 必須）。逆方向は直らず新しい非対称が残る（§3）。
  `translate(x,y)` を「2D だけ動かす」意図で**バランスさせずに**使っていたスケッチは 3D の位置がずれる
  （Examples には該当なし。回避は `pushMatrix()`/`popMatrix()` で囲む＝ Processing と同じ作法）。
  ゴールデンに検出力がないまま入れると回帰に気付けない（§4 の追補が前提）。

#### Option B: 全面統一（`blendMode` / `strokeWeight` も 2D/3D 両方へ）

- **Pros**: ADR-0005 が挙げた「2D/3D 適用規則の場当たり性」が原理的に消える。
- **Cons**: **`Canvas3D` にはブレンド状態も線幅も存在しない**（`SketchContext+Style.swift:149,167` は
  どちらも `canvas` にしか転送していない）。実装は「転送を足す」ではなく**新機能の実装**になる:
  3D 側の 5 系統のパイプライン × `BlendMode` 10 ケースぶんのパイプライン変種（カスタムマテリアルは
  利用者定義なので実行時生成）、深度書き込みとブレンドの相互作用（半透明 3D の描画順ソートは
  ADR-0003 が「別 Issue 推奨」として未着手のまま）、3D の線幅は別実装。規模は **L**、
  リスクは W1-9（Swift 6）に匹敵する。1.0 前のウィンドウに入れるのは非現実的。**却下**。

#### Option C: 見送り — 現状の割り当てを 1.0 の確定仕様として凍結

- **Pros**: 非破壊。描画結果は 1 画素も動かない。`Sketch` 層 doc の「2D のみ」注記（実装済み）と
  移行ガイドの落とし穴集で誤誘導は一応防げている。
- **Cons**: **ゼロコストではない**——#379（ADR-0005 の表の是正）が前提になり、「`push`/`pop` は
  2D/3D 両方に効くが、その中の `translate(x,y)` は 2D にしか効かない」という規則を 1.0 の
  確定仕様として明文化することになる（§1-b）。**11 examples が壊れたまま 1.0 になる**（§2）。
  Processing 移植の最頻出イディオムが警告もエラーもなく黙って別の絵を出す——ADR-0007 の原則
  （Sketch 層 = Processing 互換最大化）と正面から衝突する。座標系は既に P3D 互換なのに
  変換 API だけが非互換、という一番説明しにくい形（§1）が残る。`scale(s)` だけが両方に効き
  `scale(sx,sy)` は 2D だけ、という同一ファミリ内の割れも凍結される。
  「1.0 前に再評価する」と自ら宣言した窓を、**評価の結果ではなく実施しないことで**閉じることになる。

#### Option D（記録のみ・今回は採らない）: P3D モードのオプトイン

Processing 本家と同じく `size(w, h, P3D)` 相当のモードを設け、2D プリミティブを 3D パイプラインで
描く。§3 の逆方向まで含めて真の P3D 互換になる唯一の道だが、2D の全機能（バッチング・クリッピング・
テキストアトラス・massive・SVG 書き出し・コマンド記録）を 3D 経路へ移植する必要があり、
Epic 級。1.0 のスコープ外。**A を採っても D への道は塞がらない**（A は D の部分集合として矛盾しない）。

### 6. Option A を採る場合の付随論点（要判断）

| API | 統一できるか | 案 |
|---|---|---|
| `shearX` / `shearY` | 可能（せん断は 4x4 で表現可・単位なし） | 3D に対応する API が存在しないため、**同時に統一する**か **2D 専用のまま残す**か要判断 |
| `applyMatrix(float3x3)` | 可能（3x3 アフィンを 4x4 へ持ち上げる） | 同上。`applyMatrix(float4x4)` が 3D 専用として既にあるため、3x3 版を両方へ流すと「3x3 は両方 / 4x4 は 3D だけ」になる |
| `resetMatrix()` | — | **既に両方**に効く（変更不要） |
| `pushMatrix` / `popMatrix` / `push` / `pop` / `pushStyle` / `popStyle` | — | **既に両方**（ADR-0005 の表が実装と食い違っている件は #379 で是正） |

推奨は「まず `translate`/`rotate`/`scale` の 3 本だけを統一し、`shear`/`applyMatrix` は
利用実績がない（Examples で 3D と併用ゼロ）ため現状維持のまま doc で明示」だが、
「変換ファミリ = 変換 API 全部」と読むなら同時に統一する方が一貫する。**ユーザー判断**。

### 7. Option A を採る場合の実施手順（案）

1. ゴールデンに「2D 変換 + 3D 描画」シーンを追加し、**現状の（壊れた）出力を先にゴールデンとして固定**する
   → 実装 PR で差分が可視化される（W2-2 の追補。§4）。
2. 実装（試作の 3 行）+ 試作テストを `SketchAPISurfaceTests` へ移植 + ADR-0005 Decision 1 の表を更新。
3. 影響を受ける 11 examples を目視確認（`examples-sweep` full 推奨）。いずれも「直る」ので
   ソース変更は不要な見込みだが、2 引数と 3 引数の `translate` が混在するもの
   （`Vertices` は中央寄せ後に `translate(0, -40, 0)`）は、合成後の位置を実際に描いて確かめる。
4. CHANGELOG に **breaking** として記録し、[processing-migration-guide.md](../processing-migration-guide.md)
   の「2D and 3D are two canvases, and most transforms pick one」節（対応表 + "the arity picks the
   canvas" の rule of thumb）と「Transforms」表（`translate(x, y)` = "2D only"）を書き換える。
   **この 2 箇所は Option A で意味が反転するため、実施する場合は同一 PR で更新すること**。
   移行手段は「2D だけ動かしたい箇所を `pushMatrix()`/`popMatrix()` で囲む」。

### 8. Consequences（Option A を採る場合）

- Decision 1 の表は次のように変わる（`blendMode` / `strokeWeight` の 2D 専用は据え置き = Option B は却下）:

  | 適用先 | API |
  |---|---|
  | 2D/3D 両方 | `fill` / `stroke` / `noFill` / `noStroke` / `push`・`pop` / `pushMatrix`・`popMatrix` / `pushStyle`・`popStyle` / `resetMatrix` / `scale(s)` / **`translate(x,y)`** / **`rotate(a)`** / **`scale(sx,sy)`** |
  | 2D のみ | `blendMode` / `strokeWeight` / `shearX`・`shearY` / `applyMatrix(float3x3)`（§6 の判断次第） |
  | 3D のみ | `translate(x,y,z)` / `rotateX/Y/Z` / `scale(x,y,z)` / `applyMatrix(float4x4)` / `camera` / `lights` / `material` 系 |

- Decision 1 の「1.0 前の破壊的変更ウィンドウで再評価する」は本 Amendment で**決着**する。
- 本 Amendment は**変換ファミリの適用先だけ**を決める。ADR-0005 の表そのものの誤り
  （`push`/`pop` の分類・`pushStyle`/`popStyle` の欠落・「3D のみ」注記の欠落・`ortho()` の既定値）は
  #379 の担当。**どの Option を採っても #379 は必要**で、両者は同じ表を触るためマージ順に注意する
  （先に入った方に合わせて他方を調整）。
- `docs/processing-migration-guide.md` の「変換」表と該当する落とし穴も同時に更新する（§7-4）。
- 副産物として `screenPosition(x,y,z)` の y 反転（#378）は本判断と独立に修正が必要。
  Option A を採ると `translate(x,y)` 経由でも 3D の `screenY` を踏む経路が増えるため、
  #378 を先に片付けておく方が混乱が少ない。

### 9. 再評価の条件（Option C を採る場合に、この窓を再び開いてよい状況）

- (a) Option D（P3D モード）に着手するとき。逆方向を含めて一度に片付けられるため、
  A を飛ばして D へ進む判断はあり得る。
- (b) 1.0 後でも、`translate(x,y)` の適用先変更は **public API のシグネチャを変えない**ため
  ソース互換は壊れない（描画結果だけが変わる）。CHANGELOG での明示と minor bump があれば
  1.0 後にも実施できる——ただし「壊れた 11 examples を 1.0 に載せる」ことの是非は別問題。

## References

- Issue #151（論点の全リスト）、#150（受け口検証の統一）、#158（loadPixels の順序保証）
- Issue #221（Amendment の経緯）、#200 / #203 / #210（create*/make* 統合の実施）
- Issue #323（typed throws の延期とエラー型統一）、#332（`build-swift-5-10` の必須化）
- Issue #202 / #326（Decision 6 の実施）、#330（ゴールデン回帰基盤 — 分割の無害性の検証に使用）
- docs/ai/README.md「Invariants」（エラー報告・トリプルバッファ規約・loadPixels のパス分割）
- Amendment（ドラフト・2026-08-02）関連: Issue #325（本判断）、Epic #314 /
  [v1-release-plan.md](../design/v1-release-plan.md) W1-6、
  [ADR-0007](0007-finalize-public-api-surface.md)「原則: Processing 互換と Swift 慣行の優先順位」、
  Issue #336 / PR #377（Processing 移行ガイド — 既定カメラが P3D 既定と一致することの独立確認）、
  Issue #379（ADR-0005 の 2D/3D 適用表と実装の食い違い — どの Option でも前提）、
  Issue #378（`screenY(x,y,z)` の y 反転）、Issue #330 / PR #366（ゴールデン基盤 = §4 の計測手段）
- 試作ブランチ: `spike/p3d-transform-semantics`（コミット `ed22fd0`。判断材料であり merge 対象ではない）
