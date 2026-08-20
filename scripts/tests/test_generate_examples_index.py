#!/usr/bin/env python3
"""Unit tests for scripts/generate-examples-index.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

この索引は「やりたいことから近い作例を探す」ための生成物で、AI エージェントの
主要な入口でもある。何を載せ、どのタグを付けるかの判断は「生成物が最新か」の
チェックでは守れない（取りこぼしても出力は自己整合したまま緑になる）ため、
規則そのものをここで固定する（DEVELOPMENT.md「生成物の管理」）。

扱う規則は 3 つ:

- `shader` / `cpu-approximation` / `3d` タグ。以前はパスと説明文の部分一致で付いており、
  Examples/Topics/Shaders/ 配下（GLSL 原典の CPU 再実装）や説明文に "Metal" を
  含むものまでシェーダの参照実装に見えていた（#489）。`3d` も同じ病で、#497 が
  語単位の照合にしても「語は正しいが語義が違う」誤爆が残った（#940）。
  いまはどちらも example 自身のファイルから導く
- `KEYWORD_TAGS` の照合単位。素の部分一致をやめ「語」で照合する（#497）
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

THREE_D_SKETCH = """
import metaphor

@main
final class Spin: Sketch {
    func draw() {
        lights()
        box(100)
    }
}
"""

# 3D 変換だけを呼ぶスケッチ。`rotateX` / `rotateY` / `rotateZ` は 2D 版が無いので
# これ 1 本で 3D の根拠になる（実データでは RotateXY / RotatingArcs がこの形）。
ROTATE_ONLY_SKETCH = """
import metaphor

@main
final class Tilt: Sketch {
    func draw() { rotateX(0.4); rect(0, 0, 40, 40) }
}
"""

# 語としては 3D だが、実際は 2D しか描かないスケッチ。#940 の誤爆 8 件はこの形。
PROSE_ONLY_SKETCH = """
import metaphor

// Drag the white boxes around. Window A shows a morphing wireframe sphere,
// projected by hand — box(10) and sphere(20) appear only in these comments.
@main
final class Handles: Sketch {
    func draw() {
        pushMatrix()
        translate(width / 2, height / 2)
        vertex(10, 20)
        rect(0, 0, 40, 40)
        popMatrix()
    }
}
"""

# `converter.texture(from:)` は Core Video の変換で、3D の texture() ではない。
METHOD_CALL_SKETCH = """
import metaphor

@main
final class Classify: Sketch {
    func draw() {
        guard let tex = converter.texture(from: cgImage) else { return }
        image(frame, 0, 0)
    }
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

    # --- `3d` はソース根拠で決める（#940） -------------------------------
    #
    # 消える側だけでなく**残る側**も対で固定する。維持側を書かないと、後続が
    # 「3D API の呼び出しを 1 つ削る」「コメントも読む形へ戻す」といった単純化を
    # しても緑のまま通る。

    def test_three_d_api_call_earns_the_3d_tag(self) -> None:
        example = make_example(self.root, "Spin", swift=THREE_D_SKETCH)
        self.assertIn("3d", gen.source_tags_for(example, "supported"))

    def test_three_d_transform_alone_earns_the_3d_tag(self) -> None:
        """`rotateX` 系は 2D 版が無いので、これ 1 本でも根拠になる。"""
        example = make_example(self.root, "Tilt", swift=ROTATE_ONLY_SKETCH)
        self.assertIn("3d", gen.source_tags_for(example, "supported"))

    def test_prose_in_comments_does_not_earn_the_3d_tag(self) -> None:
        """コメントの box() / sphere() はコードではない。

        併せて、2D にも効く `pushMatrix` / `translate` / `vertex` が根拠に
        ならないことも固定する（ADR-0005 §8）。
        """
        example = make_example(self.root, "Handles", swift=PROSE_ONLY_SKETCH)
        self.assertNotIn("3d", gen.source_tags_for(example, "supported"))

    def test_method_calls_do_not_earn_the_3d_tag(self) -> None:
        """`converter.texture(from:)` は metaphor のグローバル API ではない。"""
        example = make_example(self.root, "Classify", swift=METHOD_CALL_SKETCH)
        self.assertNotIn("3d", gen.source_tags_for(example, "supported"))

