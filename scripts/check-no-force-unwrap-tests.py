#!/usr/bin/env python3
"""`Tests/` に `MetalTestHelper.<何か>!` が戻ってくるのを止める（Issue #1171 / #1003）。

## なぜ守るのか

#1003 は、GPU テストの強制アンラップが **nil を踏んだ瞬間にテストプロセスごと落とす**
ことを実測しました。1 件の赤ではなく、同時に走っていた 59 件が 1 件も判定を出さずに
全滅し、`gh run rerun --failed` も効きません。#1172 が 119 箇所を潰し、
`MetalTestHelper.commandQueue()` は `throws -> MTLCommandQueue`（非 Optional）に
なったので `commandQueue()!` は**型で**書けなくなりました。

一方 `MetalTestHelper.device` の Optional は `isGPUAvailable`（= `device != nil`）という
**ゲートそのもの**なので非 Optional にできません。つまり `MetalTestHelper.device!` は
今後もコンパイルが通り、レビューでしか捕まりません。99 箇所を潰した直後の状態を
維持するには、型の外に守りが要ります。

`makeTexture(...)` も同じ扱いにします。こちらは `MTLTexture?` を返す**都度の確保**で、
`isGPUAvailable` のゲートは成功をまったく保証しません（#1003 で実際に落ちたのは
`commandQueue()` という、まさにこの「都度の確保」でした）。

## なぜ `.swift-format` の `NeverForceUnwrap` ではないのか

**swift-format は `@Test` 属性の付いた関数の本体を `NeverForceUnwrap` の対象から外します**
（swift-format 6.3.0 で実測。関数名が `test` で始まるかどうかは無関係で、`@Test` が
付いているかどうかで決まる）。`Tests/.swift-format` に `NeverForceUnwrap: true` を置く案は、
設定のディレクトリ遡り自体は効くものの、**#1171 が止めたい「`@Test` の中に書かれた
`MetalTestHelper.device!`」をまるごと素通り**します。

実測（`NeverForceUnwrap: true` を有効にした lint と grep の対比）:

- `Tests/metaphorTests/ComputeTests.swift` — grep 13 箇所 / lint 報告 0 件（全部 `@Test` の中）
- `Tests/metaphorTests/DrawingTests.swift` — grep 13 箇所 / lint 報告 3 件（`private func` の中だけ）
- `Tests/` 全体 — grep 270 箇所 / lint 報告 48 件
- `NeverUseForceTry: true` にしても `try!` 18 箇所の報告は 0 件

`scripts/lint-swift.sh` に lint モードを足すか（#1074）とは独立に穴が残るので、
判定規則を自分で持つこちらの形にしてあります。前例は `check-no-raw-print.py`（#896）。

## 対象範囲（絞ってある。広げなかった理由も含めて）

見るのは **`Tests/**/*.swift` の `MetalTestHelper.<何か>!` だけ**です。現時点で 0 件なので、
既存コードに借金を作らずに入れられます。

意図的に対象外にしたもの:

- `MTLCreateSystemDefaultDevice()!`（230 箇所）と `<device>.makeCommandQueue()!`（40 箇所）
  — ヘルパを経由せず直接 Metal を取る書き方。**`makeCommandQueue()!` は #1003 が実際に
  踏んだ形そのもの**（都度の確保で、`device != nil` のゲートは成功を保証しない）ですが、
  270 箇所をいま直さずに禁止すると ALLOWLIST が約 30 ファイル分の例外表になり、
  「規則を入れた」ではなく「例外を並べた」になります。Issue #1178 に分けました。
- `#expect(v0!.x == 10)` のような、テスト対象の Optional をその場で開く `!`
  — 落ちても**その 1 件が赤くなるだけ**で、#1003 の故障モード（プロセスごと全滅）とは別物です。

使い方（リポジトリルートから）:

    python3 scripts/check-no-force-unwrap-tests.py

終了コード: 0 = 違反なし、1 = 見つかった。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "Tests"

# 強制アンラップを許すファイルと、その理由。**ここに足すのは最後の手段**です。
# `try #require(...)` は Swift Testing の `@Test`／`throws` なヘルパのどちらからでも
# 書けるので、「書けなかった」は理由になりません。足すなら「なぜ 1 件の赤で
# 済ませられないのか」を書くこと。
#
# 空のまま保つのが正常です（#1172 が 99 箇所を 0 にした状態の維持がこの検査の目的）。
ALLOWLIST: dict[str, str] = {}

# 強制アンラップの根に置く型。ここを起点に `.member` / `(...)` / `[...]` の連なりを
# 追って、末尾が `!` なら違反とする。
HELPER = "MetalTestHelper"

_ROOT_RE = re.compile(rf"\b{HELPER}\b")
_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_CLOSERS = {"(": ")", "[": "]"}


def strip_noncode(text: str) -> str:
    """コメントと文字列リテラルを空白へ潰す（行番号と桁は保つ）。

    テストの中の説明コメント（`// MetalTestHelper.device! は書かない` など）や
    文字列リテラルを違反として数えないため。改行はそのまま残すので、返り値の
    行番号は原文と一致する。

    落とすもの: `//` 行コメント / `/* */` ブロックコメント（Swift はネスト可）/
    `\"\"\"` 複数行文字列 / `\"...\"` 文字列リテラル（`\\\"` のエスケープを見る）。

    - Parameters:
      - text: Swift ソース 1 ファイル分。
    - Returns: 非コード部分を空白に置き換えた同じ長さの文字列。
    """
    out: list[str] = []
    i, n = 0, len(text)
    depth = 0  # /* */ のネスト段数

    def blank(chunk: str) -> str:
        return "".join(c if c == "\n" else " " for c in chunk)

    while i < n:
        if depth > 0:
            if text.startswith("/*", i):
                depth += 1
                out.append("  ")
                i += 2
            elif text.startswith("*/", i):
                depth -= 1
                out.append("  ")
                i += 2
            else:
                out.append(blank(text[i]))
                i += 1
            continue

        if text.startswith("/*", i):
            depth = 1
            out.append("  ")
            i += 2
        elif text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end == -1 else end
            out.append(blank(text[i:end]))
            i = end
        elif text.startswith('"""', i):
            end = text.find('"""', i + 3)
            end = n if end == -1 else end + 3
            out.append(blank(text[i:end]))
            i = end
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(blank(text[i:j]))
            i = j
        else:
            out.append(text[i])
            i += 1

    return "".join(out)


