#!/usr/bin/env bash
#
# changed-examples.sh — 変更された example パッケージのディレクトリを列挙する。
#
# Usage: scripts/changed-examples.sh [BASE [HEAD]]
#   BASE 省略時は origin/main、HEAD 省略時は HEAD。
#   比較は 3 点表記（BASE...HEAD = merge-base からの差分）なので、BASE 側が
#   進んでいても「この枝が変えた example」だけが出る。
#
# 出力はリポジトリルートからの相対パス（例: Examples/Basics/Form/ShapePrimitives）を
# 1 行 1 件、ソート済み・重複排除で返す。差分に現れた各ファイルからディレクトリを
# 遡り、最初に見つかった Package.swift の位置をパッケージルートとみなす
# （Examples/ の階層は 2〜4 段と一定でないため、固定の深さでは切り出せない）。
#
# 削除された example は Package.swift が残っていないので出力されない（ビルド不能）。
#
# 用途: per-PR CI の Examples 差分ビルド（ci.yml の examples-diff ジョブ / Issue #329）。
# 全 278 本のスイープは examples-sweep.yml の管轄。
set -euo pipefail

cd "$(dirname "$0")/.."

base="${1:-origin/main}"
head="${2:-HEAD}"

# core.quotePath=false: 非 ASCII を含むパスを "\346\227\245..." へエスケープさせない
# （そのままではディレクトリ名として使えなくなる）。
git -c core.quotePath=false diff --name-only "$base...$head" -- Examples/ |
  while IFS= read -r file; do
    dir="$(dirname "$file")"
    while [ "$dir" != "Examples" ] && [ "$dir" != "." ] && [ "$dir" != "/" ]; do
      if [ -f "$dir/Package.swift" ]; then
        printf '%s\n' "$dir"
        break
      fi
      dir="$(dirname "$dir")"
    done
  done | sort -u