    def test_3d_has_no_status_gate(self) -> None:
        """`cpu-approximation` と違い、stub でも box() を呼べば 3D は描かれる。"""
        example = make_example(self.root, "Spin", swift=THREE_D_SKETCH)
        self.assertIn("3d", gen.source_tags_for(example, "stub"))


class TagsForTests(unittest.TestCase):
    def test_prose_no_longer_implies_3d(self) -> None:
        """語としては合っているが語義が違う実例（#940）。

        どちらも #497 の語単位照合を**通ってしまう** — needle の側では
        取れないので、`3d` を散文から引くのをやめるしかなかった。
        """
        handles = {"description": "Click and drag the white boxes to change their position."}
        self.assertNotIn("3d", gen.tags_for(Path("Topics/GUI/Handles"), handles))

        cameras = {"description": "Lists the connected cameras with listCaptureDevices()."}
        self.assertNotIn("3d", gen.tags_for(Path("Basics/Video/CameraSwitching"), cameras))

        # 名前に 2D と書いてあるスケッチが `3d` を持っていた。
        mouse2d = {"description": "Moving the mouse changes the position and size of each box."}
        self.assertNotIn("3d", gen.tags_for(Path("Basics/Input/Mouse2D"), mouse2d))

        # 3D ノイズは次元の話で、3D 描画ではない。
        noise3d = {"description": "Using 3D noise to create simple animated texture."}
        self.assertNotIn("3d", gen.tags_for(Path("Basics/Math/Noise3D"), noise3d))

    def test_3d_comes_from_source_evidence(self) -> None:
        """散文で取らなくなったぶん、ソース根拠から渡せば付く（残る側）。"""
        tags = gen.tags_for(Path("Topics/GUI/Handles"), {}, {"3d"})
        self.assertIn("3d", tags)
        self.assertEqual(tags, sorted(tags))

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


class KeywordTagTests(unittest.TestCase):
    """`KEYWORD_TAGS` は「語」単位で照合する（#497）。

    以前は素の部分一致だったので、長い語の内側に needle が入っているだけで
    タグが付いた（"Texture" → typography、"keyword" → typography、
    "expression" → interaction、"lightness" → 3d）。実データで 13 件。

    規則は 3 つあり、**緩めると静かに退行する**。だから「消える側」と
    「残る側」を対で固定する:

    1. 語境界で切る → 誤爆が消える（`test_substring_misfires_are_gone`）
    2. 活用形は拾う → 複数形・過去形・進行形。単純な ``\\bneedle\\b`` にすると
       7 件が落ちる（`test_inflected_forms_still_match`）
    3. 照合前に CamelCase / 数字を分割する（`test_camel_case_is_split_before_matching`）

    **`3d` が #940 でソース根拠へ移ったので、この 13 件のうち 1 件が消えた** —
    "lightness" → 3d via `light` は needle ごと無くなったため、検査しても
    「語単位で照合しているから落ちている」ことの証拠にならない（部分一致へ戻しても
    緑のまま通る）。空振りする検査を残すのは無いより悪いので外した。
    同じ理由で、活用形の実例から `boxes` → 3d も外している。
    """

    # (path, metadata, 付いてはいけないタグ, 誤爆させていた語)
    MISFIRES = (
        ("Basics/Control/Conditionals2",
         {"description": 'We extend the language of conditionals by adding the keyword "else".'},
         "typography", "word ⊂ keyword"),
        ("Basics/Control/LogicalOperators",
         {"description": "combine simple relational statements into more complex expressions."},
         "interaction", "press ⊂ expressions"),
        ("Basics/Math/Noise2D",
         {"description": "Using 2D noise to create simple texture."},
         "typography", "text ⊂ texture"),
        ("Basics/Math/Noise3D",
         {"description": "Using 3D noise to create simple animated texture."},
         "typography", "text ⊂ texture"),
        ("Basics/Math/OperatorPrecedence",
         {"description": "the order in which an expression is evaluated"},
         "interaction", "press ⊂ expression"),
        ("Basics/Structure/CreateGraphics",
         {"description": "PGraphics is the main graphics and rendering context for Processing."},
         "typography", "text ⊂ context"),
        ("Samples/DynamicMeshTexture", {}, "typography", "text ⊂ DynamicMeshTexture"),
        ("Topics/Textures/TextureCube", {}, "typography", "text ⊂ Textures / TextureCube"),
        ("Topics/Textures/TextureCylinder", {}, "typography", "text ⊂ Textures / TextureCylinder"),
        ("Topics/Textures/TextureQuad", {}, "typography", "text ⊂ Textures / TextureQuad"),
        ("Topics/Textures/TextureSphere", {}, "typography", "text ⊂ Textures / TextureSphere"),
        ("Topics/Textures/TextureTriangle", {}, "typography", "text ⊂ Textures / TextureTriangle"),
    )

