#!/usr/bin/env python3
"""公開 API の doc コメントに日本語が混ざっていないかを検査する。

doc コメントは `llms.txt`（AI 向け API 正典）と DocC の入力で、日本語版
`/reference/ja/` は**英語版から生成**される（ADR-0011）。つまり英語が上流で、
日本語で書くと英語圏の利用者にも AI にも読めないものが正典になる。規約は
docs/doc-comment-style.md が正本。

## なぜ機械で守るのか

PR #361 / #365 が周辺モジュールの doc コメントをいったん英語化したが、**検査が
無かったので静かに戻った** — 2026-08-23 の実測で Audio 34 / MPS 37 / Physics 14 /
Noise 8 = 93 行の日本語が再び入っていた。MetaphorCore に至っては ADR-0011 時点の
8,500 行から 7 日で 10,049 行へ、約 220 行/日 のペースで増えていた（#334）。
文章のルールでは止まらない形の失敗なので、決定論的に落とす。

## 移行中の扱い

Core ほかの英語化は #334 で進行中なので、いま全部を落とすと常時赤になる。
代わりに ALLOWLIST が**モジュールごとに現在の行数を固定**する:

- 増えたら fail（新しい日本語 doc コメントの流入 = 退行を止める）
- 減っても fail（数字を下げてもらう = 進捗が allowlist に現れる）

英語化が終わったモジュールは ALLOWLIST から消す。**全部消えたら ALLOWLIST ごと
削除**して、以降は「Sources に日本語 doc コメントは 1 行も無い」になる。

## 除外されるもの

- `//` の通常コメント（`// MARK:` を含む）— 実装の意図を書いた日本語は残す
- `<!-- reference-shot -->` 印より後ろ — `make reference-shots` の生成物で、alt
  テキストの日本語は scripts/generate-reference-shots.py がそう書いている。手で
  直しても次の撮影で戻るため、生成器を直す #1079 の管轄
- 文字列リテラルとコード（そもそも doc コメント行しか見ない）

使い方（リポジトリルートから）:

    python3 scripts/check-doc-comment-language.py

終了コード: 0 = 想定どおり、1 = ずれている。
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"

# モジュール名 -> (許容する日本語 doc コメント行数, 理由)
#
# #334 の英語化が進むたびに数字を下げ、0 になったら行ごと消す。
# 数字は `python3 scripts/check-doc-comment-language.py` が出す実測値をそのまま置く。
ALLOWLIST: dict[str, tuple[int, str]] = {
    "MetaphorCore": (7255, "#334 で英語化中（レーン単位で進行）。0 になったら行ごと削除する"),
    "MetaphorTestSupport": (111, "product 非公開。GoldenImage.swift が大半"),
    "MetaphorLog": (22, "product 非公開（MetaphorCore が再輸出する診断ログ）"),
}

CJK = re.compile(r"[぀-ゟ゠-ヿ一-鿿]")
REFERENCE_SHOT_MARK = "<!-- reference-shot"


def japanese_doc_lines(text: str) -> list[tuple[int, str]]:
    """日本語を含む doc コメント行を (行番号, 内容) で返す。

    `<!-- reference-shot -->` 印を見つけたら、その doc コメントブロックの残りは
    生成物なので数えない。ブロックの切れ目は「`///` で始まらない行」で判定する
    （Sources に `/** */` は 1 つも無いことを確認済み）。
    """
    found: list[tuple[int, str]] = []
    in_generated_block = False
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        if not stripped.startswith("///"):
            in_generated_block = False
            continue
        if REFERENCE_SHOT_MARK in stripped:
            in_generated_block = True
        if in_generated_block:
            continue
        if CJK.search(line):
            found.append((number, stripped))
    return found


def swift_sources(root: Path = SOURCES) -> list[Path]:
    return sorted(p for p in root.rglob("*.swift") if p.is_file())


def module_of(path: Path, root: Path = SOURCES) -> str:
    return path.relative_to(root).parts[0]


def main() -> int:
    counts: Counter[str] = Counter()
    hits: dict[str, list[str]] = {}
    for path in swift_sources():
        lines = japanese_doc_lines(path.read_text(encoding="utf-8"))
        if not lines:
            continue
        module = module_of(path)
        counts[module] += len(lines)
        rel = path.relative_to(ROOT)
        hits.setdefault(module, []).extend(f"{rel}:{n}: {t}" for n, t in lines)

    failed = False
    for module in sorted(set(counts) | set(ALLOWLIST)):
        actual = counts.get(module, 0)
        expected, reason = ALLOWLIST.get(module, (0, ""))
        if actual == expected:
            continue
        failed = True
        if module not in ALLOWLIST:
            print(
                f"❌ {module}: 日本語の doc コメントが {actual} 行あります"
                "（このモジュールは英語化済みのはずです）",
                file=sys.stderr,
            )
            for line in hits[module][:20]:
                print(f"    {line}", file=sys.stderr)
            if len(hits[module]) > 20:
                print(f"    ... 他 {len(hits[module]) - 20} 行", file=sys.stderr)
        elif actual > expected:
            print(
                f"❌ {module}: 日本語の doc コメントが {expected} → {actual} 行へ"
                f" {actual - expected} 行増えています（退行）",
                file=sys.stderr,
            )
            print(f"    許容理由: {reason}", file=sys.stderr)
        else:
            print(
                f"❌ {module}: 日本語の doc コメントが {expected} → {actual} 行へ減りました。"
                "ALLOWLIST の数字を下げてください",
                file=sys.stderr,
            )
            print(f"        \"{module}\": ({actual}, ...)", file=sys.stderr)

    if failed:
        print("", file=sys.stderr)
        print(
            "doc コメントは英語で書きます（理由と文体は docs/doc-comment-style.md）。",
            file=sys.stderr,
        )
        print(
            "実装の意図を書いた `//` の通常コメントは日本語のままで構いません。",
            file=sys.stderr,
        )
        return 1

    total = sum(counts.values())
    if total:
        print(f"✅ 日本語の doc コメントは移行中の {total} 行のみ（ALLOWLIST と一致）。")
    else:
        print("✅ doc コメントに日本語はありません。ALLOWLIST を削除できます。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
