#!/usr/bin/env python3
"""Unit tests for scripts/release-bump.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

release-bump.py decides what the weekly release train ships. A wrong answer is
either a silent non-release (the failure mode the train exists to fix) or an
unintended tag, so every rule gets a case here: which types release, how the
strongest bump wins, what is deliberately ignored, and which signals escalate
to a human instead of being folded into a minor.
"""

import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "release-bump.py"
_spec = importlib.util.spec_from_file_location("release_bump", _SCRIPT)
rb = importlib.util.module_from_spec(_spec)
sys.modules["release_bump"] = rb
_spec.loader.exec_module(rb)


class ParseTypeTests(unittest.TestCase):
    def test_plain_type(self):
        self.assertEqual(rb.parse_type("feat: add circle()"), ("feat", False))

    def test_scoped_type(self):
        self.assertEqual(rb.parse_type("fix(state): reset the clock"), ("fix", False))

    def test_breaking_marker(self):
        self.assertEqual(rb.parse_type("feat(core)!: drop legacy API"), ("feat", True))

    def test_release_commit_is_not_conventional(self):
        # release.yml titles its own bump commit this way; it must never be
        # read as a releasable change, or every release would trigger another.
        self.assertEqual(rb.parse_type("Release v0.8.0 (#312)"), (None, False))

    def test_prose_subject(self):
        self.assertEqual(rb.parse_type("update the readme"), (None, False))

    def test_leading_whitespace_is_tolerated(self):
        self.assertEqual(rb.parse_type("  docs: tidy"), ("docs", False))


class BumpForTests(unittest.TestCase):
    def test_feat_is_minor(self):
        bump, breaking = rb.bump_for(["feat(shapes): add arc()"])
        self.assertEqual(bump, "minor")
        self.assertEqual(breaking, [])

    def test_fix_and_perf_are_patch(self):
        self.assertEqual(rb.bump_for(["fix: leak"])[0], "patch")
        self.assertEqual(rb.bump_for(["perf: fewer draw calls"])[0], "patch")

    def test_strongest_bump_wins_regardless_of_order(self):
        self.assertEqual(rb.bump_for(["feat: a", "fix: b"])[0], "minor")
        self.assertEqual(rb.bump_for(["fix: b", "feat: a"])[0], "minor")

    def test_non_releasing_types_alone_release_nothing(self):
        subjects = ["docs: x", "chore: y", "ci: z", "refactor: w", "test: v"]
        self.assertIsNone(rb.bump_for(subjects)[0])

    def test_non_releasing_types_ride_along(self):
        # A docs-only week ships nothing, but docs merged alongside a fix must
        # not downgrade or block that fix.
        self.assertEqual(rb.bump_for(["docs: x", "fix: y"])[0], "patch")

    def test_empty_history(self):
        self.assertEqual(rb.bump_for([]), (None, []))

    def test_breaking_marker_is_reported_not_folded_into_minor(self):
        bump, breaking = rb.bump_for(["feat!: drop 2D fallback", "fix: leak"])
        self.assertEqual(bump, "minor")  # caller escalates on `breaking`
        self.assertEqual(breaking, ["feat!: drop 2D fallback"])

    def test_breaking_on_a_non_releasing_type_still_counts(self):
        _, breaking = rb.bump_for(["refactor!: rename internals"])
        self.assertEqual(len(breaking), 1)


class PendingBreakingEntryTests(unittest.TestCase):
    def test_breaking_entry_files_are_found(self):
        with tempfile.TemporaryDirectory() as tmp:
            entries = Path(tmp) / "changelog.d"
            entries.mkdir()
            (entries / "419.added.md").write_text("- added\n", encoding="utf-8")
            (entries / "420.breaking.md").write_text("- broke\n", encoding="utf-8")
            self.assertEqual(
                rb.pending_breaking_entries(Path(tmp)), ["420.breaking.md"]
            )

    def test_no_breaking_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "changelog.d").mkdir()
            self.assertEqual(rb.pending_breaking_entries(Path(tmp)), [])


class LatestStableTagTests(unittest.TestCase):
    def _git(self, repo: Path, *args: str) -> None:
        subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)

    def test_prereleases_are_ignored_and_versions_sort_numerically(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            self._git(repo, "init", "-q")
            self._git(repo, "config", "user.email", "t@example.com")
            self._git(repo, "config", "user.name", "t")
            self._git(repo, "commit", "-q", "--allow-empty", "-m", "feat: one")
            # v0.10.0 must beat v0.9.0 (string sort would pick v0.9.0), and the
            # newer prerelease tag must not win over either. Tags are annotated
            # (`-m`) so the test passes under a global `tag.gpgSign` /
            # `tag.forceSignAnnotated`, which rejects a bare `git tag <name>`.
            for tag in ("v0.9.0", "v0.10.0", "v0.11.0-beta.1"):
                self._git(repo, "tag", "-m", tag, tag)
            self.assertEqual(rb.latest_stable_tag(repo), "v0.10.0")

    def test_no_tags_yet(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            self._git(repo, "init", "-q")
            self.assertIsNone(rb.latest_stable_tag(repo))


class MainTests(unittest.TestCase):
    def _run(self, argv: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = rb.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_subject_mode_prints_the_bump(self):
        code, out, _ = self._run(["--subject", "feat: add arc()"])
        self.assertEqual((code, out.strip()), (0, "minor"))

    def test_nothing_to_release_prints_nothing(self):
        code, out, _ = self._run(["--subject", "docs: tidy"])
        self.assertEqual((code, out), (0, ""))

    def test_fallback_covers_the_hotfix_path(self):
        # `release:now` on a chore PR still has to ship something.
        code, out, _ = self._run(["--subject", "chore: bump pin", "--fallback", "patch"])
        self.assertEqual((code, out.strip()), (0, "patch"))

    def test_fallback_does_not_downgrade_a_feat(self):
        code, out, _ = self._run(["--subject", "feat: add arc()", "--fallback", "patch"])
        self.assertEqual(out.strip(), "minor")

    def test_breaking_change_escalates(self):
        code, out, err = self._run(["--subject", "feat!: drop the old API"])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("release:major", err)

    def test_github_output_is_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.txt"
            self._run(["--subject", "fix: leak", "--github-output", str(path)])
            self.assertEqual(path.read_text(encoding="utf-8"), "bump=patch\n")

    def test_github_output_is_empty_when_nothing_to_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.txt"
            self._run(["--subject", "docs: tidy", "--github-output", str(path)])
            self.assertEqual(path.read_text(encoding="utf-8"), "bump=\n")

    def test_explain_summarises_the_history(self):
        _, _, err = self._run(
            ["--subject", "feat: a", "--subject", "docs: b", "--explain"]
        )
        self.assertIn("2 commit(s)", err)
        self.assertIn("feat", err)


if __name__ == "__main__":
    unittest.main()
