#!/usr/bin/env python3
"""Unit tests for scripts/release-bump.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

release-bump.py decides what the weekly release train ships. A wrong answer is
either a silent non-release (the failure mode the train exists to fix) or an
unintended tag, so every rule gets a case here: which types release, how the
strongest bump wins, what is deliberately ignored, and what a breaking marker
does on each side of `1.0.0` (ride in a minor, or escalate to a human).
"""

import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "release-bump.py"
_spec = importlib.util.spec_from_file_location("release_bump", _SCRIPT)
rb = importlib.util.module_from_spec(_spec)
sys.modules["release_bump"] = rb
_spec.loader.exec_module(rb)


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


@contextmanager
def _repo_released_at(tag: str | None):
    """A throwaway repository whose latest stable tag is `tag`.

    Every test that exercises the breaking-change policy pins the version this
    way instead of reading the real repository: the rule flips at `1.0.0`, and
    a test that borrowed the actual tag would start asserting the other branch
    on the day metaphor ships v1.0.0.
    """
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        _git(repo, "init", "-q")
        _git(repo, "config", "user.email", "t@example.com")
        _git(repo, "config", "user.name", "t")
        _git(repo, "commit", "-q", "--allow-empty", "-m", "chore: seed")
        if tag is not None:
            # Annotated (`-m`) so the test survives a global `tag.gpgSign` /
            # `tag.forceSignAnnotated`, which rejects a bare `git tag <name>`.
            _git(repo, "tag", "-m", tag, tag)
        yield repo


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

    def test_breaking_markers_are_reported_separately(self):
        # bump_for only counts types; what the marker means is the caller's
        # call, because it depends on the version (BreakingChangeTests).
        bump, breaking = rb.bump_for(["feat!: drop 2D fallback", "fix: leak"])
        self.assertEqual(bump, "minor")
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
    def test_prereleases_are_ignored_and_versions_sort_numerically(self):
        with _repo_released_at(None) as repo:
            # v0.10.0 must beat v0.9.0 (string sort would pick v0.9.0), and the
            # newer prerelease tag must not win over either.
            for tag in ("v0.9.0", "v0.10.0", "v0.11.0-beta.1"):
                _git(repo, "tag", "-m", tag, tag)
            self.assertEqual(rb.latest_stable_tag(repo), "v0.10.0")

    def test_no_tags_yet(self):
        with _repo_released_at(None) as repo:
            self.assertIsNone(rb.latest_stable_tag(repo))


class BreakingMeansMajorTests(unittest.TestCase):
    """Which side of 1.0.0 the version is on decides what a break means."""

    def test_zero_versions_are_before_the_freeze(self):
        self.assertFalse(rb.breaking_means_major("v0.9.0"))
        self.assertFalse(rb.breaking_means_major("v0.10.0"))

    def test_one_zero_and_later_require_a_major(self):
        self.assertTrue(rb.breaking_means_major("v1.0.0"))
        self.assertTrue(rb.breaking_means_major("v2.3.1"))
        self.assertTrue(rb.breaking_means_major("v10.0.0"))

    def test_no_release_yet_is_before_the_freeze(self):
        self.assertFalse(rb.breaking_means_major(None))

    def test_an_unreadable_tag_takes_the_strict_branch(self):
        # Better to ask a human than to fold a break into a minor on a guess.
        self.assertTrue(rb.breaking_means_major("nightly"))


def _run(argv: list[str]) -> tuple[int, str, str]:
    """`main(argv)` with its streams captured: `(exit code, stdout, stderr)`."""
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = rb.main(argv)
    return code, out.getvalue(), err.getvalue()


