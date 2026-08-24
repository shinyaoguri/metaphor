#!/usr/bin/env python3
"""scripts/check-generated-freshness.sh のユニットテスト。

リポジトリルートから:

    python3 -m unittest discover -s scripts/tests

このスクリプトは pre-push フックから切り出した「検査の実体」で、呼び出し側が 3 つ
ある（pre-push / signed-commit.py / make freshness-check）。**切り出しで壊れやすい
のは検査そのものではなくディスパッチ**なので、ここで留めるのはそちら:

  * 要求した検査だけが走り、要求していないものが走らないこと
  * 走る順序が呼び出し側の並びではなくスクリプト側の正典順であること
  * 1 本落ちたらそこで止まり、復旧手順が stderr に出ること
  * 検査名の綴り間違いが「黙って 0 本走って成功」にならないこと

最後の 1 つが本命。Issue #978 で塞いだのは「歯止めが黙って外れる」形の失敗なので、
このスクリプト自身が同じ形で失敗しては意味がない。

検査の中身（`make llms-txt` が何を作るか等）はここでは見ない。生成器の側にそれぞれ
テストがあり、ここで実物を走らせるとビルドが要る。代わりに使い捨てのリポジトリへ
生成器のスタブを置き、呼ばれたかどうかを記録させる。
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from _git_helpers import git as hermetic_git, hermetic_env, init_repo

_SCRIPTS = Path(__file__).resolve().parents[1]
_SCRIPT = _SCRIPTS / "check-generated-freshness.sh"

# 正典順。決めているのは実体側の `if wants …` ブロックの並びで、ALL_CHECKS は
# 検査名の検証と `--all` の展開に使う別物（両者がずれたらここが赤くなる）。
_ORDER = ["llms", "index", "shaders", "tutorial-snippets", "tutorial-shots",
          "reference", "status", "format"]

# 呼ばれたことを `.calls` へ 1 行足し、`.exit-<name>` があればその終了コードで落ち、
# `.dirty-<name>` があればそこに書かれたパスを書き換える（= 生成物が陳腐化していた
# ときの「再生成したら差分が出た」を再現する）スタブ。
_STUB_PY = '''#!/usr/bin/env python3
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
with (root / ".calls").open("a", encoding="utf-8") as handle:
    handle.write("NAME\\n")
dirty = root / ".dirty-NAME"
if dirty.is_file():
    target = root / dirty.read_text(encoding="utf-8").strip()
    target.write_text("regenerated\\n", encoding="utf-8")
code = root / ".exit-NAME"
sys.exit(int(code.read_text(encoding="utf-8").strip()) if code.is_file() else 0)
'''

_STUB_SH = '''#!/bin/sh
root="$(dirname "$0")/.."
echo NAME >> "$root/.calls"
if [ -f "$root/.exit-NAME" ]; then
    exit "$(cat "$root/.exit-NAME")"
fi
exit 0
'''

_MAKEFILE = """llms-txt:
\t@python3 scripts/generate-llms-txt.py
"""

# 実体が呼ぶ生成器と、`.calls` に残る名前の対応。
_PY_STUBS = {
    "generate-llms-txt.py": "llms",
    "generate-examples-index.py": "index",
    "generate-shader-sources.py": "shaders",
    "generate-tutorial-snippets.py": "tutorial-snippets",
    "generate-tutorial-shots.py": "tutorial-shots",
    "generate-reference-shots.py": "reference",
    "generate-tutorial-status.py": "status",
}


class _FakeRepoTestCase(unittest.TestCase):
    """実体を置いた使い捨てリポジトリ（開発機の git 設定からは密封 — #979）。

    スクリプトは `cd "$(dirname "$0")/.."` で自分の 1 つ上へ移るので、ここへ写せば
    そのままこの偽リポジトリをルートとして動く。
    """

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        init_repo(self.root)

        (self.root / "scripts").mkdir()
        shutil.copy2(_SCRIPT, self.root / "scripts" / _SCRIPT.name)
        for filename, name in _PY_STUBS.items():
            path = self.root / "scripts" / filename
            path.write_text(_STUB_PY.replace("NAME", name), encoding="utf-8")
        lint = self.root / "scripts" / "lint-swift.sh"
        lint.write_text(_STUB_SH.replace("NAME", "format"), encoding="utf-8")
        lint.chmod(0o755)

        (self.root / "Makefile").write_text(_MAKEFILE, encoding="utf-8")
        (self.root / "llms.txt").write_text("committed\n", encoding="utf-8")
        (self.root / "docs" / "ai").mkdir(parents=True)
        (self.root / "docs" / "ai" / "examples-index.md").write_text("i\n", encoding="utf-8")
        (self.root / "docs" / "ai" / "examples-index.json").write_text("{}\n", encoding="utf-8")
        hermetic_git("add", "-A", cwd=self.root)
        hermetic_git("commit", "-q", "-m", "seed", cwd=self.root)

    def run_script(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [str(self.root / "scripts" / _SCRIPT.name), *args],
            cwd=os.fspath(self.root),
            env=hermetic_env(),
            capture_output=True,
            text=True,
        )

    def calls(self) -> list[str]:
        log = self.root / ".calls"
        return log.read_text(encoding="utf-8").split() if log.is_file() else []

    def make_fail(self, name: str, code: int = 1) -> None:
        (self.root / f".exit-{name}").write_text(str(code), encoding="utf-8")

    def make_stale(self, name: str, path: str) -> None:
        (self.root / f".dirty-{name}").write_text(path, encoding="utf-8")


class DispatchTests(_FakeRepoTestCase):
    def test_all_runs_every_check_in_the_canonical_order(self):
        result = self.run_script("--all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), _ORDER)

    def test_a_single_name_runs_only_that_check(self):
        result = self.run_script("index")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["index"])

    def test_the_order_is_the_scripts_not_the_callers(self):
        # pre-push は needs_* の並びで渡してくるが、順序を決めるのは実体側。
        # 逆順で渡しても正典順で走る。
        result = self.run_script("format", "index", "llms")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["llms", "index", "format"])

    def test_tutorial_runs_both_snippets_and_shots(self):
        # 1 つのフラグに 2 本ぶら下がっている唯一の検査（#788）。
        self.run_script("tutorial")
        self.assertEqual(self.calls(), ["tutorial-snippets", "tutorial-shots"])


class FailureTests(_FakeRepoTestCase):
    def test_a_failing_check_stops_the_run_and_prints_the_recovery_command(self):
        self.make_fail("shaders")
        result = self.run_script("--all")
        self.assertEqual(result.returncode, 1)
        self.assertIn("python3 scripts/generate-shader-sources.py", result.stderr)
        # 落ちたところで止まる — 後ろの検査は走らない。
        self.assertEqual(self.calls(), ["llms", "index", "shaders"])

    def test_a_regenerated_artifact_that_differs_is_stale(self):
        # `make llms-txt` は通るが、書き戻した結果がコミット済みと違う形。
        # 実運用でいちばん多い失敗の仕方（#972 / #786）。
        self.make_stale("llms", "llms.txt")
        result = self.run_script("llms")
        self.assertEqual(result.returncode, 1)
        self.assertIn("llms.txt is stale", result.stderr)

    def test_a_regenerated_index_that_differs_is_stale(self):
        self.make_stale("index", "docs/ai/examples-index.md")
        result = self.run_script("index")
        self.assertEqual(result.returncode, 1)
        self.assertIn("examples index is stale", result.stderr)

    def test_a_failing_generator_is_reported_as_such(self):
        self.make_fail("index")
        result = self.run_script("index")
        self.assertEqual(result.returncode, 1)
        self.assertIn("generate-examples-index.py failed", result.stderr)


class ArgumentTests(_FakeRepoTestCase):
    def test_an_unknown_check_name_is_refused_before_anything_runs(self):
        # 綴り間違いが「0 本走って成功」になると、歯止めが黙って外れる（#978 と
        # 同じ形の失敗）。exit 2 = 使い方の誤りで、1（陳腐化）とは区別する。
        result = self.run_script("llms", "shaderz")
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown check: shaderz", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_no_checks_requested_is_refused(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 2)
        self.assertIn("no checks requested", result.stderr)

    def test_an_unknown_option_is_refused(self):
        result = self.run_script("--everything")
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown option", result.stderr)

    def test_the_label_prefixes_the_output(self):
        # pre-push は `[pre-push]` を、signed-commit.py は `[signed-commit]` を
        # 渡す。どちらの経路で止まったかが読み手に分かる必要がある。
        result = self.run_script("--label", "[pre-push]", "index")
        self.assertIn("[pre-push]", result.stdout)
        self.assertNotIn("[freshness]", result.stdout)

    def test_the_default_label_is_used_without_the_flag(self):
        result = self.run_script("index")
        self.assertIn("[freshness]", result.stdout)


if __name__ == "__main__":
    unittest.main()
