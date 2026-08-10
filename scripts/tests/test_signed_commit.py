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
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "signed-commit.py"
_spec = importlib.util.spec_from_file_location("signed_commit", _SCRIPT)
sc = importlib.util.module_from_spec(_spec)
sys.modules["signed_commit"] = sc
_spec.loader.exec_module(sc)


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
            expected_head="abc123",
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
        self.assertEqual(given["expectedHeadOid"], "abc123")

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


class MainTests(unittest.TestCase):
    def test_dry_run_reports_the_change_set_without_sending(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            import subprocess

            for args in (
                ["init", "-q"],
                ["config", "user.email", "t@example.com"],
                ["config", "user.name", "t"],
            ):
                subprocess.run(["git", "-C", str(repo), *args], check=True)
            (repo / "Package.swift").write_text("// v1\n", encoding="utf-8")

            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                code = sc.main(
                    [
                        "--repo",
                        "shinyaoguri/metaphor",
                        "--branch",
                        "release/v0.9.0",
                        "--expected-head",
                        "abc123",
                        "--message",
                        "Release v0.9.0",
                        "--repo-root",
                        str(repo),
                        "--dry-run",
                    ]
                )
            self.assertEqual(code, 0)
            self.assertIn("Package.swift", out.getvalue())
            self.assertIn("+ Package.swift", err.getvalue())

    def test_path_scoping_excludes_everything_else(self):
        # The release commit must carry the bumped files only. On a runner the
        # working tree also holds build output, and an unscoped commit would
        # sweep in whatever happens not to be gitignored.
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            import subprocess

            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            (repo / "Package.swift").write_text("// v1\n", encoding="utf-8")
            (repo / "build-output.zip").write_text("junk\n", encoding="utf-8")

            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                sc.main(
                    [
                        "--repo",
                        "o/n",
                        "--branch",
                        "b",
                        "--expected-head",
                        "s",
                        "--message",
                        "m",
                        "--repo-root",
                        str(repo),
                        "--path",
                        "Package.swift",
                        "--dry-run",
                    ]
                )
            self.assertIn("Package.swift", out.getvalue())
            self.assertNotIn("build-output.zip", out.getvalue())

    def test_no_changes_is_an_error(self):
        # A release that produced no diff must not create an empty commit —
        # it means a sed stopped matching.
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            import subprocess

            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            err = io.StringIO()
            with redirect_stderr(err):
                code = sc.main(
                    [
                        "--repo",
                        "o/n",
                        "--branch",
                        "b",
                        "--expected-head",
                        "s",
                        "--message",
                        "m",
                        "--repo-root",
                        str(repo),
                        "--dry-run",
                    ]
                )
            self.assertEqual(code, 1)
            self.assertIn("Nothing to commit", err.getvalue())


if __name__ == "__main__":
    unittest.main()
