#!/bin/bash
# scripts/ ほかの Python を ruff（pyflakes 相当の `F` 規則）で検証する。
#
# 未使用 import は動かないわけではないので、レビューでも CI でも素通りする。
# 実害は読むときに出る — import 行は「このスクリプトが何に依存しているか」の
# 要約として読まれるので、使っていないものが並んでいると共通化の範囲を読み違える。
# 実際 #1021 で shots_common.py へ寄せたとき、残っていた import が**移設し忘れ
# なのか元から不要なのか**その場で判断できず、git で前の版と突き合わせる羽目に
# なった（Issue #1022）。文章では止まらない形の失敗なので、決定論的に落とす。
#
# 規則は F401（未使用 import）だけに絞らず `F` 全体を選ぶ。導入時点で F 全体が
# クリーンだったので絞る理由がなく、F821（未定義名）や F811（再定義で潰れた定義）
# は未使用 import より実害が大きい。
#
# CI からもローカルからも同じバージョンで走らせるため、実体はこのスクリプト
# 1 本にまとめてある（ci.yml と `make lint-python` の両方がこれを呼ぶ）。
# check-no-raw-print.py などが素の python3 で済んでいるのは stdlib だけで
# 書かれているからで、外部ツールを使うこの検査は lint-workflows.sh 側の系列。
set -euo pipefail

cd "$(dirname "$0")/.."

# 更新は dependabot ではなく手動。lint の指摘が増減してある日突然 CI が赤く
# なるのを避ける（actionlint / check-jsonschema のピン留めと同じ方針）。
RUFF_VERSION="0.16.4"

# lint-workflows.sh と同じ置き場。.build/ は gitignore 済み。
VENV_DIR=".build/tools/ruff-venv"
RUFF="$VENV_DIR/bin/ruff"
STAMP="$VENV_DIR/.version"

# バージョンが一致していれば作り直さない（毎回 pip install すると数秒かかる）。
if [ ! -x "$RUFF" ] || [ "$(cat "$STAMP" 2>/dev/null || true)" != "$RUFF_VERSION" ]; then
    echo "Installing ruff ${RUFF_VERSION}..."
    rm -rf "$VENV_DIR"
    mkdir -p "$(dirname "$VENV_DIR")"
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --quiet --disable-pip-version-check "ruff==${RUFF_VERSION}"
    echo "$RUFF_VERSION" > "$STAMP"
fi

# 対象は git が追跡している .py だけ。ディレクトリ決め打ちにすると、
# scripts/__pycache__ や各 example の .build/ を踏むうえ、scripts/ の外にある
# ファイル（design/logo/3d/）を取りこぼす。
#
# --isolated = 設定ファイルを探索しない。pyproject.toml を置かずに済み、
# 手元に紛れ込んだ設定で CI と結果がずれることもない。
git ls-files -z '*.py' \
    | xargs -0 "$RUFF" check --isolated --select F --output-format concise
