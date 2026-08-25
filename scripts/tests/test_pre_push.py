#!/usr/bin/env python3
"""scripts/hooks/pre-push のユニットテスト。

リポジトリルートから:

    python3 -m unittest discover -s scripts/tests

pre-push が持つのは **「push する range を見て、どの検査を鳴らすか」だけ**で、検査の
実体は別（`scripts/check-generated-freshness.sh` と Makefile の `static-check-fast` /
`docs-check`）。だからここで留めるのもディスパッチだけです。実体を呼ばせると
`swift build` が要るうえ、壊れやすいのは実体ではなくトリガーの側でした:

  * #995 — llms.txt の入力リストが pre-push と ci.yml に別々にあってドリフトした
  * #788 — `shots_common.py` を入力に足し忘れ、撮り直し漏れが素通りした
  * #1155 — 「baseline を辿れないときは全部」と書いてあるのに `needs_format` だけ
    抜けていた（このテストの `test_a_push_without_a_baseline_runs_every_check` が
    その状態に戻ったら赤くなる）

フック本体は実物を使い、呼ばれる側だけを「呼ばれたことを `.calls` へ書き足すスタブ」
に差し替えます。`scripts/changed-llms-inputs.sh` と `scripts/pr-changed-files.sh` は
判定そのものなので実物を置きます。
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from _git_helpers import git as _hermetic_git, hermetic_env, init_repo

_SCRIPTS = Path(__file__).resolve().parents[1]
_HOOK = _SCRIPTS / "hooks" / "pre-push"
_REAL_SCRIPTS = ["changed-llms-inputs.sh", "pr-changed-files.sh"]

_ZERO = "0" * 40

# 実体の代わり。呼ばれた事実と引数を `.calls` へ 1 行足し、`.exit-freshness` が
# あればその終了コードで落ちる。
_FRESHNESS_STUB = """#!/bin/sh
root="$(dirname "$0")/.."
echo "freshness $*" >> "$root/.calls"
if [ -f "$root/.exit-freshness" ]; then
    exit "$(cat "$root/.exit-freshness")"
fi
exit 0
"""

# `make <target>` の実体。`.exit-<target>` があればその target だけが落ちる。
_MAKEFILE = """.PHONY: static-check-fast docs-check

static-check-fast:
\t@echo "static-check-fast" >> .calls
\t@if [ -f .exit-static-check-fast ]; then echo "boom" >&2; exit 1; fi

docs-check:
\t@echo "docs-check" >> .calls
\t@if [ -f .exit-docs-check ]; then echo "boom" >&2; exit 1; fi
"""


class PrePushTests(unittest.TestCase):
    """フックを置いた使い捨てリポジトリ（開発機の git 設定からは密封 — #979）。

    履歴は `origin/main` を持つところまで作る。フックは新規ブランチの push で
    `git merge-base <local> origin/main` を引くので、これが無いと「baseline が
    辿れない」経路にしか入れない。
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = init_repo(Path(self._tmp.name))

        (self.repo / "scripts" / "hooks").mkdir(parents=True)
        hook = self.repo / "scripts" / "hooks" / "pre-push"
        shutil.copy2(_HOOK, hook)
        hook.chmod(0o755)
        for name in _REAL_SCRIPTS:
            shutil.copy2(_SCRIPTS / name, self.repo / "scripts" / name)
        freshness = self.repo / "scripts" / "check-generated-freshness.sh"
        freshness.write_text(_FRESHNESS_STUB, encoding="utf-8")
        freshness.chmod(0o755)
        (self.repo / "Makefile").write_text(_MAKEFILE, encoding="utf-8")

        self.base = self.commit("seed", **{"website__index.html": "<p>v1\n"})

    # --- helpers -------------------------------------------------------------

    def git(self, *args: str) -> str:
        return _hermetic_git(*args, cwd=self.repo)

    def commit(self, message: str, **files: str) -> str:
        """`files` を書いてコミットし、SHA を返す（`__` はディレクトリ区切り）。"""
        for name, content in files.items():
            path = self.repo / name.replace("__", "/")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD").strip()

    def set_origin_main(self, sha: str) -> None:
        """`origin/main` を作る（実チェックアウトの remote-tracking ref と同じ位置）。"""
        self.git("update-ref", "refs/remotes/origin/main", sha)

    def push(self, local_sha: str, remote_sha: str = _ZERO) -> subprocess.CompletedProcess:
        """githooks(5) の pre-push 入力を 1 行流す。"""
        line = f"refs/heads/topic {local_sha} refs/heads/topic {remote_sha}\n"
        return subprocess.run(
            ["sh", "scripts/hooks/pre-push"],
            cwd=os.fspath(self.repo),
            input=line,
            env=hermetic_env(),
            capture_output=True,
            text=True,
        )

    def calls(self) -> list[str]:
        log = self.repo / ".calls"
        return log.read_text(encoding="utf-8").splitlines() if log.is_file() else []

    def fail_next(self, name: str) -> None:
        (self.repo / f".exit-{name}").write_text("1", encoding="utf-8")


