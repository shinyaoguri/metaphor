#!/bin/bash
# swift test のカバレッジをレポート（ファイル別・lcov・モジュール別サマリ）へ
# 集計する。ci.yml の `Coverage Report` ステップの実体。
#
# 実体をスクリプトへ出したのは、この振る舞いを scripts/tests/ で固定するため
# （ワークフローの `run:` は単体で走らせられず、壊れても「次に CI が走ったとき」
# まで分からない）。ローカルからも `./scripts/coverage-report.sh` で同じものを
# 走らせられる。
#
# 経緯（Issue #639）: 下のガードは「カバレッジデータが無ければ warning を出して
# 正常終了する」つもりで書かれていたが、インラインだった頃は **そこへ到達でき
# なかった**。`.build/debug` が無いと find が exit 1 を返し、pipefail 込みで
# `BIN=$(...)` の代入がその終了ステータスを引き継ぐため、`set -e` が次行の if
# より前にステップを落としていた。結果、テストが走らなかった run では原因
# ステップの赤に無関係な赤が 1 つ並び、しかもいちばん要る場面で warning が
# 出なかった。
set -euo pipefail

cd "$(dirname "$0")/.."

# テストから差し替えるためのフック（既定は swift test の出力先と artifact の
# 置き場で、CI もローカルもこの既定で走る）。
BUILD_DIR=${COVERAGE_BUILD_DIR:-.build/debug}
OUT_DIR=${COVERAGE_OUT_DIR:-coverage}

PROF="$BUILD_DIR/codecov/default.profdata"

# -L 必須: .build/debug は .build/arm64-apple-macosx/debug へのシンボリック
# リンクで、追跡しない find は何も返さない（＝これまでレポートは静かに空振り
# していた。下の warning がその再発を可視化する）。
#
# `|| true` 必須: find は探索対象が無いだけでも exit 1 を返す。これが無いと
# 上記のとおり代入の時点で落ちる。「見つからない」と「find 自体の異常」を
# 同じ扱いにするので、どちらも下のガードが warning + skip として拾う。
BIN=$(find -L "$BUILD_DIR" -name 'metaphorPackageTests' -type f 2>/dev/null | head -1 || true)
if [ -z "$BIN" ] || [ ! -f "$PROF" ]; then
    echo "::warning::coverage data not found (tests may have failed before profiling) — skipping report"
    exit 0
fi

mkdir -p "$OUT_DIR"
IGNORE='Tests/|\.build/'
# pipefail: 下の `llvm-cov report | tee` で llvm-cov の失敗を tee に握り潰させない。
xcrun llvm-cov report "$BIN" -instr-profile="$PROF" \
    -ignore-filename-regex="$IGNORE" | tee "$OUT_DIR/coverage-files.txt"
xcrun llvm-cov export "$BIN" -instr-profile="$PROF" \
    -ignore-filename-regex="$IGNORE" -format=lcov > "$OUT_DIR/coverage.lcov"
xcrun llvm-cov export "$BIN" -instr-profile="$PROF" \
    -ignore-filename-regex="$IGNORE" -format=text > "$OUT_DIR/coverage.json"
python3 scripts/coverage-summary.py "$OUT_DIR/coverage.json" \
    > "$OUT_DIR/coverage-modules.md"
cat "$OUT_DIR/coverage-modules.md"

# ジョブ要約は CI でだけ。ローカル実行が `set -u` で落ちないよう存在を見る。
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "$OUT_DIR/coverage-modules.md" >> "$GITHUB_STEP_SUMMARY"
fi
