# ADR-0002: 決定論レンダリングを段階導入する（noLoop 単一フレーム化 + シャドウ同一フレーム化）

- **Status**: Proposed
- **Date**: 2026-06-30
- **Deciders**: (PR レビューで確定)
- **PR / Commit**: (TBD)

## Context

AI協調ループ（Probe）が「編集→再観測」で意図通りの絵を検証するには、レンダリングの決定論性が前提（Epic #75 P1 / Issue #70）。現状2つの非決定論が残る（機構は [docs/design/deterministic-rendering.md](../design/deterministic-rendering.md) にコード検証済みで詳述）:

1. **noLoop が2フレーム描画** → `frameCount` が 2 になり初回 snapshot が非決定論的。2回目の描画は「クワッドclear → `loadAction=.clear` 最適化」への切り替えのためだけで、スナップショットの正しさには不要。
2. **次フレームシャドウ** → メインパス（影を読む）がシャドウ深度パス（影を書く）より先に走り、動く影が1フレーム遅延。

制約: 公開API不変が目標。レンダラ中核は829テストの土台に影響するため高リスク。Issue #70 / Epic #75 が「着手前に設計チェックポイント必須」と明記。本ADRは #71（即時描画→コマンド記録への全面移行）への布石の第一歩。

## Considered Options

### Option A: 全面コマンド記録（#71 相当）を一度に実装
- Pros: 2D/3D 双方が決定論パイプラインに乗り、根治。
- Cons: レンダラ全書き換え＝リスク過大。829テストの土台を一度に揺らす。チェックポイント要件と矛盾。

### Option B: noLoop もシャドウも触らず Probe 側で2フレーム待ちを吸収
- Pros: コア無変更でゼロリスク。
- Cons: `frameCount` 不整合と動く影の遅延は残る。決定論性という成功基準を満たさない。観測往復が遅いまま。

### Option C: 段階導入（採用）— noLoop を低リスクで単一フレーム化し、シャドウは記録/再生分離で同一フレーム化、間に設計ゲート
- Pros: リスクを分離。noLoop は独立PRで即効。シャドウは既存 `recordedDrawCalls` を活用し影オン時のみ経路変更（影オフはリグレッションゼロ）。#71 への前方互換。
- Cons: 2フェーズに分かれPR数が増える。シャドウ部で 2D/3D 重ね順の回帰リスクが残る（テストで担保）。

## Decision

Option C を採用する。決め手は「決定論性という成功基準を満たしつつ、829テストへの影響を分離・段階化できる」こと。noLoop（低リスク）を先行させ即効を出し、シャドウ同一フレーム化（中〜高リスク）は本ADR＋設計ドキュメントのレビューを設計ゲートとして通してから着手する。2D は当面即時描画を維持し、#71 でコマンド記録へ拡張する。

具体:
1. noLoop は再描画なしブリット（`useExternalRenderLoop`/`lastOutputTexture` 活用）で単一フレーム化、`frameCount=1`。
2. `Canvas3D.recordedDrawCalls` を「記録／再生」に明示分離し、`renderFrame` を `記録 → shadow → main(再生)` に組み替え。影オン時のみ。

## Consequences

### Positive
- noLoop スケッチの初回 snapshot が2フレーム待ち不要で確定（`frameCount=1`）。
- 動く影が同一フレームでジオメトリと整合。
- 公開API不変。影オフのスケッチは経路無変更。
- #71（2D含む全面コマンド記録）への土台ができる。

### Negative / Trade-offs
- **`background()` 以外の2Dを「3Dの背後」に意図描画した場合、3Dの前面に出る**（既知の制限・文書化）。支配的パターン `background → 3D → オーバーレイ` は正しい。任意順序の保持は #71（2Dコマンド記録）の領域。
- 影オン時の massive 2D インスタンス即時パスは記録経路で描画されない（安全にスキップ・稀）。
- 影の位置が変わるため視覚スナップショットの更新が必要。
- 影オン時のみ記録/再生の CPU オーバーヘッド（影オフは無変更）。

### 実装結果（2026-06-30）
- 記録→shadow→再生を**単一メインパス**で実現でき、レンダーパス増加（タイルフラッシュ増）は**発生しなかった**。当初の「+1パス」懸念は解消。
- 影オフ経路は完全に無変更で 846 既存テスト緑。影オン経路の end-to-end テスト3本（前景合成・3D再生・決定論）を追加し計849緑。

### Follow-ups / 残課題
- #71: 2D もコマンド記録化し、RenderGraph/PostProcess を含む全面決定論パイプラインへ。
- 半透明ブレンドの順序、RenderGraph/PostProcess との相互作用をフェーズ3で検証。

## References

- 設計ドキュメント: [docs/design/deterministic-rendering.md](../design/deterministic-rendering.md)
- `Sources/MetaphorCore/Sketch/SketchRunner.swift:443,463-470,488-489`（noLoop 2フレーム）
- `Sources/MetaphorCore/Core/MetaphorRenderer.swift:795,854-862,989`（renderFrame パス順 / draw(in:)）
- `Sources/MetaphorCore/Drawing/Canvas3D.swift:355,960-973,1105`（記録 / 即時描画 / シャドウサンプル）
- Issue #70、#71、Epic #75
