# API リファレンスの実行結果画像

DocC が出す API リファレンスの各ページに、**そのシンボルだけを使う短いコードと、その
実行結果**を載せるための規約です（[Issue #531](https://github.com/shinyaoguri/metaphor/issues/531)）。
目標は p5.js の [reference](https://p5js.org/reference) — 個別のメソッドごとに絵がある状態。

- 画像の置き場は Gyazo の外部 URL（リポジトリにコミットしない）: [ADR-0008](../adr/0008-docc-reference-images-via-gyazo.md)
- チュートリアル `docs/tutorial/` の規約は別物です（リポジトリ内・アニメーション WebP）:
  [ADR-0010](../adr/0010-tutorial-images-via-gyazo.md) と [docs/tutorial/README.md](../tutorial/README.md)

## 書き方

doc コメントの中に、`draw()` の本体としてそのまま動く**自己完結したコード**を書き、
`<!-- reference-shot -->` の印を付けます。

```swift
/// 円を描画します。
///
/// - Parameters:
///   - x: 中心の x 座標。
///   …
///
/// ### 実行結果
///
/// <!-- reference-shot -->
///
/// ```swift
/// background(24)
/// fill(80, 170, 255)
/// noStroke()
/// circle(width / 2, height / 2, 200)
/// ```
public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
```

`make reference-shots` を走らせると、**印から下**が実行結果込みの形に組み立て直されます。

```swift
/// ### 実行結果
///
/// <!-- reference-shot -->
///
/// @Row {
///    @Column(size: 1) {
///       ![circle(_:_:_:) の実行結果](https://i.gyazo.com/<hash>.png)
///    }
///    @Column(size: 2) {
///       ```swift
///       background(24)
///       fill(80, 170, 255)
///       noStroke()
///       circle(width / 2, height / 2, 200)
///       ```
///    }
/// }
```

- **コードは人が書く（正典）。それ以外は生成物**で、手で書いたり消したりしません
- **印から doc コメントの終わりまでが生成物領域**です。説明は印より**前**に書きます
  （後ろに書くと書き戻しで消えるため、スクリプトが検出してエラーにします）
- 背景も**スニペット自身が塗ります**。外部 URL ではダーク/Retina の出し分け
  （`~dark` / `@2x`）が効かないため、配色はスケッチ側で固定します（ADR-0008 の Negative）
- 印が HTML コメントなのは、DocC が**警告なく落とす**ため。読者には見えず、機械には
  引っかかり、見出しの文言（英語化・#334）にも依存しません
- 説明のためだけの ```swift フェンス（`Sources/` に既に 30 箇所ほどある）は印を付けません。
  印の有無が「撮る例」と「読ませるだけの例」の区別です
- スニペットは短く。1 シンボルの意味が伝わる最小限にします（p5.js の例と同じ考え方）
- **横並びのコードは 1 行 38 文字まで**（下記）

## 並べ方（レイアウト）

既定は p5.js の reference と同じ **「絵が左・コードが右」の横並び**（`@Row` / `@Column`。
幅の比は 1:2）。DocC は 735px 以下で自動的に縦へ折ります。

`shots.config.json` に `"layout": "stack"` を書くと、コードを上・絵を下の**全幅**に切り替え
られます。横長の絵や、行が長くて列に収まらないコードはこちらへ。

### なぜ 1 行 38 文字までなのか

Swift-DocC-Render のコードブロックは**折り返しも内部スクロールもせず、行の長さぶんに広がって
列からはみ出します**（`@Row` の外でも同じなので DocC 側の性質）。はみ出したぶんはページ側でも
切り落とされ、読めなくなります。一番狭くなるのは「DocC がまだ縦に折らないギリギリの幅」で、
実測するとこうなります:

| 測ったもの | 値 |
|---|---|
| 列が縦に折れる幅 | 735px 以下（`.row.with-columns` のメディアクエリ） |
| 736px のときの本文幅 / コード列 | 576px / 約 371px |
| 等幅フォント 1 文字 | 9.03px |
| コードブロックの padding | 左右 14px ずつ |

`(371 - 28) / 9.03 ≒ 38`。超えると `make reference-shots` がエラーで止まり、短く書き直すか
`layout: "stack"` へ逃がすよう促します。

### 動きがあるとき

本文に出るのは **GIF だけ**です（静止画も撮って台帳には残しますが、同じ絵を 2 枚並べても
情報が増えず、列が縦に伸びるだけなので）。

### どのシンボルに載せるか

`Sketch+*.swift` の公開関数は 250 本を超えるので、全部には付けません。**絵が無いと
分からないもの**から順に付けます。

1. 2D 図形とスタイル（`circle` / `arc` / `bezier` / `rectMode` / `strokeWeight` / `blendMode` …）
2. 変換（`translate` / `rotate` / `shearX`）と 3D プリミティブ・ライティング
3. 動きでしか分からないもの（イージング・パーティクル・`noise()`）

## 撮る

```bash
make reference-shots                                  # 画像がまだ無いものを撮る
make reference-shots ARGS="--only circle"             # 絞る
make reference-shots ARGS="--force --only circle"     # 撮り直す
make reference-shots ARGS="--list"                    # 撮影対象を並べる
```

撮影には GPU と Gyazo のトークン（1Password）が要るので**ローカル専用**です。CI が見るのは
次の 2 つ:

| 検査 | いつ | 何を見るか |
|---|---|---|
| `--check` | per-PR | スニペットを変えたのに撮り直していない／本文の URL が台帳とずれている |
| `--compile-only` | per-PR（Sources 変更時） | **doc コメントの例が実際にコンパイルできる** |
| `scripts/check-image-urls.py` | 週次（`asset-health.yml`） | Gyazo の URL が生きている |

画像そのものは比較しません（GPU の出力は環境でビット単位に一致しないため）。鮮度は
台帳 `images/manifest.json` の `snippetHash`（スニペット + 撮影設定の指紋）で見ます。

### 撮影設定

既定は 480x360 の静止画。変えるときだけ [`shots.config.json`](shots.config.json) に書きます
（台帳は生成物なので、手書きの設定とは分けます）。

```json
{
  "shots": {
    "Sources/MetaphorCore/Sketch/Sketch+Shapes.swift::rotate(_:)": {
      "motion": { "frames": 36, "every": 2, "fps": 15 }
    }
  }
}
```

- `width` / `height` — キャンバスの大きさ
- `settle` — 動くスケッチで、絵が出来上がるのを待つ秒数
- `layout` — `row`（既定・横並び）か `stack`（縦積み）
- `motion` — **GIF** を撮る（本文に出るのは GIF だけ）。DocC は WebP を無言で落とすので、
  動きを見せる手段は GIF だけです（ADR-0008）。GIF は静止画より 1 桁重いので、
  **1 フレームでは意味が分からないシンボルにだけ**付けます

`motion` を付けたスニペットは `noLoop()` されません（＝ `frameCount` で動かせます）。

## 仕組み

`scripts/generate-reference-shots.py` が次を順に行います。

1. `Sources/**/*.swift` の doc コメントから、印の付いたフェンスを集める
2. `.build/reference-shots/` に SwiftPM パッケージを 1 個生成し、**スニペット 1 本 =
   実行ターゲット 1 個**として並べて `swift build`（1 回で全部コンパイルされる）
3. `METAPHOR_PROBE=1 METAPHOR_VIEWER=1` でヘッドレス実行し、Probe の
   `.metaphor/probe/current/frame.png` を取る（動きは連続キャプチャ → ffmpeg で GIF）
4. Gyazo へ上げ、台帳 `images/manifest.json` と doc コメントの画像行へ書き戻す

アセットは**不変・追記型**です。撮り直しは既存 URL の差し替えではなく新規アップロードで、
古い URL は消しません（過去のリビジョンを開けば当時の絵が出ます）。

書き戻しは URL の文字列一致ではなく**フェンスの位置**で対応づけるので、初回・撮り直し・
途中で中断したあとの再実行が、すべて同じべき等な操作になります。
