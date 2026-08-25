#!/usr/bin/env python3
"""scripts/changed-llms-inputs.sh のユニットテスト。

リポジトリルートから:

    python3 -m unittest discover -s scripts/tests

留めているのは **Makefile が llms.txt の入力である**こと（Issue #995）。`llms.txt` は
`make llms-txt` → `make symbol-graphs` を経由して作られるので、`symbol-graphs` の
レシピを壊す変更は llms.txt を生成できなくする。ところが入力リストは長らく
`Sources/**/*.swift` と生成器スクリプトの 2 つで、`Makefile` を含んでいなかった。

その壊れ方は静かで、しかも犯人と被害者がずれる:

  * レシピを壊した PR は pre-push も CI も鳴らないまま緑で通る（実例 PR #993 は
    `Makefile` しか変えていない）
  * 次に `Sources/` を触った**無関係な**PR のところで初めて `make llms-txt` が落ちる
    （#935 が「build も test も green なのに push だけ通らない」形になった経緯）

リストは以前 `scripts/hooks/pre-push` と `.github/workflows/ci.yml` が別々に持って
いて、片方だけ直すとそこからドリフトした。いまはこのスクリプトが唯一の正典なので、
ここを固めておけば両方の呼び出し側が守られる。
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from _git_helpers import git as _hermetic_git, hermetic_env, init_repo

_SCRIPTS = Path(__file__).resolve().parents[1]
_SCRIPT = _SCRIPTS / "changed-llms-inputs.sh"
_DELEGATE = _SCRIPTS / "pr-changed-files.sh"


def _git(repo: Path, *args: str) -> str:
    """開発機のグローバル設定から密封した git（#979）。"""
    return _hermetic_git(*args, cwd=repo)


def _commit(repo: Path, message: str, **files: str) -> str:
    """`files` を書いてコミットし、SHA を返す（`__` はディレクトリ区切り）。"""
    for name, content in files.items():
        path = repo / name.replace("__", "/")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", message)
    return _git(repo, "rev-parse", "HEAD").strip()


