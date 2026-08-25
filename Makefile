.PHONY: setup build clean clean-examples test test-verbose test-coverage test-lcov ci-check static-check static-check-fast check-binary-targets preflight docs docs-check docs-ja docs-preview examples examples-check examples-list examples-index example-shots tutorial-snippets tutorial-shots tutorial-status reference-shots reference-snippets-check reference-i18n symbol-graphs llms-txt ai-docs-check freshness-check docs-links-check reference-links-check hooks contract-schema lint-workflows lint-python lint-swift format

# Default target
all: setup build

# Preflight check - verify required tools and environment
preflight:
	@./scripts/preflight-check.sh

# Initial setup - verify tools, install git hooks
#
# Syphon の submodule と xcframework のビルドはここから消えた（#792 / ADR-0014）。
# Syphon は別パッケージ shinyaoguri/metaphor-syphon が持つ。
setup: preflight hooks

# Install git hooks (pre-push llms.txt staleness check)
hooks:
	@echo "Installing git hooks (core.hooksPath=scripts/hooks)..."
	@git config core.hooksPath scripts/hooks

# Build the Swift package
build:
	@echo "Building metaphor..."
	swift build

# Build release version
release:
	@echo "Building metaphor (release)..."
	swift build -c release

# Run tests
test:
	@echo "Running tests..."
	swift test

# Run tests with verbose output
test-verbose:
	@echo "Running tests (verbose)..."
	swift test --verbose

# Run tests with code coverage report
test-coverage:
	@echo "Running tests with coverage..."
	swift test --enable-code-coverage
	@echo ""
	@echo "Coverage report:"
	@xcrun llvm-cov report \
		$$(swift test --enable-code-coverage --show-codecov-path 2>/dev/null || echo ".build/debug/metaphorPackageTests.xctest/Contents/MacOS/metaphorPackageTests") \
		-instr-profile=.build/debug/codecov/default.profdata \
		-ignore-filename-regex='Tests/|\.build/' 2>/dev/null || \
	echo "  (coverage report generation requires a successful test run with --enable-code-coverage)"

# Generate LCOV coverage data for CI integration
test-lcov:
	@echo "Running tests with coverage (LCOV)..."
	swift test --enable-code-coverage
	@xcrun llvm-cov export \
		$$(swift test --enable-code-coverage --show-codecov-path 2>/dev/null || echo ".build/debug/metaphorPackageTests.xctest/Contents/MacOS/metaphorPackageTests") \
		-instr-profile=.build/debug/codecov/default.profdata \
		-ignore-filename-regex='Tests/|\.build/' \
		-format=lcov > .build/coverage.lcov 2>/dev/null || true
	@echo "LCOV written to .build/coverage.lcov"

