# metaphor Development

このドキュメントは `metaphor` ライブラリ本体を開発する人向けです。

- `metaphor` を使ってスケッチを書く場合は、まず [README.md](README.md) の「60 秒ではじめる」を参照してください。
- ドキュメント全体の地図（誰が何を読むべきか）は [docs/README.md](docs/README.md) にあります。
- AI エージェントと保守する場合の起点は [CLAUDE.md](CLAUDE.md) です。

## Repository Setup

サブモジュールごとクローンし、ローカル開発用の Syphon.xcframework をビルドします。

```bash
git clone --recursive https://github.com/shinyaoguri/metaphor.git
cd metaphor
make setup
```

既にクローン済みの場合:

```bash
git submodule update --init --recursive
make setup
```

`make setup` は pre-push フック（生成物の鮮度チェックなど）も導入します。

## Build Commands

```bash
make setup      # サブモジュール初期化 + Syphon.xcframework ビルド
make build      # swift build
make test       # swift test
make ci-check   # CI と同条件（-warnings-as-errors）で build + test
make clean      # ビルド成果物をクリーン
make check      # セットアップ状態を確認
make docs       # DocC ドキュメントをビルド
make llms-txt   # AI-readable API reference を生成
```

テストは Swift Testing フレームワーク（`@Suite` / `@Test`）を使います。反復中は `swift test --filter <SuiteOrTestName>` で絞り、仕上げに `make test` を通してください。

### push 前は `make ci-check`

`make build` / `make test` は素の `swift build` / `swift test` です。CI（`ci.yml` の `build-and-test` と `build-swift-5-10`）は `-Xswiftc -warnings-as-errors` 付きで走るため、**警告が 1 つ入るとローカルだけ green で CI が赤**になります（strict concurrency 系の警告は Swift 6 モードでエラーになる予備軍なので、これは繰り返し起きます — #448）。

日常のターゲットは試行錯誤しやすいよう緩いまま残し、CI と同じ厳しさは `make ci-check` に集約しています。push / PR の前にこれを通してください。

```bash
make ci-check   # swift build / swift test を -Xswiftc -warnings-as-errors 付きで（METAPHOR_REQUIRE_GPU=1 も CI に合わせる）
```

`make ci-check` で再現できないものは次の 3 つです。

- **Swift 5.10 / Xcode 15.4 でのビルド** — CI の `build-swift-5-10` が担当（このジョブでしか出ない警告が実在します。#328）
- **`CONTRACT.md` のクロスリポ byte-identity** — GitHub API を叩くため CI のみ（`scripts/check-contract-identity.sh`）
- **生成物の鮮度**（`llms.txt` / examples index / shader sources）— `make setup` が入れる pre-push フックが見ます

テスト実行を切り替える環境変数（いずれも既定 OFF。ローカルでは通常不要）:

| 変数 | 効果 |
|---|---|
| `METAPHOR_PERF_TESTS=1` | 壁時計しきい値のアサーションを有効化（`PerformanceBenchmarks` と `ObservabilityOverhead: idle hot path`）。共有ランナーの負荷で揺れるため必須チェックからは分離している（#149 / #329） |
| `METAPHOR_REQUIRE_GPU=1` | 「この環境には GPU がある」と宣言する。Metal デバイスが無ければ `CI Environment Guard` が fail する。CI（`ci.yml`）が設定しており、GPU 依存テストの大量 skip が green のまま見過ごされるのを防ぐ |

### CI が赤いまま終わらせない（Stop hook）

`make ci-check` を通しても CI だけが赤くなることはあります（上の 3 つ、あるいは単なる見落とし）。push しっぱなしで気付かないのを防ぐため、Claude Code のセッションが**赤い CI を残して終われない**ようにしています。`git push` を見たら見届け対象の印を置き、セッションを終えようとしたときに PR のチェック状況を見て、実行中なら見届けを促し、赤なら失敗ジョブ名とログ取得コマンドを添えて差し戻す Stop hook です（自動修正は 3 回・待機は 6 回で打ち切り、以降は人間の判断に返します）。