class ChangedLlmsInputsTests(unittest.TestCase):
    """どのテストも次の履歴の上で走る:

        A ── B  (main: Makefile を触る = レシピを直した別の PR が先に入った状態)
        └──── (各テストがここから枝を生やす)

    `B` は per-PR CI が BASE_SHA として渡してくるもの（PR の分岐点ではなく、
    イベント発火時点の main の先端）。
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = init_repo(Path(self._tmp.name))

        # スクリプトは自分の位置からリポジトリルートと委譲先を解決するので、
        # 実チェックアウトと同じ配置で合成リポの中に置く。
        (self.repo / "scripts").mkdir()
        self.script = self.repo / "scripts" / "changed-llms-inputs.sh"
        shutil.copy2(_SCRIPT, self.script)
        shutil.copy2(_DELEGATE, self.repo / "scripts" / "pr-changed-files.sh")

        self.a = _commit(
            self.repo,
            "base",
            Makefile="llms-txt: symbol-graphs\n",
            docs__guide="guide\n",
            **{
                "Sources__MetaphorCore__Sketch__Sketch.swift": "// v1\n",
                "scripts__generate-llms-txt.py": "# v1\n",
            },
        )
        self.b = _commit(
            self.repo,
            "main moves on: someone else edited the symbol-graphs recipe",
            Makefile="llms-txt: symbol-graphs\n# main の変更\n",
        )
        _git(self.repo, "checkout", "-q", "-b", "feature", self.a)

    def run_script(self, *args: str) -> subprocess.CompletedProcess:
        # スクリプトは git を呼ぶので、同じ密封を渡す（#979）。
        return subprocess.run(
            [str(self.script), *args],
            capture_output=True,
            text=True,
            env=hermetic_env(),
        )

    def changed(self, base: str, head: str) -> list[str]:
        result = self.run_script(base, head)
        self.assertEqual(result.returncode, 0, result.stderr)
        return sorted(line for line in result.stdout.splitlines() if line)

    def changed_docc(self, base: str, head: str) -> list[str]:
        result = self.run_script("--docc", base, head)
        self.assertEqual(result.returncode, 0, result.stderr)
        return sorted(line for line in result.stdout.splitlines() if line)

    # --- 取りこぼしていた入力（Issue #995 / 実例 PR #993） -------------------

    def test_a_makefile_only_change_is_an_input(self):
        # `make llms-txt` は `make symbol-graphs` 経由なので、レシピだけを変えた
        # 枝でも鮮度検査が要る。ここが空に戻ったら #993 の素通りが復活する。
        head = _commit(
            self.repo,
            "fix the symbol-graphs recipe",
            Makefile="llms-txt: symbol-graphs\n# -F をパスから解決する\n",
        )
        self.assertEqual(self.changed(self.a, head), ["Makefile"])

    # --- もともと入っていた 2 つ ---------------------------------------------

    def test_public_sources_are_an_input(self):
        head = _commit(
            self.repo,
            "add API",
            **{"Sources__MetaphorCore__Sketch__Sketch.swift": "// v2\n"},
        )
        self.assertEqual(
            self.changed(self.a, head), ["Sources/MetaphorCore/Sketch/Sketch.swift"]
        )

    def test_a_module_top_level_file_is_an_input(self):
        # モジュール直下（1 階層）も深いパスも同じように載る。ついでに
        # `Sources/**/*.swift` の `**` が **0 階層にはマッチしない**ことも固める:
        # `Sources/Noise.swift` は載らない。SwiftPM のソースは必ず
        # `Sources/<Target>/` の下なので実害は無いが、pathspec を書き換えたときに
        # 「深さで静かに取りこぼす」向きの変化へ気付けるようにしておく。
        head = _commit(
            self.repo,
            "module top level and a file directly under Sources/",
            **{
                "Sources__MetaphorNoise__Noise.swift": "// x\n",
                "Sources__stray.swift": "// not a SwiftPM layout\n",
            },
        )
        self.assertEqual(self.changed(self.a, head), ["Sources/MetaphorNoise/Noise.swift"])

    def test_the_generator_script_is_an_input(self):
        head = _commit(
            self.repo, "tweak the filter", **{"scripts__generate-llms-txt.py": "# v2\n"}
        )
        self.assertEqual(self.changed(self.a, head), ["scripts/generate-llms-txt.py"])

    # --- 入力ではないもの（空振りを増やさない） -------------------------------

    def test_docs_only_changes_are_not_an_input(self):
        head = _commit(self.repo, "docs only", docs__new="new\n")
        self.assertEqual(self.changed(self.a, head), [])

    def test_tests_and_examples_are_not_an_input(self):
        # llms.txt は公開 API 面だけを載せるので、テストと example は含まない。
        head = _commit(
            self.repo,
            "tests and an example",
            **{
                "Tests__MetaphorCoreTests__SketchTests.swift": "// t\n",
                "Examples__Basics__Form__Shape__Sources__main.swift": "// e\n",
            },
        )
        self.assertEqual(self.changed(self.a, head), [])

    # --- --docc（DocC の警告検査の起動判定・Issue #1155） ---------------------

    def test_the_docc_catalog_is_an_input_only_with_docc(self):
        # カタログは symbol graph の入力ではないので、素の呼び出しには載らない
        # （載せると `make llms-txt` = swift build が要らないところで起動する）。
        # `--docc` を付けたときだけ載る。ここが片方に寄ったら、カタログだけ直した
        # push が DocC 検査を取りこぼすか、逆に毎回ビルドを引くかのどちらかになる。
        head = _commit(
            self.repo,
            "catalog only",
            **{"Sources__metaphor__metaphor.docc__Architecture.md": "# arch\n"},
        )
        self.assertEqual(self.changed(self.a, head), [])
        self.assertEqual(
            self.changed_docc(self.a, head),
            ["Sources/metaphor/metaphor.docc/Architecture.md"],
        )

    def test_docc_also_carries_the_llms_inputs(self):
        # docs-check も symbol-graphs 依存なので、llms.txt の入力が動けば DocC も
        # 検査が要る。`--docc` は差集合ではなく上乗せ。
        head = _commit(
            self.repo,
            "api change",
            **{"Sources__MetaphorCore__Sketch__Sketch.swift": "// v2\n"},
        )
        self.assertEqual(
            self.changed_docc(self.a, head),
            ["Sources/MetaphorCore/Sketch/Sketch.swift"],
        )

    def test_docc_does_not_fire_on_unrelated_paths(self):
        head = _commit(self.repo, "docs only", docs__new="new\n")
        self.assertEqual(self.changed_docc(self.a, head), [])

    def test_docc_must_come_before_the_revisions(self):
        # 呼び出し側（pre-push / ci.yml）はこの並びで渡す。後置を黙って無視すると
        # 「フラグを付けたつもりで付いていない」が緑のまま通る。
        result = self.run_script(self.a, "HEAD", "--docc")
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("usage:", result.stderr)

    # --- 3 点表記であること（委譲先の契約が生きているか） ---------------------

    def test_a_main_side_makefile_change_is_not_attributed_to_the_branch(self):
        # BASE_SHA は main の先端（B）なので、2 点間だと main 側の Makefile 変更が
        # 「この枝が変えた」ことになり、無関係な PR で毎回 llms.txt 検査が回る。
        head = _commit(self.repo, "docs only", docs__new="new\n")
        self.assertEqual(self.changed(self.b, head), [])

    # --- 呼び出し側が頼っている失敗のしかた -----------------------------------

    def test_missing_arguments_is_a_usage_error(self):
        for args in ([], [self.a], [self.a, self.b, "--", "Makefile"]):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn("usage:", result.stderr)

    def test_an_unreachable_revision_fails_instead_of_reporting_no_changes(self):
        # force push で古い先端が消えた場合。pre-push も ci.yml も「辿れないなら
        # 安全側に倒して検査する」ので、ここで 0 を返して黙るのが一番まずい。
        result = self.run_script("0" * 40, "HEAD")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