# CI と同条件で検証する（push / PR を出す前の 1 コマンド）
#
# ci.yml の build-and-test は `-Xswiftc -warnings-as-errors` 付きで
# build / test するのに対し、上の `build` / `test` は素の swift build /
# swift test。試行錯誤の途中で警告ひとつビルドが止まる体験を避けるため
# 日常ターゲットはあえて緩いままにし、「CI と同じ厳しさ」はここへ集約する
# （Issue #448。strict concurrency の警告は Swift 6 モードでエラーになる
# 予備軍なので、ローカル green → CI だけ赤が起きていた）。
#
# METAPHOR_REQUIRE_GPU=1 も CI に合わせる。Metal デバイスが見えない環境では
# GPU 依存テストが軒並み skip されたまま green を返すため、それを fail にする。
#
# 生成物の鮮度は 2026-08-25 からここでも見る（#978）。pre-push は push する range
# から必要な検査だけを選ぶので、**そもそも push しない限り一度も鳴らない** —
# ローカルの検証コマンドとして案内しているのが ci-check である以上、そこに無い検査は
# 「押し忘れ」ではなく「押せない」。実体は scripts/check-generated-freshness.sh で、
# pre-push と signed-commit.py も同じものを呼ぶ。
#
# 同じ理屈で、per-PR CI が走らせるステップは**手元で走らせられる限り全部ここに載せる**
# （Issue #1020）。起票時点の取りこぼしは 14 本あり、DocC の警告検査はそのうちの 1 本
# でしかなかった。CI へステップが足されるたび入口だけ増えて ci-check へ束ねる工程が
# 誰の担当でもなかったのが原因なので、対応づけは scripts/check-ci-parity.py の台帳に
# 移し、ズレたら落ちるようにしてある（下の static-check から走る）。
#
# ここで再現できないもの（いずれも別の場所で担保されている。全数は
# scripts/check-ci-parity.py の LEDGER / JOB_LEDGER が正本）:
#   - PR のタイトル / 本文 / ラベルを読む 3 ステップ → PR が無いと走らない
#   - CONTRACT.md のクロスリポ byte-identity → GitHub API が要るので CI のみ
#   - Swift 5.10 / Xcode 15.4 でのビルド → CI の build-swift-5-10
#   - website（Astro）のビルド → CI の website-build
#   - 変更された example のビルド → CI の examples-diff-build（手元は make examples-check）
#
# NOTE: swiftc のフラグが変わるとビルドキャッシュは作り直しになるので、
# `make build` と交互に走らせると毎回フルリビルドになる。実測で 10 秒台
# （ライブラリ + テスト、Apple Silicon）に収まるため、専用の --scratch-path は
# 設けず CI と同じ .build をそのまま使う。
ci-check: static-check
	@echo "Checking Swift formatting (CI parity)..."
	@./scripts/lint-swift.sh
	@echo "Building with -warnings-as-errors (CI parity)..."
	swift build -Xswiftc -warnings-as-errors
	@echo "Testing with -warnings-as-errors (CI parity)..."
	METAPHOR_REQUIRE_GPU=1 swift test -Xswiftc -warnings-as-errors
	@$(MAKE) --no-print-directory freshness-check
	@$(MAKE) --no-print-directory docs-check
	@$(MAKE) --no-print-directory reference-links-check
	@$(MAKE) --no-print-directory reference-snippets-check
	@$(MAKE) --no-print-directory ai-docs-check

# CI の「ビルドが要らない検査」をまとめて走らせる（Issue #1020）
#
# ci-check の先頭で走る。単体でも呼べるので、Swift を触っていない PR
# （docs / scripts / workflows だけ）はこれだけ通せば足りる — 実測 40 秒弱で、
# うち 35 秒は scripts/tests のユニットテスト。
#
# 中身は 2 つに割ってある（Issue #1155）。上の 11 本（static-check-fast）は合計
# 5 秒強で、**pre-push と signed-commit.py がそのまま無条件に走らせる**。scripts/tests
# だけがここに残るのは、ビルド不要な検査の中で唯一コストがビルドと同じ桁（実測
# 35.6 秒）で、`git push` の体感を変えてしまうため。パストリガーで絞る案は採らな
# かった — test_check_ci_parity.py は実物の ci.yml と Makefile を読むので、入力は
# 「隣にあるファイル」ではなく、リストが 2 箇所に分かれてドリフトする #995 の形を
# 作る（そこが見ている内容は static-check-fast 側の check-ci-parity.py が独立に見る）。
static-check: static-check-fast
	@echo "Running generator script tests (CI parity)..."
	@python3 -m unittest discover -s scripts/tests

# static-check のうち、秒未満〜2 秒で終わる 11 本（Issue #1155）
#
# 並びは**実測の所要時間の昇順**で、CI の並び順とは意図的に変えてある。CI は
# ステップ単位でログが分かれるので順序が体験に効かないが、手元では 1 本のログに
# 連なるため、0.1 秒で分かる失敗を 2 秒待たされてから見るのは無駄。
#
# check-jsonschema は preflight の必須ツールではない（pip 経由）ので、無ければ
# 断って飛ばす。CI 側は pip install してから無条件に走らせる。
static-check-fast:
	@echo "Running build-free CI checks (CI parity)..."
	@python3 scripts/changelog.py lint
	@python3 scripts/check-doc-comment-language.py
	@python3 scripts/check-no-raw-print.py
	@$(MAKE) --no-print-directory docs-links-check
	@$(MAKE) --no-print-directory lint-python
	@python3 scripts/check-ci-parity.py
	@./scripts/check-contract.sh
	@$(MAKE) --no-print-directory lint-workflows
	@python3 scripts/check-strict-concurrency.py
	@$(MAKE) --no-print-directory check-binary-targets
	@if command -v check-jsonschema >/dev/null 2>&1; then \
		$(MAKE) --no-print-directory contract-schema; \
	else \
		echo "wire-schema: SKIPPED — check-jsonschema がありません（pip install check-jsonschema）。CI では必ず走ります。"; \
	fi

