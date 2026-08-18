#!/usr/bin/env python3
"""`Sources/` に生の `print()` が再流入するのを止める（Issue #896 / #805）。

`Sources/MetaphorLog/Log.swift` の規約は「stdout はライブラリの出力チャネル
（metaphor-cli との JSON Lines）と共有しているので、**Release でも出るものは必ず
stderr へ書く。素の `print()` は使わない**」。#805 でその 3 関数
（`metaphorWarning` / `metaphorAlert` / `metaphorDiagnostic`）を切り出したあとも、
`Sources/` には生の `print("[metaphor] …")` が 17 箇所残っていた（#896）。規約は
書いてあったのに残った ＝ 文章では止まらない、という形の失敗なので、決定論的に
落とすチェックをここに置く。

## なぜ `print("[metaphor` の grep ではないのか

#896 の一覧は `grep 'print("\\[metaphor'` で作られていて、**複数行文字列の
`print(\"\"\"` は取りこぼしていた**（`Canvas2D.swift` / `Canvas2DPipelineStore.swift`
の 2 箇所は、次の行が `[metaphor] …` で始まる同じ形の生 print だった）。タグの
綴り（`[metaphor.CoreImage]` / `[MetaphorVideo]`）にも割れがあり、タグを含まない
`print("Failed …")` は最初から素通りする。守りたいのは「タグの綴り」ではなく
「stdout へ生で書かないこと」なので、**`Sources/` の生 `print(` を全部禁じて
例外を明示する**形にしてある。例外は下の ALLOWLIST が全てで、増えるときは
理由を書く（＝レビューで見える）。

## 除外されるもの

- コメント（`//` / `///`）と複数行文字列リテラルの中身 — 利用者向けの doc に
  出てくる `print(cam.name)` のような**サンプルコード**は正しい書き方であって、
  ライブラリ自身の出力ではない
- ALLOWLIST のファイル（理由つき）

使い方（リポジトリルートから）:

    python3 scripts/check-no-raw-print.py

終了コード: 0 = 生 print なし、1 = 見つかった。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"

# 生の print() を許すファイルと、その理由。**ここに足すのは最後の手段**で、
# 足すなら「なぜ 3 関数のどれでもないのか」を書くこと。
ALLOWLIST: dict[str, str] = {
    # 3 関数の実体。metaphorWarning は DEBUG 限定の stdout 出力なので print を使う。
    "Sources/MetaphorLog/Log.swift": "診断ログ 3 関数の実装そのもの",
    # ゴールデン画像比較のテストログ。ライブラリの実行時出力ではなく
    # `swift test` のコンソールへ出す実測値で、stdout に出るのが正しい。
    "Sources/MetaphorTestSupport/GoldenImage.swift": "テスト実行時の実測ログ（[golden]）",
    # Tier 1 のモジュールローカルな警告ヘルパ。MetaphorLog へ寄せる作業は
    # #896 のスコープ外として Issue #989 に分けてある（解決したらこの 3 行を消す）。
    "Sources/MetaphorAudio/Log.swift": "モジュールローカルの警告ヘルパ（Issue #989 で MetaphorLog へ寄せる）",
    "Sources/MetaphorNetwork/Log.swift": "モジュールローカルの警告ヘルパ（Issue #989 で MetaphorLog へ寄せる）",
    "Sources/MetaphorVideo/Log.swift": "モジュールローカルの警告ヘルパ（Issue #989 で MetaphorLog へ寄せる）",
}

# `print(` / `Swift.print(` / `debugPrint(`。`foo.print()`（Combine のオペレータ）は
# 対象外にしたいので、直前の 1 文字から `.` と識別子文字を除く。`Swift.` だけは
# 明示的に通す（`Swift.print(` は生の print と同じもの）。
PRINT_CALL = re.compile(r"(?:^|[^\w.])(?:Swift\.print|debugPrint|print)\s*\(")


def code_segments(line: str, in_multiline: bool) -> tuple[list[str], bool]:
    """行から「コードの部分」だけを取り出す（複数行文字列の中身を落とす）。

    `print(\"\"\"` は開き括弧が `\"\"\"` の**手前**にあるので、開始行はコードとして
    残る（＝検出できる）。中身の行と閉じ行は落ちる。

    - Parameters:
      - line: 対象行。
      - in_multiline: この行の先頭時点で複数行文字列の中にいるか。
    - Returns: (コード片のリスト, この行の末尾時点で複数行文字列の中にいるか)
    """
    segments: list[str] = []
    rest = line
    while True:
        idx = rest.find('"""')
        if idx == -1:
            if not in_multiline:
                segments.append(rest)
            break
        if in_multiline:
            rest = rest[idx + 3 :]
            in_multiline = False
        else:
            segments.append(rest[:idx])
            rest = rest[idx + 3 :]
            in_multiline = True
    return segments, in_multiline


def strip_comment(segment: str) -> str:
    """行コメント（`//` / `///`）以降を落とす。

    文字列リテラルの中の `//`（URL など）で切ってしまうことはあるが、それで
    起きるのは見逃しだけで誤検出にはならない（`print(` は `//` より手前にある）。
    """
    idx = segment.find("//")
    return segment if idx == -1 else segment[:idx]


def find_raw_prints(text: str) -> list[tuple[int, str]]:
    """Swift ソース 1 ファイル分のテキストから生 print の (行番号, 行) を返す。"""
    found: list[tuple[int, str]] = []
    in_multiline = False
    for lineno, line in enumerate(text.splitlines(), start=1):
        segments, in_multiline = code_segments(line, in_multiline)
        if any(PRINT_CALL.search(strip_comment(seg)) for seg in segments):
            found.append((lineno, line.strip()))
    return found


def swift_sources(root: Path = SOURCES) -> list[Path]:
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
        for lineno, line in find_raw_prints(path.read_text(encoding="utf-8")):
            violations.append(f"{rel}:{lineno}: {line}")

    if not violations:
        return 0

    print("::error::Sources/ に生の print() があります（Issue #896 / #805）")
    for violation in violations:
        print(f"  {violation}")
    print(
        "\n"
        "stdout は metaphor-cli との JSON Lines と同じチャネルなので、Release でも出る\n"
        "ものを print() で書くと契約側のパースを壊しうる。次のどれかへ寄せること\n"
        "（使い分けの正本は Sources/MetaphorLog/Log.swift の表）:\n"
        "\n"
        "  metaphorWarning(_:)     stdout / DEBUG のみ         ユーザーのコードが誤っている\n"
        "  metaphorAlert(_:)       stderr / 常に               正しいのに環境都合で黙って動かない\n"
        "  metaphorDiagnostic(_:)  stderr / METAPHOR_DEBUG=1   無視してよいが切り分けたい\n"
        "\n"
        "どれでもない正当な print なら scripts/check-no-raw-print.py の ALLOWLIST へ\n"
        "理由つきで追加する。",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
