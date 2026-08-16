# ADR-0012: アルファは公開 API が straight、内部と出力が premultiplied と定める

- **Status**: Accepted
- **Date**: 2026-08-16
- **Deciders**: @shinyaoguri
- **PR / Commit**: #855

## Context

metaphor は「アルファをどう扱うか」をどこにも書いていない。`grep -rn "premultipl" docs/` は 0 件で、
ADR も `CONTRACT.md` も触れていない。方針として読める記述は、コード中の 2 つのコメントだけだった。

- `Sources/MetaphorCore/Core/PipelineFactory.swift:146-151`（`ead3c9e`）
  — 「標準的な straight-alpha over: `final.a = src.a + dst.a * (1 - src.a)`」。
  `sourceAlphaBlendFactor` を `.sourceAlpha` から `.one` へ直した経緯（α が二乗され、Syphon 等で
  透明と区別が付かなくなった）
- `Sources/MetaphorCore/Core/PipelineFactory.swift:179-185`（#800 / PR #823）
  — 「引くのは色であって不透明度ではない」。`blendMode()` は描いた領域の α を削らない、という原則

規範が無いまま実装が育った結果、**同じ 1 つの構造的な取り違え**が経路ごとに独立したバグとして
表面化している。実装が置いている前提は、実際には次のように割れていた。

| 層 | 実際の前提 | 根拠 |
|---|---|---|
| 公開 API の入力（`fill` / `stroke` / `tint` / `Color`） | straight | `Color.swift:9-26`、`Canvas2DImage.swift:129-130` |
| レンダーターゲットの中身 | **premultiplied** | `.alpha` ブレンドの必然（`PipelineFactory.swift:142-151`） |
| グリフアトラス | **premultiplied** | `TextRenderer.swift:209`（`CGImageAlphaInfo.premultipliedLast` に白で焼く） |
| 読み込んだ画像 | **premultiplied** | `MImage.swift:30-46`（`MTKTextureLoader` に unpremultiply オプションは無い） |
| テクスチャを貼るフラグメント | straight | `MetaphorCanvas2DTextured.metal:22-23`（`texColor * in.color`） |
| `get()` / `loadPixels()` | 無変換（= premultiplied を straight として返す） | `MImage.swift:293-304` |
| PNG / GIF / Probe の書き出し | premultiplied（宣言と実体が一致） | `MetaphorRenderer.swift:1027`、`ProbeWriter.swift:452`、`GIFExporter.swift:396` |
| SVG 書き出し | straight | `SVGRecorder.swift:435,465` |
| CoreImage 連携 | premultiplied | `CIFilterWrapper.swift:35`（`.outputPremultiplied: true`） |
| ぼかし・縮小（Kawase / gaussian / MPS） | premultiplied | `MetaphorKawaseBlur.metal:19,44` ほか |

**premultiplied なテクスチャを straight として再サンプルする**という同一の誤りが、少なくとも 4 箇所にある。

- `text()` — アトラスが premultiplied なのに `texColor * in.color` + straight over。
  AA のカバレッジが二乗され、`fill` の α も二重に掛かる
- `image()` / `copy()` / `previousFrame()` / `createGraphics()` の戻し — 同じ構造。半透明部が暗く沈む
- `MergePass(.alpha)` — `b.rgb * b.a + a.rgb * (1 - b.a)`（`MetaphorMerge.metal:37-42`）。既報 #831
- `get()` / `loadPixels()` — 割り戻さないので `set(x, y, get(x, y))` が恒等でない

さらに `blendMode()` は、モードごとに α の意味がばらばらだった（#801 で実測）。
`.difference` / `.exclusion` はシェーダー実装で `mix(dst, blend, src.a)` と扱うのに、
`.multiply` / `.screen` / `.lightest` / `.darkest` は固定関数のブレンド係数に `src.a` が現れず、
**α=0 で塗っても下地が変わる**。

```
下地 rgba(102, 77, 51,255) に rgba(64,140,38,α) を重ねた実測（main 35f3ff3）
            α=0                  α=0.5                α=1
multiply    rgba( 26, 42,  8,  0) rgba( 26, 42,  8,128) rgba( 26, 42,  8,255)
screen      rgba(140,175, 82,255) rgba(140,175, 82,255) rgba(140,175, 82,255)
lightest    rgba(102,140, 51,255) rgba(102,140, 51,255) rgba(102,140, 51,255)
darkest     rgba( 64, 77, 38,  0) rgba( 64, 77, 38,128) rgba( 64, 77, 38,255)
```

これらを個別に直すことはできるが、**次に増える経路（新しいエフェクト・新しい出力先・新しい
テクスチャ源）でまた同じ取り違えが起きる**。#831 が要求しているのも個別修正ではなく
「どちらかに揃っていて、doc にどちらなのかが書かれていること」だった。

