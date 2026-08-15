#!/usr/bin/env python3
"""Shaders/Metal/ から 2 系統の生成物を作る。

正典は `.metal` / `.h`。生成物は手で編集しないこと（llms.txt と同じ運用）。

1. `Shaders/ShaderSources/*.txt` — ランタイムコンパイル / ホットリロード用。
2. `Shaders/BuiltinShaders+Generated.swift` — ユーザーのカスタムマテリアル
   シェーダーへ配る MSL 前文（`BuiltinShaders.canvas3DStructs` /
   `canvas3DLightingFn` の実体）。以前は Swift の文字列リテラルとして手書き
   されており、`.h` と二重管理になっていた（#707）。

生成規則:
- `Metaphor<Name>.metal` → `<name>.txt`（先頭 1 文字を小文字化。連続大文字の
  頭字語は全体を小文字化: MPSRayTracer → mpsRayTracer）
- ローカル include（`#include "X.h"`）は内容をインライン展開する
  （ランタイムコンパイルはヘッダを解決できないため）。同一ヘッダは 1 回のみ。
- ヘッダのインクルードガード（#ifndef/#define/#endif）は除去する。
- `#include <metal_stdlib>` と `using namespace metal;` は最初の 1 回だけ出力する。
- 前文（Swift）は `SWIFT_PRELUDES` の 1 ヘッダから展開する。stdlib と
  `using namespace metal;` は**出力しない**（利用者が自分で書く前提）。

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
SWIFT_PRELUDE_PATH = REPO_ROOT / "Sources/MetaphorCore/Shaders/BuiltinShaders+Generated.swift"

# Swift 定数名 → (ルートヘッダ, 展開済みとして扱うヘッダ, ガードマクロ, 由来の説明)
#
# ルートは**必ず 1 本**にする。`expand()` はルート自身を「展開済み」に登録しない
# ため、推移的に include されるヘッダ（例: MetaphorLighting.h → MetaphorPBR.h）を
# 一緒に並べると二重展開になり、MSL が二重定義でコンパイル不能になる。
#
# ガードマクロは前文が**二重に前置されても壊れない**ようにするためのもの（#713）。
# `createMaterial()` が前文を必ず足すようになった一方、以前の作法どおり自分で
# `BuiltinShaders.canvas3DStructs` を前置しているソースも動き続ける必要がある。
SWIFT_PRELUDES = [
    (
        "canvas3DStructs",
        "MetaphorCanvas3DTypes.h",
        (),
        "METAPHOR_PRELUDE_CANVAS3D_STRUCTS",
        "MetaphorCanvas3DTypes.h",
    ),
    (
        "canvas3DLightingFn",
        "MetaphorLighting.h",
        ("MetaphorCanvas3DTypes.h",),  # 構造体は canvas3DStructs 側が配る
        "METAPHOR_PRELUDE_CANVAS3D_LIGHTING",
        "MetaphorLighting.h（MetaphorPBR.h / MetaphorToneMapping.h を推移的に含む）",
    ),
]

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


def generate_prelude(root: str, preincluded: tuple, guard: str) -> str:
    """`.h` 1 本を展開して、カスタムシェーダ前文の本文を返す。

    `generate()` は通さない（あちらは stdlib が 1 度も出なければ先頭に補うので、
    前文の頭に `#include <metal_stdlib>` が生えてしまう）。ここでは stdlib と
    `using namespace metal;` を「出力済み」と種蒔きして、どちらも落とす。

    出力はインクルードガードで包む。`createMaterial()` は前文を必ず前置するので、
    以前の作法どおり自分でも前置しているソースでは前文が 2 回現れる。ガードが
    無いと MSL が構造体の二重定義で落ちる（#713）。
    """
    path = METAL_DIR / root
    if not path.is_file():
        sys.exit(f"error: missing prelude header {root}")
    state = {
        "included": set(preincluded),
        "stdlib_emitted": True,
        "using_emitted": True,
    }
    body = "\n".join(expand(path, state)).strip("\n")
    return f"#ifndef {guard}\n#define {guard}\n\n{body}\n\n#endif"


SWIFT_FILE_HEADER = '''\
// このファイルは生成物です。手で編集しないでください。
//
// 生成元: Sources/MetaphorCore/Shaders/Metal/*.h
// 再生成: python3 scripts/generate-shader-sources.py
//
// 公開 API（`BuiltinShaders.canvas3DStructs` など）とその doc コメントは
// `BuiltinShaders.swift` 側にあります。ここが持つのは中身だけです。

/// ``BuiltinShaders`` が公開する MSL 前文の実体。
///
/// 組み込みシェーダーと同じ `Shaders/Metal/*.h` から生成されるので、ライティングの
/// 実装を直せばカスタムマテリアルシェーダーへ配られる前文も一緒に動きます（#707）。
///
/// 各定数は `#ifndef` ガードで包まれています。``BuiltinShaders/canvas3DPreamble`` は
/// `createMaterial()` が必ず前置するので、以前の作法どおり自分でも前置している
/// ソースでは前文が 2 回現れます。ガードが 2 回目を空にします（#713）。
///
/// 定数そのものは `#include <metal_stdlib>` と `using namespace metal;` を持ちません
/// （それらを足した完全な前文が ``BuiltinShaders/canvas3DPreamble``）。
enum BuiltinShadersGenerated {
'''


def generate_swift_preludes() -> str:
    parts = [SWIFT_FILE_HEADER]
    for name, root, preincluded, guard, origin in SWIFT_PRELUDES:
        payload = generate_prelude(root, preincluded, guard)
        # raw string リテラルを閉じてしまう並びが入ると、生成された Swift が
        # 静かに壊れる（今の `.h` には無いが、将来の追記で踏みうる）。
        for forbidden in ('"""#', '\\#'):
            if forbidden in payload:
                sys.exit(f"error: {root}: prelude must not contain {forbidden!r}")
        parts.append(f"\n    /// 生成元: {origin}\n")
        # payload と閉じデリミタはどちらも 0 桁に置く。Swift は閉じデリミタの
        # インデント量を全行から剥がすので、字下げするとインデントの浅い行で落ちる。
        parts.append(f'    static let {name} = #"""\n{payload}\n"""#\n')
    parts.append("}\n")
    return "".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="生成せず、既存の生成物が最新かを検証する（差分で exit 1）")
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

    swift_generated = generate_swift_preludes()
    swift_current = (SWIFT_PRELUDE_PATH.read_text(encoding="utf-8")
                     if SWIFT_PRELUDE_PATH.is_file() else None)
    if args.check:
        if swift_current != swift_generated:
            stale.append(f"{SWIFT_PRELUDE_PATH.relative_to(REPO_ROOT)} (from Metal/*.h)")
    elif swift_current != swift_generated:
        SWIFT_PRELUDE_PATH.write_text(swift_generated, encoding="utf-8")
        print(f"generated {SWIFT_PRELUDE_PATH.relative_to(REPO_ROOT)}")

    if args.check and stale:
        print("error: generated shader sources are stale. "
              "Run: python3 scripts/generate-shader-sources.py",
              file=sys.stderr)
        for s in stale:
            print(f"  {s}", file=sys.stderr)
        return 1

    if args.check:
        print(f"shader sources up to date ({len(metal_files)} pairs "
              f"+ {len(SWIFT_PRELUDES)} Swift preludes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
