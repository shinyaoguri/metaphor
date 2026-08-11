#!/usr/bin/env python3
"""Unit tests for scripts/generate-tutorial-snippets.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

チュートリアル本文（docs/tutorial/*.md）へ埋め込まれるコードの正典は
Examples/Tutorial/** の SwiftPM パッケージ。ここでは擬似的なリポジトリを
tmpdir に組み立て、埋め込み・陳腐化検出・エラー検出の規則を Swift ビルド
無しで確かめる（Issue #485）。
"""

import contextlib
import importlib.util
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-tutorial-snippets.py"
_spec = importlib.util.spec_from_file_location("generate_tutorial_snippets", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_tutorial_snippets"] = gen
_spec.loader.exec_module(gen)


class SnippetTestCase(unittest.TestCase):
    """tmpdir 上に docs/tutorial と Examples/Tutorial を持つ疑似リポを張る。"""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.docs = self.root / "docs/tutorial"
        self.code = self.root / "Examples/Tutorial"
        self.docs.mkdir(parents=True)
        self.code.mkdir(parents=True)
        for name, value in (
            ("REPO_ROOT", self.root),
            ("DOCS_DIR", self.docs),
            ("CODE_DIR", self.code),
        ):
            original = getattr(gen, name)
            setattr(gen, name, value)
            self.addCleanup(setattr, gen, name, original)

    def add_package(self, ref: str, sources: dict[str, str]) -> None:
        package_dir = self.code / ref
        target = package_dir / ref.split("/")[-1].split("-", 1)[-1]
        target.mkdir(parents=True)
        (package_dir / "Package.swift").write_text("// swift-tools-version: 5.10\n")
        for name, body in sources.items():
            (target / name).write_text(body, encoding="utf-8")

    def add_doc(self, name: str, text: str) -> Path:
        path = self.docs / name
        path.write_text(text, encoding="utf-8")
        return path

    def run_main(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        original = sys.argv
        sys.argv = ["generate-tutorial-snippets.py", *argv]
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = gen.main()
        finally:
            sys.argv = original
        return code, out.getvalue(), err.getvalue()


class TestRenderSnippet(SnippetTestCase):
    def test_embeds_source_and_run_command(self) -> None:
        self.add_package("01-Part/02-Section", {"App.swift": "import metaphor\n"})
        doc = self.add_doc(
            "01-part.md",
            "# 見出し\n\n"
            "<!-- tutorial-snippet: 01-Part/02-Section -->\n"
            "<!-- /tutorial-snippet -->\n",
        )

        self.assertEqual(self.run_main()[0], 0)
        text = doc.read_text(encoding="utf-8")
        self.assertIn("```swift\nimport metaphor\n```", text)
        self.assertIn(
            "実行: `cd Examples/Tutorial/01-Part/02-Section && swift run`", text
        )

    def test_multiple_sources_are_labelled_and_sorted(self) -> None:
        self.add_package(
            "01-Part/02-Section",
            {"App.swift": "// app\n", "Particle.swift": "// particle\n"},
        )
        doc = self.add_doc(
            "01-part.md",
            "<!-- tutorial-snippet: 01-Part/02-Section -->\n<!-- /tutorial-snippet -->\n",
        )

        self.assertEqual(self.run_main()[0], 0)
        text = doc.read_text(encoding="utf-8")
        # ラベルはパッケージからの相対パス（ターゲットのディレクトリを含む）
        self.assertLess(
            text.index("**`Section/App.swift`**"),
            text.index("**`Section/Particle.swift`**"),
        )

    def test_regeneration_is_idempotent(self) -> None:
        self.add_package("01-Part/02-Section", {"App.swift": "import metaphor\n"})
        doc = self.add_doc(
            "01-part.md",
            "<!-- tutorial-snippet: 01-Part/02-Section -->\n<!-- /tutorial-snippet -->\n",
        )

        self.run_main()
        first = doc.read_text(encoding="utf-8")
        self.run_main()
        self.assertEqual(doc.read_text(encoding="utf-8"), first)

    def test_readme_is_not_scanned(self) -> None:
        # 設計文書。書式の説明としてマーカーを載せても生成対象にしない。
        doc = self.add_doc(
            "README.md",
            "<!-- tutorial-snippet: 99-Missing/99-Missing -->\n<!-- /tutorial-snippet -->\n",
        )
        original = doc.read_text(encoding="utf-8")

        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(doc.read_text(encoding="utf-8"), original)


class TestCheckMode(SnippetTestCase):
    def test_check_fails_when_code_changed(self) -> None:
        self.add_package("01-Part/02-Section", {"App.swift": "import metaphor\n"})
        self.add_doc(
            "01-part.md",
            "<!-- tutorial-snippet: 01-Part/02-Section -->\n<!-- /tutorial-snippet -->\n",
        )
        self.run_main()

        # 正典（パッケージ）だけが変わった = 本文が陳腐化した状態
        (self.code / "01-Part/02-Section/Section/App.swift").write_text(
            "import metaphor\n// 追記\n", encoding="utf-8"
        )

        code, stdout, _ = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("追記", stdout)

    def test_check_does_not_write(self) -> None:
        self.add_package("01-Part/02-Section", {"App.swift": "import metaphor\n"})
        doc = self.add_doc(
            "01-part.md",
            "<!-- tutorial-snippet: 01-Part/02-Section -->\n<!-- /tutorial-snippet -->\n",
        )
        original = doc.read_text(encoding="utf-8")

        self.assertEqual(self.run_main("--check")[0], 1)
        self.assertEqual(doc.read_text(encoding="utf-8"), original)

    def test_check_passes_when_up_to_date(self) -> None:
        self.add_package("01-Part/02-Section", {"App.swift": "import metaphor\n"})
        self.add_doc(
            "01-part.md",
            "<!-- tutorial-snippet: 01-Part/02-Section -->\n<!-- /tutorial-snippet -->\n",
        )
        self.run_main()

        self.assertEqual(self.run_main("--check")[0], 0)


class TestErrors(SnippetTestCase):
    def test_unknown_ref_fails(self) -> None:
        self.add_doc(
            "01-part.md",
            "<!-- tutorial-snippet: 01-Part/99-Missing -->\n<!-- /tutorial-snippet -->\n",
        )

        code, _, stderr = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("01-Part/99-Missing", stderr)

    def test_unclosed_block_fails(self) -> None:
        self.add_package("01-Part/02-Section", {"App.swift": "import metaphor\n"})
        self.add_doc("01-part.md", "<!-- tutorial-snippet: 01-Part/02-Section -->\n")

        code, _, stderr = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("閉じられていない", stderr)

    def test_orphan_close_marker_fails(self) -> None:
        self.add_doc("01-part.md", "<!-- /tutorial-snippet -->\n")

        code, _, stderr = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("開始マーカーの無い", stderr)

    def test_unreferenced_package_only_warns(self) -> None:
        # 執筆中はコードが先に入る。CI を止めず、気付けるように警告だけ出す。
        self.add_package("01-Part/02-Section", {"App.swift": "import metaphor\n"})

        code, _, stderr = self.run_main("--check")
        self.assertEqual(code, 0)
        self.assertIn("01-Part/02-Section", stderr)


if __name__ == "__main__":
    unittest.main()
