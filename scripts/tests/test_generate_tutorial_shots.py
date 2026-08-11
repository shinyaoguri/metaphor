#!/usr/bin/env python3
"""Unit tests for scripts/generate-tutorial-shots.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

撮影そのものは GPU とウィンドウサーバーが要るので、ここで確かめるのは
**鮮度判定の規則**だけ。PNG のバイト比較ではなく「撮影時のソースの指紋と
現在のソースが一致するか」で判定する、というのがこのスクリプトの肝で、
そこが壊れると「コードを変えたのに画像が古い」を CI が見逃す（#486）。
"""

import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-tutorial-shots.py"
_spec = importlib.util.spec_from_file_location("generate_tutorial_shots", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_tutorial_shots"] = gen
_spec.loader.exec_module(gen)

REF = "01-Part/02-Section"


class ShotsTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.docs = self.root / "docs/tutorial"
        self.images = self.docs / "images"
        self.code = self.root / "Examples/Tutorial"
        self.docs.mkdir(parents=True)
        self.code.mkdir(parents=True)
        for name, value in (
            ("REPO_ROOT", self.root),
            ("DOCS_DIR", self.docs),
            ("IMAGES_DIR", self.images),
            ("CODE_DIR", self.code),
            ("MANIFEST", self.images / "manifest.json"),
        ):
            original = getattr(gen, name)
            setattr(gen, name, value)
            self.addCleanup(setattr, gen, name, original)

    def add_package(self, ref: str = REF, body: str = "import metaphor\n") -> Path:
        package_dir = self.code / ref
        (package_dir / "Section").mkdir(parents=True)
        (package_dir / "Package.swift").write_text("// swift-tools-version: 5.10\n")
        (package_dir / "Section" / "App.swift").write_text(body, encoding="utf-8")
        return package_dir

    def add_doc(self, ref: str = REF) -> None:
        (self.docs / "01-part.md").write_text(
            f"<!-- tutorial-snippet: {ref} -->\n<!-- /tutorial-snippet -->\n",
            encoding="utf-8",
        )

    def add_image(self, ref: str = REF) -> None:
        path = gen.image_path_for(ref)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\x89PNG\r\n\x1a\n")

    def record(self, ref: str = REF) -> dict:
        return {ref: {"sourceHash": gen.source_hash(self.code / ref)}}


class TestReferencedRefs(ShotsTestCase):
    def test_reads_snippet_markers(self) -> None:
        self.add_doc()
        self.assertEqual(gen.referenced_refs(), [REF])

    def test_readme_is_not_scanned(self) -> None:
        (self.docs / "README.md").write_text(
            f"<!-- tutorial-snippet: {REF} -->\n<!-- /tutorial-snippet -->\n",
            encoding="utf-8",
        )
        self.assertEqual(gen.referenced_refs(), [])


class TestStaleness(ShotsTestCase):
    def test_fresh_when_hash_matches(self) -> None:
        self.add_package()
        self.add_image()
        self.assertEqual(gen.check([REF], self.record()), [])

    def test_stale_when_sketch_changed_after_capture(self) -> None:
        package_dir = self.add_package()
        self.add_image()
        recorded = self.record()
        (package_dir / "Section" / "App.swift").write_text(
            "import metaphor\n// 追記\n", encoding="utf-8"
        )
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_stale_when_image_missing(self) -> None:
        self.add_package()
        self.assertEqual(len(gen.check([REF], self.record())), 1)

    def test_stale_when_never_captured(self) -> None:
        self.add_package()
        self.add_image()
        self.assertEqual(len(gen.check([REF], {})), 1)

    def test_unknown_package_is_an_error(self) -> None:
        with self.assertRaises(gen.ShotError):
            gen.check(["99-Missing/99-Missing"], {})

    def test_build_products_do_not_change_the_hash(self) -> None:
        # .build は gitignore 済みで、あるかないかで撮り直しが要るとは言えない。
        package_dir = self.add_package()
        self.add_image()
        before = gen.source_hash(package_dir)
        checkout = package_dir / ".build/checkouts/dep"
        checkout.mkdir(parents=True)
        (checkout / "Dep.swift").write_text("import Foundation\n")
        self.assertEqual(gen.source_hash(package_dir), before)


if __name__ == "__main__":
    unittest.main()
