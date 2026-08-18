# ADR-0007: 1.0 凍結に向けて公開 API 表面を最終整理する(命名規範・記録 API・二層 API・`@_exported`)

- **Status**: Accepted(2026-08-02 ユーザーレビューで確定)
- **Date**: 2026-08-01(起案)/ 2026-08-02(確定)
- **Deciders**: shinyaoguri(論点 2・3・5 は推奨案を採用、論点 7 は二層原則を明確化して修正)
- **PR / Commit**: (本 PR)
- **Issue**: #320(W1-1)。網羅調査の全文は [#320 のコメント](https://github.com/shinyaoguri/metaphor/issues/320#issuecomment-5150794440)

## Context

v1.0 readiness review(G3, G16)で、v1.0 で凍結すると永久に残る API 表面の不統一が顕在化した。
main `9b7c70a`(v0.8.0 後)に対する網羅調査の要点:

1. **ON/OFF 表現が 4 系統併存**: `no*`(noFill 等 9 種)/ `enable*`+`disable*`(Shadows 等)/
   `set*`+`clear*`(PostEffects 等)/ `Bool` 引数(`pbr(_:)`)。Shadows は enable/disable なのに
   Lights は lights/noLights、という「どちらの系統かを予測する規則」がない。
2. **記録 API のプレフィックス揺れ**: 5 ファミリ中 `beginSVG` だけ `Record` なし。さらに無印
   `beginRecord`(フレーム連番)が Processing の `beginRecord()`(ベクタ記録)と**意味衝突**している。
   async の露出も不統一(同名オーバーロード 2 件 vs `*Async` サフィックス 7+ 件)。
3. **二層で別名・片肺**: Sketch 層 `screenX/Y/Z` は SketchContext 層 `screenPosition` を呼んで成分を
   捨てるだけだが名前が違う。GPU 版 `filter(_ image:, _ type:)` は SketchContext 層のみに存在し
   Sketch 層(= doc 正本、ADR-0005 Decision 3)に露出がない。
4. **`@_exported import Metal/MetalKit/simd`**(MetaphorCore.swift:24-26)が利用者名前空間に Apple
   3 フレームワークを注入。剥がすか維持するかを凍結前に確定する必要がある。実測: Examples 側の実依存は
   極小(simd 固有型 1 ファイル 4 行、MTL* 直接使用 2 本で両方明示 import 済み)だが、**公開 API
   シグネチャ側の依存は重い**(MTL* 露出 120 宣言、simd 固有型 25 宣言、MTKView 系一式)。
5. **`_metaphorSyphonRegister()`**(ADR-0001 の C コンストラクタ登録用 `@_cdecl`)が Sources 全体で
   唯一のアンダースコア接頭辞 public シンボルとして露出。Swift 側からの呼び出しはゼロ。
6. **引数ラベル混在**: 「先頭は省略ラベル・途中からラベル付き」の public 宣言が Sources 全体 107 件
   (MetaphorCore/Sketch 配下 34 件、Sketch protocol 拡張のみで 26 件)。大半は規範化可能なパターン
   だが、`saveJSON(_ value:, _ path:)` のように下層 `DataIO.saveJSON(_:toPath:)` と**層間でラベル規約が
   食い違う**実例もある。

前提: ADR-0005 が確立済みの規約(Sketch 層 = Processing 風の手軽さ優先・doc 正本 / 生成系 = typed
throws / deprecation は「deprecation を含む minor を公開してから次の minor で削除」)は本 ADR の土台で
あり変更しない。破壊的変更はすべて v0.8.x の deprecation ウィンドウ内で完遂する(v1-release-plan)。

## 原則: Processing 互換と Swift 慣行の優先順位

個別判断に先立ち、判定規則を 1 本立てる:

> **Sketch 層において、Processing(または p5.js)に対応する語彙が存在する API は Processing の名前と
> 引数順を正とする。対応物がない metaphor 独自 API は Swift API Design Guidelines に従う。
> SketchContext 層以下(SketchContext / Canvas / モジュール層)は常に Swift 慣行を正とする。**

