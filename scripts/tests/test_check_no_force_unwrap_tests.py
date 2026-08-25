#!/usr/bin/env python3
"""Unit tests for scripts/check-no-force-unwrap-tests.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「`Tests/` に `MetalTestHelper.<何か>!` が戻ってこないこと」
（Issue #1171 / #1003）。リポジトリ実体を見る `TestRepositoryIsClean` が本命で、
判定規則のテストがその周りを固める。

この検査は **swift-format の `NeverForceUnwrap` が `@Test` 属性の付いた関数の本体を
見ない**（swift-format 6.3.0 で実測）ことが存在理由なので、`@Test` の中を確かに
捕まえることを名指しでテストする。そこが抜けると、この検査は
`Tests/.swift-format` を置くのと同じものに退化する。

もう一方の失敗は**偽陽性**で、`MetalTestHelper.device != nil`（ゲートの書き方そのもの）
や `try #require(MetalTestHelper.device)`（正しい直し方）で落ちる検査は、ALLOWLIST に
無関係なファイルを足させて守りを空洞にする。
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-no-force-unwrap-tests.py"
_spec = importlib.util.spec_from_file_location("check_no_force_unwrap_tests", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_no_force_unwrap_tests"] = check
_spec.loader.exec_module(check)

ROOT = Path(__file__).resolve().parents[2]


class TestDetectsForceUnwraps(unittest.TestCase):
    def test_flags_the_device_force_unwrap(self):
        """#1172 が 99 箇所を潰した、まさにその形。"""
        found = check.find_force_unwraps("        let device = MetalTestHelper.device!\n")
        self.assertEqual([lineno for lineno, _ in found], [1])

    def test_flags_inside_a_test_function_body(self):
        """swift-format の NeverForceUnwrap が見ない場所（＝この検査の存在理由）。"""
        source = (
            '@Test("shearX offsets x")\n'
            "func shearX() throws {\n"
            "    let device = MetalTestHelper.device!\n"
            "}\n"
        )
        found = check.find_force_unwraps(source)
        self.assertEqual([lineno for lineno, _ in found], [3])

    def test_flags_a_force_unwrapped_call(self):
        """`commandQueue()` は今は非 Optional だが、規則は綴りに縛られない。"""
        found = check.find_force_unwraps("let q = MetalTestHelper.commandQueue()!\n")
        self.assertEqual(len(found), 1)

    def test_flags_a_fresh_allocation(self):
        """makeTexture は都度の確保で、isGPUAvailable のゲートは成功を保証しない。"""
        source = "let t = MetalTestHelper.makeTexture(width: 8, height: 8)!\n"
        self.assertEqual(len(check.find_force_unwraps(source)), 1)

    def test_flags_a_call_spanning_several_lines(self):
        """複数行に割れた呼び出しでも、`!` の行を報告する。"""
        source = "let t = MetalTestHelper.makeTexture(\n    width: 8,\n    height: 8\n)!\n"
        found = check.find_force_unwraps(source)
        self.assertEqual([lineno for lineno, _ in found], [4])

    def test_flags_a_force_unwrapped_subscript(self):
        source = "let x = MetalTestHelper.things[0]!\n"
        self.assertEqual(len(check.find_force_unwraps(source)), 1)

    def test_reports_every_offending_line(self):
        source = (
            "let a = MetalTestHelper.device!\nlet b = 1\nlet c = MetalTestHelper.device!\n"
        )
        found = check.find_force_unwraps(source)
        self.assertEqual([lineno for lineno, _ in found], [1, 3])

    def test_line_numbers_survive_a_multiline_string_above(self):
        """コメント・文字列を潰しても行番号がずれない。"""
        source = 'let s = """\nabc\n"""\nlet y = MetalTestHelper.device!\n'
        found = check.find_force_unwraps(source)
        self.assertEqual([lineno for lineno, _ in found], [4])


class TestIgnoresLegitimateOccurrences(unittest.TestCase):
    def test_ignores_the_availability_gate(self):
        """`device != nil` は比較であって強制アンラップではない。"""
        source = "@Suite(\"x\", .enabled(if: MetalTestHelper.device != nil))\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_the_correct_fix(self):
        source = "let device = try #require(MetalTestHelper.device)\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_plain_member_access(self):
        source = "if MetalTestHelper.isGPUAvailable { }\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_optional_chaining(self):
        source = "let x = MetalTestHelper.device?.name\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_a_line_comment(self):
        source = "// MetalTestHelper.device! と書かないこと\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_a_block_comment(self):
        source = "/* MetalTestHelper.device! */\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_a_nested_block_comment(self):
        """Swift のブロックコメントはネストできる。"""
        source = "/* a /* MetalTestHelper.device! */ b */\nlet x = 1\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_a_multiline_string_literal(self):
        source = 'let s = """\nMetalTestHelper.device!\n"""\n'
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_a_string_literal(self):
        source = 'let s = "MetalTestHelper.device!"\n'
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_ignores_an_identifier_that_merely_starts_with_the_helper_name(self):
        source = "let d = MetalTestHelperExtra.device!\n"
        self.assertEqual(check.find_force_unwraps(source), [])


