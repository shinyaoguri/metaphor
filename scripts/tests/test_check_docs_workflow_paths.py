#!/usr/bin/env python3
"""Unit tests for scripts/check-docs-workflow-paths.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「website のビルド入力を docs.yml の `on.push.paths` が覆っている」こと
そのもの（Issue #554）。取りこぼしてもビルドは緑のまま公開サイトだけが古くなるため、
リポジトリ実体を見るテスト（`TestRepositoryIsConsistent`）を本命に置き、判定規則の
テストでその周りを固める。
"""

import importlib.util
import sys
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-docs-workflow-paths.py"
_spec = importlib.util.spec_from_file_location("check_docs_workflow_paths", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_docs_workflow_paths"] = check
_spec.loader.exec_module(check)

WORKFLOW = """\
name: Documentation

on:
  push:
    branches: [main]
    paths:
      - 'Sources/**'
      - 'website/**'
      - 'docs/tutorial/**'
      - '.github/workflows/docs.yml'
  workflow_dispatch:

jobs:
  build-docs:
    runs-on: macos-26
"""

CONFIG = """\
const tutorial = defineCollection({
  loader: glob({
    base: '../docs/tutorial',
    pattern: ['[0-9][0-9]-*.{md,mdx}'],
  }),
});
"""


class TestExternalBuildInputs(unittest.TestCase):
    def test_base_outside_website_is_repo_relative(self):
        self.assertEqual(check.external_build_inputs(CONFIG), ["docs/tutorial"])

    def test_base_inside_website_is_ignored(self):
        # `website/**` が丸ごと覆うので、突き合わせの対象にしない。
        source = "loader: glob({ base: './src/content/notes' })"
        self.assertEqual(check.external_build_inputs(source), [])

    def test_double_quoted_base_is_read(self):
        source = 'loader: glob({ base: "../docs/tutorial" })'
        self.assertEqual(check.external_build_inputs(source), ["docs/tutorial"])

    def test_duplicate_bases_collapse(self):
        self.assertEqual(check.external_build_inputs(CONFIG + CONFIG), ["docs/tutorial"])

    def test_multiple_bases_are_all_reported(self):
        source = CONFIG + "loader: glob({ base: '../Examples' })"
        self.assertEqual(check.external_build_inputs(source), ["docs/tutorial", "Examples"])

    def test_base_outside_repository_is_rejected(self):
        source = "loader: glob({ base: '../../elsewhere' })"
        with self.assertRaises(ValueError):
            check.external_build_inputs(source)


class TestWorkflowPushPaths(unittest.TestCase):
    def test_reads_the_paths_block(self):
        self.assertEqual(
            check.workflow_push_paths(WORKFLOW),
            ["Sources/**", "website/**", "docs/tutorial/**", ".github/workflows/docs.yml"],
        )

    def test_stops_at_the_next_key(self):
        # `workflow_dispatch:` 以降を巻き込まない（インデントが浅くなったら終わり）。
        self.assertNotIn("workflow_dispatch:", check.workflow_push_paths(WORKFLOW))

    def test_skips_comment_lines_above_the_block(self):
        commented = WORKFLOW.replace(
            "    paths:", "    # website のビルド入力を漏らさないこと\n    paths:"
        )
        self.assertEqual(check.workflow_push_paths(commented)[0], "Sources/**")

    def test_missing_paths_block_is_empty(self):
        self.assertEqual(check.workflow_push_paths("on:\n  push:\n    branches: [main]\n"), [])


class TestIsCovered(unittest.TestCase):
    def test_exact_directory(self):
        self.assertTrue(check.is_covered("docs/tutorial", ["docs/tutorial/**"]))

    def test_parent_directory(self):
        self.assertTrue(check.is_covered("docs/tutorial", ["docs/**"]))

    def test_trailing_star_star_slash_star(self):
        self.assertTrue(check.is_covered("docs/tutorial", ["docs/tutorial/**/*"]))

    def test_sibling_directory_does_not_cover(self):
        self.assertFalse(check.is_covered("docs/tutorial", ["docs/adr/**"]))

    def test_prefix_of_name_does_not_cover(self):
        # `docs/tut/**` は `docs/tutorial` を覆わない（文字列前方一致で誤判定しない）。
        self.assertFalse(check.is_covered("docs/tutorial", ["docs/tut/**"]))

    def test_partial_glob_does_not_count_as_coverage(self):
        # 配下すべてを確実に拾うとは言えない書き方は「覆えていない」に倒す。
        self.assertFalse(check.is_covered("docs/tutorial", ["docs/tutorial/*.md"]))
        self.assertFalse(check.is_covered("docs/tutorial", ["docs/*/**"]))

    def test_plain_file_entry_does_not_cover(self):
        self.assertFalse(check.is_covered("docs/tutorial", ["Package.swift"]))


class TestFindUncovered(unittest.TestCase):
    def test_consistent_pair(self):
        self.assertEqual(check.find_uncovered(CONFIG, WORKFLOW), [])

    def test_reports_the_missing_input(self):
        without_tutorial = WORKFLOW.replace("      - 'docs/tutorial/**'\n", "")
        self.assertEqual(check.find_uncovered(CONFIG, without_tutorial), ["docs/tutorial"])


class TestRepositoryIsConsistent(unittest.TestCase):
    """本命: 実ファイル同士が食い違ったら CI を赤くする。"""

    def test_docs_workflow_covers_every_website_build_input(self):
        uncovered = check.find_uncovered(
            check.CONTENT_CONFIG.read_text(encoding="utf-8"),
            check.DOCS_WORKFLOW.read_text(encoding="utf-8"),
        )
        self.assertEqual(
            uncovered,
            [],
            "website のビルド入力が .github/workflows/docs.yml の on.push.paths に "
            f"入っていません: {uncovered}. paths に '<パス>/**' を足してください。",
        )


if __name__ == "__main__":
    unittest.main()
