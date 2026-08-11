#!/usr/bin/env python3
"""Unit tests for scripts/generate-examples-index.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

この索引は「やりたいことから近い作例を探す」ための生成物で、AI エージェントの
主要な入口でもある。何を載せ、どのタグを付けるかの判断は「生成物が最新か」の
チェックでは守れない（取りこぼしても出力は自己整合したまま緑になる）ため、
規則そのものをここで固定する（DEVELOPMENT.md「生成物の管理」）。

扱う規則は 2 つ:

- `shader` / `cpu-approximation` タグ。以前はパスと説明文の部分一致で付いており、
  Examples/Topics/Shaders/ 配下（GLSL 原典の CPU 再実装）や説明文に "Metal" を
  含むものまでシェーダの参照実装に見えていた（#489）。いまは example 自身の
  ファイルから導く
- 索引に載せるパッケージの範囲。Examples/Tutorial/ の学習用スケッチは除外する
  （#484 / #485）
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


CPU_SKETCH = """
import metaphor

// NOTE: Original uses a GLSL edge detection shader.
// This version uses CPU convolution as approximation.
@main
final class EdgeDetect: Sketch {
    func draw() { image(edgeImg, 0, 0) }
}
"""

EFFECT_SKETCH = """
import metaphor

@main
final class Glow: Sketch {
    func setup() { addPostEffect(BloomEffect()) }
}
"""


def make_example(root: Path, name: str, *, swift: str = CPU_SKETCH,
                 glsl: bool = False, metal: bool = False) -> Path:
    """Write a minimal example package and return its directory."""
    example_dir = root / name
    (example_dir / name).mkdir(parents=True)
    (example_dir / "Package.swift").write_text("// swift-tools-version:5.10\n")
    (example_dir / name / "App.swift").write_text(swift)
    if glsl:
        (example_dir / "data").mkdir()
        (example_dir / "data" / "effect.glsl").write_text("void main() {}\n")
    if metal:
        (example_dir / name / "Effect.metal").write_text("// MSL\n")
    return example_dir


class SourceTagsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_glsl_without_shader_api_is_cpu_approximation(self) -> None:
        """Topics/Shaders/*: the GLSL original is kept, the port is CPU-side."""
        example = make_example(self.root, "EdgeDetect", glsl=True)
        self.assertEqual(
            gen.source_tags_for(example, "supported"), {"cpu-approximation"}
        )

    def test_shader_api_call_earns_the_shader_tag(self) -> None:
        example = make_example(self.root, "Glow", swift=EFFECT_SKETCH)
        self.assertEqual(gen.source_tags_for(example, "supported"), {"shader"})

    def test_shader_api_wins_over_a_leftover_glsl_file(self) -> None:
        """A ported sketch flips from cpu-approximation to shader on its own."""
        example = make_example(self.root, "Glow", swift=EFFECT_SKETCH, glsl=True)
        self.assertEqual(gen.source_tags_for(example, "supported"), {"shader"})

    def test_own_metal_source_earns_the_shader_tag(self) -> None:
        example = make_example(self.root, "Raymarch", metal=True)
        self.assertEqual(gen.source_tags_for(example, "supported"), {"shader"})

    def test_placeholders_are_not_cpu_approximations(self) -> None:
        """A stub/obsolete example implements nothing to approximate with."""
        example = make_example(self.root, "DomeProjection", glsl=True)
        self.assertEqual(gen.source_tags_for(example, "obsolete"), set())
        self.assertEqual(gen.source_tags_for(example, "stub"), set())

    def test_build_products_are_ignored(self) -> None:
        """Gitignored build output must not leak into the committed index."""
        example = make_example(self.root, "Plain")
        checkout = example / ".build" / "checkouts" / "dep"
        checkout.mkdir(parents=True)
        (checkout / "Vendored.metal").write_text("// MSL\n")
        (checkout / "vendored.glsl").write_text("void main() {}\n")
        (checkout / "Dep.swift").write_text(EFFECT_SKETCH)
        self.assertEqual(gen.source_tags_for(example, "supported"), set())


class TagsForTests(unittest.TestCase):
    def test_path_and_prose_no_longer_imply_a_shader(self) -> None:
        tags = gen.tags_for(Path("Topics/Shaders/EdgeDetect"), {})
        self.assertNotIn("shader", tags)
        self.assertIn("shaders", tags)  # plain path tag, unchanged

        metal_only = {"description": "metaphor is Metal-only; non-goal."}
        self.assertNotIn("shader", gen.tags_for(Path("Demos/Tests/SpecsTest"), metal_only))

    def test_source_tags_are_merged_in(self) -> None:
        tags = gen.tags_for(
            Path("Topics/Shaders/EdgeDetect"), {}, {"cpu-approximation"}
        )
        self.assertIn("cpu-approximation", tags)
        self.assertEqual(tags, sorted(tags))


class DiscoverExamplesTests(unittest.TestCase):
    def test_discovery_carries_the_source_tags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_example(root, "EdgeDetect", glsl=True)
            (found,) = gen.discover_examples(root)
            self.assertIn("cpu-approximation", found["tags"])
            self.assertNotIn("shader", found["tags"])


class DiscoveryFilterTests(unittest.TestCase):
    """索引に載せるパッケージの範囲（#484 / #485）。"""

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