class TestScopeIsDeliberatelyNarrow(unittest.TestCase):
    """対象外にしたものが「実装漏れ」ではなく「決めごと」であることを固定する。

    広げると既存コードに借金を作る（着手時の実測で 270 箇所）。範囲を動かすなら
    ここのテストを書き換えることになるので、黙って広がることも狭まることもない。
    """

    def test_does_not_flag_a_direct_device_creation(self):
        """`MTLCreateSystemDefaultDevice()!` は 230 箇所ある。別 Issue（#1178）。"""
        source = "let device = MTLCreateSystemDefaultDevice()!\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_does_not_flag_a_direct_command_queue_creation(self):
        """`makeCommandQueue()!` は 40 箇所ある。別 Issue（#1178）。"""
        source = "let queue = device.makeCommandQueue()!\n"
        self.assertEqual(check.find_force_unwraps(source), [])

    def test_does_not_flag_unwrapping_the_value_under_test(self):
        """落ちてもその 1 件が赤くなるだけで、#1003 の故障モードとは別物。"""
        source = "#expect(v0!.x == 10)\n#expect(c!.r == 1.0)\n"
        self.assertEqual(check.find_force_unwraps(source), [])


class TestStripNonCode(unittest.TestCase):
    def test_preserves_line_count(self):
        source = 'let s = """\nabc\ndef\n"""\n// tail\nlet y = 2\n'
        self.assertEqual(
            check.strip_noncode(source).count("\n"), source.count("\n")
        )

    def test_preserves_length(self):
        """桁がずれないので、報告する行の中身が原文と一致する。"""
        source = 'let s = "abc" // tail\n/* block */\n'
        self.assertEqual(len(check.strip_noncode(source)), len(source))

    def test_code_after_a_multiline_string_is_still_scanned(self):
        source = 'let s = """\nbody\n"""\nlet d = MetalTestHelper.device!\n'
        self.assertEqual([lineno for lineno, _ in check.find_force_unwraps(source)], [4])


class TestAllowlist(unittest.TestCase):
    def test_allowlisted_files_are_not_scanned(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Tests" / "PkgTests").mkdir(parents=True)
            allowed = root / "Tests" / "PkgTests" / "Legacy.swift"
            allowed.write_text("let d = MetalTestHelper.device!\n", encoding="utf-8")
            other = root / "Tests" / "PkgTests" / "Other.swift"
            other.write_text("let d = MetalTestHelper.device!\n", encoding="utf-8")

            original_root, original_allowlist = check.ROOT, check.ALLOWLIST
            try:
                check.ROOT = root
                check.ALLOWLIST = {"Tests/PkgTests/Legacy.swift": "テスト用"}
                scanned = check.swift_sources(root / "Tests")
            finally:
                check.ROOT, check.ALLOWLIST = original_root, original_allowlist

            self.assertEqual(scanned, [other])

    def test_every_allowlisted_path_exists(self):
        """消えたファイルが理由つきで残り続けないようにする。"""
        for rel in check.ALLOWLIST:
            with self.subTest(path=rel):
                self.assertTrue((ROOT / rel).is_file(), f"{rel} が存在しない")

    def test_every_allowlisted_path_actually_force_unwraps(self):
        """`!` が消えたのに例外だけ残る（＝穴が広がる）のを防ぐ。"""
        for rel in check.ALLOWLIST:
            with self.subTest(path=rel):
                text = (ROOT / rel).read_text(encoding="utf-8")
                self.assertTrue(
                    check.find_force_unwraps(text),
                    f"{rel} に強制アンラップが無い。ALLOWLIST から外せる",
                )


class TestRepositoryIsClean(unittest.TestCase):
    def test_no_helper_force_unwrap_left_in_tests(self):
        violations = []
        for path in check.swift_sources():
            rel = path.relative_to(ROOT).as_posix()
            for lineno, line in check.find_force_unwraps(
                path.read_text(encoding="utf-8")
            ):
                violations.append(f"{rel}:{lineno}: {line}")
        self.assertEqual(violations, [], "\n".join(violations))


if __name__ == "__main__":
    unittest.main()