回帰テストもこれを見張れない。`Sources/MetaphorTestSupport/GoldenImage.swift:441-449` は
ゴールデン画像に不透明を強制していて（「PNG 保存は premultiplied 往復のため非不透明画素は
再現しない」）、α<1 の合成結果を検証するテストは 1 本も無い。

## Considered Options

### Option A: 規範を置かず、症状ごとに直す

- Pros: 各修正が小さく、影響範囲が読みやすい。既存の絵が変わる範囲を最小にできる
- Cons: 4 箇所を直しても**次の経路でまた再発する**。「この経路は straight か premultiplied か」を
  毎回議論し直すことになる。#831 の要求（doc に書かれていること）を満たさない

### Option B: 内部も straight alpha に統一する

- Pros: 公開 API と内部表現が同じで、`get()` / `set()` の往復が自明に恒等になる
- Cons: Metal のブレンドは premultiplied を作るので、**描画のたびに割り戻しが要る**。
  α が小さい画素で 8bit の階調が壊れる。**ぼかし・縮小・フィルタは premultiplied でないと正しくない**
  （straight のまま平均すると透明画素の色が混ざる）ため、Kawase / gaussian / MPS / CoreImage を
  すべて逆向きに直すことになる。PNG / Probe / GIF の `premultipliedLast` 宣言も全部覆る

### Option C: 公開 API は straight、内部と出力は premultiplied（採用）

- Pros: **既に実態がそうなっている**（レンダーターゲット・アトラス・読み込み画像・書き出し宣言・
  フィルタ群がすべて premultiplied）。直すのは「境界で変換していない箇所」だけで、経路は有限。
  フィルタ・リサンプルが正しい側に乗る。p5.js / Processing 互換の API 表面（`fill(r,g,b,a)` が
  straight）を保てる
- Cons: 境界がどこかを実装が把握し続ける必要がある。カスタム 2D シェーダは premultiplied を
  返す契約になり、既存のユーザーシェーダに影響する（0.x なので minor で発車できる）。
  修正により**半透明の絵が変わる**（正しくなる方向だが、既存の見た目に依存した作品はずれる）

### Option D: 公開 API にも premultiplied を露出する

- Pros: 内部と外部が一致し、変換点が消える
- Cons: `fill(255, 0, 0, 128)` が「赤の半透明」でなくなる。Processing 由来の発想という
  プロジェクトの前提（CLAUDE.md）に反し、利用者に合成理論の知識を要求する

## Decision

**Option C を採る。公開 API の入力・出力は straight alpha、内部（レンダーターゲット、テクスチャ、
パス間の受け渡し）と外部出力は premultiplied alpha。両者の変換は境界で実装が行い、利用者には見せない。**

決め手は 2 つ。実装の大半（レンダーターゲット・アトラス・画像ロード・書き出し宣言・フィルタ群）が
すでに premultiplied で動いていて、Option B はそれを全部逆向きに直す作業になること。そして
ぼかし・縮小・フィルタは premultiplied でなければ原理的に正しく書けないこと。

### 規範（実装が守るべき形）

1. **公開 API は straight**。`fill` / `stroke` / `tint` / `Color` / `background` の α は「不透明度」であり、
   `get()` / `loadPixels()` / `pixels` が返す値も straight。`set(x, y, get(x, y))` は恒等である
2. **内部は premultiplied**。レンダーターゲット・オフスクリーン・グリフアトラス・読み込み画像・
   RenderGraph のパス間・PostProcess の中間テクスチャに入っている RGB は α を掛けた後の値である
3. **変換は境界で行う**。straight を内部へ入れるところで premultiply し、内部から公開 API へ
   返すところで un-premultiply する。境界は「頂点色の組み立て」「ピクセル読み書き」の 2 種類に集約する
4. **新しい経路を足すときは、その経路がどちらの世界にいるかを doc コメントに書く**

### 規範から決まる帰結

1. `.alpha` のブレンド係数は `(source: .one, destination: .oneMinusSourceAlpha)`（premultiplied over）。
   組み込みフラグメントは premultiplied を返す
2. **`blendMode()` はどのモードでも `result.rgb = mix(dst, blend(src, dst), src.a)` /
   `result.a = src.a + dst.a·(1 − src.a)`**。α は「混ぜ方をどれだけ効かせるか」であり、
   モードによって効いたり効かなかったりしない（#801）
3. 2 の帰結として **`.subtract` の結果 α も over になる**。PR #823 が選んだ「下地の α をそのまま残す」は
   本 ADR で改める。#800 が確立した原則（`blendMode()` は描いた領域の不透明度を削らない）は保たれる
   — over は α を削らないからで、変わるのは「半透明な下地の上に不透明な src を重ねたときに
   結果が不透明になるか、下地の α のままか」の一点だけ
4. クリアカラーも premultiplied で格納する（`background(α<1)` の実装が満たすべき形）
5. `PostEffect` は premultiplied を受け取り premultiplied を返す。RGB だけを弄って α を素通しする
   実装（vignette / colorGrade）は premultiplied では正しい。bloom extract の `α = 1` 固定は誤り