def _skip_balanced(text: str, i: int) -> int:
    """`text[i]` の開き括弧に対応する閉じ括弧の**次**の位置を返す（無ければ -1）。"""
    opener = text[i]
    closer = _CLOSERS[opener]
    depth = 0
    while i < len(text):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1


def _chain_end_is_force_unwrap(text: str, i: int) -> int:
    """`MetalTestHelper` の直後 `i` から続く連なりを追い、`!` で終わるなら `!` の位置。

    `.device` / `.commandQueue()` / `.makeTexture(width: 8)` / `[0]` のような
    メンバ参照・呼び出し・添字の連なりを、改行をまたいでも追う。末尾が `!`
    （`!=` ではない）なら強制アンラップ。そうでなければ -1。
    """
    n = len(text)
    while i < n:
        while i < n and text[i] in " \t\n\r":
            i += 1
        if i >= n:
            return -1
        ch = text[i]
        if ch == ".":
            i += 1
            while i < n and text[i] in " \t\n\r":
                i += 1
            m = _IDENT_RE.match(text, i)
            if not m:
                return -1
            i = m.end()
        elif ch in _CLOSERS:
            i = _skip_balanced(text, i)
            if i == -1:
                return -1
        elif ch == "!":
            # `!=` は比較（`MetalTestHelper.device != nil`）であって強制アンラップではない。
            return -1 if text.startswith("!=", i) else i
        else:
            return -1
    return -1


def find_force_unwraps(text: str) -> list[tuple[int, str]]:
    """Swift ソース 1 ファイル分から `MetalTestHelper…!` の (行番号, 行) を返す。"""
    code = strip_noncode(text)
    found: list[tuple[int, str]] = []
    lines = text.splitlines()
    for match in _ROOT_RE.finditer(code):
        bang = _chain_end_is_force_unwrap(code, match.end())
        if bang == -1:
            continue
        # 起点ではなく `!` の行を報告する（複数行にまたがる呼び出しでは、
        # 直すべき場所は `!` の側にある）。
        lineno = code.count("\n", 0, bang) + 1
        found.append((lineno, lines[lineno - 1].strip() if lineno <= len(lines) else ""))
    return found


def swift_sources(root: Path = TESTS) -> list[Path]:
    """検査対象の Swift ファイル（ALLOWLIST を除く）。"""
    files = []
    for path in sorted(root.rglob("*.swift")):
        rel = path.relative_to(ROOT).as_posix()
        if rel in ALLOWLIST:
            continue
        files.append(path)
    return files


def main() -> int:
    violations: list[str] = []
    for path in swift_sources():
        rel = path.relative_to(ROOT).as_posix()
        for lineno, line in find_force_unwraps(path.read_text(encoding="utf-8")):
            violations.append(f"{rel}:{lineno}: {line}")

    if not violations:
        return 0

    print(f"::error::Tests/ に {HELPER} の強制アンラップがあります（Issue #1171 / #1003）")
    for violation in violations:
        print(f"  {violation}")
    print(
        "\n"
        "`!` が nil を踏むとテストプロセスごと落ち、同時に走っていたテストが 1 件も\n"
        "判定を出さずに全滅します（#1003 の実測では 59 件）。`gh run rerun --failed`\n"
        "も効きません。1 件の赤で済む形へ寄せてください:\n"
        "\n"
        "  let device = try #require(MetalTestHelper.device)\n"
        "  let texture = try #require(MetalTestHelper.makeTexture())\n"
        "\n"
        "`@Suite(.enabled(if: MetalTestHelper.isGPUAvailable))` のゲートが保証するのは\n"
        "`device != nil` だけで、makeTexture のような**都度の確保**の成功は保証しません。\n"
        "\n"
        "どうしても外せない事情があるなら scripts/check-no-force-unwrap-tests.py の\n"
        "ALLOWLIST へ理由つきで追加してください（空のまま保つのが正常です）。",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
