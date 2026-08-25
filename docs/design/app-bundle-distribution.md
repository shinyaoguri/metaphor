# 設計: 完成作品を自己完結した macOS App bundle として配布する

- **ステータス**: **責務分担・保証範囲・コマンド名は確定（[ADR-0015](../adr/0015-app-bundle-runtime-resolution-vs-assembly.md)）。実装は未着手** — Level 1 / 2 の子 Issue が担う。確定仕様は実装と ADR が正
- **親**: [#573](https://github.com/shinyaoguri/metaphor/issues/573)（検討 Issue・決着済み）/ [roadmap-processing-unity.md](roadmap-processing-unity.md) の Epic L
- **作成**: 2026-08-24

## この文書の役割

[ADR-0015](../adr/0015-app-bundle-runtime-resolution-vs-assembly.md) が「なぜこの分担なのか」を持ち、
本書が「**どう作るか**」を持つ。段階の定義、`.app` のレイアウト、含める / 除外するもの、検査項目、
検証手順が対象。コマンドのオプション名やファイル名など、実装 PR で確定するものは叩き台として書く。

## 前提 — なぜ `.app` が要るのか

配布の前に、**制作の途中で `.app` が必要になる**。

- **カメラ・マイクを使う作品は `swift run` では完成させられない**。TCC のダイアログは `Info.plist` に
  用途文言を持つバンドルにしか出ない（[#685](https://github.com/shinyaoguri/metaphor/issues/685)・
  既存の英語ドキュメントは [docs/permissions.md](../permissions.md)）
- 常設運用（Dock / ログイン項目 / クラッシュ後の自動復帰）はいずれも `.app` 前提
  （[#416](https://github.com/shinyaoguri/metaphor/issues/416)）

つまり `metaphor bundle` は「配布したい人だけの機能」ではなく、**入力を使う作品と常設作品の
制作導線そのもの**である。

## 段階と完了条件

| Level | 何ができる | 完了条件 |
|---|---|---|
| **1. Local App Bundle** | 同じ Mac で `.app` として起動できる | `Info.plist`（用途文言を含む）/ 実行ファイル / リソース / icon / 表示名を持ち、`open` で起動して描画する。TCC ダイアログが出る |
| **2. Transferable Bundle** | 互換条件を満たす**別の** Apple Silicon Mac で起動できる | 絶対パス依存ゼロ・ランタイム依存を同梱・リソースが bundle 内で解決・ad-hoc 署名・quarantine 時の挙動を説明済み。**クリーンルーム smoke が通る** |
| **3. Developer ID Distribution** | 作者の証明書で配布できる | hardened runtime / entitlements / nested code の署名順序 / notarize + staple / credential を残さない署名経路 |
| **4. Installation / Kiosk** | 常設向けの運用成果物 | **本書の対象外**。[#416](https://github.com/shinyaoguri/metaphor/issues/416) が担う |

**最初に保証するのは Level 1 + 2**（ADR-0015）。Level 3 は道を閉じないことだけを条件にする。

## `.app` のレイアウト

```text
MyArtwork.app/
  Contents/
    Info.plist                  ← 生成（識別子・バージョン・用途文言・最小 OS）
    MacOS/
      MyArtwork                 ← Release ビルドの実行ファイル
    Resources/
      metaphor_MetaphorCore.bundle    ← 本体のシェーダーリソース
      MyArtwork_MyArtwork.bundle      ← 作品自身の Resources/ ・Presets/
      AppIcon.icns              ← 任意
      metaphor-manifest.json    ← 生成（下記）
    Frameworks/
      Syphon.framework          ← 依存する作品だけ。rpath を張り替える
```

### なぜ `Contents/Resources/` なのか

SwiftPM が生成する `Bundle.module` アクセサは `Bundle.main.bundleURL/<name>.bundle`（= `.app` **直下**）を
見て、無ければ**ビルドした Mac の `.build` 絶対パス**へフォールバックする（実物のコードは
[ADR-0015](../adr/0015-app-bundle-runtime-resolution-vs-assembly.md) に引用）。`.app` 直下のフラットな
`*.bundle` は `codesign` が扱えないため、そこへ合わせると Level 3 が閉じる。

したがって**本体側が解決規則を持ち**、`.app` の中では `Contents/Resources/` を先に見る。
`swift run` では従来どおり `Bundle.module` へフォールバックするので、開発中の経路は変わらない。

> この解決規則は metaphor の**公開仕様**として扱うが、CONTRACT.md の契約点にはしない。
> metaphor-cli は「そこに置く」だけで、ランタイムの結合が増えるわけではない（ADR-0015 論点 14 / 15）。

## bundle に含めるもの / 既定で除外するもの

**含める**: Release 実行ファイル / 本体と作品の SwiftPM リソースバンドル / 依存する dynamic framework /
`Info.plist` / app icon / 用途文言 / runtime manifest。

**既定で除外する**: `.git/` / `.build/` 全体 / `.metaphor/`（Probe の一時 evidence・パラメータの作業状態）/
ソースファイル / ビルドログ / AI・MCP の資格情報 / 署名の資格情報 / 開発機に固有の絶対パス。

アセット収集の正典は **SwiftPM の `resources:` 宣言**（[#645](https://github.com/shinyaoguri/metaphor/issues/645)
の「宣言されていないと読めない」と同じ規律）。明示 include は追加のみで、動的に組み立てられたパスの
自動検出は行わない — 見つからないものは**黙って落とさず警告する**。

## runtime manifest（叩き台）

`Contents/Resources/metaphor-manifest.json`。起動不能時に「何をどう bundle したか」を後から読むためのもの。

```json
{
  "metaphorVersion": "0.x.y",
  "cliVersion": "0.x.y",
  "buildConfiguration": "release",
  "architecture": ["arm64"],
  "minimumMacOS": "14.0",
  "resources": ["…"],
  "frameworks": ["…"],
  "permissions": ["camera", "microphone"],
  "sourceRevision": "…",
  "createdAt": "…"
}
```

制作時の一時状態（Take・[#570](https://github.com/shinyaoguri/metaphor/issues/570)）は含めない。
provenance は `sourceRevision` までに留める。

## コマンド（叩き台）

```text
metaphor bundle                       # Release build → .app 生成 → ad-hoc 署名
metaphor bundle --output Dist/
metaphor bundle --check               # 組み立てる前に、足りない設定を洗い出す
metaphor bundle --verify Dist/MyArtwork.app
```

app metadata（表示名 / 識別子 / icon / 最小 OS / 用途文言 / 追加リソース）は**実行時設定
（`SketchConfig`）とは別のプロジェクト直下ファイル**に置く。ファイル名とスキーマは cli 側の実装 Issue で確定する。

### `--check`（組み立て前）

- 識別子が未設定 / 仮のままでないか
- **capability を使っているのに用途文言が無い**（判定材料は本体が capability 情報として出す）
- 宣言されていないアセットを読もうとしていないか（分かる範囲で warning）
- 最小 OS / アーキテクチャの整合

### `--verify`（組み立て後 = Level 2 の門）

- `codesign --verify` が通る
- **実行ファイルとリソースに、ビルドした Mac の絶対パス参照が無い**
- `otool -L` / rpath の解決先がすべて bundle 内か システムか
- 宣言されたリソースが bundle 内に実在する
- 別ディレクトリへ移動・rename しても起動する
- quarantine / Gatekeeper の挙動を説明する（ad-hoc 署名なので「開発元を確認できません」が出る）

## 検証 — クリーンルーム smoke

別の Mac を用意する前に、**同じ Mac で「他人の Mac らしさ」を作って**捕まえる。今回の
`Bundle.module` フォールバック（ADR-0015）はこれで検出できる。

1. `metaphor bundle` で `.app` を作る
2. `.app` をリポジトリの外（例: `/tmp` 配下の別ディレクトリ）へコピーする
3. **`.build/` を退避する**（`mv .build .build.hidden`）。作者の絶対パスへのフォールバックを断つ
4. `open -n <コピーした .app>` で起動し、描画を確認する
5. `.build/` を戻す

その後に本物の受け渡しを 1 回行う: [#414](https://github.com/shinyaoguri/metaphor/issues/414) の
リファレンス作品を別の Apple Silicon Mac へコピーし、Swift / Xcode / metaphor-cli / リポジトリの
いずれも無い状態で起動する。

## 責務分担

| | 担うもの |
|---|---|
| **metaphor（本体）** | `.app` 内でのリソース解決・作品アセットのパス解決・capability 情報・起動時の構造化診断。配布アプリでも通常の描画経路を変えない |
| **metaphor-cli** | Release build・`.app` の組み立て・リソース / framework のコピーと rpath・`Info.plist` / manifest 生成・`codesign` の orchestration・`--check` / `--verify`・安全な資格情報の受け取り（Level 3） |
| **sketch project** | app metadata・明示リソース・用途文言 / entitlement・配布権のあるアセット・署名 identity の選択 |

## 実装の割り当て

依存順は [#1107](https://github.com/shinyaoguri/metaphor/issues/1107) → [cli#191](https://github.com/shinyaoguri/metaphor-cli/issues/191)、
[cli#190](https://github.com/shinyaoguri/metaphor-cli/issues/190) は #1107 と並行可、
[#1109](https://github.com/shinyaoguri/metaphor/issues/1109) は `--check` / `--verify` の警告機能の前提。

| Issue | 段 | 内容 |
|---|---|---|
| [#1107](https://github.com/shinyaoguri/metaphor/issues/1107) | Level 2 の門 | 本体のリソースが `.app` 内で解決できない問題を直す |
| [#1108](https://github.com/shinyaoguri/metaphor/issues/1108) | Level 2 | 作品アセットのパス解決と doc の `Bundle.module` 案内の是正 |
| [#1109](https://github.com/shinyaoguri/metaphor/issues/1109) | Level 1 / 2 | capability 情報と起動時の構造化診断 |
| [cli#190](https://github.com/shinyaoguri/metaphor-cli/issues/190) | Level 1 | `metaphor bundle` の組み立て・`--check` |
| [cli#191](https://github.com/shinyaoguri/metaphor-cli/issues/191) | Level 2 | `--verify` とクリーンルーム smoke |

## 関連

- [ADR-0015](../adr/0015-app-bundle-runtime-resolution-vs-assembly.md) — 責務分担の判断と却下案
- [ADR-0014](../adr/0014-viewer-frame-ipc-and-syphon-plugin.md) — Syphon 同梱の論点を消した判断
- [docs/permissions.md](../permissions.md) — TCC と `Info.plist`（英語）。`metaphor bundle` での包み方と
  `metaphor-app.json` の書き方を案内している（[cli#190](https://github.com/shinyaoguri/metaphor-cli/issues/190) で更新済み）
- [CONTRACT.md](../../CONTRACT.md) — `METAPHOR_STATE_DIR`（`.app` 起動で cwd が `/` になる問題の着地点）
- [#416](https://github.com/shinyaoguri/metaphor/issues/416) — Level 4（常設運用）の担当
