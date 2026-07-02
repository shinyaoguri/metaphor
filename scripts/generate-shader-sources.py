#!/usr/bin/env python3
"""Shaders/Metal/*.metal から Shaders/ShaderSources/*.txt を生成する。

正典は `.metal`（プリコンパイル用）。`.txt` はランタイムコンパイル /
ホットリロード用の**生成物**で、手で編集しないこと（llms.txt と同じ運用）。

生成規則:
- `Metaphor<Name>.metal` → `<name>.txt`（先頭 1 文字を小文字化。連続大文字の
  頭字語は全体を小文字化: MPSRayTracer → mpsRayTracer）
- ローカル include（`#include "X.h"`）は内容をインライン展開する
  （ランタイムコンパイルはヘッダを解決できないため）。同一ヘッダは 1 回のみ。
- ヘッダのインクルードガード（#ifndef/#define/#endif）は除去する。
- `#include <metal_stdlib>` と `using namespace metal;` は最初の 1 回だけ出力する。

生成は決定的（入力が同じなら出力はバイト単位で同じ）。
`--check` で陳腐化検出（差分があれば exit 1）。
"""

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
METAL_DIR = REPO_ROOT / "Sources/MetaphorCore/Shaders/Metal"
TXT_DIR = REPO_ROOT / "Sources/MetaphorCore/Shaders/ShaderSources"

LOCAL_INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"\s*$')
STDLIB_INCLUDE_RE = re.compile(r'^\s*#include\s+<metal_stdlib>\s*$')
USING_METAL_RE = re.compile(r'^\s*using\s+namespace\s+metal\s*;\s*$')
GUARD_IFNDEF_RE = re.compile(r'^\s*#ifndef\s+\w+_h\s*$')
GUARD_DEFINE_RE = re.compile(r'^\s*#define\s+\w+_h\s*$')
ENDIF_RE = re.compile(r'^\s*#endif\s*.*$')


def txt_name_for(metal_path: Path) -> str:
    base = metal_path.stem
    if base.startswith("Metaphor"):
        base = base[len("Metaphor"):]
    # 先頭の連続大文字（頭字語）は、次に小文字が続く直前まで小文字化する。
    # 例: MPSRayTracer → mpsRayTracer / Canvas3D → canvas3D / Blit → blit
    m = re.match(r'^([A-Z]+)(?=[A-Z][a-z]|$|[0-9])', base)
    if m and len(m.group(1)) > 1:
        head = m.group(1)
        base = head.lower() + base[len(head):]
    else:
        base = base[0].lower() + base[1:]
    return base + ".txt"


def strip_include_guard(lines: list[str]) -> list[str]:
    result = [l for l in lines if not (GUARD_IFNDEF_RE.match(l) or GUARD_DEFINE_RE.match(l))]
    # 末尾側の最後の #endif（ガードの閉じ）を 1 つだけ除去
    for i in range(len(result) - 1, -1, -1):
        if ENDIF_RE.match(result[i]):
            del result[i]
            break
        if result[i].strip():
            break
    return result


def expand(path: Path, state: dict) -> list[str]:
    out: list[str] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if path.suffix == ".h":
        lines = strip_include_guard(lines)

    for line in lines:
        local = LOCAL_INCLUDE_RE.match(line)
        if local:
            header = METAL_DIR / local.group(1)
            if header.name in state["included"]:
                continue
            state["included"].add(header.name)
            if not header.is_file():
                sys.exit(f"error: {path.name}: missing local include {header.name}")
            out.extend(expand(header, state))
            continue
        if STDLIB_INCLUDE_RE.match(line):
            if state["stdlib_emitted"]:
                continue
            state["stdlib_emitted"] = True
            out.append("#include <metal_stdlib>")
            continue
        if USING_METAL_RE.match(line):
            if state["using_emitted"]:
                continue
            state["using_emitted"] = True
            out.append("using namespace metal;")
            continue
        out.append(line)
    return out


def generate(metal_path: Path) -> str:
    state = {"included": set(), "stdlib_emitted": False, "using_emitted": False}
    body = expand(metal_path, state)
    text = "\n".join(body).rstrip("\n") + "\n"
    if not state["stdlib_emitted"]:
        text = "#include <metal_stdlib>\nusing namespace metal;\n\n" + text
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="生成せず、既存の .txt が最新かを検証する（差分で exit 1）")
    args = parser.parse_args()

    metal_files = sorted(METAL_DIR.glob("Metaphor*.metal"))
    if not metal_files:
        sys.exit("error: no .metal files found")

    stale: list[str] = []
    for metal_path in metal_files:
        txt_path = TXT_DIR / txt_name_for(metal_path)
        generated = generate(metal_path)
        current = txt_path.read_text(encoding="utf-8") if txt_path.is_file() else None
        if args.check:
            if current != generated:
                stale.append(f"{txt_path.relative_to(REPO_ROOT)} (from {metal_path.name})")
        elif current != generated:
            txt_path.write_text(generated, encoding="utf-8")
            print(f"generated {txt_path.relative_to(REPO_ROOT)}")

    if args.check and stale:
        print("error: shader sources are stale. Run: python3 scripts/generate-shader-sources.py",
              file=sys.stderr)
        for s in stale:
            print(f"  {s}", file=sys.stderr)
        return 1

    if args.check:
        print(f"shader sources up to date ({len(metal_files)} pairs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
