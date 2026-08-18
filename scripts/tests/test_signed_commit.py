#!/usr/bin/env python3
"""Unit tests for scripts/signed-commit.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

This script sits on the release path and cannot be rehearsed there: a mistake
shows up as a failed release after the Syphon build and a full CI run. So the
two pure pieces — reading `git status --porcelain` and assembling the GraphQL
input — are tested directly, with the release workflow's own change set (edited
files plus deleted `changelog.d/` entries) as the central case.
"""

import base64
import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import ExitStack, redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from _git_helpers import git as hermetic_git, hermetic_environ, init_repo

_SCRIPT = Path(__file__).resolve().parents[1] / "signed-commit.py"
_spec = importlib.util.spec_from_file_location("signed_commit", _SCRIPT)
sc = importlib.util.module_from_spec(_spec)
sys.modules["signed_commit"] = sc
_spec.loader.exec_module(sc)

# `expectedHeadOid` is a GitObjectID, so the payload only ever carries the full
# 40-character form — `main()` normalizes whatever was passed through
# `git rev-parse` first (Issue #981). Tests that never resolve a real commit use
# this placeholder, which `rev-parse` echoes back even in an empty repository.
_FULL_SHA = "0" * 39 + "1"


class ParsePorcelainTests(unittest.TestCase):
    def test_release_change_set(self):
        # What `release.yml` actually produces: edited files plus the collected
        # changelog.d entries, which the release commit has to carry as deletions
        # (otherwise the next release collects them a second time).
        porcelain = "\n".join(
            [
                " M Package.swift",
                " M CHANGELOG.md",
                " M Sources/MetaphorCore/Core/MetaphorVersion.swift",
                " D changelog.d/419.added.md",
                " D changelog.d/298.fixed.md",
            ]
        )
        additions, deletions = sc.parse_porcelain(porcelain)
        self.assertEqual(
            additions,
            [
                "CHANGELOG.md",
                "Package.swift",
                "Sources/MetaphorCore/Core/MetaphorVersion.swift",
            ],
        )
        self.assertEqual(
            deletions, ["changelog.d/298.fixed.md", "changelog.d/419.added.md"]
        )

    def test_staged_and_unstaged_are_treated_alike(self):
        additions, deletions = sc.parse_porcelain("M  a.txt\n M b.txt\nMM c.txt")
        self.assertEqual(additions, ["a.txt", "b.txt", "c.txt"])
        self.assertEqual(deletions, [])

    def test_deletion_in_either_column(self):
        _, deletions = sc.parse_porcelain("D  staged.md\n D unstaged.md")
        self.assertEqual(deletions, ["staged.md", "unstaged.md"])

    def test_untracked_files_are_additions(self):
        additions, _ = sc.parse_porcelain("?? brand-new.md")
        self.assertEqual(additions, ["brand-new.md"])

    def test_rename_becomes_delete_plus_add(self):
        additions, deletions = sc.parse_porcelain("R  old.md -> new.md")
        self.assertEqual((additions, deletions), (["new.md"], ["old.md"]))

    def test_quoted_path_is_unquoted(self):
        additions, _ = sc.parse_porcelain(' M "docs/\\303\\251t\\303\\251.md"')
        self.assertEqual(len(additions), 1)
        self.assertNotIn('"', additions[0])

    def test_empty_output(self):
        self.assertEqual(sc.parse_porcelain(""), ([], []))

    def test_blank_lines_are_skipped(self):
        additions, _ = sc.parse_porcelain(" M a.txt\n\n")
        self.assertEqual(additions, ["a.txt"])


class BuildPayloadTests(unittest.TestCase):
    def _payload(self, message="Release v0.9.0"):
        return sc.build_payload(
            repo="shinyaoguri/metaphor",
            branch="release/v0.9.0",
            expected_head=_FULL_SHA,
            message=message,
            additions=[("Package.swift", "BASE64")],
            deletions=["changelog.d/419.added.md"],
        )

    def test_branch_and_lock(self):
        payload = self._payload()
        given = payload["variables"]["input"]
        self.assertEqual(
            given["branch"],
            {
                "repositoryNameWithOwner": "shinyaoguri/metaphor",
                "branchName": "release/v0.9.0",
            },
        )
        # Optimistic locking: without this the mutation could land on a branch
        # someone else moved.
        self.assertEqual(given["expectedHeadOid"], _FULL_SHA)

    def test_file_changes(self):
        changes = self._payload()["variables"]["input"]["fileChanges"]
        self.assertEqual(
            changes["additions"], [{"path": "Package.swift", "contents": "BASE64"}]
        )
        self.assertEqual(changes["deletions"], [{"path": "changelog.d/419.added.md"}])

    def test_single_line_message_has_no_body(self):
        message = self._payload()["variables"]["input"]["message"]
        self.assertEqual(message, {"headline": "Release v0.9.0"})

    def test_multiline_message_splits_on_blank_line(self):
        message = self._payload("Release v0.9.0\n\nAPI freeze.")["variables"]["input"][
            "message"
        ]
        self.assertEqual(
            message, {"headline": "Release v0.9.0", "body": "API freeze."}
        )

    def test_mutation_is_included(self):
        self.assertIn("createCommitOnBranch", self._payload()["query"])