# Clean build artifacts (including every per-example .build)
clean: clean-examples
	@echo "Cleaning..."
	swift package clean
	rm -rf .build

# Remove per-example SPM build artifacts.
# Each example under Examples/ is an independent SwiftPM package, so each grows
# its own .build/ — hundreds of duplicated dirs totalling tens of GB. These are
# git-ignored, so deleting them is always safe (they rebuild on demand).
clean-examples:
	@echo "Cleaning Examples/**/.build ..."
	@find Examples -type d -name .build -prune -exec rm -rf {} + 2>/dev/null || true

# Full clean (kept as an alias; there is nothing beyond `clean` to remove any more)
clean-all: clean

# Check if setup is complete (git hooks + toolchain). There are no vendored
# binaries to verify since Syphon moved to metaphor-syphon (#792 / ADR-0014).
check:
	@if [ "$$(git config core.hooksPath)" = "scripts/hooks" ]; then \
		echo "git hooks: OK (core.hooksPath=scripts/hooks)"; \
	else \
		echo "git hooks: NOT INSTALLED - run 'make hooks'"; \
	fi
	@./scripts/preflight-check.sh

# Root manifest must stay free of binaryTargets (#792 / ADR-0014): a remote binary
# artifact is downloaded by every consumer that resolves the package, even when the
# product that needs it is unused. Same check as CI.
check-binary-targets:
	@./scripts/check-no-binary-targets.sh

# Extract symbol graphs (shared step for docs and llms-txt)
# Each module is independent — run extraction in parallel via xargs -P.
# Saves ~60s on CI (12 modules × ~7s sequential → bounded by core count).
#
# C target（CMetaphorIPC）のモジュールは modulemap を -Xcc で渡す（Swift から見える
# 型を symbol graph が解決するため）。Syphon の framework 探索（-F）は metaphor-syphon へ
# 移った（#792 / ADR-0014）。
#
# 抽出の前にディレクトリごと捨てるのは、swift-symbolgraph-extract が既存ファイルを上書き
# するだけで消さないため。Package から消えたモジュールの symbol graph が残り続け、llms.txt
# に消えたはずの節が復活し、DocC にも消えたページが混ざる（#1058。M4 / #1040 で Syphon が
# root manifest から外れたあとに実際に起きた）。抽出は元から毎回全モジュールを回すので、
# 増える手間はディレクトリ 1 つの削除だけで所要時間は実質変わらない。
#
# 説明をレシピの外（この位置）に置いているのは 2 つの理由による。レシピ本体は `\` 継続行の
# ひとかたまりなので、途中に `#` を挟むと以降が丸ごとシェルコメントに飲まれる。加えて
# scripts/validate-ai-docs.sh が `awk '/^symbol-graphs:/,/^# Generate llms.txt/'` で
# このブロックを読み、`Metaphor*` 語を拾ってモジュール網羅を判定するので、ブロック内に
# 語彙を増やすと網羅判定が鈍る。下の `# Generate llms.txt` は境界なので消さないこと。
symbol-graphs: build
	@echo "Extracting symbol graphs..."
	@rm -rf .build/symbol-graphs
	@mkdir -p .build/symbol-graphs
	@SDK_PATH="$$(xcrun --show-sdk-path)"; \
	export SDK_PATH; \
	printf '%s\n' metaphor MetaphorCore MetaphorLog \
		MetaphorAudio MetaphorNetwork MetaphorPhysics MetaphorML MetaphorVideo \
		MetaphorNoise MetaphorMPS MetaphorCoreImage \
		MetaphorRenderGraph MetaphorSceneGraph \
	| xargs -n1 -P8 -I{} xcrun swift-symbolgraph-extract \
		-module-name {} \
		-target arm64-apple-macosx14.0 \
		-sdk "$$SDK_PATH" \
		-I .build/arm64-apple-macosx/debug/Modules \
		-Xcc -fmodule-map-file=.build/arm64-apple-macosx/debug/CMetaphorIPC.build/module.modulemap \
		-minimum-access-level public \
		-skip-inherited-docs \
		-emit-extension-block-symbols \
		-output-dir .build/symbol-graphs

# Generate llms.txt (AI-readable API reference)
llms-txt: symbol-graphs
	@python3 scripts/generate-llms-txt.py -o llms.txt

