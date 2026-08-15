#!/usr/bin/env python3
"""Unit tests for scripts/generate-shader-sources.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

このスクリプトは 2 系統の生成物を作る。`.txt`（ランタイムコンパイル用）と、
カスタムマテリアルシェーダーへ配る Swift の MSL 前文（#707）。後者は
**公開 API の値**なので、生成規則が壊れると利用者のシェーダーが黙って
コンパイル不能になる。

「生成物が最新か」の `--check` は自己整合なので規則そのものを守れない
（DEVELOPMENT.md「生成物の管理」）。ここで固定するのは:

- ローカル include の展開規則（インクルードガード除去・同一ヘッダ 1 回）と、
  **ルートを複数並べると二重展開になる**という前文マニフェストの制約
- 前文には stdlib / `using namespace metal;` を出さないこと
- 前文が**ガードで包まれている**こと（二重に前置されても壊れない・#713）
- 生成 Swift が複数行リテラルとして成立する形（インデント剥がしに耐える）
- 前文の割り当て（構造体は canvas3DStructs 側、関数は canvas3DLightingFn 側、
  postFX の型は postProcessStructs 側）
"""

import importlib.util
import re
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-shader-sources.py"
_spec = importlib.util.spec_from_file_location("generate_shader_sources", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_shader_sources"] = gen
_spec.loader.exec_module(gen)

REPO_ROOT = Path(__file__).resolve().parents[2]


class TxtNameTests(unittest.TestCase):
    """`.metal` → `.txt` の命名規則。"""

    def test_strips_prefix_and_lowercases_head(self):
        self.assertEqual(gen.txt_name_for(Path("MetaphorBlit.metal")), "blit.txt")
        self.assertEqual(gen.txt_name_for(Path("MetaphorCanvas3D.metal")), "canvas3D.txt")

    def test_acronym_head_is_lowercased_as_a_whole(self):
        self.assertEqual(gen.txt_name_for(Path("MetaphorMPSRayTracer.metal")), "mpsRayTracer.txt")


class ExpandRuleTests(unittest.TestCase):
    """一時ディレクトリの擬似ヘッダで、include 展開の規則を固定する。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self._saved_metal_dir = gen.METAL_DIR
        gen.METAL_DIR = self.dir
        self.addCleanup(self._restore)

    def _restore(self):
        gen.METAL_DIR = self._saved_metal_dir
        self._tmp.cleanup()

    def write(self, name, text):
        (self.dir / name).write_text(text, encoding="utf-8")

    def prelude(self, root, preincluded=(), guard="GUARD"):
        return gen.generate_prelude(root, preincluded, guard)

    def test_include_guard_is_stripped_and_body_inlined_once(self):
        self.write("Leaf.h", "#ifndef Leaf_h\n#define Leaf_h\nstruct Leaf { int a; };\n#endif\n")
        self.write("Mid.h", '#ifndef Mid_h\n#define Mid_h\n#include "Leaf.h"\nint mid();\n#endif\n')
        # Root は Leaf を直接も、Mid 経由でも include する
        self.write("Root.h", '#ifndef Root_h\n#define Root_h\n#include "Leaf.h"\n#include "Mid.h"\n#endif\n')

        out = self.prelude("Root.h")

        self.assertEqual(out.count("struct Leaf"), 1, "同一ヘッダは 1 回だけ展開される")
        self.assertIn("int mid();", out)
        # ヘッダ自身のガードは剥がれ、前文用のガードが 1 組だけ残る。
        self.assertEqual(out.count("#ifndef"), 1)
        self.assertEqual(out.count("#define"), 1)
        self.assertEqual(out.count("#endif"), 1)
        for name in ("Leaf_h", "Mid_h", "Root_h"):
            self.assertNotIn(name, out)

    def test_prelude_is_wrapped_in_its_guard(self):
        # 前文は `createMaterial()` が必ず前置する。以前の作法で自分でも前置している
        # ソースでは 2 回現れるので、ガードが無いと MSL が二重定義で落ちる（#713）。
        self.write("Root.h", "#ifndef Root_h\n#define Root_h\nstruct R { int a; };\n#endif\n")

        out = self.prelude("Root.h", guard="METAPHOR_PRELUDE_TEST")

        self.assertTrue(out.startswith(
            "#ifndef METAPHOR_PRELUDE_TEST\n#define METAPHOR_PRELUDE_TEST\n"))
        self.assertTrue(out.endswith("#endif"))

    def test_root_is_not_registered_so_listing_it_twice_would_duplicate(self):
        # マニフェストのルートを 1 本に縛っている理由の回帰。`expand()` はルート自身を
        # 「展開済み」に登録しないので、推移的に include されるヘッダを一緒に並べると
        # 二重定義になる（MSL がコンパイル不能になる）。
        self.write("Leaf.h", "#ifndef Leaf_h\n#define Leaf_h\nstruct Leaf { int a; };\n#endif\n")
        self.write("Root.h", '#ifndef Root_h\n#define Root_h\n#include "Leaf.h"\n#endif\n')

        state = {"included": set(), "stdlib_emitted": True, "using_emitted": True}
        both = "\n".join(gen.expand(self.dir / "Leaf.h", state)
                         + gen.expand(self.dir / "Root.h", state))
        self.assertEqual(both.count("struct Leaf"), 2)

        # 正しい使い方（ルート 1 本）なら 1 回だけ
        self.assertEqual(self.prelude("Root.h").count("struct Leaf"), 1)

    def test_preincluded_headers_are_skipped(self):
        self.write("Types.h", "#ifndef Types_h\n#define Types_h\nstruct T { int a; };\n#endif\n")
        self.write("Fn.h", '#ifndef Fn_h\n#define Fn_h\n#include "Types.h"\nint f(T t);\n#endif\n')

        out = self.prelude("Fn.h", ("Types.h",))

        self.assertNotIn("struct T", out, "前文をまたいで構造体が二重定義されない")
        self.assertIn("int f(T t);", out)

    def test_prelude_never_emits_stdlib_or_using(self):
        self.write("Root.h", "#ifndef Root_h\n#define Root_h\n"
                             "#include <metal_stdlib>\nusing namespace metal;\n"
                             "struct R { int a; };\n#endif\n")

        out = self.prelude("Root.h")

        self.assertNotIn("metal_stdlib", out)
        self.assertNotIn("using namespace metal", out)
        self.assertIn("struct R", out)

    def test_generate_still_adds_stdlib_for_txt_outputs(self):
        # `.txt` 側は逆に、stdlib が 1 度も出なければ先頭に補う（前文と非対称）。
        self.write("MetaphorNoStdlib.metal", "kernel void k() {}\n")

        out = gen.generate(self.dir / "MetaphorNoStdlib.metal")

        self.assertTrue(out.startswith("#include <metal_stdlib>\nusing namespace metal;\n"))


class SwiftPreludeFileTests(unittest.TestCase):
    """生成される Swift ファイルの形と、前文の割り当て。"""

    @classmethod
    def setUpClass(cls):
        cls.swift = gen.generate_swift_preludes()
        cls.preludes = {name: gen.generate_prelude(root, pre, guard)
                        for name, root, pre, guard, _ in gen.SWIFT_PRELUDES}

    def test_closing_delimiter_and_payload_are_unindented(self):
        # Swift は閉じデリミタのインデント量を全行から剥がすので、閉じが字下げ
        # されていると、それより浅い行があるだけでコンパイルエラーになる。
        for line in self.swift.splitlines():
            if line.strip() == '"""#':
                self.assertEqual(line, '"""#', "閉じデリミタは 0 桁に置く")

    def test_payload_cannot_close_the_raw_string(self):
        for name, payload in self.preludes.items():
            self.assertFalse('"""#' in payload, f"{name} が raw string を閉じてしまう")
            self.assertFalse('\\#' in payload, f"{name} に raw string の補間開始が含まれる")

    def test_generated_type_is_internal(self):
        # public にすると llms.txt と DocC に新しい公開型が生える。
        self.assertIn("\nenum BuiltinShadersGenerated {\n", self.swift)
        self.assertNotIn("public enum BuiltinShadersGenerated", self.swift)

    def test_structs_go_to_structs_prelude_and_not_to_the_lighting_one(self):
        # マニフェストの割り当てが入れ替わると、公開している 2 つの前文の意味が
        # 静かに変わる（`--check` は自己整合なので気付けない）。
        structs = self.preludes["canvas3DStructs"]
        lighting = self.preludes["canvas3DLightingFn"]

        # 失敗メッセージに前文の全文（数百行）を出さないよう assertTrue/assertFalse を使う。
        for name in ("Canvas3DUniforms", "Light3D", "Material3D", "ShadowFragmentUniforms"):
            self.assertTrue(f"struct {name}" in structs,
                            f"{name} が canvas3DStructs から消えている")
            self.assertFalse(f"struct {name}" in lighting,
                             f"{name} が canvas3DLightingFn にも入っている（二重定義）")

    def test_lighting_prelude_carries_the_public_entry_points(self):
        lighting = self.preludes["canvas3DLightingFn"]
        for fn in ("calculateLighting", "calculatePBRLighting", "calculateBlinnPhongLighting",
                   "calculateShadow", "metaphorSkipsLighting"):
            self.assertTrue(fn in lighting, f"{fn} が canvas3DLightingFn から消えている")

    def test_each_prelude_has_its_own_guard(self):
        # ガードを共有すると、先に置かれた前文だけが展開されて片方が消える。
        guards = [guard for _, _, _, guard, _ in gen.SWIFT_PRELUDES]
        self.assertEqual(len(guards), len(set(guards)), f"ガードが衝突している: {guards}")
        for name, payload in self.preludes.items():
            self.assertTrue(payload.startswith("#ifndef METAPHOR_PRELUDE_"),
                            f"{name} がガードで包まれていない")

    def test_stage_in_structs_are_published_to_users(self):
        # フラグメントの stage_in を前文が配らないと、利用者は組み込みの
        # `Canvas3DVertexOut` を手で書き写すことになる（#713 で前文へ移した）。
        structs = self.preludes["canvas3DStructs"]
        for name in ("Canvas3DVertexIn", "Canvas3DVertexOut",
                     "Canvas3DTexVertexIn", "Canvas3DTexVertexOut"):
            self.assertTrue(f"struct {name}" in structs,
                            f"{name} が canvas3DStructs から消えている")

    def test_postprocess_prelude_carries_the_postfx_types(self):
        # postFX の前文（#718）。`createPostEffect()` がこれを必ず前置するので、
        # ここから型が落ちるとユーザーのソースが `unknown type name` で落ちる。
        post = self.preludes["postProcessStructs"]
        for name in ("PPVertexOut", "PostProcessParams"):
            self.assertTrue(f"struct {name}" in post,
                            f"{name} が postProcessStructs から消えている")
        self.assertFalse("struct Canvas3DUniforms" in post,
                         "3D の構造体が postProcessStructs に混ざっている")

    def test_no_duplicate_struct_definitions_across_both_preludes(self):
        combined = "\n".join(self.preludes.values())
        names = re.findall(r'^struct (\w+)', combined, flags=re.MULTILINE)
        self.assertEqual(len(names), len(set(names)), f"構造体が二重定義されている: {names}")


class GeneratedArtifactFreshnessTests(unittest.TestCase):
    """リポジトリにチェックインされている生成物が、規則どおりに作られているか。"""

    def test_checked_in_swift_prelude_matches_the_generator(self):
        # `--check` と同じことだが、ビルド不要でここでも落ちるようにしておく。
        current = gen.SWIFT_PRELUDE_PATH.read_text(encoding="utf-8")
        self.assertTrue(current == gen.generate_swift_preludes(),
                        f"{gen.SWIFT_PRELUDE_PATH.relative_to(REPO_ROOT)} が古い。"
                        "python3 scripts/generate-shader-sources.py を実行してコミットしてください")


if __name__ == "__main__":
    unittest.main()
