#!/usr/bin/env python3
"""Unit tests for scripts/tests/_git_helpers.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

The seal exists because the developer's global git config reached into the
throwaway repositories other tests build, and `commit.gpgsign = true` turned
`git commit` there into either exit 128 or a wait on a signing agent nobody is
there to unlock (Issue #979 / #974). A regression is invisible from CI — a runner
has no signing config, so the suite stays green there whatever this file does,
and the breakage would only ever surface as "the tests fail on my machine".

So every test builds its own hostile config and hands it to git through the same
channel a real machine would use. Each one comes with its control: plain `git`,
same repository, same hostile config, has to fail — a seal that is never shown
against a failing baseline proves nothing.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from _git_helpers import git, hermetic_env, hermetic_environ, init_repo

# A signing setup that cannot possibly work: `ssh-keygen` is pointed at a program
# and a key that are not there. On a real machine the same shape fails because
# the private key lives in an agent (1Password) that is locked or unreachable.
# The identity is included on purpose, so the control fails *for the signing
# reason* rather than for a missing `user.name`.
_SIGNING_PROGRAM = "/nonexistent/op-ssh-sign"
_HOSTILE_CONFIG = f"""\
[user]
\tname = Hostile Global
\temail = hostile@example.invalid
\tsigningkey = /nonexistent/signing-key.pub
[gpg]
\tformat = ssh
[gpg "ssh"]
\tprogram = {_SIGNING_PROGRAM}
[commit]
\tgpgsign = true
[tag]
\tgpgsign = true
[init]
\tdefaultBranch = hostile-default
"""


class SealTestCase(unittest.TestCase):
    """A throwaway repository sitting under a hostile git config."""

    def channel(self, hostile: Path) -> dict[str, str]:
        """Where the hostile config comes from. Subclasses pick the other one."""
        return {"GIT_CONFIG_GLOBAL": str(hostile), "GIT_CONFIG_SYSTEM": os.devnull}

    def setUp(self) -> None:
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)

        self.hostile = root / "hostile-gitconfig"
        self.hostile.write_text(_HOSTILE_CONFIG, encoding="utf-8")

        # The other channel is pinned to devnull rather than left alone, so the
        # test measures one channel at a time however the machine is configured.
        for name, value in self.channel(self.hostile).items():
            self.addCleanup(self._restore, name, os.environ.get(name))
            os.environ[name] = value

        self.repo = init_repo(root / "repo")
        (self.repo / "file.txt").write_text("hello\n", encoding="utf-8")

    @staticmethod
    def _restore(name: str, value: str | None) -> None:
        if value is None:
            os.environ.pop(name, None)
        else:
            os.environ[name] = value

    def plain_git(self, *args: str) -> subprocess.CompletedProcess:
        """git with no seal — inherits the hostile config, like any other tool."""
        return subprocess.run(
            ["git", *args], cwd=str(self.repo), capture_output=True, text=True
        )

    def assert_control_cannot_commit(self) -> None:
        # If this ever passes, every other test here stops meaning anything: it
        # would mean the hostile config never reached git in the first place.
        self.plain_git("add", "-A")
        result = self.plain_git("commit", "-q", "-m", "control")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(_SIGNING_PROGRAM, result.stderr)

    def sealed_commit(self, message: str = "sealed") -> None:
        git("add", "-A", cwd=self.repo)
        git("commit", "-q", "-m", message, cwd=self.repo)


class GlobalConfigTests(SealTestCase):
    """`~/.gitconfig` — the channel that actually bit us (#979 / #974)."""

    def test_the_control_cannot_commit(self):
        self.assert_control_cannot_commit()

    def test_a_sealed_commit_goes_through(self):
        self.sealed_commit()
        self.assertEqual(
            git("log", "-1", "--format=%s", cwd=self.repo).strip(), "sealed"
        )

    def test_the_identity_comes_from_the_environment(self):
        # Not from the repository and not from any config file — which is what
        # lets these tests run on a machine where `user.name` was never set.
        self.sealed_commit()
        self.assertEqual(
            git("log", "-1", "--format=%an <%ae>", cwd=self.repo).strip(),
            "metaphor tests <tests@example.invalid>",
        )

    def test_no_setting_survives_the_seal(self):
        # The point of sealing the config *file* rather than overriding
        # `commit.gpgsign`: settings nobody thought to override are gone too.
        for key in ("commit.gpgsign", "user.name", "init.defaultBranch"):
            with self.subTest(key=key):
                result = subprocess.run(
                    ["git", "config", "--get", key],
                    cwd=str(self.repo),
                    capture_output=True,
                    text=True,
                    env=hermetic_env(),
                )
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.returncode, 1)  # 1 = key not set

    def test_an_annotated_tag_goes_through(self):
        # `tag.gpgsign` is a second way the same machine breaks a test —
        # release-bump's fixtures tag their seed commit.
        self.sealed_commit()
        git("tag", "-m", "v0.1.0", "v0.1.0", cwd=self.repo)
        self.assertEqual(git("tag", "--list", cwd=self.repo).strip(), "v0.1.0")

    def test_init_repo_pins_the_branch_name(self):
        # The hostile config sets `init.defaultBranch`; sealing it away drops git
        # to its built-in `master`, so the branch has to be named explicitly.
        self.assertEqual(
            git("symbolic-ref", "--short", "HEAD", cwd=self.repo).strip(), "main"
        )

    def test_hermetic_env_carries_the_seal_to_other_programs(self):
        # `pr-changed-files.sh` runs as a subprocess and calls git itself, so the
        # seal has to survive being handed over as a plain environment — and to
        # cover both channels, since a subprocess gets whichever the machine set.
        for name in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM"):
            self.addCleanup(self._restore, name, os.environ.get(name))
            os.environ[name] = str(self.hostile)

        env = hermetic_env()
        self.assertEqual(env["GIT_CONFIG_GLOBAL"], os.devnull)
        self.assertEqual(env["GIT_CONFIG_SYSTEM"], os.devnull)
        for args in (["add", "-A"], ["commit", "-q", "-m", "via env"]):
            result = subprocess.run(
                ["git", *args],
                cwd=str(self.repo),
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_hermetic_environ_seals_code_that_shells_out_itself(self):
        # For a function under test that runs git internally, `env=` is not ours
        # to pass, so `os.environ` takes the seal (signed-commit.py's `main()`).
        self.assertNotEqual(os.environ["GIT_CONFIG_GLOBAL"], os.devnull)
        with hermetic_environ():
            self.assertEqual(os.environ["GIT_CONFIG_GLOBAL"], os.devnull)
            self.plain_git("add", "-A")
            self.assertEqual(
                self.plain_git("commit", "-q", "-m", "sealed").returncode, 0
            )
        # …and put back afterwards, so one test cannot leak into the next.
        self.assertNotEqual(os.environ["GIT_CONFIG_GLOBAL"], os.devnull)


class SystemConfigTests(SealTestCase):
    """The same hostile config, arriving as the *system* one.

    Sealing `GIT_CONFIG_GLOBAL` alone would leave this half open, and a machine
    configured through `/etc/gitconfig` — a managed fleet, or a Homebrew git with
    its own — would keep failing after the fix.
    """

    def channel(self, hostile: Path) -> dict[str, str]:
        return {"GIT_CONFIG_SYSTEM": str(hostile), "GIT_CONFIG_GLOBAL": os.devnull}

    def test_the_control_cannot_commit(self):
        self.assert_control_cannot_commit()

    def test_a_sealed_commit_goes_through(self):
        self.sealed_commit()
        self.assertEqual(
            git("log", "-1", "--format=%s", cwd=self.repo).strip(), "sealed"
        )


if __name__ == "__main__":
    unittest.main()