# Validate AI-facing docs and generated-reference assumptions
ai-docs-check:
	@./scripts/validate-ai-docs.sh

# 生成物が入力に追随しているかを 1 コマンドで検査する（Issue #978）
#
# 実体は pre-push フックと共有する。違うのはトリガーだけで、pre-push は push する
# range から必要な検査を選び、ここと signed-commit.py は経路を問わず全部を走らせる
# （作業ツリーしか見られない側で変更パスから絞ると、`git merge origin/main` 由来の
# 陳腐化を取りこぼす — #786 / #972）。
#
# ai-docs-check には寄せていない。あちらは「ドキュメントの記述がコードと合っているか」
# を**ビルドせずに**見る軽い検査で、`make llms-txt`（= `swift build`）を持ち込むと
# 性格が変わる。こちらは既にビルドしている ci-check にぶら下げる。
freshness-check:
	@./scripts/check-generated-freshness.sh --all

# Validate relative links in docs/** and the ADR index (Issue #1044)
#
# docs/adr は append-only で相互参照が増え続ける一方、リンクが切れても踏んだ人が
# 現れるまで誰も気付けない。make docs-check は DocC の警告検査で Markdown を見ない。
# 外部 URL は対象外（ネットワーク依存を持ち込まない）。判定規則はスクリプト側が正本。
docs-links-check:
	@python3 scripts/check-docs-links.py

# Validate the DocC reference URLs that docs/** link out to (Issue #987)
#
# 上の docs-links-check の担当外（外部 URL）のうち、リファレンスだけをここで見る。
# URL にはシグネチャが焼き込まれているので、引数ラベルが 1 つ増えただけで 404 になる
# （#959 では 4 本が同時に死んでいた）。公開サイトへ HTTP は投げない — flaky を
# 持ち込むうえ、見に行く先が公開済みのリファレンスでは main へ入る前の変更を
# 検知できない。判定はローカルの DocC 出力に当てるので、`docs` に依存する
# （実測 4 秒。symbol graph の抽出と docc convert はどちらも数秒）。
reference-links-check: docs
	@python3 scripts/check-reference-links.py --docs-dir $(DOCC_OUTPUT)

# Validate wire-schema contract (contract/examples/ against contract/*.schema.json).
# Requires check-jsonschema (pip install check-jsonschema).
contract-schema:
	@./scripts/check-contract-schema.sh

# Lint GitHub Actions workflows with actionlint (same entry point as CI).
# Pins actionlint and downloads it on demand; shellcheck makes it check run: too.
lint-workflows:
	@./scripts/lint-workflows.sh

# Lint Python scripts with ruff (same version as CI)
#
# 未使用 import ほか pyflakes 相当の指摘を機械で拾う（Issue #1022）。
# ruff は stdlib ではないので、バージョンの pin と venv への隔離は
# スクリプト側が持つ（ci.yml もこれと同じ実体を呼ぶ）。
lint-python:
	@./scripts/lint-python.sh

# Lint Swift formatting with swift-format (same entry point as CI)
#
# 検証だけで書き換えない。整形するのは `make format`。設定は .swift-format が
# 正本で、対象の選び方（Examples と生成物を外す理由）はスクリプト側にある。
lint-swift:
	@./scripts/lint-swift.sh

# Format Swift sources in place with swift-format
format:
	@./scripts/lint-swift.sh --fix

# Build DocC documentation
# Uses manual symbol graph extraction to work around SPM binary target issue
# base path は公開時と同じ /metaphor/reference/（DocC は baseUrl を出力へ焼き込む
# ので、ここが CI とずれるとローカルでは気付けない不具合になる — Issue #529）
# 日本語版は同じ骨格を /metaphor/reference/ja/ へもう一度出す（DOCC_BASE_PATH）。
DOCC_CATALOG ?= Sources/metaphor/metaphor.docc
DOCC_BASE_PATH ?= metaphor/reference
DOCC_OUTPUT ?= .build/docs

# header.html（言語切替）は --experimental-enable-custom-templates が無いと注入されない。
# コマンド本体は docs と docs-check で共有する（片方だけフラグが増えると、
# 「手元では出ない警告で CI が落ちる」が起きるため）。
DOCC_CONVERT = xcrun docc convert $(DOCC_CATALOG) \
		--additional-symbol-graph-dir .build/symbol-graphs \
		--transform-for-static-hosting \
		--experimental-enable-custom-templates \
		--hosting-base-path $(DOCC_BASE_PATH) \
		--output-path $(DOCC_OUTPUT)

