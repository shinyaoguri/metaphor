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

## References

- Issue #151（論点の全リスト）、#150（受け口検証の統一）、#158（loadPixels の順序保証）
- Issue #221（Amendment の経緯）、#200 / #203 / #210（create*/make* 統合の実施）
- docs/ai/README.md「Invariants」（エラー報告・トリプルバッファ規約）
