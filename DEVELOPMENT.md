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

`make ci-check` で再現できないものは次の 4 つです。

- **Swift 5.10 / Xcode 15.4 でのビルド** — CI の `build-swift-5-10` が担当（このジョブでしか出ない警告が実在します。#328）
- **`website/` の Astro ビルド** — CI の `website-build` が担当（#491）。手元で見るなら `cd website && npm ci && npm run build`
  - 公開サイトは Astro（LP + `/tutorial/`）と DocC（`/reference/`）の 2 つのビルドを**並べた**ものです。両方そろった状態を手元で見るには、`make docs` の後に下記の「公開サイトの構成を手元で確認する」を実行します（構成のずれで公開側だけ壊れた前科があります — #529）
- **`CONTRACT.md` のクロスリポ byte-identity** — GitHub API を叩くため CI のみ（`scripts/check-contract-identity.sh`）
- **生成物の鮮度**（`llms.txt` / examples index / shader sources / tutorial snippets）— `make setup` が入れる pre-push フックが見ます

動作を切り替える環境変数（いずれも既定 OFF。ローカルでは通常不要）:

| 変数 | 効果 |
|---|---|
| `METAPHOR_PERF_TESTS=1` | 壁時計しきい値のアサーションを有効化（`PerformanceBenchmarks` と `ObservabilityOverhead: idle hot path`）。共有ランナーの負荷で揺れるため必須チェックからは分離している（#149 / #329） |
| `METAPHOR_REQUIRE_GPU=1` | 「この環境には GPU がある」と宣言する。Metal デバイスが無ければ `CI Environment Guard` が fail する。CI（`ci.yml`）が設定しており、GPU 依存テストの大量 skip が green のまま見過ごされるのを防ぐ |
| `METAPHOR_COMMAND_RECORD=1` | 影オフのスケッチでもメインパスを「記録 → 再生」経路で処理する（既定は影オン時のみ）。2D/3D が呼び出し順どおりに合成されるため、2D を 3D の背後に置ける。既定 OFF なのは、影オフ既定 = 即時経路を ADR-0003 Amendment（#327）で 1.0 の確定仕様として凍結したため。**既知の制限**: この経路では `loadPixels()` の同一フレーム readback が効かず、直近のコミット済みフレームへフォールバックする（初回に警告。`draw()` が記録パスとして先に走りメインパスを分割できないため — ADR-0005 Decision 6 / #326）。オーバーヘッドは記録された 3D ドローコール 1 件あたり ≈ 0.22µs、遅延 2D コマンド 1 件あたり ≈ 0.13µs で、バッチに畳まれる 2D や `circles()` の GPU インスタンシングは実質ゼロ（#327 の実測） |

### ワークフローを触ったら `make lint-workflows`

`.github/workflows/*.yml` は actionlint で検証します（#460）。CI の `build-and-test` が同じスクリプトを呼ぶので、手元で通れば CI でも通ります。

```bash
make lint-workflows   # .github/workflows/*.yml を actionlint にかける
```

これが要るのは、**リリース系ワークフローは PR では走らない**からです（`release.yml` / `release-train.yml` / `release-on-merge.yml` は dispatch / schedule / `pull_request:closed`）。構文や式を壊しても PR では何も起きず、気付くのは「リリースが出ない」「トレインが発車しない」という形になります。

- **actionlint と shellcheck の両方**を `scripts/lint-workflows.sh` で pin しています。無ければ `.build/tools/` へ落として SHA256 を検証してから実行します（手元に同版が入っていればそれを使うので、`brew install` 済みでも無駄になりません）
- shellcheck が要るのは、あると actionlint が `run:` の中身まで検証するからです（導入時に `release.yml` の SC2086 をこれで捕まえました）。**GitHub の macOS ランナーには shellcheck が入っていない**ので、「あれば使う」にすると検証範囲が CI でだけ黙って狭くなります。だから任意ではなく固定で落とします
- 偽陽性の抑制は `.github/actionlint.yaml`。理由をコメントで残してあります

`run:` のコメントで **行頭を `# shellcheck` にしない**でください。shellcheck の directive と解釈されて `SC1073` で落ちます。

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
| `Sources/MetaphorCore/Shaders/BuiltinShaders+Generated.swift`（カスタムシェーダーへ配る 2D / 3D / postFX の MSL 前文） | `Shaders/Metal/*.h`, `scripts/generate-shader-sources.py` | `python3 scripts/generate-shader-sources.py` |
| `docs/tutorial/*.md` の埋め込みコードブロック | `Examples/Tutorial/**`, `scripts/generate-tutorial-snippets.py` | `make tutorial-snippets` |
| `docs/tutorial/images/**` + `manifest.json` | `Examples/Tutorial/**` の実行結果, `docs/tutorial/images/motion.json`, `scripts/generate-tutorial-shots.py` | `make tutorial-shots`（GPU が要るのでローカル専用） |
| README 群の「どこまで公開されているか」（`README.md` / `README.en.md` / `docs/README.md` / `docs/README.en.md` / `Examples/README.md` の `<!-- tutorial-status: … -->` ブロック） | `docs/tutorial/*.md` の frontmatter（`part` / `title` / `draft`）, `scripts/generate-tutorial-status.py` | `make tutorial-status` |