docs: symbol-graphs
	@echo "Building DocC documentation..."
	$(DOCC_CONVERT)

# DocC の警告 0 を要求する（Issue #396）。閾値ではなく 0 件固定。
# 警告のほとんどは**解決できないシンボルリンク**で、internal 型を指す ``…`` や
# オーバーロードの曖昧参照は放置すると必ず増える（起票時 11 件 → 31 件）。
# docs.yml は **main への push でしか走らない**ため、PR 時点では誰も気付けなかった。
# symbol-graphs は llms.txt の鮮度検査と同じものを使い回す（抽出は並列で数秒）。
docs-check: symbol-graphs
	@echo "Checking DocC warnings (must be zero)..."
	$(DOCC_CONVERT) --warnings-as-errors

# Build the Japanese reference (ADR-0011)
# 英語の doc コメントが正典で、日本語は台帳 docs/reference/i18n/ja.json を当てた生成物。
# 訳が無い箇所は英語のまま残る（落とさない）ので、#334 の英語化が進むほど日本語化も進む。
# DocC が読むヘッダーはカタログ直下の header.html 1 本きりなので、カタログを複製して
# 日本語版のヘッダーへ差し替えてから convert する。
# カタログの**ディレクトリ名がドキュメントのルート名になる**ので、複製先でも
# metaphor.docc の名前を保つ（metaphor-ja.docc にすると日本語版だけ
# /ja/documentation/metaphor-ja/ に出て、英語版とのパスの 1:1 対応が壊れる）。
docs-ja:
	@rm -rf .build/ja-catalog
	@mkdir -p .build/ja-catalog
	@cp -R $(DOCC_CATALOG) .build/ja-catalog/$(notdir $(DOCC_CATALOG))
	@cp docs/reference/i18n/header.ja.html .build/ja-catalog/$(notdir $(DOCC_CATALOG))/header.html
	@$(MAKE) docs DOCC_CATALOG=.build/ja-catalog/$(notdir $(DOCC_CATALOG)) \
		DOCC_BASE_PATH=metaphor/reference/ja DOCC_OUTPUT=.build/docs-ja
	@python3 scripts/translate-reference.py --apply --docs-dir .build/docs-ja

# Update the Japanese reference ledger
# 既定は未訳の書き出し（何で訳しても良い → --import で戻す）。
# ARGS="--engine google" なら Cloud Translation で直接埋める（GOOGLE_API_KEY が要る）。
reference-i18n: docs
	@python3 scripts/translate-reference.py --docs-dir .build/docs \
		--export .build/reference-untranslated.json $(ARGS)

# Preview DocC documentation locally
docs-preview: symbol-graphs
	@echo "Previewing DocC documentation..."
	xcrun docc preview Sources/metaphor/metaphor.docc \
		--additional-symbol-graph-dir .build/symbol-graphs

# Run examples in parallel (excludes _Legacy/ by default)
examples:
	@./scripts/run-examples.sh --parallel 10

# Build-only verification of all examples (parallel)
examples-check:
	@./scripts/run-examples.sh --build-only --parallel 10

# Run examples sequentially (interactive, with note prompts)
examples-seq:
	@./scripts/run-examples.sh

# List all available examples
examples-list:
	@./scripts/run-examples.sh --list

# Generate AI-friendly examples index from example metadata
examples-index:
	@python3 scripts/generate-examples-index.py

# Shoot Examples/**/<Name>.png by running each example (needs a GPU)
# 既定は「画像がまだ無い example だけ」を撮る。原典由来の 162 枚は一括では
# 置き換えない（#501。個別に差し替えるときは --only と --force を併用）。
example-shots:
	@python3 scripts/generate-example-shots.py $(ARGS)

# Embed Examples/Tutorial/** code into docs/tutorial/*.md
# 正典はパッケージ側。本文の埋め込みブロックは生成物なので手で編集しない。
tutorial-snippets:
	@python3 scripts/generate-tutorial-snippets.py

# Re-shoot docs/tutorial/images/** by running each tutorial sketch (needs a GPU)
# 撮影はローカル専用。CI は --check で「コードを変えたのに撮り直していない」
# だけを見る（GPU 出力はビット単位で再現しないため画像自体は比較しない）。
tutorial-shots:
	@python3 scripts/generate-tutorial-shots.py $(ARGS)