- 「Processing 語彙か」は Processing/p5.js リファレンスに同名・同義の API があるかで機械的に判定する
  (裁量を挟まない)。
- この原則により `noFill()` と `loadJSON(_:as:)` が同居する現状は「不統一」ではなく「二層の設計」として
  正当化され、以降の新 API 追加時の判定も自動化される。

**確定(2026-08-02 ユーザー決定)**: 上記原則を次の言葉で確認した — 「利用者から一番見える層
(Sketch 層)は Processing との互換性を最大化する。利用者が通常触らない内部層(SketchContext 以下)は
可能な限り Swift API Design Guidelines に準拠する」。ただし SketchContext の**転送メソッド**は
Sketch 層のミラーとして同形(同名・同ラベル)を許容する — 転送の対称性検証(#331 のテスト網)を
単純に保つためであり、内部層の**新規・非転送 API** は Guidelines 完全準拠を規範とする。

## 論点と選択肢

### 論点 1: ON/OFF 表現(4 系統)の統一

- **Option A: 出自で規範化する(推奨)** — Processing 語彙 = `no*` / metaphor 独自の ON/OFF =
  `enable*`+`disable*` / コレクション操作 = `add*`+`remove*`+`clear*`+`set*` の 4 動詞。
  `Bool` 引数トグルの新設は禁止(既存 `pbr(_:)` は Processing の `hint()` 相当の軽量スイッチとして維持)。
  - Pros: 現状の大半を追認するため移行コストが最小(rename ゼロ)。原則と整合し、新 API の判定が機械的。
  - Cons: 表面上は `noLights` と `disableShadows` が並ぶ見た目の不揃いが残る(規則性は doc で示す)。
- **Option B: `no*` へ全面統一**(`noShadows()` 等を新設)
  - Pros: 見た目が Processing 風に揃う。
  - Cons: Processing に存在しない語彙を `no*` で発明することになり、原則(語彙の機械判定)が崩れる。
    rename 6 件+の breaking を新たに作る。
- **Option C: `enable*`/`disable*` へ全面統一**(noFill → disableFill)
  - Cons: Processing 互換の中核を壊す。論外に近いが記録のため列挙。

Option A の付随修正(additive・非破壊): `SoundFile.disableAnalysis()` の追加(対欠損の補完)、
`setRenderGraph(nil)` でのクリアを doc 明記。`setClearColor` は Metal 語彙(clear color)由来の
複合名詞であり `clear*` 系(削除動詞)ではないことを doc に明記して維持。

### 論点 2: 記録・書き出し API の命名

- **Option A: `begin<Media>Record` / `end<Media>Record` に統一し、無印と SVG を改名する(推奨)**
  - `beginSVG`/`endSVG` → `beginSVGRecord`/`endSVGRecord`
  - 無印 `beginRecord`/`endRecord`(フレーム連番)→ `beginFrameRecord`/`endFrameRecord`
  - `beginOfflineRender`/`endOfflineRender` は維持(「記録」ではなくレンダリングモードの切替。
    規範: 記録系 = `*Record`、モード系 = `*Render`)
  - Pros: 5 ファミリの規則が 1 本になる。**Processing の `beginRecord()`(ベクタ記録)との意味衝突が
    解消する** — 現状は Processing 経験者が `beginRecord()` を SVG 記録と誤解する構造で、凍結後は
    直せない混乱源。
  - Cons: rename 4 件の breaking(deprecated エイリアス 2 リリース運用で吸収)。
- **Option B: `beginSVG` のみ改名(無印は維持)**
  - Pros: breaking が 2 件で済む。
  - Cons: 「無印 = フレーム連番」の Processing 衝突が残る。中途半端。
- **Option C: 現状維持 + doc 明記**
  - Cons: 凍結後に永久固定。doc で「beginRecord は Processing の beginRecord とは別物」と言い訳し続ける。

### 論点 3: 非同期 API の露出方式

- **Option A: `*Async` サフィックスに統一(推奨)** — 同名 async オーバーロード 2 件
  (`Sketch.endGIFRecord(_:) async` / `endVideoRecord() async`、+VideoExporter)を
  `endGIFRecordAsync` / `endVideoRecordAsync` へ移行。
  - Pros: 既存多数派(load 系 7+ 件、SketchContext.endGIFRecordAsync、GIFExporter.endRecordAsync)に
    少数派 2 件を寄せる最小移行。同名 sync/async オーバーロードは「async コンテキストから同期版を明示的に
    選べない」Swift の解決規則の罠があり、利用者正面から排除する価値がある。
  - Cons: Swift Concurrency の長期的な慣行(async のみ提供)とはずれるが、同期版を消せない
    (Processing 風の手軽さ)以上、サフィックスが現実解。
- **Option B: 同名オーバーロードに統一** — `*Async` 7+ 件を改名。
  - Cons: 移行数が多く、かつ上記の解決規則の罠を全面採用することになる。
- **Option C: 現状維持** — Cons: 同一ファミリ(GIF)内で層により方式が違う状態が凍結される。

save 系に async がない非対称は additive で解消可能なため本 ADR のスコープ外(0.9.x でも追加可)。

### 論点 4: 二層 API(Sketch 層 vs SketchContext 層)の名前と欠落

- **Option A: 「Sketch 層 = 利用者 API の正典、下位層名は実装都合で可」を規範化する(推奨)**
  - `screenX/Y/Z`(Processing 語彙)は維持。下位層 `screenPosition` も維持(転送層の実装名)。
    二層で名前が違うこと自体は問題としない — ADR-0005 Decision 3(doc 正本 = Sketch 層)の帰結。
  - **利用者向け機能が Sketch 層に欠けているものは引き上げる**: GPU 版 `filter(_ image:, _ type:)` を
    Sketch 層に追加(CPU 版 `MImage.filter(_:)` との使い分け — GPU=レンダラ経由/CPU=単体画像 — を
    両者の doc に明記)。
  - Pros: 転送層の自由度を保ちつつ、利用者から見える面(llms.txt)の完全性だけを約束する。
  - Cons: 「Sketch 層に何があるべきか」の線引きは個別判断が残る(→ 実装 Issue で表にして確定)。
- **Option B: 二層で名前を機械的に一致させる**
  - Cons: 転送層に Processing 名を強制(または Sketch 層に実装名を露出)することになり、
    どちらの層の設計も歪む。工数も大きい。

`modelX/Y/Z`(screenX の逆変換、Processing パリティの片肺)の追加は additive のためスコープ外
(follow-up として記録)。`screenX`+`screenY` 連続呼び出しで変換が 2 回走る非効率も実装最適化の話で
スコープ外(Issue 化)。

### 論点 5: `@_exported import Metal / MetalKit / simd` の扱い

- **Option A: 3 つとも維持し、意図的な再エクスポートとして凍結宣言する(推奨)**
  - Pros: 公開 API シグネチャに MTL* が 120 宣言・simd 固有型が 25 宣言露出している以上、剥がしても
    API から Apple 型は消えない — 「import metaphor 1 行でシグネチャの型がすべて使える」体験の維持が
    名前空間純化より価値が高い。`@_exported` は非公式属性だが、アンブレラ `metaphor` 自体が 12 連発で
    構造的に依存しており、リスクの増分はゼロ。
  - Cons: 利用者名前空間への注入は凍結後に剥がせない(major でしか外せない)。simd のグローバル関数
    (`dot`/`cross`/`normalize` 等)と利用者コードの名前衝突リスクは残る(実害報告なし)。
- **Option B: 3 つとも剥がす**
  - Pros: 名前空間が純粋になる。Examples 実測では breaking は極小(修正 1 ファイル)。
  - Cons: プラグイン作者・カスタム描画作者(`MetaphorPlugin.pre(commandBuffer:)` 等の利用者)全員に
    `import Metal` を書く義務が生じる。エラーメッセージも不親切になる(型は見えるのに名前解決できない)。
- **Option C: simd のみ維持、Metal/MetalKit を剥がす**
  - Cons: 「どれが再エクスポートされているか」を利用者が覚える必要が生じ、A/B どちらの利点も薄まる。

採用時は MetaphorCore.swift の doc コメントに「意図的な再エクスポート(契約の一部)」と明記し、
API 安定性ポリシー(W4-1 / #338)にも記載する。

### 論点 6: `_metaphorSyphonRegister()` と「doc では内部」な public 表面

- **Option A: `internal` + `@_cdecl` 化(推奨)** — `@_cdecl("metaphor_syphon_register")` は
  アクセス修飾子と独立に C リンケージのシンボルを生成するため、`public` は必須でない(調査で Swift 側
  呼び出しゼロを確認済み)。ADR-0001 の spike と同じ 4 組合せ(debug/release × 同一/クロスパッケージ)で
  自動登録が生きることを再検証してから適用する。
  - Pros: 唯一のアンダースコア public シンボルが消える。利用者影響ゼロ(検証前提)。
  - Cons: spike 再検証の手間。リンク挙動依存という ADR-0001 由来の性質は変わらない。
- **Option B: `@_spi(Bootstrap) public` 化** — Cons: SPI import が必要な利用者は存在せず、
  `@_cdecl` との併用は冗長。A で足りる。

付随方針: doc 自身が「内部」と明記している public 表面は **`internal`(テスト参照のみなら
`@testable` で足りるもの)または `@_spi(MetaphorInternal)`(モジュール横断で必要なもの)へ移す**。
候補: `SyphonPlugin`(テスト参照のみ)、`MetaphorRenderer.onCaptureOutput` / `shadowDeferActive` /
`onRecordFrame` / `onReplayMain`(ADR-0003 の内部フック)、`SketchContext.encoder` /
`gifExporter` 等。**個別の可否は実装 Issue で表にして確定する**(metaphor-cli・Plugin 作者・
TestSupport からの参照を機械的に確認してから。契約面は `./scripts/check-contract.sh` で検証)。

### 論点 7: 引数ラベル混在(107 件)の扱い

- **Option A(確定形): パターン規範化 + metaphor 独自 API の逸脱のみ是正**
  - **規範化(維持)**: Processing 語彙 API の必須座標・寸法・色は省略ラベル、オプション修飾はラベル付き
    (`directionalLight(_:_:_:color:)` 型 = P1)。「主対象 1 個 + オプションラベル」(`loadImage(_:cache:)`
    型 = P2)は Swift 慣行そのものとして維持。
  - **save 系 3 件(`saveStrings(_:_:)` / `saveJSON(_:_:pretty:)` / `saveTable(_:_:...)`)は維持**:
    p5.js に同名・同順の API(`saveStrings(list, filename)` / `saveJSON(json, filename)` /
    `saveTable(table, filename)`)が存在するため原則により **Processing 語彙と判定**され、位置引数を
    維持する。下層 `DataIO.saveJSON(_:toPath:)` とのラベル差は「Sketch 層 = Processing 互換 /
    内部層 = Swift 慣行」という二層の設計の正当な帰結であり、食い違いではない(起案時は是正候補と
    したが、2026-08-02 の原則確定により除外)。`createMergePass(_:_:blend:)` も 2 引数が対称なので維持。
  - **是正(P4 のみ)**: `dispatch(_ kernel:, threads:, _ configure:)` / `dispatch(_ kernel:, width:,
    height:, _ configure:)` の末尾クロージャ `_` に `configure:` ラベルを付与。metaphor 独自 API
    (Processing に対応物なし)のため Guidelines 準拠へ。trailing closure 呼び出しは不変のため実質非破壊。
  - **内部層の規範**: SketchContext 以下の新規・非転送 API は Guidelines 完全準拠(転送メソッドのみ
    Sketch 層のミラーを許容)。
- **Option B: 全 107 件を Swift API Design Guidelines へ準拠させる(却下)**
  - Cons: Processing 互換の中核(座標の位置引数)まで壊れる。工数・breaking とも過大で、原則に反する。
- **Option C: 現状維持(却下)** — Cons: 独自 API の冗長な `_`(dispatch)まで凍結される。

## Decision(2026-08-02 確定)

| # | 論点 | 推奨 | breaking |
|---|---|---|---|
| 0 | 原則 | 見える層(Sketch)= Processing 互換最大化 / 内部層 = 可能な限り Swift Guidelines(転送メソッドはミラー許容) | — |
| 1 | ON/OFF 4 系統 | 出自で規範化(rename なし)+ 対欠損の additive 補完 | なし |
| 2 | 記録 API | `begin<Media>Record` 統一: `beginSVG`→`beginSVGRecord`、無印→`beginFrameRecord`。OfflineRender は維持 | 4 件 |
| 3 | async 露出 | `*Async` サフィックス統一(オーバーロード 2 件を改名) | 2 件 |
| 4 | 二層 API | Sketch 層 = 正典・下位層名は自由。GPU `filter` を Sketch 層へ引き上げ | なし(追加のみ) |
| 5 | `@_exported` | 3 つとも維持・凍結宣言(doc + 安定性ポリシーに明記) | なし |
| 6 | Syphon 登録・内部 public | `internal`+`@_cdecl` 化(spike 再検証後)。「doc では内部」表面は internal/@_spi へ(個別表で確定) | なし(契約検証前提) |
| 7 | 引数ラベル | P1/P2 規範化維持。save 系は p5.js 語彙として維持。是正は dispatch 2 件のみ | 2 件(実質非破壊) |

rename の移行はすべて ADR-0005 Amendment の規約に従う: **deprecated エイリアスを含む minor を公開して
から、次の minor で削除**(0.8.x 内に 2 リリースを確保。v1-release-plan「順序を決める依存関係 4」)。

## Consequences

### Positive
- 新 API 追加時の命名判定が機械化され、凍結後のドリフトを規範で防げる。
- Processing の `beginRecord` との意味衝突という「凍結後に直せない混乱源」が解消する。
- breaking の総量が確定する: **rename 8 シグネチャ**(記録 4 + async 2 + dispatch ラベル 2。
  dispatch は trailing closure 呼び出しでは非破壊)+ 隠蔽系(利用者影響ゼロ見込み)。
  W1-3(#322)の作業範囲がこの表で固定される。

### Negative / Trade-offs
- `noLights` と `disableShadows` の見た目の不揃いは「出自の違い」として残る(doc で規則を示す)。
- `@_exported` の凍結により、将来 Swift が `@_exported` を廃止した場合の対応は major 送りになる。
- 0.8.x 内に deprecation → 削除の 2 リリースが必要になり、リリース刻みの制約が生じる。

### Follow-ups / 残課題
- ~~`modelX/Y/Z` の追加(Processing パリティ、additive)— 0.9.x でも可~~ → **[#814](https://github.com/shinyaoguri/metaphor/issues/814) で実施済み**。Processing の `modelX/Y/Z` は `cameraInv * modelview * point`(`modelview = camera * currentMatrix`)でカメラが打ち消し合い、実質 `currentMatrix * point` = **ワールド座標**を返す(カメラ非依存)。「`screenX/Y/Z` の逆変換」は p5.js の `screenToWorld()` の仕様で別物であり、そちらは別途起票した。
- save 系の `*Async` 追加(additive)— 0.9.x でも可
- `screenX`+`screenY` 連続呼び出しの二重変換の解消(実装最適化)
- `frameRate` getter(#273 と統合して判断)/ `SketchConfig.syphon`+`syphonName` 二重表現の doc 明記
- `update(deltaTime:)` の無意味引数(SubsystemBridge)の整理
- llms.txt 生成器が `public extension` ブロック記法(Sketch+Probe.swift 等 2 箇所)を取りこぼす件の検証

### 実装 Issue へのマッピング

- **#321(deprecated 7 件削除)**: **実施済み(PR #354、2026-08-01)**。起案時に挙げた追加 2 点
  (SketchContext 側 9 引数 `camera` / deprecation message の文言)は削除により消滅。
- **#322(命名統一実装)**: Decision 表 #1(対欠損補完)#2(記録 rename)#3(async rename)
  #4(filter 引き上げ)#7(dispatch ラベル是正)。deprecated エイリアス → 次 minor で削除の 2 段階。
  **両フェーズとも実施済み**: フェーズ 1 = 旧名のエイリアス化(PR #368、2026-08-01)、
  フェーズ 2 = 旧名 16 箇所の削除(2026-08-14)。フェーズ 2 の窓は
  `v0.9.0`(2026-08-10、deprecation を含む minor)の公開で充足した。ADR-0009 で API 凍結を
  撤回したため、削除は major ではなく **minor + Breaking Changes** で入っている。
- **#323(typed throws)**: 本 ADR の原則(下位層 = Swift 慣行)を前提にエラー型を設計。
- **#388(論点 6 の内部 public 隠蔽)**: **実施済み(2026-08-02)**。個別判定表の全文は
  [#388 のコメント](https://github.com/shinyaoguri/metaphor/issues/388)。結論だけ記すと:
  - `_metaphorSyphonRegister()` → `internal func metaphorSyphonRegister()`(`@_cdecl` は据え置き)。
    ADR-0001 と同じ 4 組合せ(debug/release × 同一パッケージ/クロスパッケージ)で自動登録と
    Syphon サーバー起動を再実測し、全て green。`nm` で見ると internal 化により C シンボルは
    release で private external になるが、bootstrap.c は同一リンク単位にあるため解決される。
  - `SyphonPlugin` / `MetaphorRenderer.onCaptureOutput` / `shadowDeferActive` / `onRecordFrame` /
    `onReplayMain` → `internal`(参照元はいずれも同一モジュール内 + `@testable` テストのみ)。
  - **`@_spi(MetaphorInternal)` は不採用**: 候補すべてが「同一モジュール + `@testable`」で足り、
    モジュール横断で必要なものが 1 件も無かった。Sources の `@_spi` 使用は引き続き 0 件。
  - `SketchContext.renderer` / `encoder` / `resourceLoader` / `assetCache` / `gifExporter` /
    `orbitCamera` は **public のまま維持**。doc が「エスケープハッチ(上級者向け)」と明記しており
    「doc では内部」に該当しない。`Examples/Samples/RayTracing` が `context.renderer` を実使用。
- **新規起票(ADR 確定後)**: Follow-ups の各項。`modelX/Y/Z` は [#814](https://github.com/shinyaoguri/metaphor/issues/814) として起票・実施済み。

## References

- 網羅調査全文: [#320 コメント](https://github.com/shinyaoguri/metaphor/issues/320#issuecomment-5150794440)(行番号つき全リスト・Examples 実測・シグネチャ露出件数)
- ADR-0005(Sketch 層規約・deprecation ウィンドウ)/ ADR-0001(Syphon 自動登録と `@_cdecl`)/ ADR-0003(コマンド記録の内部フック)
- [docs/design/v1-release-plan.md](../design/v1-release-plan.md)(G3, G16, W1-1, 依存関係 4)
- Swift API Design Guidelines / Processing・p5.js リファレンス(語彙判定の外部正典)
- Issue #320, #321, #322, #323, #273, #298