- 生成器は**決定的**であること（全コレクションをソート）。非決定的出力は auto-fix bot が毎回 push する原因になります。
- **前文（カスタムシェーダーへ配る MSL の頭）は 2D / 3D / postFX とも `.h` からの生成物**です（3D は #707、postFX は #718、2D は #714）。構造体を直すときは `Shaders/Metal/Metaphor{Canvas2D,Canvas3D,PostProcess}Types.h` を直して再生成します — Swift 側に前文の文字列を書き足さないでください。組み込みシェーダーも同じ `.h` を include するので、片方だけ直して食い違うことがありません（`ShaderPreludeTests` が Swift 側とのレイアウト一致まで見ます）。
- 生成器のフィルタ規則は `python3 -m unittest discover -s scripts/tests` で検証します（CI 常設・ビルド不要）。「生成物が最新か」のチェックは規則そのものを守れません — API 面を取りこぼしても出力は自己整合したまま緑になるため、採用・除外の判断を変えたらここにテストを足します。
- AI 向けドキュメント（CLAUDE.md / docs/ai/）とコードの整合は `make ai-docs-check` で検証できます。ドキュメント・モジュール一覧・バージョンスニペットを変えたら実行してください。

## 公開サイトの構成を手元で確認する

公開サイト（`https://shinyaoguri.github.io/metaphor/`）は 2 つのビルドを**並べた**ものです。混ぜてはいません（#529）。

| パス | 出どころ |
|---|---|
| `/` · `/en/` · `/tutorial/` | Astro（`website/`） |
| `/reference/` | DocC（`make docs` の `.build/docs` を丸ごと配置） |

`docs.yml` がやっているのは「Astro の `dist` へ `.build/docs` を `reference/` として置く」だけなので、手元でも同じ形を組み立てられます。**DocC は `--hosting-base-path metaphor/reference` を焼き込むため、`/metaphor/` をルートに見せる形で配信しないと CSS も配色も当たりません**（この足場を作らずに `dist` を直接開くと壊れて見えます）。

```bash
make docs                                   # .build/docs
cd website && npm ci && npm run build && cd ..
cp -R .build/docs website/dist/reference
mkdir -p /tmp/site/metaphor && cp -R website/dist/. /tmp/site/metaphor/
cd /tmp/site && python3 -m http.server 8000  # → http://localhost:8000/metaphor/
```

`/metaphor/reference/theme-settings.json` が 200 で引ければ、リファレンス面の配色（`Sources/metaphor/metaphor.docc/theme-settings.json`）が公開サイトでも効きます。

### `theme-settings.json` を触るときの制約

DocC-Render はこのファイルの `theme.color` を**そのままの階層で** CSS 変数名にします（`color.foo.bar` → `--color-foo-bar`）。したがって:

- **色名は `theme.color` の直下にフラットに並べる。** `standard` / `custom` のようなグループを挟むと `--color-custom-0-name` のような無意味な変数になり、**エラーも警告も出ないまま何も効きません**（#529 でこの状態だったことが判明）。
- **値は 1 つしか書けず、light / dark で出し分けられません。** 上書きは inline style として `<body>` に載るので、DocC 側の `prefers-color-scheme` 定義に必ず勝ちます。背景（`fill*`）やテキスト（`figure-gray*`）を指定すると**ダークモードが無効になり、白背景に固定されます**。上書きは light / dark の両方で成立する色（アクセント）に限り、地の色は DocC の既定に任せます。
- そのため上書きする色は**両モードでコントラスト比 4.5:1 を満たす明度**を選びます（白背景と黒背景の両方で 4.5 を超えられる帯は狭く、相対輝度 0.18 前後が上限です）。

確認は `make docs` 後の実ページで行います（`getComputedStyle(document.body).getPropertyValue('--color-standard-blue')` が期待値かどうか）。JSON を書いただけでは効いたことになりません。

## Syphon Framework Handling

- ローカル開発では `Frameworks/Syphon.xcframework` が存在する場合、`Package.swift` はローカルパスを使用します。
- SPM ユーザー向けには、`Package.swift` が GitHub Releases からビルド済み XCFramework を取得します。
- `Frameworks/Syphon.xcframework` は `make setup` で生成されます。
- Syphon に依存するのは `MetaphorSyphon` ターゲットだけです（[ADR-0001](docs/adr/0001-separate-syphon-into-its-own-target.md)）。

## PR に見た目の証跡を載せる

**描画結果が変わる PR(シェーダ・ライティング・変換・レイアウト・ゴールデン更新・example の見た目)には、before/after の画像を PR 本文に載せる**。レビューで diff から見た目を想像させない。**動きが変わる PR(アニメーション・パーティクル・物理・イージング・orbitControl 等のインタラクション・時間依存シェーダ)には、画像に加えて GIF も載せる** — 時間方向の変化は静止画を何枚並べても判定できない。

