#!/usr/bin/env bash
#
# changed-llms-inputs.sh — 「その枝が llms.txt の入力を変えたか」を列挙する。
#
# Usage: scripts/changed-llms-inputs.sh BASE HEAD
#   例: scripts/changed-llms-inputs.sh "$BASE_SHA" "$HEAD_SHA"
#
# 出力が空でなければ llms.txt の鮮度検査（`make llms-txt` して差分を見る）を回す。
# 入力は 3 つ:
#
#   - Sources/**/*.swift            API 面そのもの
#   - scripts/generate-llms-txt.py  生成器
#   - Makefile                      `llms-txt: symbol-graphs` のレシピ
#
# **Makefile が入力なのは自明でない**。生成器は Python なので `scripts/` だけを見て
# しまいがちだが、`make llms-txt` は `make symbol-graphs`（swift symbolgraph-extract の
# 起動）に依存していて、そのレシピは Makefile が持つ。ここを壊す変更は llms.txt を
# 生成できなくするのに、`Sources/` にも生成器にも触っていない（Issue #995）。
#
# 実例: PR #993 は symbol-graphs レシピだけを直したが、pre-push の `make llms-txt` は
# 一度も走らなかった。逆向きも同じで、レシピを壊した PR は緑のまま通り、**次に
# Sources/ を触った無関係な PR** のところで初めて push が止まる。原因のコミットと
# 症状の出る場所が離れるので、#935 は「build も test も green なのに push だけ通らない」
# という分かりにくい形になった。
#
# このリストが 1 箇所に居るのは、以前 pre-push（scripts/hooks/pre-push）と per-PR CI
# （.github/workflows/ci.yml）が同じリストを別々に持っていて、片方だけ直すとそこから
# ドリフトしたため。**新しい入力を足すときはここだけを直す**。
#
# CI 側ではこの判定が DocC の警告検査（`make docs-check`）の起動にも使われる。
# docs-check も symbol-graphs 依存なので入力は同じで、カタログ（*.docc/**）の分だけ
# 呼び出し側が足している。
#
# 比較は 3 点表記。理由と落とし穴は scripts/pr-changed-files.sh が正本で、ここは
# pathspec を与えて委譲するだけ。base / head が辿れないときの終了ステータスも
# そのまま返すので、呼び出し側でフォールバックできる。
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 BASE HEAD" >&2
  exit 2
fi

exec "$(dirname "$0")/pr-changed-files.sh" "$1" "$2" -- \
  'Sources/**/*.swift' 'scripts/generate-llms-txt.py' 'Makefile'
