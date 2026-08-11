#!/usr/bin/env python3
"""Unit tests for scripts/generate-examples-index.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

この索引は「やりたいことから近い作例を探す」ための生成物で、AI エージェントの
主要な入口でもある。どのパッケージを載せる / 載せないかの判断は「生成物が最新か」
のチェックでは守れない（取りこぼしても出力は自己整合したまま緑になる）ため、
採用・除外の規則をここで固定する（DEVELOPMENT.md「生成物の管理」）。
"""

import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-examples-index.py"
_spec = importlib.util.spec_from_file_location("generate_examples_index", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_examples_index"] = gen
_spec.loader.exec_module(gen)


class TestDiscoverExamples(unittest.TestCase):
    def setUp(self) -> None:
        self.examples = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.examples, ignore_errors=True)

    def add_package(self, rel: str) -> Path:
        package_dir = self.examples / rel
        package_dir.mkdir(parents=True)
        (package_dir / "Package.swift").write_text("// swift-tools-version: 5.10\n")
        return package_dir

    def paths(self) -> list[str]:
        return [e["path"] for e in gen.discover_examples(self.examples)]

    def test_discovers_regular_examples(self) -> None:
        self.add_package("Basics/Form/ShapePrimitives")
        self.assertEqual(self.paths(), ["Examples/Basics/Form/ShapePrimitives"])

    def test_tutorial_packages_are_excluded(self) -> None:
        # チュートリアルの学習用スケッチは索引に載せない（#484 / #485）。
        self.add_package("Basics/Form/ShapePrimitives")
        self.add_package("Tutorial/01-GettingStarted/03-SketchSkeleton")
        self.assertEqual(self.paths(), ["Examples/Basics/Form/ShapePrimitives"])

    def test_exclusion_applies_only_at_top_level(self) -> None:
        # 除外は Examples/ 直下のディレクトリ名でのみ効く。深い位置の同名
        # ディレクトリまで巻き添えにしない。
        self.add_package("Topics/Tutorial/Something")
        self.assertEqual(self.paths(), ["Examples/Topics/Tutorial/Something"])

    def test_build_dirs_are_not_walked(self) -> None:
        self.add_package("Basics/Form/ShapePrimitives")
        nested = self.examples / "Basics/Form/ShapePrimitives/.build/checkouts/dep"
        nested.mkdir(parents=True)
        (nested / "Package.swift").write_text("// dependency\n")
        self.assertEqual(self.paths(), ["Examples/Basics/Form/ShapePrimitives"])


if __name__ == "__main__":
    unittest.main()
