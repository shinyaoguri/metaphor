# doc コメントの言語と書き方

公開 API の doc コメント（`///` と `/** */`）は**英語で書きます**。このページはその規約と、訳すときの語彙の決め方です。

コード中の通常コメント（`//`）と、Issue / PR / コミットメッセージは**日本語のままで構いません**。英語にするのは「利用者が読むもの」だけです。

## なぜ英語か

doc コメントは 3 つの生成物の入力になっていて、いずれも利用者向けの正典です。

| 生成物 | 何に使われるか |
|---|---|
| `llms.txt` | AI エージェント向けの API 正典（`make llms-txt` が doc コメントから生成） |
| DocC（`/reference/`） | 公開 API リファレンス |
| `/reference/ja/` | 上の日本語版。**英語版の render JSON に対訳台帳を当てて生成**（[ADR-0011](adr/0011-docc-english-canon-japanese-generated.md)） |

日本語版が英語版から生成される以上、**英語が上流**です。doc コメントを日本語で書くと、日本語版は出るものの英語版がその日本語のまま出てしまい、英語圏の利用者にも AI にも読めないものが正典になります。

## 対象と対象外

**対象**: `///` と `/** */` の doc コメント。public / internal を問いません。

**対象外**（触らない）:

- コード、識別子、パラメータ名
- 文字列リテラル
- `//` の通常コメント（`// MARK:` を含む）— 実装の意図を書いた日本語はそのまま残します
- **`<!-- reference-shot -->` 印より後ろ** — `make reference-shots` の生成物です。画像の alt テキストが日本語なのは生成器がそう書いているためで、手で直しても次の撮影で戻ります

## 書き方

### DocC の構造を保つ

1 行目のサマリ、`- Parameter(s):` / `- Returns:` / `- Note:` / `- Important:`、バッククォートのシンボル参照は形を変えずに訳します。

```swift
/// Draws a circle at the given position.
///
/// - Parameters:
///   - x: The center x coordinate.
///   - y: The center y coordinate.
///   - diameter: The diameter in pixels.
/// - Note: Affected by `fill()` and `stroke()`.
```

### 文体は 3 人称単数現在の断定形

Apple のドキュメントに合わせます。命令形（"Draw a circle"）ではなく "Draws a circle" です。

```swift
/// Transfers samples from the audio thread to the main thread.
/// Receives UDP OSC messages using Network.framework.
```

### 語彙は Processing / p5.js リファレンスに合わせる

利用者の多くが Processing / p5.js から来ます。同じものを別の語で呼ばないでください。

| 概念 | 使う語 | 使わない語 |
|---|---|---|
| スケッチ | sketch | program, app |
| 描画ループ | draw loop | render loop, main loop |
| フレーム | frame | tick |
| 既定値 | default | initial value |
| 後処理 | post-processing | post effect |
| 描画パス | render pass | drawing pass |

Apple のフレームワークに属する語（`MTLTexture`, actor, Sendable など）は Apple の言い方に従います。

### 内部性の注記は訳して残す

「内部出力プラグイン」「直接使用を意図しない」のような但し書きは、消さずに英語にします。読者が使ってよい API かどうかの判断材料です。

## 元の日本語は捨てない

英語化するとき、**元の日本語文は対訳台帳 `docs/reference/i18n/ja.json` の訳として移します**。台帳に訳が無い箇所は日本語版でも英語のまま出るため、移さないと `/reference/ja/` の読者にとっては退行になります。

```bash
make reference-i18n   # 未訳を書き出す
```

台帳のキーは英文の sha256、値は `{en, ja}` の対です。英文を書き換えるとキーが変わるので、**英語化と台帳の更新は同じ PR で**行ってください。

## 検査

`scripts/check-doc-comment-language.py` が `Sources/**/*.swift` の doc コメントに CJK が無いかを見ます。CI（`build-and-test`）と pre-push フックの両方が呼びます。

移行中は未英語化のファイルを allowlist に載せてあります。英語化を進めるたびに allowlist から削り、**空になったら allowlist ごと消します**（進捗は #334）。