class DispatchTests(PrePushTests):
    def test_the_build_free_checks_run_even_when_nothing_they_watch_changed(self):
        # 本命（#1155）。`website/` はどの鮮度検査の入力でもないので、以前の
        # pre-push はこの push で 1 本も鳴らなかった。CI は同じ push でも lint 群を
        # 無条件に走らせるので、ここが空に戻ると「CI だけが赤い」が復活する。
        self.set_origin_main(self.base)
        head = self.commit("website only", **{"website__index.html": "<p>v2\n"})
        result = self.push(head, self.base)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["static-check-fast"])

    def test_a_delete_only_push_runs_nothing(self):
        # ブランチの削除には検査すべき内容が無い。ここが 1 本でも鳴ると、
        # `git push origin --delete` が 5 秒待たされるようになる。
        self.set_origin_main(self.base)
        result = self.push(_ZERO, self.base)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_the_docc_check_runs_when_the_catalog_changes(self):
        # カタログは llms.txt の入力ではないので鮮度検査は鳴らない。DocC だけが
        # 鳴るのが正しい（判定は changed-llms-inputs.sh --docc が正本）。
        self.set_origin_main(self.base)
        head = self.commit(
            "catalog only",
            **{"Sources__metaphor__metaphor.docc__Architecture.md": "# arch\n"},
        )
        result = self.push(head, self.base)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["static-check-fast", "docs-check"])

    def test_a_swift_source_change_runs_the_freshness_checks_and_docc(self):
        self.set_origin_main(self.base)
        head = self.commit(
            "api change", **{"Sources__MetaphorCore__Sketch.swift": "// v2\n"}
        )
        result = self.push(head, self.base)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0], "static-check-fast")
        self.assertEqual(self.calls()[-1], "docs-check")
        freshness = [line for line in self.calls() if line.startswith("freshness ")]
        self.assertEqual(len(freshness), 1, self.calls())
        self.assertIn("llms", freshness[0].split())
        self.assertIn("reference", freshness[0].split())
        self.assertIn("format", freshness[0].split())

    def test_the_build_free_checks_come_before_anything_that_builds(self):
        # ci.yml と同じ並び。5 秒で分かる失敗を `make llms-txt`（= swift build）の
        # あとに見るのは無駄なので、順序そのものを固定する。
        self.set_origin_main(self.base)
        head = self.commit(
            "api change", **{"Sources__MetaphorCore__Sketch.swift": "// v2\n"}
        )
        self.push(head, self.base)

        self.assertEqual(self.calls()[0], "static-check-fast")

    def test_a_push_without_a_baseline_runs_every_check(self):
        # origin/main が無い（clone 直後や、追跡先を辿れない）ときは安全側に倒す。
        # `format` が抜けていたのが #1155 で見つかった取りこぼし。
        head = self.commit("anything", **{"website__index.html": "<p>v2\n"})
        result = self.push(head)

        self.assertEqual(result.returncode, 0, result.stderr)
        freshness = [line for line in self.calls() if line.startswith("freshness ")]
        self.assertEqual(len(freshness), 1, self.calls())
        requested = set(freshness[0].split()[1:])
        self.assertEqual(
            requested,
            {
                "--label",
                "[pre-push]",
                "llms",
                "index",
                "shaders",
                "tutorial",
                "reference",
                "status",
                "format",
            },
        )
        self.assertIn("static-check-fast", self.calls())
        self.assertIn("docs-check", self.calls())


class FailureTests(PrePushTests):
    def test_a_failing_build_free_check_aborts_before_anything_builds(self):
        self.set_origin_main(self.base)
        head = self.commit(
            "api change", **{"Sources__MetaphorCore__Sketch.swift": "// v2\n"}
        )
        self.fail_next("static-check-fast")
        result = self.push(head, self.base)

        self.assertEqual(result.returncode, 1)
        # 落ちたところで止まる — 後ろの（ビルドを伴う）検査は走らない。
        self.assertEqual(self.calls(), ["static-check-fast"])
        # 復旧手順と降り方が出ること。exit code だけ返して黙るのが一番まずい。
        self.assertIn("make ci-check", result.stderr)
        self.assertIn("--no-verify", result.stderr)

    def test_a_failing_docc_check_aborts_the_push(self):
        self.set_origin_main(self.base)
        head = self.commit(
            "catalog only",
            **{"Sources__metaphor__metaphor.docc__Architecture.md": "# arch\n"},
        )
        self.fail_next("docs-check")
        result = self.push(head, self.base)

        self.assertEqual(result.returncode, 1)
        self.assertIn("llms.txt", result.stderr)
        self.assertIn("--no-verify", result.stderr)

    def test_a_failing_freshness_check_still_aborts_the_push(self):
        # 切り出し（#978）で既にあった歯止め。新しい検査を前後に足しても
        # 効き続けることを固める。
        self.set_origin_main(self.base)
        head = self.commit(
            "api change", **{"Sources__MetaphorCore__Sketch.swift": "// v2\n"}
        )
        self.fail_next("freshness")
        result = self.push(head, self.base)

        self.assertEqual(result.returncode, 1)
        self.assertNotIn("docs-check", self.calls())


if __name__ == "__main__":
    unittest.main()