class MainTests(unittest.TestCase):
    def test_subject_mode_prints_the_bump(self):
        code, out, _ = _run(["--subject", "feat: add arc()"])
        self.assertEqual((code, out.strip()), (0, "minor"))

    def test_nothing_to_release_prints_nothing(self):
        code, out, _ = _run(["--subject", "docs: tidy"])
        self.assertEqual((code, out), (0, ""))

    def test_fallback_covers_the_hotfix_path(self):
        # `release:now` on a chore PR still has to ship something.
        code, out, _ = _run(["--subject", "chore: bump pin", "--fallback", "patch"])
        self.assertEqual((code, out.strip()), (0, "patch"))

    def test_fallback_does_not_downgrade_a_feat(self):
        code, out, _ = _run(["--subject", "feat: add arc()", "--fallback", "patch"])
        self.assertEqual(out.strip(), "minor")

    def test_github_output_is_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.txt"
            _run(["--subject", "fix: leak", "--github-output", str(path)])
            self.assertEqual(path.read_text(encoding="utf-8"), "bump=patch\n")

    def test_github_output_is_empty_when_nothing_to_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.txt"
            _run(["--subject", "docs: tidy", "--github-output", str(path)])
            self.assertEqual(path.read_text(encoding="utf-8"), "bump=\n")

    def test_explain_summarises_the_history(self):
        _, _, err = _run(
            ["--subject", "feat: a", "--subject", "docs: b", "--explain"]
        )
        self.assertIn("2 commit(s)", err)
        self.assertIn("feat", err)


class BreakingChangeTests(unittest.TestCase):
    """What a breaking marker does, on both sides of 1.0.0.

    The version is pinned per test (`_repo_released_at`) rather than read from
    the repository, so both branches stay covered before and after v1.0.0.
    """

    def _run_at(self, tag: str | None, argv: list[str]) -> tuple[int, str, str]:
        with _repo_released_at(tag) as repo:
            return _run(["--repo", str(repo), *argv])

    def test_breaking_rides_in_a_minor_while_0_x(self):
        code, out, err = self._run_at("v0.9.0", ["--subject", "feat!: drop the old API"])
        self.assertEqual((code, out.strip()), (0, "minor"))
        self.assertIn("::warning::", err)
        self.assertIn("feat!: drop the old API", err)

    def test_breaking_raises_a_patch_week_to_a_minor(self):
        code, out, _ = self._run_at(
            "v0.9.0", ["--subject", "fix: leak", "--subject", "feat!: drop the old API"]
        )
        self.assertEqual((code, out.strip()), (0, "minor"))

    def test_breaking_on_a_non_releasing_type_still_ships(self):
        # PR #637 (`refactor(api)!: …`, the removal half of #322): `refactor`
        # releases nothing on its own, so without the forced minor the removal
        # would ride in no release at all.
        code, out, _ = self._run_at(
            "v0.9.0", ["--subject", "refactor(api)!: remove the deprecated names"]
        )
        self.assertEqual((code, out.strip()), (0, "minor"))

    def test_no_release_yet_still_counts_as_0_x(self):
        code, out, _ = self._run_at(None, ["--subject", "feat!: drop the old API"])
        self.assertEqual((code, out.strip()), (0, "minor"))

    def test_breaking_escalates_from_1_0_on(self):
        code, out, err = self._run_at("v1.0.0", ["--subject", "feat!: drop the old API"])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("release:major", err)

    def test_pending_changelog_entry_rides_in_a_minor_while_0_x(self):
        # The second breaking signal: an entry file with no `!` in any subject.
        with _repo_released_at("v0.9.0") as repo:
            entries = repo / "changelog.d"
            entries.mkdir()
            (entries / "322.breaking.md").write_text("- removed\n", encoding="utf-8")
            _git(repo, "commit", "-q", "--allow-empty", "-m", "docs: tidy")
            code, out, err = _run(["--repo", str(repo)])
        self.assertEqual((code, out.strip()), (0, "minor"))
        self.assertIn("322.breaking.md", err)

    def test_pending_changelog_entry_escalates_from_1_0_on(self):
        with _repo_released_at("v1.0.0") as repo:
            entries = repo / "changelog.d"
            entries.mkdir()
            (entries / "322.breaking.md").write_text("- removed\n", encoding="utf-8")
            code, _, err = _run(["--repo", str(repo)])
        self.assertEqual(code, 2)
        self.assertIn("release:major", err)

    def test_the_bump_reaches_github_output(self):
        # The train reads the bump from $GITHUB_OUTPUT, not from stdout.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.txt"
            self._run_at(
                "v0.9.0",
                ["--subject", "refactor!: rename", "--github-output", str(path)],
            )
            self.assertEqual(path.read_text(encoding="utf-8"), "bump=minor\n")


if __name__ == "__main__":
    unittest.main()