この仕掛けは**このリポジトリには同梱していません**。守る対象がリポジトリの構成ではなく Claude の振る舞いなので、開発者個人の Claude 環境（[shinyaoguri/claude-plugins](https://github.com/shinyaoguri/claude-plugins) の `repo-standards` プラグイン）が全プロジェクト向けに供給しています（経緯は同リポの [ADR 0016](https://github.com/shinyaoguri/claude-plugins/blob/main/docs/decisions/0016-agent-behavior-hooks-in-plugin.md)）。外部のコントリビュータの手元では動かないので、このリポジトリのセットアップとしては何も要りません。

差し戻されたときの直し方は通常のローカル検証と同じで、`make ci-check` を CI と同条件で通してから追加コミットしてください。

カバレッジのモジュール別サマリは CI の artifact（`coverage-report`）とジョブ要約で確認できます。手元で見るには:

```bash
swift test --enable-code-coverage
BIN=$(find -L .build/debug -name metaphorPackageTests -type f | head -1)
xcrun llvm-cov export "$BIN" -instr-profile=.build/debug/codecov/default.profdata \
    -ignore-filename-regex='Tests/|\.build/' -format=text \
    | python3 scripts/coverage-summary.py
```

## Running Examples

各 example は独立した Swift Package です。

```bash
cd Examples/Basics/Form/ShapePrimitives
swift run
```

カテゴリ構成と追加方法は [Examples/README.md](Examples/README.md) を参照してください。

CI での検証範囲は 3 段構えです（全 278 本を毎 PR で建てるのはコストが見合わないため）:

- **PR が `Examples/` を触ったとき** — 触った example だけを `ci.yml` の `examples-diff-build` がビルド（対象の列挙は `./scripts/changed-examples.sh`）
- **週次 + リリース前** — 代表セット（~19 本）を `examples-sweep.yml` と `release.yml` がビルド
- **全数** — `examples-sweep.yml` の workflow_dispatch（`full=true`）、または手元で `make examples-check`

## 生成物の管理（重要）

以下のファイルはチェックインされていますが**生成物**です。手で編集せず、入力を変えたら再生成してコミットします。pre-push フックと CI が陳腐化を検出します。

| 出力 | 入力 | 再生成コマンド |
|---|---|---|
| `llms.txt` | `Sources/**/*.swift`, `scripts/generate-llms-txt.py` | `make llms-txt` |
| `docs/ai/examples-index.{md,json}` | `Examples/**`, `scripts/generate-examples-index.py` | `make examples-index` |
| `Sources/MetaphorCore/Shaders/ShaderSources/*.txt` | `Shaders/Metal/*.metal`, `scripts/generate-shader-sources.py` | `python3 scripts/generate-shader-sources.py` |

- 生成器は**決定的**であること（全コレクションをソート）。非決定的出力は auto-fix bot が毎回 push する原因になります。
- 生成器のフィルタ規則は `python3 -m unittest discover -s scripts/tests` で検証します（CI 常設・ビルド不要）。「生成物が最新か」のチェックは規則そのものを守れません — API 面を取りこぼしても出力は自己整合したまま緑になるため、採用・除外の判断を変えたらここにテストを足します。
- AI 向けドキュメント（CLAUDE.md / docs/ai/）とコードの整合は `make ai-docs-check` で検証できます。ドキュメント・モジュール一覧・バージョンスニペットを変えたら実行してください。

## Syphon Framework Handling

- ローカル開発では `Frameworks/Syphon.xcframework` が存在する場合、`Package.swift` はローカルパスを使用します。
- SPM ユーザー向けには、`Package.swift` が GitHub Releases からビルド済み XCFramework を取得します。
- `Frameworks/Syphon.xcframework` は `make setup` で生成されます。
- Syphon に依存するのは `MetaphorSyphon` ターゲットだけです（[ADR-0001](docs/adr/0001-separate-syphon-into-its-own-target.md)）。

## PR に見た目の証跡を載せる

**描画結果が変わる PR(シェーダ・ライティング・変換・レイアウト・ゴールデン更新・example の見た目)には、before/after の画像を PR 本文に載せる**。レビューで diff から見た目を想像させない。**動きが変わる PR(アニメーション・パーティクル・物理・イージング・orbitControl 等のインタラクション・時間依存シェーダ)には、画像に加えて GIF も載せる** — 時間方向の変化は静止画を何枚並べても判定できない。

リポジトリに画像・GIF をコミットしない(容量を圧迫する)。ゴールデン PNG のように既にコミットされているもの以外は Gyazo へ上げて URL を貼る。

- **ゴールデン PNG を更新した PR**: 画像は既にコミットに入っているので、raw URL で埋め込むのが最速。

  ```markdown
  | before (main) | after (this PR) |
  |---|---|
  | ![before](https://raw.githubusercontent.com/shinyaoguri/metaphor/<base-sha>/Tests/metaphorTests/Golden/<scene>.png) | ![after](https://raw.githubusercontent.com/shinyaoguri/metaphor/<head-sha>/Tests/metaphorTests/Golden/<scene>.png) |
  ```

  `<base-sha>` は分岐元の main、`<head-sha>` は PR の先頭コミット。GitHub の
  Files changed でも画像 diff(2-up / swipe / onion skin)が見られるが、
  PR 本文に並べておくとレビューの入口で意図が伝わる。
- **ゴールデンにないシーンの見た目変更**: まず「そのシーンをゴールデン化できないか」を
  検討する(証跡と回帰検出網を同時に得られる)。ゴールデン化が不適切な場合は
  Probe でヘッドレスにスクリーンショットを撮る — `METAPHOR_PROBE=1` で起動し
  `.metaphor/probe/current/frame.png` を取得(request.json は起動前に置く。
  詳細は [CONTRACT.md](CONTRACT.md))。撮った PNG は Gyazo へ上げて URL を貼る
  (下の「Gyazo へ上げる」)。
- 差分が微妙な場合は、ゴールデンテストの失敗アーティファクト(実画像・期待画像・
  差分画像)をローカルで生成して差分画像も添える(`.build/golden-failures/`)。

### アニメーションするスケッチを撮るときの注意

- **回転・移動が `frameCount` 依存だと 2 回の実行で絵が揃わない**。比較用に一時的に
  `Float(frameCount)` を定数へ置換して位相を固定すると、frame 番号がずれても同じ絵になる
  (撮影後に戻す)。
- **request.json を起動前に置くと frame 1 が撮れるが、「前フレームまでの描画状態」に依存する
  バグはそこでは再現しない**。数フレーム走らせてから request.json を書く。どちらも
  「撮ったのに差が出ない → 修正が効いていないと誤読する」に直結する。

### 動きの証跡を GIF で撮る

Probe は時間軸も撮れる。`request.json` に `frames`(採取枚数、上限 64)と `every`(ストライド)を
書くと `.metaphor/probe/current/sequence/frame.NNNN.png`(0 始まり 4 桁)と `sequence.json` が出る
(MCP 経由なら `capture_sequence`)。この連番を GIF にまとめる:

```bash
ffmpeg -y -framerate 15 -start_number 0 \
  -i .metaphor/probe/current/sequence/frame.%04d.png \
  -filter_complex "[0:v]fps=15,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 motion.gif
```

画面収録ではなくレンダラ由来のフレームから作るので、他アプリの映り込みもウィンドウ位置への
依存もない。目安は幅 720 / 15fps / 3〜6 秒(1200x800 の 60 枚で 1MB 弱)。**GIF は静止画の
置き換えではなく併載** — 差分の精査は静止画の方が向く。

### Gyazo へ上げる

Gyazo の Upload API へ渡すと `https://i.gyazo.com/<id>.gif` が返る。GitHub は外部画像を camo
経由で配信するが、アニメーションはそのまま再生される。

```bash
curl -s -F "access_token=$(op read "${GYAZO_TOKEN_REF:-op://Automation/Gyazo API/credential}")" \
  -F "imagedata=@motion.gif" https://upload.gyazo.com/api/upload
```

返り値 `url` を `![説明](URL)` で PR 本文に貼り、**どこを見てほしいか**を本文で補う。
アクセストークンは 1Password から都度読む(平文の環境変数として常駐させない)。
手順の一般形は repo-standards プラグインの gyazo-capture スキルにある。

## Cross-Repo Contract

環境変数・stdin JSON Lines・Probe ファイル・Syphon pin など、[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) との実行時契約に触れる変更は、**両リポジトリの同時更新**が必要です。対象と変更ルールは [CONTRACT.md](CONTRACT.md) を参照し、`./scripts/check-contract.sh` が green であることを確認してください。

## Release Process

リリースは PR の `release:patch|minor|major` ラベル駆動です。手順の全体は [docs/releasing.md](docs/releasing.md) を参照してください。

release workflow は Syphon.xcframework をビルドして GitHub Release asset として公開し、`Package.swift` の binary target URL/checksum を更新します。

ユーザー影響のある変更は [CHANGELOG.md](CHANGELOG.md) を直接編集せず、[`changelog.d/`](changelog.d/README.md) に 1 変更 = 1 ファイル（`<slug>.<category>.md`）を置いてください（並行 PR が同じ行で conflict しないため）。リリース時に `scripts/changelog.py` がそれらを `## [Unreleased]` へ集約し、`## [X.Y.Z] - YYYY-MM-DD` へ昇格して GitHub Release 本文の先頭へ転記します。**`changelog.d/` と Unreleased がどちらも空だとリリースは冒頭で中断します**（`python3 scripts/changelog.py check` で手元でも確認可）。

## Notes

- macOS 14.0+ / Apple Silicon / Swift 5.10+ を対象にしています。
- レンダリング挙動の検証は、目視ではなく `MetaphorTestSupport` によるピクセル / readback テストを優先してください。
- 実装のデバッグマップ・不変条件（トリプルバッファリング、compute→render 同期、Probe のゼロコスト規約など）は [docs/ai/README.md](docs/ai/README.md) にまとまっています。
