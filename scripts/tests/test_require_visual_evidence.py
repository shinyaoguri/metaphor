#!/usr/bin/env python3
"""Unit tests for scripts/require-visual-evidence.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

This check blocks merges, so both directions cost something real: a miss lets
a drawing change land with no record of what it draws (unrecoverable — `main`
is squash-only), and a false positive stops work that never touched a pixel.
The path list is therefore pinned against the actual PRs it was derived from
(Issue #631), so widening or narrowing it has to be a deliberate edit here too.
"""

import importlib.util
import io
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "require-visual-evidence.py"
_spec = importlib.util.spec_from_file_location("require_visual_evidence", _SCRIPT)
rve = importlib.util.module_from_spec(_spec)
sys.modules["require_visual_evidence"] = rve
_spec.loader.exec_module(rve)

GYAZO = "![before/after](https://i.gyazo.com/0123456789abcdef0123456789abcdef.png)"


def run(changed: list[str], body: str = "", labels: list[str] | None = None):
    """Invoke the CLI the way ci.yml does; return (exit code, stdout, stderr)."""
    argv = ["--body", body]
    for label in labels or []:
        argv += ["--label", label]
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = rve.main(argv, stdin=io.StringIO("\n".join(changed)))
    return code, out.getvalue(), err.getvalue()


class IsVisualPathTests(unittest.TestCase):
    """Which files are treated as drawing changes."""

    def test_every_listed_directory_counts(self):
        for directory in rve.VISUAL_DIRS:
            with self.subTest(directory=directory):
                self.assertTrue(
                    rve.is_visual_path(f"Sources/MetaphorCore/{directory}/Thing.swift")
                )

    def test_nested_file_counts(self):
        self.assertTrue(
            rve.is_visual_path("Sources/MetaphorCore/Shaders/Metal/Blur.metal")
        )

    def test_core_is_excluded_on_purpose(self):
        # #609 touched Core/ResourceLoader.swift, but that PR is caught by its
        # Sketch/ change. Core/ holds plenty that never reaches a pixel, so
        # including it would fire on work that changes nothing visible.
        self.assertFalse(
            rve.is_visual_path("Sources/MetaphorCore/Core/ResourceLoader.swift")
        )

    def test_other_modules_do_not_count(self):
        self.assertFalse(rve.is_visual_path("Sources/MetaphorNetwork/MIDIManager.swift"))
        self.assertFalse(rve.is_visual_path("Sources/MetaphorPhysics/Physics2D.swift"))

    def test_non_sources_paths_do_not_count(self):
        self.assertFalse(rve.is_visual_path("docs/tutorial/01-hello.md"))
        self.assertFalse(rve.is_visual_path("Examples/Basics/Form/Shapes/App.swift"))

    def test_a_bare_directory_name_is_not_a_file(self):
        self.assertFalse(rve.is_visual_path("Sources/MetaphorCore/Drawing"))


class HasEvidenceTests(unittest.TestCase):
    """What counts as an image in the PR body."""

    def test_gyazo_direct_url(self):
        self.assertTrue(rve.has_evidence(GYAZO))

    def test_gyazo_page_url(self):
        self.assertTrue(
            rve.has_evidence("https://gyazo.com/0123456789abcdef0123456789abcdef")
        )

    def test_gyazo_gif(self):
        self.assertTrue(
            rve.has_evidence("https://i.gyazo.com/abc123def456abc123def456abc12345.gif")
        )

    def test_github_attachment(self):
        self.assertTrue(
            rve.has_evidence("https://github.com/user-attachments/assets/abc-123")
        )

    def test_legacy_github_user_images(self):
        self.assertTrue(
            rve.has_evidence("https://user-images.githubusercontent.com/1/2.png")
        )

    def test_prose_about_images_is_not_an_image(self):
        self.assertFalse(rve.has_evidence("before/after のスクリーンショットは省略します"))

    def test_a_link_to_some_other_host_is_not_accepted(self):
        self.assertFalse(rve.has_evidence("https://example.com/screenshot.png"))

    def test_empty_body(self):
        self.assertFalse(rve.has_evidence(""))
        self.assertFalse(rve.has_evidence(None))


class MainTests(unittest.TestCase):
    """End-to-end, the way ci.yml calls it."""

    def test_no_visual_change_is_not_asked(self):
        code, out, _ = run(["Sources/MetaphorNetwork/MIDIManager.swift"])
        self.assertEqual(code, 0)
        self.assertIn("要求しません", out)

    def test_nothing_changed_at_all(self):
        code, _, _ = run([])
        self.assertEqual(code, 0)

    def test_drawing_change_without_evidence_fails(self):
        code, _, err = run(["Sources/MetaphorCore/Drawing/TextRenderer.swift"])
        self.assertEqual(code, 1)
        self.assertIn("::error::", err)
        # The message has to say how to get out of it, both ways.
        self.assertIn("Gyazo", err)
        self.assertIn(rve.SKIP_LABEL, err)

    def test_drawing_change_with_evidence_passes(self):
        code, out, _ = run(
            ["Sources/MetaphorCore/Drawing/TextRenderer.swift"], body=GYAZO
        )
        self.assertEqual(code, 0)
        self.assertIn("視覚証跡あり", out)

    def test_label_skips_the_check_but_says_so(self):
        code, out, _ = run(
            ["Sources/MetaphorCore/Drawing/TextRenderer.swift"],
            labels=[rve.SKIP_LABEL],
        )
        self.assertEqual(code, 0)
        # Skipping is recorded in the log, never silent.
        self.assertIn("::notice::", out)

    def test_an_unrelated_label_does_not_skip(self):
        code, _, err = run(
            ["Sources/MetaphorCore/Drawing/TextRenderer.swift"], labels=["enhancement"]
        )
        self.assertEqual(code, 1)
        self.assertIn("::error::", err)

    def test_one_visual_file_among_many_is_enough_to_ask(self):
        code, _, _ = run(
            [
                "README.md",
                "Sources/MetaphorPhysics/Physics2D.swift",
                "Sources/MetaphorCore/UI/PerformanceHUD.swift",
            ]
        )
        self.assertEqual(code, 1)

    def test_long_file_lists_are_truncated_in_the_message(self):
        changed = [f"Sources/MetaphorCore/Drawing/F{i}.swift" for i in range(8)]
        code, _, err = run(changed)
        self.assertEqual(code, 1)
        self.assertIn("ほか", err)


class RegressionTests(unittest.TestCase):
    """The PRs the path list was derived from (Issue #631)."""

    CASES = (
        # (PR, changed files, should the check fire?)
        (591, ["Sources/MetaphorCore/Drawing/TextRenderer.swift"], True),
        (575, ["Sources/MetaphorCore/UI/PerformanceHUD.swift"], True),
        (
            609,
            [
                "Sources/MetaphorCore/Core/ResourceLoader.swift",
                "Sources/MetaphorCore/Sketch/Sketch+3D.swift",
                "Sources/MetaphorCore/Sketch/SketchContext+3D.swift",
            ],
            True,
        ),
        (
            592,
            [
                "Sources/MetaphorNetwork/MIDIManager.swift",
                "Sources/MetaphorNetwork/MIDIMessage.swift",
            ],
            False,
        ),
        (628, ["scripts/generate-example-shots.py"], False),
    )

    def test_historical_prs(self):
        for pr, changed, should_fire in self.CASES:
            with self.subTest(pr=pr):
                code, _, _ = run(changed)
                self.assertEqual(code, 1 if should_fire else 0)


if __name__ == "__main__":
    unittest.main()