# Write "how far the tutorial is published" into the entry docs from frontmatter
# 正典は docs/tutorial/*.md の frontmatter。README 群の案内は生成物（#584）。
tutorial-status:
	@python3 scripts/generate-tutorial-status.py

# Shoot the DocC reference images by running the snippets in doc comments (needs a GPU)
# 正典は doc コメントの ```swift フェンス。画像行は生成物で、URL は Gyazo（ADR-0008）。
# 撮影はローカル専用。CI は --check（鮮度）と --compile-only（例が壊れていないか）を見る。
reference-shots:
	@python3 scripts/generate-reference-shots.py $(ARGS)

# doc コメントのスニペットが**実際にコンパイルできる**ことだけを見る（#531）
# 撮影（reference-shots）と違って GPU も Gyazo トークンも要らないので per-PR で回せる。
# CI の `Verify reference snippets compile` と同じ実体（Issue #1020 で ci-check にも接続）。
reference-snippets-check:
	@python3 scripts/generate-reference-shots.py --compile-only

help:
	@echo "metaphor Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make preflight      - Check required tools and environment"
	@echo "  make setup          - Verify tools and install git hooks"
	@echo "  make hooks          - Install git hooks only (core.hooksPath=scripts/hooks)"
	@echo "  make build          - Build the Swift package"
	@echo "  make release        - Build release version"
	@echo "  make test           - Run tests"
	@echo "  make test-verbose   - Run tests with verbose output"
	@echo "  make test-coverage  - Run tests and show coverage report"
	@echo "  make test-lcov     - Run tests and generate LCOV for CI"
	@echo "  make ci-check       - Run every per-PR CI check that works locally (run before pushing)"
	@echo "  make static-check   - The build-free half of ci-check (lints, contract, script tests)"
	@echo "  make static-check-fast - static-check minus the script tests (what pre-push runs)"
	@echo "  make clean          - Clean build artifacts (incl. Examples/**/.build)"
	@echo "  make clean-examples - Remove per-example .build dirs only"
	@echo "  make check          - Check if setup is complete"
	@echo "  make symbol-graphs  - Extract symbol graphs (shared step)"
	@echo "  make llms-txt       - Generate llms.txt (AI API reference)"
	@echo "  make ai-docs-check  - Validate AI-facing docs and llms.txt assumptions"
	@echo "  make freshness-check - Verify every generated artifact tracks its inputs"
	@echo "  make docs-links-check - Check relative links in docs/** and the ADR index"
	@echo "  make reference-links-check - Check the DocC reference URLs docs/** link out to"
	@echo "  make contract-schema - Validate wire-schema contract (needs check-jsonschema)"
	@echo "  make lint-workflows - Lint .github/workflows with actionlint (same as CI)"
	@echo "  make lint-python    - Lint scripts/*.py with ruff (same as CI)"
	@echo "  make lint-swift     - Check Swift formatting with swift-format (same as CI)"
	@echo "  make format         - Format Swift sources in place with swift-format"
	@echo "  make docs           - Build DocC documentation"
	@echo "  make docs-check     - Build DocC and fail on any warning (CI と同条件)"
	@echo "  make docs-ja        - Build the Japanese reference from the ledger (ADR-0011)"
	@echo "  make reference-i18n - Export untranslated reference strings (ARGS=\"--engine google\")"
	@echo "  make docs-preview   - Preview DocC documentation locally"
	@echo "  make examples       - Run examples in parallel (10 workers)"
	@echo "  make examples-seq   - Run examples sequentially (interactive)"
	@echo "  make examples-check - Build-only verification (parallel)"
	@echo "  make examples-list  - List all available examples"
	@echo "  make examples-index - Generate AI-friendly examples index"
	@echo "  make example-shots  - Shoot missing example result images (needs a GPU)"
	@echo "  make tutorial-snippets - Embed Examples/Tutorial code into docs/tutorial"
	@echo "  make tutorial-shots - Re-shoot tutorial result images (needs a GPU)"
	@echo "  make tutorial-status - Write the tutorial publication status into the READMEs"
	@echo "  make reference-shots - Re-shoot DocC reference result images (needs a GPU)"
	@echo "  make reference-snippets-check - Compile the snippets in doc comments (same as CI)"
	@echo "  make help           - Show this help"
