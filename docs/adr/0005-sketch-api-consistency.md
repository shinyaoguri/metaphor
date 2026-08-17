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

   > **この表は [Amendment（2026-08-02）§8](#8-consequences) で更新済み。** 現行の規範は §8 の表と、
   > それをシェイプ・メッシュ系へ広げた [Amendment（2026-08-18）§2](#2-決定-規範表の範囲をシェイプとメッシュへ広げる)
   > を参照する（下表は決定当時の記録として残す）。
   >
   > **「両層の doc に明記」も [Amendment（2026-08-18）§1](#1-決定-作用先注記の正本は-sketch-層のみdecision-3-を採る) で
   > 改めた**——作用先注記の正本は Sketch 層だけで、SketchContext 層には置かない。

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

## Amendment（2026-08-02, Issue #325）— 変換ファミリを P3D 意味論へ統一する

**決定: Option A を採用**（2026-08-02 のユーザーレビューで確定）。`translate(x, y)` /
`rotate(a)` / `scale(sx, sy)` を 2D・3D 双方の変換行列へ適用する。Decision 1 が
「1.0 前の破壊的変更ウィンドウで再評価する」と宣言した follow-up はここで決着する。

決め手は「**統一は既存スケッチを壊す変更ではなく、壊れているものを直す変更だった**」という
実測結果である（§1・§2）。3D の既定カメラが既に Processing P3D と同型のピクセル空間で
あるため、2D 変換を 3D へ流すことは座標系をまたぐ操作ですらない。実装は 3 行で、
既存テストの赤 0・既存ゴールデン 6 枚とも差分ピクセル 0（§4）。

**適用範囲は `translate`/`rotate`/`scale` の 3 本に限る**（`shearX`/`shearY` /
`applyMatrix(float3x3)` は 2D 専用のまま。§6）。また **A は P3D の「半分」**であり、
逆方向（3D 変換 API が 2D 描画に効く）は構造的に到達不能なまま残る（§3）。

以下は決定の根拠となった実測記録。

### 1. 前提の訂正: 2D と 3D の座標系は既に一致している

ADR-0005 執筆時の Option A の Cons は「既存スケッチの描画結果が変わる破壊的変更」だったが、
再評価の過程で**前提が違っていた**ことが分かった。`Canvas3D.begin()` は毎フレーム
Processing P3D と同型の既定カメラへリセットする（[Canvas3D+Frame.swift の begin()](../../Sources/MetaphorCore/Drawing/Canvas3D+Frame.swift)）:

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

実例での実測（`Topics/Shaders/ToonShading`、640×360、Probe で 1 フレーム取得し
フレームバッファ全体の bbox を測定）:

| | 描画内容の bbox | 重心 | 被覆率 |
|---|---|---|---|
| 統一前 | **(0,0)–(138,121)**（左上で画面外へ切れている） | (62.1, 54.7) | 6.4% |
| 統一後 | (191,51)–(448,308) | **(319.6, 179.4)** ≒ 画面中心 | 22.7% |

Examples 278 本の全数調査。**判定基準は「3D プリミティブ（`box` / `sphere` /
`cylinder` / `cone` / `torus` / `plane` / `beginShape3D`）を描いていること」**である
——`beginShape()`（2 引数版）で始めた形状の中の 3 引数 `vertex(x, y, z)` は
**z を落として 2D キャンバスへルーティングされる**ため（`SketchContext+3D.swift:20-28`。
Processing 互換として意図的にそうしてある）、`vertex(x,y,z)` を使っているだけでは
3D 描画にならない。

| 区分 | 本数 | 統一後に起きること |
|---|---:|---|
| **3D プリミティブ描画 + 2 引数 `translate(x, y)`** | **4** | 3D の位置決めが**意図どおりに直る**（統一前は左上に張り付き） |
| 3D プリミティブ描画 + 1 引数 `rotate(a)` | **0** | — |
| 3D プリミティブ描画 + 2 引数 `scale(sx, sy)` | **0**（`scale(sx,sy)` は Examples 全体で使用ゼロ） | — |
| 3D 変換の下で 2D 描画（逆方向） | 9 | **直らない**（§3） |

該当 4 本: `Demos/Performance/Esfera` / `Topics/Geometry/NoiseSphere` /
`Topics/Shaders/EdgeFilter` / `Topics/Shaders/ToonShading`。いずれも Processing からの
移植で、`translate(width/2, height/2)` が効く前提で書かれている。
**これらは「統一で壊れる」のではなく「統一しないと壊れたまま」である**——この点が
ADR-0005 執筆時の想定（= 動いているスケッチが壊れる）と逆であり、判断の軸が変わる。

移行ガイド（PR #377）は現状を正しく記述しているが、その記述が
「a ported `P3D` sketch that wraps a 3D object in `translate(x, y)` will not move it —
write `translate(x, y, 0)`」という**回避策の案内**になっている。座標系まで P3D 互換なのに
変換 API だけ書き換えを強いる、という状態を 1.0 の仕様として選ぶかどうかが本判断である。

`Topics/Shaders/EdgeFilter` は非対称が最も分かりやすく出ている例で、
`translate(width/2, height/2)`（2 引数 = 効かなかった）→ `rotateX`/`rotateY`（3 引数系 = 効く）
→ `translate(150, 0)`（2 引数 = 効かなかった）と 3 つの変換が交互に並ぶ。統一前は
**回転だけが効いて配置が一切効かない**ため、箱と球が両方ワールド原点に重なっていた。

### 3. 限界: A は P3D の「半分」であり、残り半分は構造的に到達不能

Processing P3D は**単一のレンダラ**で、`rect()` も 3D ジオメトリとして同じ行列スタックを通る。
metaphor は 2D と 3D で**別のパイプライン**を持つ:

- `Canvas2D` の変換は `float3x3` のアフィンで、頂点は CPU 側で変換してピクセル空間の
  オルソ投影へ書き込む（[Canvas2DVertexWriter.swift:49](../../Sources/MetaphorCore/Drawing/Canvas2DVertexWriter.swift#L49)）。深度もパースもない。
- `rotateX` / `rotateY` は `float3x3` では**表現できない**。したがって「3D 変換 API を 2D 描画にも効かせる」
  逆方向は、2D プリミティブを 3D パイプラインで描く（= P3D レンダラを新設する）以外に手段がない。

Option A では直らない例は Examples 内に **9 本**ある。2 つのパターンに分かれる:

1. **3D 変換の下で 2D プリミティブを描く** — `Basics/Transform/RotateXY`（`rotateX`/`rotateY` で
   `rect()` を回す Processing 本家の移植）、`Topics/Image Processing/Explode`
   （画素セルを `translate(x, y, z)` で押し出して `rect()` を描く）。
2. **`beginShape()` + 3 引数 `vertex(x, y, z)` で 3D 形状を組み立てている** —
   `Topics/Geometry/{Icosahedra, ShapeTransform, Vertices}` / `Topics/Textures/{TextureCylinder,
   TextureQuad}` / `Demos/Graphics/Patch` / `Demos/Performance/StaticParticlesImmediate`。
   これらは `beginShape3D()` ではなく 2D の `beginShape()` で始めているため、
   **z が落ちて 2D キャンバスへ流れる**（`SketchContext+3D.swift:20-28`）。結果として
   2 引数 `translate` による配置は効くが `rotateX`/`rotateY` が効かず、立体が平面に潰れて見える。
   Option A はこの経路に一切触れない（2D へ流れている以上、3D 変換の統一とは無関係）。

この非対称（2D 変換 API は両方に効く / 3D 変換 API は 3D だけ）は **1.0 に残る**。
上記 9 本は「P3D レンダラ（Option D）がないとできないこと」として doc に明記し、
examples 側は `beginShape3D()` へ書き換える（パターン 2）か 3D API で描き直す（パターン 1）のが
現実的な着地になる。**本 Amendment のスコープ外で、Issue #387 として起票した。**

### 4. 実測: 実装コストと回帰

差分は `SketchContext` の 3 メソッドに 1 行ずつ:

```swift
public func translate(_ x: Float, _ y: Float) { canvas.translate(x, y);   canvas3D.translate(x, y, 0) }
public func rotate(_ angle: Float)           { canvas.rotate(angle);     canvas3D.rotateZ(angle) }
public func scale(_ sx: Float, _ sy: Float)  { canvas.scale(sx, sy);     canvas3D.scale(sx, sy, 1) }
```

`rotate(a)` → `rotateZ(a)` は符号規約まで一致する（`Canvas2D.rotate` の 3x3 と
`float4x4(rotationZ:)` の左上 2x2 が同一）。`TransformSemanticsTests` が行列同値で凍結する。

| 測定項目 | 結果 |
|---|---|
| `swift test` | 全緑（1214 → 1227。新規 `TransformSemanticsTests` 9 本 + ゴールデン 1 枚） |
| **既存**テストの赤 | **0** |
| 既存ゴールデン 6 枚 | **6/6 が差分ピクセル 0**（`maxChannelDiff=0`, `differingPixels=0/16384`） |
| 新規テストの有効性 | 実装を戻すと `TransformSemanticsTests` 9 本中 **5 本が赤** |
| 新規ゴールデンの検出力 | 実装を戻すと `transform-2d-on-3d` が `maxChannelDiff=190` / 差分 **24.2%** で赤 |

**既存ゴールデンが 1 画素も動かない**のは、既存 6 シーンのうち 3D を含む 3 つが
**すべて 3 引数 `translate` を使っており、2 引数 `translate` を使うシーンが存在しない**ため。
つまり既存ゴールデンはこの変更に検出力を持たない。そこで
**`transform-2d-on-3d`（2D 変換 3 種 + 3D 描画）を新設**し、この軸を画素で凍結した。

同様に、**既存テストの赤が 0 であることは「安全」ではなく「未固定」の証拠**だった——
ADR-0005 Decision 1 の規範表はどのテストにも凍結されていなかった（Issue #385）。
`TransformSemanticsTests` が表そのもの（2D/3D 両方・2D のみ・3D のみの 3 区分）を凍結する。

### 5. Considered Options

#### Option A（採用）: 変換ファミリのみ P3D 意味論へ統一

`translate(x,y)` / `rotate(a)` / `scale(sx,sy)` を 2D・3D 双方へ適用する。

- **Pros**: 座標系が既に一致しているので実装 3 行（§1, §4）。壊れている 4 examples が直る（§2）。
  ADR-0007 の原則（Sketch 層 = Processing 互換最大化）に素直に従う——`translate`/`rotate`/`scale` は
  Processing 語彙そのもので、P3D では 2D 変換 API が 3D にも効く。`pushMatrix`/`popMatrix`/`push`/`pop` は
  **既に**両方を保存・復元するため、囲まれた変換は 3D へ漏れない（試作テストで確認）。
  「引数の数で作用先が変わる」という暗記事項が消える。
- **Cons**: 破壊的変更（0.x として許容範囲だが CHANGELOG 必須）。逆方向は直らず新しい非対称が残る（§3）。
  `translate(x,y)` を「2D だけ動かす」意図で**バランスさせずに**使っていたスケッチは 3D の位置がずれる
  （Examples には該当なし。回避は `pushMatrix()`/`popMatrix()` で囲む＝ Processing と同じ作法）。
  既存ゴールデンに検出力がない（→ `transform-2d-on-3d` を新設して対処済み。§4）。

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
  確定仕様として明文化することになる（§1-b）。**4 examples が壊れたまま 1.0 になる**（§2）。
  Processing 移植の最頻出イディオムが警告もエラーもなく黙って別の絵を出す——ADR-0007 の原則
  （Sketch 層 = Processing 互換最大化）と正面から衝突する。座標系は既に P3D 互換なのに
  変換 API だけが非互換、という一番説明しにくい形（§1）が残る。`scale(s)` だけが両方に効き
  `scale(sx,sy)` は 2D だけ、という同一ファミリ内の割れも凍結される。
  「1.0 前に再評価する」と自ら宣言した窓を、**評価の結果ではなく実施しないことで**閉じることになる。

#### Option D（記録のみ・今回は採らない）: P3D モードのオプトイン


Processing 本家と同じく `size(w, h, P3D)` 相当のモードを設け、2D プリミティブを 3D パイプラインで
描く。§3 の逆方向まで含めて真の P3D 互換になる唯一の道だが、2D の全機能（バッチング・クリッピング・
テキストアトラス・massive・SVG 書き出し・コマンド記録）を 3D 経路へ移植する必要があり、
Epic 級。1.0 のスコープ外。**A を採用しても D への道は塞がらない**（A は D の部分集合として矛盾しない）。

### 6. 適用範囲: `translate` / `rotate` / `scale` の 3 本に限る

統一するのは **`translate(x,y)` / `rotate(a)` / `scale(sx,sy)` の 3 本だけ**とする。

| API | 統一できるか | 決定 |
|---|---|---|
| `shearX` / `shearY` | 可能（せん断は 4x4 で表現可・単位なし） | **2D 専用のまま**。3D に対応する API がなく、Examples でも 3D との併用はゼロ。doc に「統一の対象外」と明記した |
| `applyMatrix(float3x3)` | 可能（3x3 アフィンを 4x4 へ持ち上げる） | **2D 専用のまま**。`applyMatrix(float4x4)` が 3D 専用として既にあり、3x3 版を両方へ流すと「3x3 は両方 / 4x4 は 3D だけ」という別の非対称を作る |
| `resetMatrix()` | — | **既に両方**に効く（変更なし） |
| `pushMatrix` / `popMatrix` / `push` / `pop` / `pushStyle` / `popStyle` | — | **既に両方**（Decision 1 の旧表との食い違いは §8 の表と #379 で解消済み） |

「変換ファミリ = 変換 API 全部」と読めば `shear`/`applyMatrix` も対象になるが、
**Processing 互換の実利がある 3 本に絞る**方を採った。`shearX`/`shearY` は Processing にも
3D 版がなく、`applyMatrix` は行列を自前で組む利用者向けで「どちらに効くか」を明示的に
選べた方が扱いやすい。

### 7. 実施の記録

1. ゴールデン `transform-2d-on-3d`（2D 変換 3 種 + 3D 描画）を新設し、この軸に検出力を持たせた（§4）。
2. 実装（3 行）+ `TransformSemanticsTests`（適用規則の表そのものを凍結する 9 本）を追加。
3. 影響を受ける 4 examples のうち `ToonShading` を Probe で before/after 実測し、
   画面外 → 画面中央に戻ることを確認（§2）。4 本ともソース変更は不要（意図どおりに直る）。
4. CHANGELOG に **breaking** として記録し、[processing-migration-guide.md](../processing-migration-guide.md)
   の「2D and 3D are two canvases, and most transforms pick one」節（対応表 + "the arity picks the
   canvas" の rule of thumb）と「Transforms」表を書き換えた。
   移行手段は「2D だけ動かしたい箇所を `pushMatrix()`/`popMatrix()` で囲む」。

### 8. Consequences

- Decision 1 の表は次のように変わる（`blendMode` / `strokeWeight` の 2D 専用は据え置き = Option B は却下）:

  | 適用先 | API |
  |---|---|
  | 2D/3D 両方 | `fill` / `stroke` / `noFill` / `noStroke` / `push`・`pop` / `pushMatrix`・`popMatrix` / `pushStyle`・`popStyle` / `resetMatrix` / `scale(s)` / **`translate(x,y)`** / **`rotate(a)`** / **`scale(sx,sy)`** |
  | 2D のみ | `blendMode` / `strokeWeight` / `shearX`・`shearY` / `applyMatrix(float3x3)` |
  | 3D のみ | `translate(x,y,z)` / `rotateX/Y/Z` / `scale(x,y,z)` / `applyMatrix(float4x4)` / `camera` / `lights` / `material` 系 |

  > **この表はスタイルと変換の API しか列挙していない。** シェイプ・メッシュ系と、
  > 「記録中のシェイプが決める」という第 4 の区分は
  > [Amendment（2026-08-18）§2](#2-決定-規範表の範囲をシェイプとメッシュへ広げる) が足す。

- Decision 1 の「1.0 前の破壊的変更ウィンドウで再評価する」は本 Amendment で**決着**した。
- **breaking**: 3D 描画を含むスケッチで 2 引数 `translate` / 1 引数 `rotate` / 2 引数 `scale` を
  使っていた場合、これまで 3D に効かなかったものが効くようになる。「2D だけを動かす」意図で
  使っていた箇所は `pushMatrix()` / `popMatrix()` で囲む（Processing と同じ作法）。
  `public` API のシグネチャは変わらないため**ソース互換は壊れない**——変わるのは描画結果だけ。
- 本 Amendment は**変換ファミリの適用先だけ**を決めた。ADR-0005 の表そのものの誤りのうち
  `push`/`pop` の分類と `pushStyle`/`popStyle` の欠落は、本 Amendment の表（上記）で是正済み。
  残り（Sketch 層 doc の「3D のみ」注記の欠落・`ortho()` の既定値）は **#379 で消化した**
  ——`Sketch+3D.swift` のカメラ/投影・ライティング・シャドウ・マテリアル・テクスチャ・3D 変換に
  「**3D のみ**」注記を入れ、`ortho()` の既定値を実装（`left` 0 / `right` 幅 / `bottom` 高さ /
  `top` 0。Y 下向き）に合わせ、Decision 1 の旧表に本 §8 への前方参照を足した（2026-08-15）。
- `screenPosition(x,y,z)` の y 反転（#378）は本判断と独立に修正が必要。統一により
  `translate(x,y)` 経由でも 3D の `screenY` を踏む経路が増えるため、優先度は上がった。
- 逆方向が直らない 9 examples（§3）は **#387** で扱う。
- 適用規則を凍結するテストが皆無だった件（#385）は、本 PR の `TransformSemanticsTests` と
  ゴールデン `transform-2d-on-3d` で解消した。

### 9. 再評価の条件（この窓を再び開いてよい状況）

- Option D（P3D モード）に着手するとき。§3 の逆方向を含めて一度に片付けられるため、
  本 Amendment の到達点をその部分集合として取り込むことになる。

## Amendment（2026-08-18, Issue #677）— 作用先注記の正本は Sketch 層だけとし、規範表をシェイプとメッシュへ広げる

Decision 1 の「**両層の doc に**明記する」と Decision 3 の「SketchContext 層は
『転送のみ』の簡潔なコメントに寄せる」は、**両層 doc の扱いで噛み合っていない**（#677）。
#379 / PR #675 で Sketch 層に 33 本の注記が入った一方、`SketchContext+3D.swift` /
`SketchContext+Transform.swift` の作用先注記は **0 件**のままで、実装は Decision 3 に寄っている。
どちらが正かを決めないまま「機械的に注記を写す」ことはしない、という判断を先に確定させる。

### 1. 決定: 作用先注記の正本は Sketch 層のみ（Decision 3 を採る）

**「2D のみ」「2D/3D 両方」「3D のみ」の注記は `Sketch+*.swift` にだけ置く**。
`SketchContext+*.swift` は「転送のみ」の簡潔なコメントに寄せ、作用先注記を**置かない**
——したがって二重管理も発生しない。Decision 1 の「両層の doc に明記」は本 Amendment で
**Sketch 層のみに改める**。

根拠は 3 つ:

- **Decision 3 の方が新しく、実装もそちらに寄っている**（実測 0 件）。Decision 3 自身が
  「doc 正本は Option A（Sketch 層）」と決めており、Decision 1 の「両層」はその正本論と
  最初から緊張関係にあった。
- **`SketchContext` はユーザーが最初に触る面ではない**。Processing 風のグローバル API は
  `Sketch` プロトコル拡張として晒され、`llms.txt`（= AI 生成コードの品質に直結する面）も
  Sketch 層 API を主として並べる。ADR-0005 が挙げた「doc の 3 層複製」（Context の 4 番目）は、
  複製を増やして揃えるのではなく**複製をやめる**ことで解く。
- **二重管理はドリフト源そのもの**。同じ注記を 2 か所に置けば、片方だけ直る事故が必ず起きる
  ——それが本 ADR の Context 4 で問題視した状態である。

### 2. 決定: 規範表の範囲をシェイプとメッシュへ広げる

§8 の表はスタイルと変換の API しか列挙しておらず、`box()` / `sphere()` / `mesh()` /
`loadModel()` などは**どの表にも載っていなかった**。利用者の問い（「これは 2D に効くのか
3D に効くのか」）は同じなので、規範の範囲に含める。§8 の表に次の行を足す:

| 適用先 | API |
|---|---|
| 3D のみ（シェイプ） | `beginShape3D` / `normal` / `box` / `sphere` / `plane` / `cylinder` / `cone` / `torus` |
| 3D のみ（メッシュ） | `mesh` / `drawInstanced` / `dynamicMesh` / `createDynamicMesh` / `create*Mesh` 系 / `loadModel` / `loadModelAsync` |
| 記録中のシェイプが決める | 3 引数以上の `vertex(x,y,z…)` / `endShape3D` |

最後の行は**新しい区分**である。`vertex(x, y, z)` と `endShape3D()` は
`beginShape3D()` で始めたシェイプなら 3D へ、2D の `beginShape()` で始めたシェイプなら
z を落として 2D へ流れる（`SketchContext+3D.swift`。Processing 互換として意図的にそうしてあり、
初回だけ警告する。2026-08-02 Amendment §3 のパターン 2 / Issue #387）。
「3D のみ」と書くと**実装と食い違う**ため、区分を足して正確に書く。
§8 の表からはこの節への前方参照を張った（表そのものは決定当時の記録として据え置く）。

`create*Mesh` 系・`loadModel` 系は描画しないので「作用する」ではなく
「**生成されたメッシュを描けるのは 3D のみ**」と書く（`createMaterial` の既存注記と同じ形）。

### 3. 帰結

- `Sketch+3D.swift` の public メンバ **67 本すべて**が作用先注記を持つ状態になった。
  内訳は「**3D のみ**」37 本（うち 33 本は #379 / PR #675）+ `pushMatrix` / `popMatrix` の
  「**2D と 3D の両方**」2 本 + `toneMapping` の同義の注記（「掛かるのは **3D のライティング
  結果だけ**」）1 本 + **本 Amendment の 27 本**。
- 回帰は `Tests/metaphorTests/SketchScopeNoteTests.swift` が凍結する。`Sketch+3D.swift` に
  注記なしの public メンバを足すと赤くなるので、**新 API を足す人が ADR を読んでいなくても
  規約から外れない**。「新 API 追加時は本 ADR の規約に従う」（Consequences）を文書だけで
  担保していた状態を、機械判定へ移す。
- `SketchContext+*.swift` は**触らない**。注記を置かないことが本 Amendment の決定である。
- 挙動は変わらない（doc コメントと ADR 本文のみ）。`llms.txt` も動かない
  ——`scripts/generate-llms-txt.py` は要約に `-` 始まりの行を採らないため、`- Note:` は載らない。

## References

- Issue #151（論点の全リスト）、#150（受け口検証の統一）、#158（loadPixels の順序保証）
- Issue #221（Amendment の経緯）、#200 / #203 / #210（create*/make* 統合の実施）
- Issue #323（typed throws の延期とエラー型統一）、#332（`build-swift-5-10` の必須化）
- Issue #202 / #326（Decision 6 の実施）、#330（ゴールデン回帰基盤 — 分割の無害性の検証に使用）
- docs/ai/README.md「Invariants」（エラー報告・トリプルバッファ規約・loadPixels のパス分割）
- Amendment（2026-08-02）関連: Issue #325 / PR #384（本判断と実装）、Epic #314 /
  [v1-release-plan.md](../design/v1-release-plan.md) W1-6、
  [ADR-0007](0007-finalize-public-api-surface.md)「原則: Processing 互換と Swift 慣行の優先順位」、
  Issue #336 / PR #377（Processing 移行ガイド — 既定カメラが P3D 既定と一致することの独立確認）、
  Issue #379（ADR-0005 の 2D/3D 適用表の残りの是正）、Issue #378（`screenY(x,y,z)` の y 反転）、
  Issue #385（適用規則を凍結するテスト）、Issue #387（逆方向が直らない 9 examples）、
  Issue #330 / PR #366（ゴールデン基盤 = §4 の計測手段）
- Amendment（2026-08-18）関連: Issue #677（Decision 1 と Decision 3 の噛み合わせ・シェイプ系の注記欠落）、
  Issue #379 / PR #675（Sketch 層の 33 本の注記 = 本 Amendment の前段）、
  Issue #387（2D の `beginShape()` に 3 引数 `vertex` を流す経路）
- 回帰の凍結先: `Tests/metaphorTests/TransformSemanticsTests.swift`、
  `Tests/metaphorTests/Golden/transform-2d-on-3d.png`、
  `Tests/metaphorTests/SketchScopeNoteTests.swift`（作用先注記の存在そのもの）
- 判断材料に使った試作ブランチ: `spike/p3d-transform-semantics`（コミット `ed22fd0`。実装は本 PR に取り込み済み）
