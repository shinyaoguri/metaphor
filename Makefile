.PHONY: setup build clean clean-examples test test-verbose test-coverage test-lcov ci-check check-binary-targets preflight docs docs-check docs-ja docs-preview examples examples-check examples-list examples-index example-shots tutorial-snippets tutorial-shots tutorial-status reference-shots reference-i18n symbol-graphs llms-txt ai-docs-check hooks contract-schema lint-workflows lint-python

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
# ここで再現できないもの（いずれも別の場所で担保されている）:
#   - Swift 5.10 / Xcode 15.4 でのビルド → CI の build-swift-5-10
#   - CONTRACT.md のクロスリポ byte-identity → GitHub API が要るので CI のみ
#   - 生成物の鮮度（llms.txt / examples index / shader sources /
#     tutorial snippets / tutorial publication status）→ pre-push フック
#
# NOTE: swiftc のフラグが変わるとビルドキャッシュは作り直しになるので、
# `make build` と交互に走らせると毎回フルリビルドになる。実測で 10 秒台
# （ライブラリ + テスト、Apple Silicon）に収まるため、専用の --scratch-path は
# 設けず CI と同じ .build をそのまま使う。
ci-check:
	@echo "Building with -warnings-as-errors (CI parity)..."
	swift build -Xswiftc -warnings-as-errors
	@echo "Testing with -warnings-as-errors (CI parity)..."
	METAPHOR_REQUIRE_GPU=1 swift test -Xswiftc -warnings-as-errors

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
# 説明をレシピの外（この位置）に置いているのは 2 つの理由による。レシピ本体は `\` 継続行の
# ひとかたまりなので、途中に `#` を挟むと以降が丸ごとシェルコメントに飲まれる。加えて
# scripts/validate-ai-docs.sh が `awk '/^symbol-graphs:/,/^# Generate llms.txt/'` で
# このブロックを読み、`Metaphor*` 語を拾ってモジュール網羅を判定するので、ブロック内に
# 語彙を増やすと網羅判定が鈍る。下の `# Generate llms.txt` は境界なので消さないこと。
symbol-graphs: build
	@echo "Extracting symbol graphs..."
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
	@echo "  make ci-check       - Build + test with CI's -warnings-as-errors (run before pushing)"
	@echo "  make clean          - Clean build artifacts (incl. Examples/**/.build)"
	@echo "  make clean-examples - Remove per-example .build dirs only"
	@echo "  make check          - Check if setup is complete"
	@echo "  make symbol-graphs  - Extract symbol graphs (shared step)"
	@echo "  make llms-txt       - Generate llms.txt (AI API reference)"
	@echo "  make ai-docs-check  - Validate AI-facing docs and llms.txt assumptions"
	@echo "  make contract-schema - Validate wire-schema contract (needs check-jsonschema)"
	@echo "  make lint-workflows - Lint .github/workflows with actionlint (same as CI)"
	@echo "  make lint-python    - Lint scripts/*.py with ruff (same as CI)"
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
	@echo "  make help           - Show this help"
