---
name: shots
description: metaphor の実行結果画像（DocC リファレンス・チュートリアル・Examples）を撮る・撮り直す・鮮度検査で止まったのを直すときに読む。3 つの make ターゲットの使い分けと、画像の置き場・台帳・正典の対応。Use when running make reference-shots / tutorial-shots / example-shots, when a --check freshness gate fails in CI or pre-push, or when a captured image looks black, stale, or wrong.
---

# metaphor の実行結果画像を撮る

撮影スクリプトは 3 本あり、**用途ごとに正典も置き場も台帳も違う**。まずどれの話かを
決めてから、詳細はそれぞれの正本ドキュメントへ行く。ここはその分岐だけを持つ。

## どれを撮るのか

| 撮るもの | コマンド | 正典（人が書くもの） | 画像の置き場 | 台帳 |
|---|---|---|---|---|
| API リファレンス | `make reference-shots` | `Sources/**/*.swift` の doc コメントの `<!-- reference-shot -->` 付き ```swift フェンス | **Gyazo**（ADR-0008） | `docs/reference/images/manifest.json` |
| チュートリアル | `make tutorial-shots` | `Examples/Tutorial/**` のスケッチ | **Gyazo**（ADR-0010） | `docs/tutorial/images/manifest.json` |
| Examples | `make example-shots` | `Examples/**` のスケッチ | **リポジトリ内**（パッケージ直下） | `docs/ai/examples-shots.json` |

**Examples だけリポジトリ内**なのは置き場の設計判断で、間違いではない。画像行や URL は
どれも**生成物**なので手で書かない — スクリプトが台帳と本文の両方へ書き戻す。

規約の正本:

- [`docs/reference/README.md`](../../../docs/reference/README.md) — 書き方・レイアウト・反転警告
- [`docs/tutorial/README.md`](../../../docs/tutorial/README.md) — 節の型・動きの証跡・alt
- [`Examples/README.md`](../../../Examples/README.md) — パッケージの構成

## 撮る前に

- **GPU が要る**（実際にスケッチを走らせて Probe が書いた `frame.png` を拾う）。CI では
  走らせない
- **Gyazo のトークンが要る**（reference / tutorial のみ）。読み口は `secret-read` で、
  1Password がロックされていても Keychain のキャッシュから読める。詳細は repo-standards
  プラグインの `gyazo-capture` スキル
- 既定は「まだ画像が無いものだけ」。**撮り直すなら `--force`**:

  ```bash
  make reference-shots ARGS="--only circle --force"
  make tutorial-shots ARGS="--only 01-GettingStarted/03-SketchSkeleton --force"
  make example-shots ARGS="--only Examples/Basics/Form --force"
  ```

- **撮り直すと URL が変わる**。アセットは不変・追記型で、古い URL は消さない（過去の
  リビジョンを開けば当時の絵が出る）。意味もなく `--force` を広く当てない

## 撮ったあとにコミットするもの

| | コミットする |
|---|---|
| reference | `Sources/`（doc コメントの画像行）+ `docs/reference/images/manifest.json` |
| tutorial | `docs/tutorial/`（本文の画像行）+ 同ディレクトリの `images/manifest.json` |
| example | パッケージ直下の画像 + `docs/ai/examples-shots.json` |

## 鮮度検査（`--check`）で止まったとき

「コードを変えたのに画像を撮り直していない」を検出する。**画像そのものは比較しない** —
GPU の出力は環境でビット単位に一致しないため、台帳に記録した**撮影時のソースの指紋**と
現在のソースを突き合わせる。だから GPU の無い CI でも走る。

見張っている場所が用途で違う:

| | pre-push | CI |
|---|---|---|
| reference | ✅ | ✅（`--check` と `--compile-only`） |
| tutorial | ✅ | ✅ |
| example | ❌ | ❌ |

止まったら、**指摘された対象だけ**を `--only` で撮り直す。全部撮り直す必要はない。

`--compile-only`（reference のみ）は GPU もトークンも要らず、doc コメントのスニペットが
コンパイルできることだけを見る。例が壊れていないかを手早く確かめたいときに使う。

## よく踏むもの

- **真っ黒になる** — 動くスケッチの 1 フレーム目を撮っている。下見を挟む仕組みがあるので、
  それが効いていないケースを疑う（`noLoop()` の誤検出など）
- **`noLoop()` と入力台本は両立しない** — 止まるスケッチは起動後に置いた request を処理
  する機会が無い。`probe-input.jsonl` を置いた節は動き続ける必要がある
- **反転しても同じ絵**（reference） — 上下・左右に反転して PSNR を測り、閾値を超えると
  警告する。**引数を間違えても同じ絵になる**例は、リファレンスとして役に立たないという
  判断（`docs/reference/README.md` の「反転一致の警告」）
- **撮れないものは撮らないと申告する** — マイク・カメラ・ML のように実行環境で絵が決まる
  ものは、パッケージ直下に `no-capture.txt` を置いて**理由を 1 行書く**。理由が空だと
  止まる（撮り忘れと区別できなくなるため）

## これは別の話

**PR / Issue に添える証跡**（画面のスクリーンショット、動きの GIF）はここではなく、
repo-standards プラグインの `gyazo-capture` スキルが扱う。あちらは台帳も鮮度検査も無く、
その場で撮ってその場で貼るためのもの。

見分け方: **ドキュメント本文に載り続けるなら**ここ、**その PR / Issue でだけ見せるなら**
`gyazo-capture`。

## 実装

3 本のスクリプトは `scripts/shots_common.py` を共有する（撮影時のソースの指紋・来歴・
画像の縦横・入力台本・**Probe の応答の読み方**・**Gyazo への上げ口**）。撮影まわりを直す
ときは、その 1 本を直せば 3 本に効くのか、用途固有の側なのかをまず見分ける。