6. カスタム 2D シェーダのフラグメントは premultiplied を返す。`in.color` は従来どおり straight で渡し、
   前文に変換ヘルパを置く

### 外部出力での扱い

| 出力 | 出すもの | 備考 |
|---|---|---|
| 画面 | premultiplied をブレンド無しで転送 | ドローアブルは不透明合成なので α は事実上使われない |
| PNG / Probe / GIF | `premultipliedLast` と宣言して渡す | ImageIO が割り戻すので**ファイルは straight**。現状のままで正しい |
| SVG | straight（`fill-opacity`） | 現状のままで正しい |
| Syphon | premultiplied を無加工で publish | **受け手は premultiplied over で合成すること**を doc に明記する |
| 動画（h264 / hevc） | α を捨て、黒に合成済みの RGB が残る | コーデックが α を持てない。doc に明記する |

## Consequences

### Positive

- `text()` の AA と `fill` の α が二重に掛からなくなる。文字が痩せない
- 半透明画像・半透明オフスクリーンを重ねたときに暗く沈まなくなる
- `set(x, y, get(x, y))` が恒等になる
- `blendMode()` の α がモード間で揃い、`fill` の α で効き具合を調節できる（#801）
- 新しいエフェクト・出力先を足す人が、参照すべき規範を 1 つ持てる（#831 の要求）

### Negative / Trade-offs

- **既存の絵が変わる**。半透明の画像・文字・オフスクリーン合成に依存した作品は見た目がずれる
  （正しくなる方向だが、ずれることには変わりない）。0.x なので minor で発車する
- カスタム 2D シェーダのフラグメントが premultiplied を返す契約になる。破壊的変更として changelog に記録する
- 「内部は premultiplied」を実装者が意識し続ける必要がある。境界を 2 種類に集約し、
  doc コメントで示すことで担保する

### Follow-ups / 残課題

実装は Epic #854 に集約し、次の順で当てる。

1. 基盤 — `.alpha` の premultiplied 化、組み込みフラグメント 4 系統、クリアカラー、`pixels` の境界変換、
   カスタムシェーダ前文のヘルパ。これで #846（`text()`）/ #847（`image()`）/ #848（`pixels`）が閉じる。
   α<1 を見張る回帰テストの土台（#850）は同時に進める — これが無いと退行を検出できない
2. `blendMode()` の α 統一（#801）
3. `MergePass(.alpha)` の二重乗算（#831）、`background(α<1)`（#829）、`Graphics3D.background()`（#830）
4. `PostEffect` の α 契約と bloom extract（#849）、出力境界（Syphon / 動画 / GIF）の文書化（#851）

本 ADR が扱わないもの:

- **3D の半透明**（深度書き込み常時 ON・描画順ソート無し）。ADR-0003 が「別 Issue 推奨」とした宿題で、
  α の表現形式とは別の問題
- **PBR / IBL の透過**。`MetaphorPBR.h` / `MetaphorLighting.h` は `float3` の世界で、透過は設計に入っていない
- `blendMode()` を 3D へ広げること。ADR-0005 Amendment で却下済み

## References

- `Sources/MetaphorCore/Core/PipelineFactory.swift:104-210` — `BlendMode` とブレンド係数
- `Sources/MetaphorCore/Shaders/Metal/MetaphorCanvas2D{,Textured,Instanced,Massive}.metal` — 組み込みフラグメント 4 系統
- `Sources/MetaphorCore/Drawing/TextRenderer.swift:209` — グリフアトラスの premultiplied 焼き込み
- `Sources/MetaphorCore/Drawing/MImage.swift:30-46,293-327` — 画像ロードとピクセル読み書き
- `Sources/MetaphorCore/Shaders/Metal/MetaphorMerge.metal:37-42` — `MergePass(.alpha)`
- `Sources/MetaphorTestSupport/GoldenImage.swift:441-449` — ゴールデン画像の不透明強制
- [ADR-0003](0003-unified-command-stream.md) — 3D 半透明の描画順を別 Issue とした判断
- [ADR-0005](0005-sketch-api-consistency.md) — `blendMode()` を 2D のみとした判断（Amendment）
- [ADR-0009](0009-unfreeze-api-until-1-0.md) — 1.0 まで破壊的変更を許容する
- Issue [#801](https://github.com/shinyaoguri/metaphor/issues/801) / [#829](https://github.com/shinyaoguri/metaphor/issues/829) / [#830](https://github.com/shinyaoguri/metaphor/issues/830) / [#831](https://github.com/shinyaoguri/metaphor/issues/831)、Epic [#854](https://github.com/shinyaoguri/metaphor/issues/854)
- Issue [#800](https://github.com/shinyaoguri/metaphor/issues/800) / PR [#823](https://github.com/shinyaoguri/metaphor/pull/823) — `.subtract` の α（本 ADR で扱いを改める）
