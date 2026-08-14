#!/usr/bin/env python3
"""Unit tests for scripts/pr-changed-files.sh.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

The thing being pinned is the difference between `A B` and `A...B` (Issue #642).
`github.event.pull_request.base.sha` is the base branch tip at event time, not
the PR's branch point, so a two-dot diff folds whatever landed on `main` after
the branch point into "what this PR changed". Both per-PR gates break on that,
in opposite directions and both silently:

  * the visual-evidence check (Issue #631) fails PRs that touched no Swift at
    all, which teaches people to wave `no-visual-change` through
  * the changelog check (Issue #461) *passes* PRs with no entry of their own,
    because a release deletes every `changelog.d/*.md` and two-dot reports
    those deletions as additions on the PR side

Neither shows up as a broken check — the gate stays green and stops meaning
anything. So the tests build a real repository where `main` has moved on, which
is the only shape where the two spellings disagree.
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "pr-changed-files.sh"


def _git(repo: Path, *args: str) -> str:
    """Run git in `repo`, returning stdout."""
    result = subprocess.run(
        ["git", "-C", str(repo), "-c", "commit.gpgsign=false", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def _commit(repo: Path, message: str, **files: str | None) -> str:
    """Write/delete `files` (None deletes), commit, and return the new SHA."""
    for name, content in files.items():
        path = repo / name.replace("__", "/")
        if content is None:
            path.unlink()
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", message)
    return _git(repo, "rev-parse", "HEAD").strip()


class PrChangedFilesTests(unittest.TestCase):
    """Every test runs against this history:

        A ── B  (main: edits a drawing file, deletes the old changelog entry —
        │        what a release commit looks like)
        ├──── C (feature: docs only)
        └──── D (feature-with-entry: docs + its own changelog.d entry)

    `B` is what the workflow passes as BASE_SHA once main has moved on.
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(self._tmp.name)

        _git(self.repo, "init", "-q", "-b", "main")
        _git(self.repo, "config", "user.email", "t@example.com")
        _git(self.repo, "config", "user.name", "t")

        # The script resolves the repository root from its own location, so it
        # has to live inside the synthetic repo (same as in a real checkout).
        (self.repo / "scripts").mkdir()
        self.script = self.repo / "scripts" / "pr-changed-files.sh"
        shutil.copy2(_SCRIPT, self.script)

        self.a = _commit(
            self.repo,
            "base",
            **{
                "Sources__MetaphorCore__Drawing__Renderer.swift": "// v1\n",
                "docs__guide.md": "guide\n",
                "changelog.d__old.feature.md": "shipped already\n",
            },
        )
        self.b = _commit(
            self.repo,
            "main moves on: a drawing change, and a release collecting the entry",
            **{
                "Sources__MetaphorCore__Drawing__Renderer.swift": "// v2\n",
                "changelog.d__old.feature.md": None,
            },
        )

        _git(self.repo, "checkout", "-q", "-b", "feature", self.a)
        self.c = _commit(self.repo, "docs only", **{"docs__new.md": "new\n"})

        _git(self.repo, "checkout", "-q", "-b", "feature-with-entry", self.a)
        self.d = _commit(
            self.repo,
            "docs plus an entry",
            **{"docs__new.md": "new\n", "changelog.d__mine.fix.md": "mine\n"},
        )

    def run_script(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [str(self.script), *args], capture_output=True, text=True
        )

    def changed(self, *args: str) -> list[str]:
        result = self.run_script(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return sorted(line for line in result.stdout.splitlines() if line)

    def two_dot(self, base: str, head: str, *args: str) -> list[str]:
        """The spelling this script exists to replace, for contrast."""
        out = _git(self.repo, "diff", "--name-only", base, head, *args)
        return sorted(line for line in out.splitlines() if line)

    # --- the false positive that motivated this (Issue #642) ---------------

    def test_a_main_side_drawing_change_is_not_attributed_to_the_branch(self):
        # The branch touched no Swift at all, so the visual-evidence check must
        # see nothing under Sources/.
        self.assertEqual(self.changed(self.b, self.c, "--", "Sources/*"), [])

    def test_two_dot_is_what_gets_this_wrong(self):
        # Same inputs, the old spelling: main's drawing change shows up as if
        # the branch had made it. This is the failure being fixed, pinned so
        # that reverting the script cannot look like an equivalent rewrite.
        self.assertEqual(
            self.two_dot(self.b, self.c, "--", "Sources/*"),
            ["Sources/MetaphorCore/Drawing/Renderer.swift"],
        )

    # --- the false negative on the other gate (Issue #461) ------------------

    def test_an_entry_deleted_by_a_release_is_not_an_addition_on_the_branch(self):
        # `feature` added no changelog.d entry. The release on main deleted
        # old.feature.md, and two-dot would hand that back as an addition —
        # letting a PR that wrote nothing satisfy the changelog gate.
        self.assertEqual(
            self.changed(self.b, self.c, "--diff-filter=A", "--", "changelog.d/*.md"),
            [],
        )
        self.assertEqual(
            self.two_dot(self.b, self.c, "--diff-filter=A", "--", "changelog.d/*.md"),
            ["changelog.d/old.feature.md"],
        )

    def test_the_branchs_own_entry_is_still_found(self):
        self.assertEqual(
            self.changed(self.b, self.d, "--diff-filter=A", "--", "changelog.d/*.md"),
            ["changelog.d/mine.fix.md"],
        )

    # --- ordinary behaviour -------------------------------------------------

    def test_files_the_branch_did_change_are_listed(self):
        self.assertEqual(self.changed(self.b, self.d), sorted(
            ["changelog.d/mine.fix.md", "docs/new.md"]
        ))

    def test_pathspec_filters(self):
        self.assertEqual(self.changed(self.b, self.d, "--", "docs/*"), ["docs/new.md"])

    def test_up_to_date_branch_matches_two_dot(self):
        # When base is already an ancestor of head the two spellings agree, so
        # switching cost nothing for PRs that are not behind.
        self.assertEqual(
            self.changed(self.a, self.c), self.two_dot(self.a, self.c)
        )

    def test_non_ascii_paths_are_not_octal_escaped(self):
        # Without `core.quotePath=false` git prints "docs/\346\227\245..." and
        # the judging scripts would compare against a path that does not exist.
        _git(self.repo, "checkout", "-q", "feature")
        head = _commit(self.repo, "japanese filename", **{"docs__日本語.md": "x\n"})
        self.assertIn("docs/日本語.md", self.changed(self.b, head))

    def test_runs_from_any_working_directory(self):
        # ci.yml runs it from the repository root, but the pathspecs are
        # repo-relative regardless (same contract as changed-examples.sh).
        result = subprocess.run(
            [str(self.script), self.b, self.d, "--", "docs/*"],
            capture_output=True,
            text=True,
            cwd=str(self.repo / "scripts"),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "docs/new.md")

    # --- failure modes the caller depends on ---------------------------------

    def test_missing_arguments_is_a_usage_error(self):
        result = self.run_script(self.b)
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_unreachable_revision_fails_so_ci_can_fall_back(self):
        # `Detect Source changes` wraps the call in `if ! changed_files=$(...)`
        # to survive a force-pushed tip going away; that only works if a bad
        # revision is a non-zero exit rather than empty output.
        result = self.run_script("0" * 40, self.d)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
