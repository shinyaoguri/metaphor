#!/usr/bin/env python3
"""Unit tests for scripts/generate-examples-index.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

Focus: the `shader` / `cpu-approximation` tags. They used to come from a
substring match on the example's path and description, which tagged every
sketch under Examples/Topics/Shaders/ (CPU reimplementations of a GLSL
original) and every description containing the word "Metal" as a shader
reference (#489). They are now derived from the example's own files.
"""

import importlib.util
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


if __name__ == "__main__":
    unittest.main()
