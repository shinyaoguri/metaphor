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

- **GPU が要る**（実際にスケッチを走らせて Probe が書いた `frame.png` を拾う）。手元に
  GPU が無いとき・手元を数時間塞ぎたくないときは **CI で撮れる**（下記）
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

## CI で撮る

`shots.yml`（手動起動）が同じスクリプトを `macos-26` ランナーで走らせ、差分があれば
**PR を開く**。手元の GPU を数時間塞がずに済む。

```bash
gh workflow run shots.yml -f target=reference
gh workflow run shots.yml -f target=tutorial -f only=01-GettingStarted/03-SketchSkeleton -f force=true
```

`target` は `reference` / `tutorial` / `example`。トークンは Actions secrets の
`GYAZO_TOKEN`（手元の `secret-read` とは別経路 — #1116）。

**PR を確認せずに merge しない。** 絵が変わったのが意図した変更か退行かは機械では判別
できない（台帳の指紋はスケッチと撮影設定しか見ないので、ライブラリの実装が変わって絵が
変わっても気付けない — #586。実例は #1112）。直接 push ではなく PR にしているのはこのため。

## 撮ったあとにコミットするもの

| | コミットする |
|---|---|
| reference | `Sources/`（doc コメントの画像行）+ `docs/reference/images/manifest.json` |
| tutorial | `docs/tutorial/`（本文の画像行）+ 同ディレクトリの `images/manifest.json` |
| example | パッケージ直下の画像 + `docs/ai/examples-shots.json` |

## 鮮度検査（`--check`）で止まったとき

「コードを変えたのに画像を撮り直していない」を検出する。**画像そのものは比較しない** —
撮り直しには GPU と 1 本ごとの起動時間が要り、per-PR で全数を撮り直すのは現実的でないため、
台帳に記録した**撮影時のソースの指紋**と現在のソースを突き合わせる。指紋の比較は一瞬で済む。

バイト比較そのものは reference の `--verify-bytes` が行う（撮り直して台帳の `sha256` と
突き合わせ、Gyazo へは上げない）。`macos-26` ランナーには GPU があるので CI でも走り、
「別マシン・別 GPU でも同じ絵になるか」を実測できる（`shot-reproducibility.yml`）。

（バイト比較しない理由は「GPU の出力が非決定だから」ではない。同じマシン・同じ実装なら
バイト単位で一致する。ただし別マシン・別 GPU・OS メジャーアップデート後は未測定で保証
しない → [ADR-0010 の Amendment 2026-08-23](../../../docs/adr/0010-tutorial-images-via-gyazo.md)）

見張っている場所が用途で違う:

| | pre-push | per-PR CI | 週次 |
|---|---|---|---|
| reference | ✅ | ✅（`--check` と `--compile-only`） | — |
| tutorial | ✅ | ✅ | — |
| example | ❌ | ❌ | ✅ `asset-health.yml` |

**example だけ per-PR に無いのは意図的**（#1161）。費用ではない — 検査は 0.08 秒・GPU 不要
で、他の 2 本より軽い。分けているのは**落ちたときに人が取れる行動**が違うため:

- reference / tutorial は、落ちても再生成 or 撮り直しの正解が 1 つに決まる
- example の復旧は GPU での撮り直しで、対象はどれも動くスケッチなので**撮るたびに別の絵に
  なる**。退行か意図した変更かは機械では判別できず（#586）、**人の目視レビューが要る**。
  per-PR の必須ゲートにすると、`Examples/` に触れただけの PR へ溜まっている他人の
  backlog を渡すことになる

週次で鳴らすので「気付いた人が撮る」以外の検出機会はある（見張りが無いと溜まることは実測
済み — #726 が 5 本 → #732 で解消 → 8 日後に 6 本へ再蓄積）。

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

**PR / Issue に添える証跡**（画面のスクリーンショット、動きのアニメーション WebP）はここではなく、
repo-standards プラグインの `gyazo-capture` スキルが扱う。あちらは台帳も鮮度検査も無く、
その場で撮ってその場で貼るためのもの。

見分け方: **ドキュメント本文に載り続けるなら**ここ、**その PR / Issue でだけ見せるなら**
`gyazo-capture`。

## 実装

3 本のスクリプトは `scripts/shots_common.py` を共有する（撮影時のソースの指紋・来歴・
画像の縦横・入力台本・**Probe の応答の読み方**・**撮影の骨格**・**Gyazo への上げ口**）。
撮影まわりを直すときは、その 1 本を直せば 3 本に効くのか、用途固有の側なのかをまず見分ける。

**撮影の骨格**は `probe_capture()`（request をいつ置き、どう待ち、どう後片付けするか =
CONTRACT.md 契約点 4 の producer 側）。段取り — 下見を挟むか・連番で撮るか・ビルドを自分で
持つか — は用途で違うので各スクリプトが書くが、契約に触れる操作はこの context manager の
メソッド越しにだけ行う。GPU が無くても偽の Probe（`scripts/tests/_probe_fakes.py`）で
段取りだけは検査できる。
