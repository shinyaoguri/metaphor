# ADR-0015: `.app` 配布は本体が実行時のファイル解決を、metaphor-cli が bundle の組み立てを担う

- **Status**: Accepted
- **Date**: 2026-08-24
- **Deciders**: @shinyaoguri
- **PR / Commit**: (この ADR を含む PR。実装は §Follow-ups の子 Issue が担う)

## Context

完成した作品を作者の Mac の外へ持ち出す導線は、[#573](https://github.com/shinyaoguri/metaphor/issues/573)
で 15 個の論点を抱えたまま検討 Issue に留まっていた。Epic L（[#416](https://github.com/shinyaoguri/metaphor/issues/416)・
現場運用束）が「`.app` 化は本 Epic の前提条件。#573 との責務分担を決めるのが先」と判定しているため、
この判断が出るまで常設運用が着手できない。

### 起票時から消えた論点

#573 の論点のうち 3 つは、起票後の別作業で前提ごと消えている。

- **カメラ・マイクの無言失敗**（[#685](https://github.com/shinyaoguri/metaphor/issues/685)・CLOSED）—
  TCC のダイアログは `Info.plist` を持つバンドルにしか出ない。**配布以前に、これらを使う作品は
  `swift run` では完成させられない**。権限状態は公開 API から読めるようになった
- **`.app` 起動で cwd が `/` になり `.metaphor/` が壊れる**（[#688](https://github.com/shinyaoguri/metaphor/issues/688)・CLOSED）—
  `METAPHOR_STATE_DIR` として [CONTRACT.md](../../CONTRACT.md) の契約点 2 / 4 / 7 / 8 に着地済み
- **Syphon framework を常時同梱するか**（[ADR-0014](0014-viewer-frame-ipc-and-syphon-plugin.md)）—
  root `Package.swift` から binaryTarget が消え、Syphon は独立パッケージのオプトインになった。
  使わない作品には framework 自体が存在しない

### 決定を強制した実測 — 現在の `.app` は他の Mac では起動しない

[#414](https://github.com/shinyaoguri/metaphor/issues/414) のリファレンス作品（`0815-strata`）は
手書きの `make-app.sh` で `.app` に包まれ、SwiftPM のリソースバンドルを `Contents/MacOS/` へ置いている。
ところが SwiftPM が生成する `Bundle.module` アクセサ
（`.build/…/MetaphorCore.build/DerivedSources/resource_bundle_accessor.swift`）の実物はこうなっている。

```swift
let mainPath = Bundle.main.bundleURL.appendingPathComponent("metaphor_MetaphorCore.bundle").path
let buildPath = "/…/0815-strata/.build/arm64-apple-macosx/release/metaphor_MetaphorCore.bundle"

let preferredBundle = Bundle(path: mainPath)
guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
    Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
}
```

`.app` 起動では `Bundle.main.bundleURL` が **`.app` 自身**になるため、`mainPath` は
`strata.app/metaphor_MetaphorCore.bundle`（`Contents/` の隣）を指す。`Contents/MacOS/` へ置いた
バンドルは**一度も見られていない**。実際に効いているのは第 2 候補の **`buildPath` = 作者の `.build` の
絶対パス**で、作者の Mac だから偶然存在しているだけである。

`MetaphorCore` はシェーダーソース 228K をリソースバンドルで持つ（[Package.swift](../../Package.swift) の
`.copy("Shaders/Metal")` / `.copy("Shaders/ShaderSources")`、読み出しは
[`ShaderLibrary.loadShaderSource`](../../Sources/MetaphorCore/Core/ShaderLibrary.swift) と
`makeDefaultLibrary(bundle: Bundle.module)`）ので、これは Syphon やカメラを使うかに関係なく**全作品に効く**。
渡した先では `fatalError("could not load resource bundle")` で即死する。

同じ穴は作品自身のアセットにもある。`loadFont` / `loadImage` の doc コメントは
`Bundle.module.path(forResource:…)` を勧めており（[`Sketch+Image.swift`](../../Sources/MetaphorCore/Sketch/Sketch+Image.swift)）、
これも `.app` では同じ経路で作者の `.build` に落ちる。

つまり #573 本文が懸念していた「**作者の環境では偶然見つかるものに依存しない**」は、
**すでに破れている**。そして SwiftPM が期待する置き場（`.app` 直下のフラットな `*.bundle`）は
`codesign` が扱えないレイアウトなので、そこへ合わせにいくと Developer ID / notarization への道が閉じる。

### 制約

- **`swift run` の経路を変えない**（#573 の非目標）。開発中の解決は今までどおり動くこと
- **SwiftPM のアクセサ実装に従属しない**。`Bundle.module` の探索順はツールチェーンが決めるもので、
  更新で無言に変わりうる
- **Level 3（Developer ID / notarization）への道を閉じない**
- metaphor と metaphor-cli は別リポジトリで、結合は CONTRACT.md の契約点だけ

## Considered Options

### Option A: 本体が実行時のファイル解決を、cli が bundle の組み立てを担う

`MetaphorCore` は `Bundle.module` への依存をやめ、`.app` の中では `Contents/Resources/` を先に見る
薄いルックアップに置き換える（見つからなければ従来どおり `Bundle.module` へフォールバック）。
作品アセットの相対パス解決も同じ規則に載せる。metaphor-cli は `metaphor bundle` で Release build →
`.app` 生成 → リソース / framework の配置 → `Info.plist` / manifest 生成 → ad-hoc 署名 → 検査を行う。

- Pros: `.app` が**署名できるレイアウト**（`Contents/Resources/`）になり Level 3 まで道が続く。
  解決規則が metaphor 自身の管理下に入り、ツールチェーンの都合で無言に壊れない。
  組み立ては誰がやっても同じ機械作業なので cli 側に置くと `new` / `run` / `watch` の導線に載る
- Cons: 本体側に小さな実装が要る（`Bundle.module` 参照の置き換えと、その回帰テスト）

### Option B: 全部 metaphor-cli 側で解決する（本体は無変更）

cli が SwiftPM アクセサの探索先に合わせ、`.app` **直下**へリソースバンドルを置く。

- Pros: 本体の変更がゼロ。最短で Level 1 / 2 に到達する
- Cons: `.app` 直下のフラットな `*.bundle` は `codesign` が扱えない（`make-app.sh` が実際に
  `bundle format unrecognized` を踏んでいる）ため **Level 3 が閉じる**。SwiftPM の生成コードという
  非公開の実装詳細に恒久的に従属し、ツールチェーン更新で無言に壊れる。
  作品側が直接書く `Bundle.module` は cli からは手当てできない

### Option C: 本体が SwiftPM command plugin で `.app` まで作る

`swift package bundle` で完結させ、metaphor-cli を経由しない。

- Pros: 作品リポジトリだけで閉じる。cli を入れていない利用者にも届く
- Cons: 署名・notarization の orchestration を plugin サンドボックス内で行うことになり、
  ネットワークとキーチェーンの制約に当たる。`metaphor new` / `run` / `watch` という既存の導線から
  外れ、CLI 側にすでにある Release build / バイナリ解決（`SketchBinaryResolver`）を二重に持つ

## Decision

**Option A** を採る。境界は「**`.app` の中でファイルが見つかること = 本体**」「**`.app` を組み立てること = cli**」。

決め手は 2 つ。(1) 実測のとおり `.app` 内の解決はすでに壊れており、これは cli が外から直せない
**ランタイムの振る舞い**である。(2) 署名できるレイアウト（`Contents/Resources/`）を選べるのは
解決規則を自分で持つ Option A だけで、B は Level 3 を閉じてしまう。

あわせて**最初に保証する範囲を Level 1 + 2**（別の Apple Silicon Mac で起動する ad-hoc 署名 bundle）とし、
**コマンド名を `metaphor bundle`**（`--check` / `--verify` を持つ）に決める。この 2 つは責務分担と
独立した判断ではなく、「どこまでを本体 / cli のどちらが保証するか」の範囲指定なので同じ ADR に含める
（README の「1 ADR = 1 判断」に対する明示的な例外）。

## Consequences

### #573 の 15 論点の決着

| # | 論点 | 決着 |
|---|---|---|
| 1 | 最初に保証する配布レベル | **Level 1 + 2**（transferable / ad-hoc 署名）。Level 3 は後段 |
| 2 | コマンド名 | **`metaphor bundle`**（`--check` / `--verify`） |
| 3 | SwiftPM Resources と明示 manifest | **SwiftPM Resources が正典**。明示 include は追加のみで、Level 1+2 では manifest を持たない。自動検出は warning に留め、黙って欠落させない |
| 4 | 設定の置き場 | 実行時設定（`SketchConfig`）と**分離**し、プロジェクト直下の独立ファイルへ。`Package.swift` には置かない（SwiftPM に非標準キーを持ち込めない）。ファイル名とスキーマは cli 側 Issue で確定 |
| 5 | icon / bundle ID / version の既定値 | 既定値を持ち、弱い既定（仮の bundle ID など）は `--check` が警告する。値は cli 側 Issue で確定 |
| 6 | usage description / entitlement | **明示設定が正典**（source scan で推測しない）。本体が capability 情報を出し、`--check` が「使っているのに文言が無い」を警告する |
| 7 | Syphon の同梱・optional 化 | **論点消滅**（ADR-0014）。既定同梱はせず、依存する作品だけ `Contents/Frameworks/` へ入れて rpath を直す |
| 8 | unsigned / ad-hoc の説明 | Level 2 は ad-hoc 固定。Gatekeeper / quarantine の挙動を bundle 完了時に出力し、docs にも書く |
| 9 | Developer ID / notarization の credential | Level 3 へ送る。「credential をプロジェクトにもログにも保存しない」原則だけ先に固定する |
| 10 | clean machine の検証環境 | 別 Mac を用意する前に**静的検査 + クリーンルーム起動 smoke**（`.build` を退避して起動）で捕まえる。本 ADR の実測はこれで検出できる |
| 11 | asset license / third-party notice | Level 2 では必須にしない。Level 3 で扱う |
| 12 | Take（[#570](https://github.com/shinyaoguri/metaphor/issues/570)）の provenance | manifest には `sourceRevision` だけ。未決の #570 には依存させない |
| 13 | #416 の kiosk / watchdog との境界 | `metaphor bundle` は `.app` を作るまで。launchd / ログイン項目 / 自動復帰は #416（Level 4） |
| 14 | クロスリポ契約が必要か | **不要**。ランタイム契約点は増えない（cli は Package から機械的に組み立てるだけ） |
| 15 | bundle format を公開契約とするか | **cli の実装詳細**。ただし「`.app` 内での resource 解決規則」は本体の公開仕様として `docs/` に規定する（CONTRACT.md には載せない） |

### Positive

- `.app` が署名できるレイアウトになり、Level 3（Developer ID / notarization）への道が開いたまま残る
- リソース解決が metaphor の管理下に入り、SwiftPM のツールチェーン更新で無言に壊れなくなる
- #416（常設運用）の前提条件が外れ、Epic L が着手可能になる
- `swift run` の経路は変わらない（フォールバックとして `Bundle.module` を残すため）

### Negative / Trade-offs

- 本体に「バンドル内の置き場」という知識が入る。純粋な描画ランタイムからは少し外れる
- 作品が直接 `Bundle.module` を書いている場合は救えない。doc コメントの是正と移行案内が要る
- `.app` を作らないと再現しない不具合が増えるので、クリーンルーム smoke を CI かローカル検査で
  回さないと退行に気付けない

### Follow-ups / 残課題

実装は以下の子 Issue が担う（依存順: [#1107](https://github.com/shinyaoguri/metaphor/issues/1107) →
[cli#191](https://github.com/shinyaoguri/metaphor-cli/issues/191)、
[cli#190](https://github.com/shinyaoguri/metaphor-cli/issues/190) は #1107 と並行可、
[#1109](https://github.com/shinyaoguri/metaphor/issues/1109) は `--check` / `--verify` の警告機能の前提）。

- [**#1107**](https://github.com/shinyaoguri/metaphor/issues/1107)（metaphor・Level 2 のブロッカー）—
  `.app` 内で resource bundle が解決できず、ビルドした Mac の `.build` 絶対パスへフォールバックする問題を直す
- [**#1108**](https://github.com/shinyaoguri/metaphor/issues/1108)（metaphor）— 作品アセットのパス解決を
  `.app` でも成立させ、`Bundle.module` を勧めている doc コメントを是正する
- [**#1109**](https://github.com/shinyaoguri/metaphor/issues/1109)（metaphor）— 配布 bundle 向けの
  capability 情報と起動時の構造化診断を出す
- [**cli#190**](https://github.com/shinyaoguri/metaphor-cli/issues/190)（metaphor-cli）— `metaphor bundle` で
  `.app` を組み立てる（Level 1）
- [**cli#191**](https://github.com/shinyaoguri/metaphor-cli/issues/191)（metaphor-cli）—
  `metaphor bundle --verify` で別 Mac 起動可能性を検査する（Level 2）

未決のまま残すもの: app metadata ファイルの名前・スキーマ（D で確定）、Level 3 の CI 署名経路、
Level 4（キオスク / 常設）は #416 の担当範囲。

## References

- [#573](https://github.com/shinyaoguri/metaphor/issues/573) — 本 ADR の元になった検討 Issue
- [#416](https://github.com/shinyaoguri/metaphor/issues/416) — Epic L（現場運用束）。本判断の下流
- [#414](https://github.com/shinyaoguri/metaphor/issues/414) — 作品駆動検証。実測の出どころ
- [#685](https://github.com/shinyaoguri/metaphor/issues/685) / [#688](https://github.com/shinyaoguri/metaphor/issues/688) — 起票時の前提を変えた 2 件
- [ADR-0014](0014-viewer-frame-ipc-and-syphon-plugin.md) — Syphon 同梱論点を消した判断
- [docs/design/app-bundle-distribution.md](../design/app-bundle-distribution.md) — 段階・レイアウト・検査項目
- [docs/permissions.md](../permissions.md) — TCC と `Info.plist` の既存ドキュメント
- [`Sources/MetaphorCore/Core/ShaderLibrary.swift`](../../Sources/MetaphorCore/Core/ShaderLibrary.swift) — `Bundle.module` の読み出し箇所