リポジトリに画像・GIF をコミットしない(容量を圧迫する)。ゴールデン PNG のように既にコミットされているもの以外は Gyazo へ上げて URL を貼る。ドキュメントの画像も同じ方針で、DocC は [ADR-0008](docs/adr/0008-docc-reference-images-via-gyazo.md)、チュートリアルは [ADR-0010](docs/adr/0010-tutorial-images-via-gyazo.md)(撮影からアップロード・本文の URL 書き戻しまで `make tutorial-shots` が行う)。

### CI が検査する(Issue #631)

`Sources/MetaphorCore/` の `Drawing` / `Sketch` / `Shaders` / `UI` / `PostProcess` / `Particle` / `Geometry` を触った PR は、**本文に画像が 1 枚も無いと CI が落ちる**。squash マージなのでブランチは消え、PR 本文がそのまま履歴に残る唯一の記録になる — merge 後に足すことはできない。

落ちたら、どちらかで通る。

1. before/after を撮って本文に貼る(動きが変わるなら GIF も)
2. 本当に絵が変わらないなら PR に `no-visual-change` ラベルを貼る(内部リファクタ・境界値の修正など。「絵は変わらない」という判断が PR に残る)

本文とラベルは実行時に API から読むので、直したあと `gh run rerun --failed <run-id>` だけで通り、push は要らない。対象ディレクトリの判定は [`scripts/require-visual-evidence.py`](scripts/require-visual-evidence.py) が正本(`python3 -m unittest discover -s scripts/tests` で検証)。

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

## 依存更新 PR（dependabot）を手元で検証する

dependabot の PR は PR head だけで CI が回ります。ルールセットの `strict_required_status_checks_policy` は off なので BEHIND のままでも merge できますが（[docs/releasing.md](docs/releasing.md)）、その分**個別に green な PR 同士の意味的な衝突は merge 後の `push: main` CI まで表に出ません**。website の改修と astro の bump が並走したときのように、合成しないと分からないものは merge 前に確かめます。

```bash
./scripts/verify-dep-pr.sh 441
```

使い捨ての worktree（`$TMPDIR`）で `origin/main` と PR head をマージし、PR が触った領域の検証だけを回します。**手元の作業ツリー・ローカルブランチ・HEAD には触れません**（終了時に worktree も一時 ref も片付きます）。

| PR が触った領域 | やること |
|---|---|
| `website/**` | `npm ci && npm run build`（CI の `website-build` ジョブと同じコマンド） |
| `.github/workflows/**` | ローカル検証は無し（PR の checks が正）。runner 一覧だけ出して、Node 版縛りのある `actions/*` bump の判断材料にする |
| `Sources/**` · `Package.swift` · `Vendor/**` | 対象外（`Syphon.xcframework` が要る）。セットアップ済みの手元ツリーで `make ci-check` |

領域を指定して回すこともできます（`--only website`）。PR 以外の ref も `--ref <git-ref> --only website` で同じ検証にかけられます。

## Cross-Repo Contract

環境変数・stdin JSON Lines・Probe ファイル・Syphon pin など、[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) との実行時契約に触れる変更は、**両リポジトリの同時更新**が必要です。対象と変更ルールは [CONTRACT.md](CONTRACT.md) を参照し、`./scripts/check-contract.sh` が green であることを確認してください。

## Release Process

リリースは**週次トレイン**です。毎週月曜 09:00 JST に `release-train.yml` が `main` の履歴を見て、前回の stable タグ以降に `feat` があれば minor、`fix`/`perf` だけなら patch を出します（何も無ければ出しません）。**PR 側でリリースのために行う操作はありません。** 月曜を待てない hotfix だけ `release:now` ラベルで即時に出せます。手順の全体は [docs/releasing.md](docs/releasing.md) を参照してください。

```bash
python3 scripts/release-bump.py --explain   # 次のトレインが何を出すかを手元で確認
```

release workflow は Syphon.xcframework をビルドして GitHub Release asset として公開し、`Package.swift` の binary target URL/checksum を更新します。

ユーザー影響のある変更は [CHANGELOG.md](CHANGELOG.md) を直接編集せず、[`changelog.d/`](changelog.d/README.md) に 1 変更 = 1 ファイル（`<slug>.<category>.md`）を置いてください（並行 PR が同じ行で conflict しないため）。リリース時に `scripts/changelog.py` がそれらを `## [Unreleased]` へ集約し、`## [X.Y.Z] - YYYY-MM-DD` へ昇格して GitHub Release 本文の先頭へ転記します。**`changelog.d/` と Unreleased がどちらも空だとリリースは冒頭で中断します**（`python3 scripts/changelog.py check` で手元でも確認可）。

## Notes

- macOS 14.0+ / Apple Silicon / Swift 5.10+ を対象にしています。
- レンダリング挙動の検証は、目視ではなく `MetaphorTestSupport` によるピクセル / readback テストを優先してください。
- 実装のデバッグマップ・不変条件（トリプルバッファリング、compute→render 同期、Probe のゼロコスト規約など）は [docs/ai/README.md](docs/ai/README.md) にまとまっています。
