#!/usr/bin/env python3
"""Unit tests for scripts/require-changelog-entry.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

This check decides whether a PR is allowed to merge without saying what
changed. Both directions are damaging: a false pass puts the discovery back on
the weekly train (the failure mode Issue #461 exists to fix), and a false fail
blocks internal work that legitimately ships without an entry (#335 / #404).
So every rule gets a case here — which types demand an entry, what counts as an
entry, and the two ways out (write one, or record the decision with a label).
"""

import importlib.util
import io
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "require-changelog-entry.py"
_spec = importlib.util.spec_from_file_location("require_changelog_entry", _SCRIPT)
rce = importlib.util.module_from_spec(_spec)
sys.modules["require_changelog_entry"] = rce
_spec.loader.exec_module(rce)


def run(subject: str, added: list[str], labels: list[str] | None = None):
    """Invoke the CLI the way ci.yml does; return (exit code, stdout, stderr)."""
    argv = ["--subject", subject]
    for label in labels or []:
        argv += ["--label", label]
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = rce.main(argv, stdin=io.StringIO("\n".join(added)))
    return code, out.getvalue(), err.getvalue()


class EntryRequiredTests(unittest.TestCase):
    """Which PR titles have to be written down."""

    def test_feat_requires_an_entry(self):
        self.assertTrue(rce.entry_required("feat: add circle()")[0])

    def test_fix_requires_an_entry(self):
        self.assertTrue(rce.entry_required("fix(state): reset the clock")[0])

    def test_perf_requires_an_entry(self):
        self.assertTrue(rce.entry_required("perf: batch the draw calls")[0])

    def test_chore_does_not(self):
        self.assertFalse(rce.entry_required("chore(deps): bump actions/cache")[0])

    def test_ci_does_not(self):
        self.assertFalse(rce.entry_required("ci: lint workflows")[0])

    def test_docs_does_not(self):
        self.assertFalse(rce.entry_required("docs: fix a typo")[0])

    def test_breaking_marker_requires_an_entry_even_for_a_quiet_type(self):
        # A break is exactly what an upgrader needs told, whatever the type.
        self.assertTrue(rce.entry_required("chore!: drop the legacy flag")[0])

    def test_breaking_feat_requires_an_entry(self):
        self.assertTrue(rce.entry_required("feat(core)!: drop legacy API")[0])

    def test_non_conventional_title_is_left_to_the_title_lint(self):
        # ci.yml's PR-title lint owns that failure; reporting it twice with
        # different wording only confuses the author.
        self.assertFalse(rce.entry_required("いろいろ直した")[0])

    def test_the_type_list_is_release_bumps_list(self):
        """The releasing types are imported, never re-listed here."""
        for commit_type, _ in rce._release_bump.BUMP_BY_TYPE.items():
            with self.subTest(commit_type=commit_type):
                self.assertTrue(rce.entry_required(f"{commit_type}: x")[0])


class IsEntryTests(unittest.TestCase):
    """What counts as an entry file."""

    def test_entry_file(self):
        self.assertTrue(rce.is_entry("changelog.d/circle-api.added.md"))

    def test_readme_is_documentation_not_an_entry(self):
        self.assertFalse(rce.is_entry("changelog.d/README.md"))

    def test_other_directories_do_not_count(self):
        self.assertFalse(rce.is_entry("docs/whatever.added.md"))
        self.assertFalse(rce.is_entry("CHANGELOG.md"))

    def test_nested_paths_do_not_count(self):
        self.assertFalse(rce.is_entry("changelog.d/nested/thing.added.md"))

    def test_non_markdown_does_not_count(self):
        self.assertFalse(rce.is_entry("changelog.d/notes.txt"))


class CommandTests(unittest.TestCase):
    """End-to-end through main(), as ci.yml calls it."""

    def test_feat_without_an_entry_fails(self):
        code, _, err = run("feat: add circle()", ["Sources/MetaphorCore/Canvas2D.swift"])
        self.assertEqual(code, 1)
        self.assertIn("::error::", err)
        # The message has to carry both ways out, or it just blocks.
        self.assertIn("changelog.d/<slug>.<category>.md", err)
        self.assertIn("no-changelog", err)

    def test_feat_with_an_entry_passes(self):
        code, out, _ = run(
            "feat: add circle()",
            ["Sources/MetaphorCore/Canvas2D.swift", "changelog.d/circle.added.md"],
        )
        self.assertEqual(code, 0)
        self.assertIn("changelog.d/circle.added.md", out)

    def test_readme_alone_does_not_satisfy_the_check(self):
        code, _, err = run("feat: add circle()", ["changelog.d/README.md"])
        self.assertEqual(code, 1)
        self.assertIn("::error::", err)

    def test_dependabot_chore_passes_without_an_entry(self):
        code, out, _ = run("chore(deps): bump actions/cache from 5 to 6", [])
        self.assertEqual(code, 0)
        self.assertIn("不要", out)

    def test_no_changelog_label_passes_and_is_announced(self):
        code, out, _ = run(
            "feat: add circle()", ["Sources/x.swift"], labels=["no-changelog"]
        )
        self.assertEqual(code, 0)
        self.assertIn("::notice::", out)

    def test_other_labels_do_not_skip_the_check(self):
        code, _, err = run(
            "feat: add circle()", ["Sources/x.swift"], labels=["enhancement", "bug"]
        )
        self.assertEqual(code, 1)
        self.assertIn("::error::", err)

    def test_breaking_change_without_an_entry_fails(self):
        code, _, err = run("chore!: drop the legacy flag", [])
        self.assertEqual(code, 1)
        self.assertIn("::error::", err)

    def test_no_added_files_at_all_is_handled(self):
        # An empty stdin (a PR that only deletes or modifies files).
        code, _, err = run("fix: correct the offset", [])
        self.assertEqual(code, 1)
        self.assertIn("::error::", err)


if __name__ == "__main__":
    unittest.main()
