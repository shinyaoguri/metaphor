#!/usr/bin/env python3
"""Unit tests for scripts/coverage-report.sh.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「カバレッジデータが無い run でも warning を出して正常終了する」こと
そのもの（Issue #639）。このガードはインラインの `run:` だった頃、`set -e` に
先回りされて **一度も実行されていなかった** — 壊れていることは「テストが落ちた run で
Coverage Report まで赤くなる」という形でしか現れず、原因ステップの赤に紛れて
読み飛ばされる。ワークフロー内の `run:` は単体で走らせられないので、実体を
スクリプトへ出したうえでここに固定する。

`xcrun` はスタブへ差し替える（llvm-cov の出力そのものはこのテストの関心事ではなく、
ガードを抜けた先で実際にレポートが書かれることだけを見る）。
"""

import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = _ROOT / "scripts" / "coverage-report.sh"
CI_WORKFLOW = _ROOT / ".github" / "workflows" / "ci.yml"

WARNING = "::warning::coverage data not found"

# `xcrun llvm-cov <report|export> ...` のスタブ。-format で分岐して、
# coverage-summary.py が読める最小の JSON を返す。
STUB_XCRUN = """\
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
    -format=lcov)
        echo "SF:Sources/MetaphorCore/Stub.swift"
        exit 0
        ;;
    -format=text)
        cat <<'JSON'
{"data": [{"files": [{"filename": "Sources/MetaphorCore/Stub.swift",
  "summary": {"lines": {"covered": 5, "count": 10},
              "functions": {"covered": 1, "count": 2}}}]}]}
JSON
        exit 0
        ;;
    esac
done
echo "stub llvm-cov report"
"""


class CoverageReportTestCase(unittest.TestCase):
    """スクリプトを実プロセスとして走らせる共通の足場。"""

    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.out_dir = self.tmp / "coverage-out"

    def stub_xcrun(self) -> Path:
        """スタブ `xcrun` を置いたディレクトリを返す（PATH の先頭に載せる用）。"""
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir(exist_ok=True)
        stub = bin_dir / "xcrun"
        stub.write_text(STUB_XCRUN, encoding="utf-8")
        stub.chmod(0o755)
        return bin_dir

    def make_build_dir(self, *, binary=True, profdata=True, via_symlink=False) -> Path:
        """swift test の出力を模したディレクトリを作り、その入口を返す。"""
        real = self.tmp / "build" / "arm64-apple-macosx" / "debug"
        real.mkdir(parents=True)
        if binary:
            (real / "metaphorPackageTests").write_text("", encoding="utf-8")
        if profdata:
            (real / "codecov").mkdir()
            (real / "codecov" / "default.profdata").write_text("", encoding="utf-8")
        if not via_symlink:
            return real
        # 本物の .build/debug と同じ形（ディレクトリ自体がシンボリックリンク）。
        link = self.tmp / "build" / "debug"
        link.symlink_to(real)
        return link

    def run_script(self, build_dir, *, path_prefix=None, summary=None):
        env = os.environ.copy()
        env["COVERAGE_BUILD_DIR"] = str(build_dir)
        env["COVERAGE_OUT_DIR"] = str(self.out_dir)
        # CI から起動されたときの値を引き継がない（テストが環境で変わらないよう）。
        env.pop("GITHUB_STEP_SUMMARY", None)
        if path_prefix is not None:
            env["PATH"] = f"{path_prefix}{os.pathsep}{env['PATH']}"
        if summary is not None:
            env["GITHUB_STEP_SUMMARY"] = str(summary)
        return subprocess.run(
            [str(SCRIPT)], capture_output=True, text=True, env=env, check=False
        )


class TestSkipsWithoutCoverageData(CoverageReportTestCase):
    """本命: データが無い run で warning を出して正常終了すること。"""

    def assert_skipped(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(WARNING, result.stdout)
        self.assertFalse(self.out_dir.exists(), "skip したのにレポートを書いている")

    def test_build_directory_missing(self):
        # Issue #639 の再現形: テストが走る前に落ちた run では .build ごと無い。
        # find が exit 1 を返し、代入がそれを引き継いでガードの手前で落ちていた。
        self.assert_skipped(self.run_script(self.tmp / "no-such-build"))

    def test_test_binary_missing(self):
        self.assert_skipped(self.run_script(self.make_build_dir(binary=False)))

    def test_profdata_missing(self):
        # ビルドは通ったがテストが落ちた（プロファイルが出ていない）場合。
        self.assert_skipped(self.run_script(self.make_build_dir(profdata=False)))


class TestWritesReport(CoverageReportTestCase):
    """データがあるときは skip せずレポートを書くこと（ガードの裏返し）。"""

    def test_reports_through_the_symlinked_build_directory(self):
        # .build/debug は実体へのシンボリックリンク。find の -L を落とすと何も
        # 見つからず、レポートは静かに空振りする（この形が過去の実態）。
        result = self.run_script(
            self.make_build_dir(via_symlink=True), path_prefix=self.stub_xcrun()
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(WARNING, result.stdout)
        for name in (
            "coverage-files.txt",
            "coverage.lcov",
            "coverage.json",
            "coverage-modules.md",
        ):
            self.assertTrue((self.out_dir / name).is_file(), f"{name} が無い")
        self.assertIn(
            "MetaphorCore",
            (self.out_dir / "coverage-modules.md").read_text(encoding="utf-8"),
        )

    def test_appends_to_the_job_summary_when_running_in_ci(self):
        summary = self.tmp / "step-summary.md"
        summary.write_text("", encoding="utf-8")
        result = self.run_script(
            self.make_build_dir(), path_prefix=self.stub_xcrun(), summary=summary
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Coverage by module", summary.read_text(encoding="utf-8"))

    def test_runs_without_a_job_summary_outside_ci(self):
        # ローカル実行では GITHUB_STEP_SUMMARY が無い（`set -u` で落ちないこと）。
        result = self.run_script(self.make_build_dir(), path_prefix=self.stub_xcrun())
        self.assertEqual(result.returncode, 0, result.stderr)


class TestWorkflowUsesTheScript(CoverageReportTestCase):
    """ロジックがワークフローへ書き戻されたら気付けるようにする。"""

    def test_ci_workflow_calls_the_script(self):
        self.assertIn(
            "./scripts/coverage-report.sh",
            CI_WORKFLOW.read_text(encoding="utf-8"),
            "ci.yml の Coverage Report がスクリプトを呼んでいません"
            "（インラインへ戻すとこのテストでは守れなくなります）。",
        )


if __name__ == "__main__":
    unittest.main()
