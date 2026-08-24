#!/usr/bin/env python3
"""Unit tests for scripts/check-ci-parity.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「per-PR CI のステップが `make ci-check` に載っている」ことそのもの
（Issue #1020）。取りこぼすと「手元で green にしたのに CI が赤い」が静かに戻るので、
リポジトリ実体を見るテスト（`TestRepositoryIsConsistent`）を本命に置き、判定規則の
テストでその周りを固める。
"""

import importlib.util
import sys
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-ci-parity.py"
_spec = importlib.util.spec_from_file_location("check_ci_parity", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_ci_parity"] = check
_spec.loader.exec_module(check)

REPO_ROOT = Path(__file__).resolve().parents[2]

WORKFLOW = """\
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - name: Lint PR title
        run: true
      - name: Check docs links
        run: python3 scripts/check-docs-links.py
      - name: Build
        run: swift build -Xswiftc -warnings-as-errors
      - name: Upload coverage report
        uses: actions/upload-artifact@v7
        with:
          name: coverage-report
          path: coverage/

  ci-gate:
    runs-on: ubuntu-latest
    steps:
      - name: Require every upstream job to be success or skipped
        run: true
"""

MAKEFILE = """\
.PHONY: ci-check static-check docs-links-check build

DOCC_OUTPUT ?= .build/docs

docs-links-check:
\t@python3 scripts/check-docs-links.py

static-check:
\t@$(MAKE) --no-print-directory docs-links-check

ci-check: static-check
\tswift build -Xswiftc -warnings-as-errors
"""

LEDGER = {
    "Lint PR title": ("ci-only", "PR が無いと走らない"),
    "Upload coverage report": ("ci-only", "artifact を残すだけ"),
    "Check docs links": ("local", "make docs-links-check"),
    "Build": ("local", "swift build -Xswiftc -warnings-as-errors"),
}

JOB_LEDGER = {
    "build-and-test": "鏡になるジョブ",
    "ci-gate": "集約ゲート",
}


def _check(workflow=WORKFLOW, makefile=MAKEFILE, ledger=None, job_ledger=None):
    return check.check(
        workflow,
        makefile,
        ledger=LEDGER if ledger is None else ledger,
        job_ledger=JOB_LEDGER if job_ledger is None else job_ledger,
    )


class TestWorkflowParsing(unittest.TestCase):
    def test_reads_step_names_of_the_named_job_only(self):
        self.assertEqual(
            check.step_names(WORKFLOW, "build-and-test"),
            ["Lint PR title", "Check docs links", "Build", "Upload coverage report"],
        )
        self.assertEqual(
            check.step_names(WORKFLOW, "ci-gate"),
            ["Require every upstream job to be success or skipped"],
        )

    def test_ignores_the_name_key_inside_with(self):
        # `with: name: coverage-report` はステップ名ではない。
        self.assertNotIn("coverage-report", check.step_names(WORKFLOW, "build-and-test"))

    def test_reads_job_names(self):
        self.assertEqual(check.job_names(WORKFLOW), ["build-and-test", "ci-gate"])

    def test_does_not_mistake_on_triggers_for_jobs(self):
        # `on:` 直下の `pull_request:` もインデント 2 だが、jobs: より前にある。
        self.assertNotIn("pull_request", check.job_names(WORKFLOW))


class TestMakefileReachability(unittest.TestCase):
    def test_follows_prerequisites_and_sub_make(self):
        targets, recipes = check.reachable(MAKEFILE, "ci-check")
        self.assertIn("static-check", targets)
        self.assertIn("docs-links-check", targets)
        self.assertIn("swift build -Xswiftc -warnings-as-errors", "\n".join(recipes))

    def test_unrelated_targets_are_not_reachable(self):
        targets, _ = check.reachable(MAKEFILE, "docs-links-check")
        self.assertNotIn("ci-check", targets)

    def test_variable_assignments_are_not_targets(self):
        rules = check.parse_makefile(MAKEFILE)
        self.assertNotIn("DOCC_OUTPUT", rules)
        self.assertNotIn(".PHONY", rules)


class TestLedgerRules(unittest.TestCase):
    def test_consistent_input_passes(self):
        self.assertEqual(_check(), [])

    def test_new_ci_step_without_a_ledger_entry_fails(self):
        workflow = WORKFLOW.replace(
            "      - name: Build\n",
            "      - name: Brand new check\n        run: true\n      - name: Build\n",
            1,
        )
        problems = _check(workflow=workflow)
        self.assertTrue(any("Brand new check" in p for p in problems), problems)

    def test_stale_ledger_entry_fails(self):
        workflow = WORKFLOW.replace("- name: Check docs links", "- name: Check doc links", 1)
        problems = _check(workflow=workflow)
        self.assertTrue(any("もうありません" in p for p in problems), problems)

    def test_declared_local_but_unwired_from_ci_check_fails(self):
        # 台帳には書いたが Makefile へ配線し忘れた、という次の失敗も止める。
        makefile = MAKEFILE.replace(
            "ci-check: static-check", "ci-check:", 1
        )
        problems = _check(makefile=makefile)
        self.assertTrue(any("docs-links-check" in p for p in problems), problems)

    def test_declared_local_command_missing_from_recipes_fails(self):
        makefile = MAKEFILE.replace("swift build -Xswiftc -warnings-as-errors", "swift build", 1)
        problems = _check(makefile=makefile)
        self.assertTrue(any("'Build'" in p for p in problems), problems)

    def test_new_job_without_a_ledger_entry_fails(self):
        workflow = WORKFLOW.replace(
            "  ci-gate:\n", "  brand-new-job:\n    runs-on: ubuntu-latest\n  ci-gate:\n", 1
        )
        problems = _check(workflow=workflow)
        self.assertTrue(any("brand-new-job" in p for p in problems), problems)

    def test_unreadable_job_fails_loudly(self):
        # ジョブ名やインデントが変わって 1 つも読めなくなったら、黙って緑にしない。
        problems = check.check(WORKFLOW, MAKEFILE, LEDGER, JOB_LEDGER, job="no-such-job")
        self.assertTrue(any("1 つも読めませんでした" in p for p in problems), problems)


class TestRepositoryIsConsistent(unittest.TestCase):
    """本命: 実際の ci.yml と Makefile が台帳どおりであること。"""

    def test_repository_passes(self):
        workflow = (REPO_ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertEqual(check.check(workflow, makefile), [])

    def test_every_local_entry_names_something_that_exists(self):
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        rules = check.parse_makefile(makefile)
        for name, (kind, value) in check.LEDGER.items():
            if kind == "local" and value.startswith("make "):
                target = value.split(None, 1)[1]
                self.assertIn(target, rules, f"{name}: Makefile に target '{target}' が無い")


if __name__ == "__main__":
    unittest.main()
