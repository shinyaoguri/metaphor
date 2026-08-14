#!/usr/bin/env bash
#
# pr-changed-files.sh — 「その枝が変えたファイル」を列挙する。
#
# Usage: scripts/pr-changed-files.sh BASE HEAD [git-diff-args...]
#   例: scripts/pr-changed-files.sh "$BASE_SHA" "$HEAD_SHA" -- 'Sources/*'
#       scripts/pr-changed-files.sh "$BASE_SHA" "$HEAD_SHA" \
#           --diff-filter=A -- 'changelog.d/*.md'
#
# 比較は 3 点表記（BASE...HEAD = merge-base からの差分）。**2 点間 diff にしては
# ならない**（Issue #642）。`github.event.pull_request.base.sha` はその PR の分岐点
# ではなく **イベント発火時点の base ブランチの先端**なので、PR がブランチしたあとに
# main が進むと、2 点間では main 側の変更が「この PR の変更」として混ざる。
#
#   $ git diff --name-only 888c547 498557d -- 'Sources/*'      # 2 点間
#   Sources/MetaphorCore/Export/VideoExporter.swift
#   Sources/MetaphorCore/Sketch/Sketch+Advanced.swift
#   ...                                     # 498557d は docs しか触っていない PR
#   $ git diff --name-only 888c547...498557d -- 'Sources/*'    # 3 点表記
#   （0 件）
#
# これを取り違えると、視覚証跡チェック（Issue #631）は無関係な PR を落とし、
# changelog エントリチェック（Issue #461）は逆に取りこぼす（リリースが消した
# changelog.d/*.md が `--diff-filter=A` に乗るため）。どちらも「ゲートは在るのに
# 効いていない」形で壊れるので、判定側ではなくここで一度だけ正しく取る。
#
# 追加引数は revspec の後ろへそのまま渡す（git はオプションを revspec の後にも
# 受け付ける）。pathspec を渡すときは呼び出し側で `--` を付けること。
#
# base / head が辿れないとき（force push で古い先端が消えた等）は git の終了
# ステータスをそのまま返すので、呼び出し側でフォールバックできる。
#
# 用途: per-PR CI のゲート（ci.yml）。Examples 差分ビルドの列挙は
# changed-examples.sh の管轄で、そちらも同じ 3 点表記。
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 BASE HEAD [git-diff-args...]" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

base="$1"
head="$2"
shift 2

# core.quotePath=false: 非 ASCII を含むパスを "\346\227\245..." へエスケープさせない
# （そのままでは判定側でパスとして扱えなくなる）。
git -c core.quotePath=false diff --name-only "$base...$head" "$@"
