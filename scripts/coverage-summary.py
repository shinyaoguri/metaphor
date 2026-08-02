#!/usr/bin/env python3
"""llvm-cov の JSON エクスポートをモジュール別カバレッジ表(Markdown)へ集計する。

使い方:

    xcrun llvm-cov export "$TEST_BINARY" \\
        -instr-profile=.build/debug/codecov/default.profdata \\
        -ignore-filename-regex='Tests/|\\.build/' \\
        -format=text > coverage.json
    python3 scripts/coverage-summary.py coverage.json > coverage-modules.md

引数を省略した場合は標準入力から読む。

モジュール名はファイルパスの `Sources/<Module>/...` から取る(SwiftPM のターゲット
ディレクトリ規約)。`Sources/` 配下でないファイルは `(other)` にまとめる。

出力は行カバレッジ(実行された行数 / 実行可能な行数)と関数カバレッジ。
モジュール名でソートするため、同じ入力からは常に同じ出力になる(CI で差分を
取ってもノイズが出ない)。
"""

import json
import sys
from pathlib import PurePosixPath

OTHER = "(other)"


def module_of(filename: str) -> str:
    """ファイルパスから SwiftPM のモジュール名を推定する。"""
    parts = PurePosixPath(filename).parts
    # 末尾側の "Sources" を採用する(チェックアウト先が .../Sources/... に
    # 埋まっていても、パッケージ内の Sources/<Module>/ を正しく拾うため)。
    for i in range(len(parts) - 2, -1, -1):
        if parts[i] == "Sources":
            return parts[i + 1]
    return OTHER


def percent(covered: int, count: int) -> str:
    if count == 0:
        return "n/a"
    return f"{covered / count * 100:.1f}%"


def main() -> int:
    if len(sys.argv) > 2:
        print(f"usage: {sys.argv[0]} [coverage.json]", file=sys.stderr)
        return 2
    if len(sys.argv) == 2:
        with open(sys.argv[1], encoding="utf-8") as f:
            report = json.load(f)
    else:
        report = json.load(sys.stdin)

    # module -> {"lines": [covered, count], "functions": [covered, count]}
    modules: dict[str, dict[str, list[int]]] = {}
    for data in report.get("data", []):
        for entry in data.get("files", []):
            summary = entry.get("summary", {})
            bucket = modules.setdefault(
                module_of(entry.get("filename", "")),
                {"lines": [0, 0], "functions": [0, 0]},
            )
            for kind in ("lines", "functions"):
                stats = summary.get(kind, {})
                bucket[kind][0] += int(stats.get("covered", 0))
                bucket[kind][1] += int(stats.get("count", 0))

    if not modules:
        print("カバレッジデータが空でした(llvm-cov の出力を確認してください)。")
        return 0

    print("## Coverage by module")
    print()
    print("| Module | Lines | Covered | Line % | Func % |")
    print("| --- | ---: | ---: | ---: | ---: |")

    totals = {"lines": [0, 0], "functions": [0, 0]}
    # `(other)` は末尾に置きつつ、それ以外はモジュール名順(決定的)。
    for name in sorted(modules, key=lambda n: (n == OTHER, n)):
        stats = modules[name]
        for kind in ("lines", "functions"):
            totals[kind][0] += stats[kind][0]
            totals[kind][1] += stats[kind][1]
        print(
            f"| {name} | {stats['lines'][1]} | {stats['lines'][0]} "
            f"| {percent(*stats['lines'])} | {percent(*stats['functions'])} |"
        )

    print(
        f"| **Total** | **{totals['lines'][1]}** | **{totals['lines'][0]}** "
        f"| **{percent(*totals['lines'])}** | **{percent(*totals['functions'])}** |"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
