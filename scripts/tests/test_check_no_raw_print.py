#!/usr/bin/env python3
"""Unit tests for scripts/check-no-raw-print.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「`Sources/` に生の `print()` が戻ってこないこと」（Issue #896 / #805）。
リポジトリ実体を見るテスト（`TestRepositoryIsClean`）が本命で、判定規則のテストは
その周りを固める。特に大事なのは**偽陽性を出さないこと** — doc コメントの
`print(cam.name)` は利用者向けのサンプルコードとして正しく、これで落ちるチェックは
`ALLOWLIST` に無関係なファイルを足させてしまい、守りそのものが空洞化する。
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-no-raw-print.py"
_spec = importlib.util.spec_from_file_location("check_no_raw_print", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_no_raw_print"] = check
_spec.loader.exec_module(check)

ROOT = Path(__file__).resolve().parents[2]


class TestDetectsRawPrints(unittest.TestCase):
    def test_flags_a_plain_print(self):
        found = check.find_raw_prints('    print("[metaphor] boom: \\(error)")\n')
        self.assertEqual([lineno for lineno, _ in found], [1])

    def test_flags_a_print_without_any_tag(self):
        """タグの綴りではなく `print(` 自体を見ている（#896 の grep の穴）。"""
        found = check.find_raw_prints('print("failed to open the file")\n')
        self.assertEqual(len(found), 1)

    def test_flags_a_multiline_string_print(self):
        """`print(\"\"\"` の開始行は検出し、中身の行では二重に数えない。"""
        source = (
            "func warn() {\n"
            '    print("""\n'
            "    [metaphor] this is a long message\n"
            "    spanning several lines\n"
            '    """)\n'
            "}\n"
        )
        found = check.find_raw_prints(source)
        self.assertEqual([lineno for lineno, _ in found], [2])

    def test_flags_swift_qualified_print(self):
        found = check.find_raw_prints("Swift.print(value)\n")
        self.assertEqual(len(found), 1)

    def test_flags_debug_print(self):
        found = check.find_raw_prints("debugPrint(value)\n")
        self.assertEqual(len(found), 1)

    def test_reports_every_offending_line(self):
        source = 'print("a")\nlet x = 1\nprint("b")\n'
        self.assertEqual([lineno for lineno, _ in check.find_raw_prints(source)], [1, 3])


class TestIgnoresLegitimateOccurrences(unittest.TestCase):
    def test_ignores_doc_comment_sample_code(self):
        """利用者向けの doc に出てくる print はサンプルであって出力ではない。"""
        source = "///     print(cam.name, cam.kind)\n/// print(error.description)\n"
        self.assertEqual(check.find_raw_prints(source), [])

    def test_ignores_line_comment(self):
        self.assertEqual(check.find_raw_prints('    // print("debug")\n'), [])

    def test_ignores_trailing_comment_after_code(self):
        source = "let x = 1  // print(x) を消した\n"
        self.assertEqual(check.find_raw_prints(source), [])

    def test_ignores_print_inside_a_multiline_string_literal(self):
        """複数行文字列の中身（例: 生成コードのテンプレート）は対象外。"""
        source = 'let template = """\nprint("hello from the generated sketch")\n"""\n'
        self.assertEqual(check.find_raw_prints(source), [])

    def test_ignores_a_method_named_print(self):
        """Combine の `.print()` のようなメソッド呼び出しは生 print ではない。"""
        self.assertEqual(check.find_raw_prints("publisher.print()\n"), [])

    def test_ignores_identifiers_that_merely_contain_print(self):
        source = "let footprint = measureFootprint()\nsprint(x)\n"
        self.assertEqual(check.find_raw_prints(source), [])

    def test_multiline_string_does_not_leak_into_the_next_declaration(self):
        """閉じたあとのコードはまた検査対象に戻る。"""
        source = 'let s = """\nbody\n"""\nprint("after")\n'
        self.assertEqual([lineno for lineno, _ in check.find_raw_prints(source)], [4])


class TestAllowlist(unittest.TestCase):
    def test_allowlisted_files_are_not_scanned(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Sources" / "Pkg").mkdir(parents=True)
            allowed = root / "Sources" / "Pkg" / "Log.swift"
            allowed.write_text('print("hi")\n', encoding="utf-8")
            other = root / "Sources" / "Pkg" / "Other.swift"
            other.write_text('print("hi")\n', encoding="utf-8")

            original_root, original_allowlist = check.ROOT, check.ALLOWLIST
            try:
                check.ROOT = root
                check.ALLOWLIST = {"Sources/Pkg/Log.swift": "テスト用"}
                scanned = check.swift_sources(root / "Sources")
            finally:
                check.ROOT, check.ALLOWLIST = original_root, original_allowlist

            self.assertEqual(scanned, [other])

    def test_every_allowlisted_path_exists(self):
        """消えたファイルが理由つきで残り続けないようにする。"""
        for rel in check.ALLOWLIST:
            with self.subTest(path=rel):
                self.assertTrue((ROOT / rel).is_file(), f"{rel} が存在しない")

    def test_every_allowlisted_path_actually_prints(self):
        """print が無くなったのに例外だけ残る（＝穴が広がる）のを防ぐ。"""
        for rel in check.ALLOWLIST:
            with self.subTest(path=rel):
                text = (ROOT / rel).read_text(encoding="utf-8")
                self.assertTrue(
                    check.find_raw_prints(text),
                    f"{rel} に生 print が無い。ALLOWLIST から外せる",
                )


class TestRepositoryIsClean(unittest.TestCase):
    def test_no_raw_print_left_in_sources(self):
        violations = []
        for path in check.swift_sources():
            rel = path.relative_to(ROOT).as_posix()
            for lineno, line in check.find_raw_prints(
                path.read_text(encoding="utf-8")
            ):
                violations.append(f"{rel}:{lineno}: {line}")
        self.assertEqual(violations, [], "\n".join(violations))


if __name__ == "__main__":
    unittest.main()
