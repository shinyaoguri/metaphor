#!/usr/bin/env python3
"""Unit tests for scripts/check-theme-settings.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「`theme-settings.json` に無言で効かないキーが入っていない」ことそのもの
（#529 / #763）。書き間違えても DocC は何も言わず公開ページだけが既定のまま出るので、
リポジトリ実体を見るテスト（`TestRepositoryIsConsistent`）を本命に置き、判定規則の
テストでその周りを固める。
"""

import importlib.util
import sys
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-theme-settings.py"
_spec = importlib.util.spec_from_file_location("check_theme_settings", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_theme_settings"] = check
_spec.loader.exec_module(check)

GOOD = {
    "theme": {
        "color": {"standard-blue": "#6165EF", "article": "#6165EF"},
        "typography": {"html-font": "system-ui"},
    },
    "features": {"docs": {"quickNavigation": {"enable": True}}},
}


class TestLeafPaths(unittest.TestCase):
    def test_flattens_to_dotted_paths(self):
        self.assertEqual(
            check.leaf_paths(GOOD),
            [
                "theme.color.standard-blue",
                "theme.color.article",
                "theme.typography.html-font",
                "features.docs.quickNavigation.enable",
            ],
        )

    def test_empty_settings(self):
        self.assertEqual(check.leaf_paths({}), [])


class TestMatches(unittest.TestCase):
    def test_exact(self):
        self.assertTrue(check.matches("meta.title", "meta.title"))

    def test_wildcard_covers_descendants(self):
        self.assertTrue(check.matches("theme.color.standard-blue", "theme.*"))
        self.assertTrue(check.matches("theme.icons.chevron", "theme.*"))

    def test_wildcard_does_not_cross_siblings(self):
        self.assertFalse(check.matches("features.docs.i18n.enable", "theme.*"))

    def test_prefix_of_name_does_not_match(self):
        # `theme.*` が `themes.color` に当たらない（文字列前方一致で誤判定しない）。
        self.assertFalse(check.matches("themes.color", "theme.*"))


class TestFindIneffective(unittest.TestCase):
    def test_good_settings_have_no_problems(self):
        self.assertEqual(check.find_ineffective(GOOD), [])

    def test_i18n_flag_is_rejected(self):
        # #763: 実装はあるが availableLocales が空なので効かない。
        settings = {"features": {"docs": {"i18n": {"enable": True}}}}
        problems = check.find_ineffective(settings)
        self.assertEqual([path for path, _ in problems], ["features.docs.i18n.enable"])
        self.assertIn("availableLocales", problems[0][1])

    def test_meta_title_is_rejected(self):
        # #763: 取得より前に既定値へ束縛されるので `<title>` は変わらない。
        problems = check.find_ineffective({"meta": {"title": "metaphor"}})
        self.assertEqual([path for path, _ in problems], ["meta.title"])

    def test_unknown_key_is_rejected(self):
        problems = check.find_ineffective({"features": {"docs": {"darkMode": {"enable": True}}}})
        self.assertEqual([path for path, _ in problems], ["features.docs.darkMode.enable"])
        self.assertIn("読まない", problems[0][1])

    def test_on_this_page_navigator_needs_disable_not_enable(self):
        # 実装が読むのは `disable`（既定 ON を切る）。`enable` と書いても無視される。
        self.assertEqual(
            check.find_ineffective(
                {"features": {"docs": {"onThisPageNavigator": {"disable": True}}}}
            ),
            [],
        )
        problems = check.find_ineffective(
            {"features": {"docs": {"onThisPageNavigator": {"enable": True}}}}
        )
        self.assertEqual(
            [path for path, _ in problems], ["features.docs.onThisPageNavigator.enable"]
        )

    def test_theme_keys_are_open(self):
        # theme 配下は CSS 変数へ素通しになるので、名前を列挙して縛らない。
        self.assertEqual(
            check.find_ineffective({"theme": {"borderRadius": "8px", "icons": {"chevron": "…"}}}),
            [],
        )


class TestFindNestedFlatSections(unittest.TestCase):
    def test_flat_colors_pass(self):
        self.assertEqual(check.find_nested_flat_sections(GOOD), [])

    def test_grouped_colors_are_reported(self):
        # #529 の形。`--color-custom-…` という別物の変数になって何も効かなかった。
        settings = {"theme": {"color": {"custom": {"brand": "#6165EF"}}}}
        self.assertEqual(check.find_nested_flat_sections(settings), ["theme.color.custom.brand"])

    def test_other_sections_may_nest(self):
        self.assertEqual(
            check.find_nested_flat_sections({"theme": {"icons": {"chevron": {"path": "…"}}}}), []
        )


class TestRenderSettingPaths(unittest.TestCase):
    SOURCE = (
        'const i=(0,r.PL)(["meta","title"],"Documentation");'
        'enablei18n:({availableLocales:e})=>(0,j.PL)(["features","docs","i18n","enable"],!1)&&e.length>1,'
        '(0,j.PL)(["theme","icons",t],null)'
    )

    def test_extracts_quoted_paths(self):
        paths = check.render_setting_paths([self.SOURCE])
        self.assertIn("meta.title", paths)
        self.assertIn("features.docs.i18n.enable", paths)

    def test_variable_segment_becomes_wildcard(self):
        # 名前を変数で渡している階層（アイコン名など）は `*` に畳む。
        self.assertIn("theme.icons.*", check.render_setting_paths([self.SOURCE]))

    def test_unrelated_arrays_are_ignored(self):
        self.assertEqual(check.render_setting_paths(['["foo","bar"]']), set())


class TestRepositoryIsConsistent(unittest.TestCase):
    """本命: 実ファイルに効かないキーが入ったら CI を赤くする。"""

    def test_every_theme_settings_file_is_effective(self):
        files = check.theme_settings_files()
        self.assertTrue(files, "theme-settings.json が 1 つも見つかりません")
        import json

        for path in files:
            settings = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(
                check.find_ineffective(settings),
                [],
                f"{path} に DocC-Render が読まないキーがあります",
            )
            self.assertEqual(
                check.find_nested_flat_sections(settings),
                [],
                f"{path} の色名が入れ子です（#529）",
            )


if __name__ == "__main__":
    unittest.main()
