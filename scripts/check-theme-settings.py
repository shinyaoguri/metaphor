#!/usr/bin/env python3
"""DocC の `theme-settings.json` に、無言で効かないキーが混ざっていないか検査する。

このファイルの怖さは**間違いが一切表に出ない**こと。DocC はスキーマ検証をせず、
DocC-Render は知らないキーを黙って無視する。書いた本人は効いたつもりで、公開ページだけが
既定のまま出る。同じ穴を 2 回踏んでいる:

- [#529](https://github.com/shinyaoguri/metaphor/issues/529) — `theme.color` に `standard` /
  `custom` のグループを挟んでいた。DocC-Render は `color.<名前>` をそのまま CSS 変数
  `--color-<名前>` にするので、入れ子にすると `--color-custom-0-name` のような別物になる
- [#763](https://github.com/shinyaoguri/metaphor/issues/763) — `features.docs.i18n.enable` と
  `meta.title`。どちらも DocC-Render に**実装はある**が、静的ホスティングでは成立しない
  条件が付いていて効かない（下の `INEFFECTIVE` に理由を書いてある）

正本は Xcode 同梱の DocC-Render（`$(xcrun --find docc)/../../share/docc/render/js/*.js`）で、
そこで `getSetting([...])` に渡されているパスがこのファイルから読まれるキーのすべて。
ただし CI をその抽出結果に直結させると Xcode の更新で無関係な PR が落ちるので、

- 既定（`python3 scripts/check-theme-settings.py`）… 下の表と突き合わせるだけ。Xcode 非依存
- `--against-render` … render の実装から抽出して表とのドリフトを報告する（落とさない）

の 2 段にしてある。DocC を更新したら `--against-render` を回して表を直す。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# 効くと実測で確かめたキー。`*` はどんな名前でもよい階層（色名・アイコン名など）。
EFFECTIVE = (
    "features.docs.quickNavigation.enable",
    "features.docs.onThisPageNavigator.disable",  # 既定 ON を切るためのキー。`enable` ではない
    "theme.*",  # color / typography / borderRadius / icons / device-frames / code は CSS 変数と設定の両方へ
    "meta.*",  # `meta.title` を除く（下記）。将来 render が読むキーが増えたときのために開けておく
)

# render に実装はあるが、静的ホスティングでは効かないキー。書いても表に出ないので通さない。
INEFFECTIVE = {
    "features.docs.i18n.enable": (
        "有効化の条件が `availableLocales.length > 1` で、availableLocales は render JSON の "
        "`metadata.availableLocales` からしか埋まらない。DocC 本体はこれを出力しないので "
        "単体では効かない（#763）"
    ),
    "meta.title": (
        "`getSetting([\"meta\",\"title\"], \"Documentation\")` がモジュール読み込み時に"
        "定数へ束縛され、theme-settings.json の取得はそのあと。`<title>` も `og:site_name` も"
        "既定の \"Documentation\" のまま出る（#763 で実測）"
    ),
}

# `theme.color` だけは入れ子を許さない（#529）。値はスカラーでなければならない。
FLAT_SECTIONS = ("theme.color",)

# render のバンドルから `getSetting(["a","b",...])` のパスを拾う。ミニファイで関数名は
# 変わるので、引数の配列リテラルの形だけを見る。変数で渡している階層は `*` として扱う。
_SETTING_PATH_RE = re.compile(
    r"""\[\s*"(?P<root>features|meta|theme)"\s*(?P<rest>(?:,\s*(?:"[^"]*"|[A-Za-z_$][\w$]*)\s*)*)\]"""
)
_SETTING_SEGMENT_RE = re.compile(r""""([^"]*)"|([A-Za-z_$][\w$]*)""")


def leaf_paths(settings: dict, prefix: str = "") -> list[str]:
    """設定の葉までのドット区切りパスを列挙する。"""
    paths: list[str] = []
    for key, value in settings.items():
        path = f"{prefix}{key}"
        if isinstance(value, dict):
            paths.extend(leaf_paths(value, f"{path}."))
        else:
            paths.append(path)
    return paths


def matches(path: str, pattern: str) -> bool:
    """`theme.*` のようなワイルドカード付きパターンに当たるか。

    `*` はその階層以下すべてを意味する（`theme.*` は `theme.color.standard-blue` にも当たる）。
    """
    if pattern.endswith(".*"):
        return path == pattern[:-2] or path.startswith(pattern[:-1])
    return path == pattern


def find_ineffective(settings: dict) -> list[tuple[str, str]]:
    """効かないキーを (パス, 理由) で返す。既知の無効キーと、表に無いキーの両方。"""
    problems: list[tuple[str, str]] = []
    for path in leaf_paths(settings):
        if path in INEFFECTIVE:
            problems.append((path, INEFFECTIVE[path]))
            continue
        if not any(matches(path, pattern) for pattern in EFFECTIVE):
            problems.append((path, "DocC-Render が読まないキー（無言で無視される）"))
    return problems


def find_nested_flat_sections(settings: dict) -> list[str]:
    """フラットでなければならない節に入れ子があれば、そのパスを返す（#529）。"""
    nested: list[str] = []
    for path in leaf_paths(settings):
        for section in FLAT_SECTIONS:
            if path.startswith(f"{section}.") and path.count(".") > section.count(".") + 1:
                nested.append(path)
    return nested


def render_setting_paths(sources: list[str]) -> set[str]:
    """DocC-Render のバンドルから、読まれる設定パスを抽出する。"""
    found: set[str] = set()
    for source in sources:
        for match in _SETTING_PATH_RE.finditer(source):
            segments = [match.group("root")]
            for quoted, identifier in _SETTING_SEGMENT_RE.findall(match.group("rest")):
                segments.append(quoted if quoted else "*")
            found.add(".".join(segments))
    return found


def render_js_sources() -> list[str]:
    """Xcode 同梱の DocC-Render の JS を読む。見つからなければ空。"""
    try:
        docc = subprocess.run(
            ["xcrun", "--find", "docc"], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return []
    render_js = Path(docc).parent.parent / "share" / "docc" / "render" / "js"
    if not render_js.is_dir():
        return []
    return [path.read_text(encoding="utf-8", errors="replace") for path in render_js.glob("*.js")]


def theme_settings_files() -> list[Path]:
    """リポジトリ内の theme-settings.json をすべて返す（カタログが増えても拾う）。"""
    return sorted(REPO_ROOT.glob("Sources/**/*.docc/theme-settings.json"))


def report_drift() -> None:
    """render の実装と `EFFECTIVE` / `INEFFECTIVE` の表のずれを報告する（落とさない）。"""
    sources = render_js_sources()
    if not sources:
        print("SKIP: DocC-Render のバンドルが見つかりません（Xcode が要ります）")
        return
    known = set(INEFFECTIVE)
    for path in render_setting_paths(sources):
        if path in known or any(matches(path, pattern) for pattern in EFFECTIVE):
            continue
        print(f"DRIFT: render は {path} を読みますが、このスクリプトの表にありません")
    print(f"（render から {len(render_setting_paths(sources))} 個の設定パスを抽出しました）")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--against-render",
        action="store_true",
        help="DocC-Render の実装から設定パスを抽出し、表とのずれを報告する（終了コードは変えない）",
    )
    args = parser.parse_args()

    failed = False
    for path in theme_settings_files():
        relative = path.relative_to(REPO_ROOT)
        settings = json.loads(path.read_text(encoding="utf-8"))
        for key, reason in find_ineffective(settings):
            print(f"FAIL: {relative} の `{key}` は効きません — {reason}")
            failed = True
        for nested in find_nested_flat_sections(settings):
            print(f"FAIL: {relative} の `{nested}` は入れ子です — 色名は `theme.color` 直下へ（#529）")
            failed = True
        if not failed:
            print(f"OK: {relative} は DocC-Render が読むキーだけで書かれています")

    if args.against_render:
        report_drift()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
