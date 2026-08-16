# ADR-0011: リファレンスは英語を正典とし、日本語版は機械翻訳の生成物として並べる

- **Status**: Accepted
- **Date**: 2026-08-16
- **Deciders**: @shinyaoguri
- **PR / Commit**: (この ADR を含む PR)

## Context

DocC は日本語で書かれてきた。一方 [#334](https://github.com/shinyaoguri/metaphor/issues/334)（Epic [#314](https://github.com/shinyaoguri/metaphor/issues/314) / W3-1）は
「公開 API の doc コメントを英語化する」と決めており、周辺 11 モジュールは完了済み
（PR #361 / #365）。残るのは MetaphorCore（`///` 11,548 行のうち 8,454 行が日本語）と
umbrella、`.docc` 記事 14 本。

この英語化は**日本語の原文を上書きする不可逆な作業**なので、着手前に「日本語のリファレンス
を出すのか、出すならどう作るのか」を決めておく必要がある。決めないまま進めると、後から
日本語版が欲しくなったときに復元できるのは git 履歴だけになる。

### 外部の制約（調べて分かったこと）

- **Swift-DocC は authoring localization を持たない**。[swiftlang/swift-docc#648](https://github.com/swiftlang/swift-docc/issues/648) は
  2023-06 起票のまま open、ラベルは `needs forum discussion` で PR も assignee も無い。
  1 つのカタログに日英を入れて言語トグルを出すことはできない。`swift-docc-render` の
  `src/lang` は UI ラベル（"Overview" 等）の i18n であって本文の多言語対応ではない
- **p5.js も機械翻訳ではない**。本家 reference は言語別ディレクトリ（`en` / `es` / `hi` /
  `ko` / `zh-Hans`）を持つ人手のコミュニティ翻訳で、**日本語は本家に入っていない**
  （別プロジェクトが非公式に運用している）。「p5.js のようにドロップダウンで切り替える」の
  実体は翻訳エンジンではなく、翻訳された Markdown 群だった
- **Google 翻訳ウィジェットの埋め込みは使えない**。2019 年に新規提供が終了し、いまは政府・
  非営利・学術に限定されている。「貼るだけ」の解は存在しない
- **DocC のカスタマイズで使えるのは `header.html` / `footer.html`**。Swift Forums で
  提案されていた `custom-scripts.json` は swift-docc に実装が無い。実装済みなのは
  `--experimental-enable-custom-templates` を付けたときにカタログ直下の `header.html` を
  `index.html` の `<template id="custom-header">` へ注入する経路で
  （`ConvertFileWritingConsumer.swift`）、DocC-Render がこれを Shadow DOM へ clone する

## Considered Options

### Option A: 英語一本にし、日本語のリファレンスは出さない
- Pros: 維持が 1 系統。`llms.txt` が生成物として自動追随するので AI 向け正典も同時に揃う。
  DocC の制約と一切衝突しない
- Cons: 日本語話者が API の説明を日本語で引けない。日本語ファーストのチュートリアル
  （Epic [#483](https://github.com/shinyaoguri/metaphor/issues/483)）から地続きで来た読者が、リファレンスに入った瞬間に英語だけになる

### Option B: 英語を正典とし、日本語版を機械翻訳の生成物として別アーカイブで出す（採用）
- Pros: ソースは英語 1 本のままで正典が二重化しない。日本語版は画像（[ADR-0008](0008-docc-reference-images-via-gyazo.md)）や
  `llms.txt` と同じ「手で書かない・いつでも再生成できる」生成物として既存の運用に乗る。
  訳が無い箇所は英語のまま残せるので、#334 の英語化が段階的に進む移行期でも破綻しない
- Cons: 訳の品質は機械翻訳相当。英語原文が変わると訳が古くなるので鮮度の検査が要る。
  DocC の UI ラベルは英語のまま残る

### Option C: 人手の対訳を維持する（p5.js 型）
- Pros: 品質は最も高い。用語を作品・チュートリアルと完全に揃えられる
- Cons: 対訳の維持が本質的に重い。p5.js ですら日本語は本家に入っていない（コミュニティの
  規模があってなお維持できていない）。bus factor 1 のプロジェクトで選ぶ形ではない

### Option D: DocC 公式の i18n を待つ
- Pros: いつか来れば最も素直な形になる
- Cons: #648 は 3 年動いていない。待機は方針にならない

## Decision

**B を採る。** 英語の doc コメントを正典とし、日本語リファレンスは
`docs/reference/i18n/ja.json`（対訳台帳）を当てて生成し、`/reference/ja/` へ英語版と
同じ構造で並べる。決め手は「日本語話者を切り捨てずに、正典を二重化しない」ことと、
リポジトリが既に持っている生成物の運用（`make reference-shots` / `make tutorial-shots`）に
そのまま乗ることの 2 点。

## Consequences

### 翻訳を当てる層は render JSON

`docc convert` の出力 `data/documentation/**/*.json` を訳す。symbol graph の `docComment`
（DocC がパースする前の生テキスト）を訳す案もあったが、`- Parameter x:` のような構文を
翻訳が壊すとパラメータ表が丸ごと消える。render JSON は DocC がパースした後なので、宣言・
パラメータ表・コードブロック（`codeListing`）・[#531](https://github.com/shinyaoguri/metaphor/issues/531) の画像は別のノード型として分かれており、
**壊しようがないことをコードで保証できる**。

### 翻訳の単位は「テキストノード」ではなく「インライン列」

DocC は 1 つの文を型の違うノードへ刻む。`Sets the fill color.` は
`[text("Sets the "), codeVoice("fill"), text(" color.")]` になる。テキストノード単位で
訳すと `" and "` `" is "` のような切れ端が単独で翻訳器へ渡り、日本語として繋がらない
（実装中に実測したところ、英語化済みモジュールだけで 77 件の断片が出た）。そこで
`abstract` / `inlineContent` をまとめて 1 単位にし、テキスト以外をプレースホルダ
（`⟦0⟧`）へ退避してから訳し、訳文を割り戻して元の位置へ差し込む。プレースホルダが訳文
から失われていたら**その段落は訳を捨てて原文を残す**。

### 言語切替はページ内では完結しない

`<template>` の中の `<script>` は clone されても実行されない（HTML の仕様）。しかも
Shadow DOM に入った script はコードがテキストとして見えてしまう。したがって「いま見ている
ページの相手言語」へ飛ばすことはできず、`header.html` は言語ごとに静的なものを用意し、
**リンク先は各言語のトップ**になる。カタログが読むヘッダーは 1 本きりなので、
`make docs-ja` はカタログを複製して `docs/reference/i18n/header.ja.html` と差し替える。

複製先のディレクトリ名は `metaphor.docc` のまま保つ。**カタログのディレクトリ名が
ドキュメントのルート名になる**ため、`metaphor-ja.docc` にすると日本語版だけ
`/ja/documentation/metaphor-ja/` に出て、言語切替の前提であるパスの 1:1 対応が壊れる
（実装中に踏んだ）。

### Positive

- 日本語話者がリファレンスを日本語で引ける。website の言語（`defaultLocale: 'ja'`）と
  リファレンスの入口が揃う
- 正典は英語 1 本。#334 をそのまま完遂でき、`llms.txt` も追随する
- 訳が無い箇所は英語のまま出るので、移行期にどの状態でも壊れない。#334 が Core を英語化
  するほど日本語版の網羅も自動的に広がる

### Negative / Trade-offs

- **訳の品質は機械翻訳相当**で、人手の校正はしない。読者には日本語版のヘッダーで
  「この日本語版は英語のリファレンスからの機械翻訳です」と明示し、English への導線を常に
  出す
- **DocC の UI ラベル（Overview / Topics / View symbol / Language: Swift）は英語のまま**。
  DocC-Render の言語は選べない
- **同じページのまま言語を切り替えることはできない**（上記の script 制約）
- 英語原文が変われば訳は古くなる。`--check` が未訳を数え、公開ワークフローの Summary へ
  出す。**公開は止めない**（英語のまま出るので実害が無く、#334 が Core を英語化した直後は
  必ず未訳が増えるため）
- `--experimental-enable-custom-templates` は experimental なので、DocC の更新で
  `header.html` の扱いが変わる可能性がある。壊れても日本語版そのものは出続ける
  （失われるのは言語切替のリンクだけ）

### Follow-ups / 残課題

- #334 の残り（MetaphorCore 8,454 行 / umbrella / `.docc` 記事 14 本）。ここが英語化される
  ほど日本語版の網羅が広がる
- `theme-settings.json` に書かれている `features.docs.i18n.enable` は DocC の公式
  ドキュメントに無いフラグで、効いていない（[#529](https://github.com/shinyaoguri/metaphor/issues/529) と同じ「書いてあるが無言で効かない」状態）。
  DocC の UI 改善とあわせて別 Issue
- 英語版チュートリアル（[#548](https://github.com/shinyaoguri/metaphor/issues/548)）は本 ADR のスコープ外。チュートリアルは日本語ファーストの
  ままで、リファレンスとは方向が逆であることに注意（本文が正典なので機械翻訳では出さない）

## References

- `scripts/translate-reference.py` — 抽出・台帳・適用・鮮度検査
- `docs/reference/i18n/ja.json` — 対訳台帳（生成物）
- `docs/reference/i18n/header.ja.html` / `Sources/metaphor/metaphor.docc/header.html`
- `Makefile` の `docs` / `docs-ja` / `reference-i18n`
- [ADR-0008](0008-docc-reference-images-via-gyazo.md) — DocC の画像を外部 URL で参照する（生成物の扱いの先例）
- [ADR-0010](0010-tutorial-images-via-gyazo.md) — チュートリアルの画像と台帳
- [swiftlang/swift-docc#648](https://github.com/swiftlang/swift-docc/issues/648) — Internationalization support（open）
- [p5.js-website の reference](https://github.com/processing/p5.js-website/tree/main/src/content/reference) — 言語別ディレクトリと人手翻訳