class EncodeFileTests(unittest.TestCase):
    def test_bytes_are_base64_encoded(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f.txt"
            path.write_text("hello\n", encoding="utf-8")
            self.assertEqual(
                base64.b64decode(sc.encode_file(path)).decode("utf-8"), "hello\n"
            )


class _RepoTestCase(unittest.TestCase):
    """A throwaway repository, sealed off from the developer's git config (#979).

    `main()` shells out to git itself — `status --porcelain`, and since #981 also
    `rev-parse` — so `env=` is not ours to pass; `os.environ` gets the seal
    instead. Without it the developer's global config reaches into these
    repositories: a `core.excludesFile` that happens to cover `*.zip` would make
    the path-scoping test below pass for the wrong reason, and keep passing after
    the scoping broke.
    """

    def setUp(self) -> None:
        stack = ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(hermetic_environ())
        self.repo = init_repo(Path(stack.enter_context(tempfile.TemporaryDirectory())))

    def seed(self) -> str:
        """Give the repository one commit, and return its full SHA."""
        hermetic_git("commit", "-q", "--allow-empty", "-m", "seed", cwd=self.repo)
        return hermetic_git("rev-parse", "HEAD", cwd=self.repo).strip()

    def run_main(self, *args: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = sc.main([*args, "--repo-root", str(self.repo), "--dry-run"])
        return code, out.getvalue(), err.getvalue()


class ResolveHeadTests(_RepoTestCase):
    """`expectedHeadOid` only accepts 40 characters; everything else is expanded.

    The four shapes below are the ones a caller actually reaches for — and before
    #981 three of them died as a `Could not coerce value ... to GitObjectID`
    after the whole change set had been base64-encoded and sent.
    """

    def test_a_short_sha_is_expanded(self):
        head = self.seed()
        self.assertEqual(sc.resolve_head(head[:7], self.repo), head)

    def test_a_branch_name_is_expanded(self):
        head = self.seed()
        self.assertEqual(sc.resolve_head("main", self.repo), head)

    def test_head_is_expanded(self):
        head = self.seed()
        self.assertEqual(sc.resolve_head("HEAD", self.repo), head)

    def test_a_full_sha_is_passed_through_even_without_the_object(self):
        # No `--verify`, on purpose: a caller that read the branch head from the
        # API holds a valid SHA this checkout has never seen, and the mutation
        # is what checks it anyway.
        self.seed()
        self.assertEqual(sc.resolve_head(_FULL_SHA, self.repo), _FULL_SHA)

    def test_an_unknown_ref_is_an_error(self):
        self.seed()
        with self.assertRaises(subprocess.CalledProcessError):
            sc.resolve_head("no-such-ref", self.repo)


class MainTests(_RepoTestCase):
    def test_dry_run_reports_the_change_set_without_sending(self):
        (self.repo / "Package.swift").write_text("// v1\n", encoding="utf-8")

        code, out, err = self.run_main(
            "--repo",
            "shinyaoguri/metaphor",
            "--branch",
            "release/v0.9.0",
            "--expected-head",
            _FULL_SHA,
            "--message",
            "Release v0.9.0",
        )
        self.assertEqual(code, 0)
        self.assertIn("Package.swift", out)
        self.assertIn("+ Package.swift", err)

    def test_path_scoping_excludes_everything_else(self):
        # The release commit must carry the bumped files only. On a runner the
        # working tree also holds build output, and an unscoped commit would
        # sweep in whatever happens not to be gitignored.
        (self.repo / "Package.swift").write_text("// v1\n", encoding="utf-8")
        (self.repo / "build-output.zip").write_text("junk\n", encoding="utf-8")

        _, out, _ = self.run_main(
            "--repo",
            "o/n",
            "--branch",
            "b",
            "--expected-head",
            _FULL_SHA,
            "--message",
            "m",
            "--path",
            "Package.swift",
        )
        self.assertIn("Package.swift", out)
        self.assertNotIn("build-output.zip", out)

    def test_no_changes_is_an_error(self):
        # A release that produced no diff must not create an empty commit —
        # it means a sed stopped matching.
        code, _, err = self.run_main(
            "--repo",
            "o/n",
            "--branch",
            "b",
            "--expected-head",
            _FULL_SHA,
            "--message",
            "m",
        )
        self.assertEqual(code, 1)
        self.assertIn("Nothing to commit", err)

    def test_the_expanded_sha_is_what_reaches_the_payload(self):
        head = self.seed()
        (self.repo / "Package.swift").write_text("// v1\n", encoding="utf-8")

        with mock.patch.object(sc, "build_payload", wraps=sc.build_payload) as built:
            code, _, _ = self.run_main(
                "--repo",
                "o/n",
                "--branch",
                "b",
                "--expected-head",
                "HEAD",
                "--message",
                "m",
            )
        self.assertEqual(code, 0)
        self.assertEqual(built.call_args.kwargs["expected_head"], head)

    def test_an_unknown_expected_head_fails_before_anything_is_encoded(self):
        # The whole point of #981: the complaint has to name the argument, and
        # arrive before the change set is read, encoded and uploaded.
        self.seed()
        (self.repo / "Package.swift").write_text("// v1\n", encoding="utf-8")

        with mock.patch.object(sc, "encode_file") as encode:
            code, _, err = self.run_main(
                "--repo",
                "o/n",
                "--branch",
                "b",
                "--expected-head",
                "no-such-ref",
                "--message",
                "m",
            )
        self.assertEqual(code, 1)
        self.assertIn("--expected-head", err)
        self.assertIn("no-such-ref", err)
        encode.assert_not_called()


if __name__ == "__main__":
    unittest.main()