    # (path, metadata, 残らないといけないタグ, 拾えている語)
    INFLECTED = (
        ("Basics/Data/CharactersStrings",
         {"description": "to display text to the screen, and to load images or files."},
         "image", "images"),
        ("Topics/File IO/TileImages", {}, "image", "TileImages"),
        ("Basics/Math/Graphing2DEquation",
         {"featured": ["loadPixels_", "updatePixels_"]},
         "image", "loadPixels_（末尾の _ は \\b を壊す）"),
        ("Basics/Structure/Coordinates",
         {"description": "the distance from the origin in units of pixels."},
         "image", "pixels"),
        ("Topics/Fractals and L-Systems/Mandelbrot",
         {"featured": ["loadPixels_", "pixels[]"]},
         "image", "pixels[]"),
        ("Basics/Input/StoringInput",
         {"description": "The positions of the mouse are recorded into an array"},
         "export", "recorded"),
        ("Topics/Motion/Brownian",
         {"description": "Recording random movement as a continuous line."},
         "export", "recording"),
    )

    def test_substring_misfires_are_gone(self) -> None:
        for path, metadata, tag, why in self.MISFIRES:
            with self.subTest(path=path, tag=tag):
                self.assertNotIn(tag, gen.tags_for(Path(path), metadata), why)

    def test_inflected_forms_still_match(self) -> None:
        """語境界だけに単純化すると、この 7 件が黙って落ちる。"""
        for path, metadata, tag, why in self.INFLECTED:
            with self.subTest(path=path, tag=tag):
                self.assertIn(tag, gen.tags_for(Path(path), metadata), why)

    def test_digit_run_splits_before_the_digit(self) -> None:
        """英字→数字で切る（数字→大文字で切ると "Noise 3 D" 相当になる）。

        **この規則は実データではもう 1 件もタグを動かさない。** 消費者だった
        `3d` needle が #940 でソース根拠へ移ったため。規則自体は残す（ただ同然で、
        数字を含む次の needle が来たら要る）が、example で検査すると空振りするので
        `split_humps` を直接固定する。
        """
        self.assertEqual(gen.split_humps("Noise3D"), "Noise 3D")
        self.assertEqual(
            gen.split_humps("GravitationalAttraction3D"), "Gravitational Attraction 3D"
        )
        # 分割した結果に "3d" が語として立っていること（needle が復活したとき用）。
        self.assertIsNotNone(
            gen.keyword_pattern("3d").search(gen.split_humps("Noise3D").lower())
        )

    def test_es_plural_is_still_matched(self) -> None:
        """`e?s` の `es` 側も、同じく実データの消費者を失った（`boxes` → `box`）。

        パターンを直接検査して、`(?:e?s|…)` を `(?:s|…)` へ削る単純化を止める。
        """
        self.assertIsNotNone(gen.keyword_pattern("box").search("drag the boxes around"))
        self.assertIsNotNone(gen.keyword_pattern("press").search("presses the key"))
        # 活用形ではない語の内側は依然として拾わない（"boxing" は `ing` 形なので拾う）。
        self.assertIsNone(gen.keyword_pattern("box").search("a boxwood fence"))

    def test_camel_case_is_split_before_matching(self) -> None:
        self.assertEqual(gen.split_humps("TextureSphere"), "Texture Sphere")
        # 頭字語 + 語も切る。切らないと "OSCReceiver" が live タグを取り落とす。
        self.assertEqual(gen.split_humps("OSCReceiver"), "OSC Receiver")
        self.assertIn("live", gen.tags_for(Path("Topics/Network/OSCReceiver"), {}))

    def test_featured_identifiers_are_split_and_matched(self) -> None:
        """`featured` は "mousePressed_" 形式。分割と _ の扱いを同時に踏む。"""
        tags = gen.tags_for(Path("Topics/GUI/Button"), {"featured": ["mousePressed_"]})
        self.assertIn("interaction", tags)

    def test_multi_word_needle_matches_across_any_whitespace(self) -> None:
        """2 語からなる needle（`ray tracing`）。

        分割が入れる空白 1 個とも、Processing 由来の説明文が持ったままの
        改行 + インデントとも噛み合う必要がある。
        """
        pattern = gen.keyword_pattern("ray tracing")
        self.assertTrue(pattern.search("real-time ray tracing on the gpu"))
        self.assertTrue(pattern.search("real-time ray\n  tracing on the gpu"))
        self.assertIsNone(pattern.search("arrays tracing indices"))


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
