#!/usr/bin/env python3
"""Issue のタイトルの型からラベルを決め、付ける。

無ラベルの Issue が 292 件中 95 件まで溜まった原因は、付け忘れではなく
**起票の入口が 2 系統あって片方だけ塞がっている**ことだった (Issue #663):

    Issue テンプレート (Web UI)  -> `.github/ISSUE_TEMPLATE/*.yml` の
                                    `labels:` が効くので付く
    `gh issue create` (AI・CLI)  -> テンプレートを通らないので何も付かない

後者は AI が使う経路で、塞ぐ手立てが無い。代わりに **立った後で付ける**のが
このスクリプトで、`.github/workflows/issue-labeler.yml` が新しい Issue ごとに
`--title` で呼ぶ。溜まった分は `--backfill` が同じ写像で片付ける。

## なぜタイトルから決まるのか

無ラベル 95 件のうち 92 件 (97%) はタイトルが Conventional Commits の形を
していた。AI は PR タイトルの規約 (`ci.yml` の *Lint PR title*、型の正本は
Issue #498) を Issue にも流用するので、そこから決定論的に写せる。LLM に本文を
読ませる案もあったが、残る 3% のために外部依存とレート制限を持ち込む釣り合いが
取れない。読めなかったものは `status: needs-triage` が付いて人に回る。

## ラベル体系

Issue 運用の一般的な慣行に合わせ、次元を prefix で分けてある。1 つの Issue に
付くのは `type:` 1 枚 (必要なら `status:` 1 枚) だけで、色は次元ごとに揃える。
`area:` を入れていないのは、タイトルの scope が 40 種類以上に散っていて
(`Examples`/`examples` のような表記揺れもあり、72 件は scope 自体が無い)、
そのままラベルにすると「増やしすぎない」に反するから。

**この写像がラベル体系の正本**。`.github/ISSUE_TEMPLATE/*.yml` の `labels:` と
CONTRIBUTING.md の対応表はここに従う。PyYAML は CI に入っていないので、定義を
YAML に外出しせずここに置いて二重定義を避けている。

Usage:

    # 1 件を判定してラベル名を stdout に出す (ワークフローが使う)
    python3 scripts/label-issues.py --title 'fix(Core): 落ちる'

    # 溜まった無ラベル Issue に一括で付ける (まず --dry-run で一覧を見る)
    python3 scripts/label-issues.py --backfill --dry-run
    python3 scripts/label-issues.py --backfill

    # ラベル体系そのものを GitHub へ反映する (リネーム + 作成)
    python3 scripts/label-issues.py --sync-labels --dry-run

Exit codes: 0 = 成功、1 = `gh` の呼び出しに失敗。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

# `type(scope)!: summary` — scope と breaking marker は任意。
#
# `release-bump.py` の `_SUBJECT` と同じ形だが、2 点だけ違う:
#
#   1. 型に `/` を許す — Issue では 2 つの領域に跨ることを示す
#      `docs/api(Text): ...` という書き方が実際に使われている。
#   2. 区切りに続く空白まで求める — `ci.yml` の PR lint (`: .+`) と揃えて、
#      `fix:` で終わるタイトルを型と見なさないため。要約の中身は PR lint と
#      同じく一切問わない (日本語・記号・空白の数、いずれも自由)。
#
# 大文字で始まる前置き (`3D: 箱が出ない` の `3D`) は型ではなく、ここで弾かれて
# triage に落ちる。
_SUBJECT = re.compile(
    r"^(?P<type>[a-z]+(?:/[a-z]+)?)(?:\((?P<scope>[^)]*)\))?(?P<breaking>!)?: "
)

TRIAGE_LABEL = "status: needs-triage"

# 型 -> ラベル。左の型は実際に Issue で使われているものだけを並べてある
# (件数は Issue #663 の調査時点)。
#
# `design` / `api` / `dev` は PR タイトルの許可型 (ci.yml) には無いが、Issue では
# 使われている。Issue には PR に無い「検討」の段階があり、実際 #663 の調査時点で
# `design(...)` が 7 件あった。Issue #498 が PR lint の側を Issue の慣行に寄せた
# のと同じ向きで、ここでも実態を追認している。
#
# `perf` が maintenance 側にあるのは意図的。`release-bump.py` の `BUMP_BY_TYPE`
# では `perf` は patch リリースを起こす型だが、それは「リリースに値するか」の
# 判定で、「何の Issue か」の分類とは別問題。性能改善は新しい機能ではない。
LABEL_BY_TYPE = {
    "fix": "type: bug",
    "feat": "type: feature",
    "api": "type: feature",
    "docs": "type: docs",
    "docs/api": "type: docs",
    "design": "type: design",
    "chore": "type: maintenance",
    "ci": "type: maintenance",
    "test": "type: maintenance",
    "refactor": "type: maintenance",
    "build": "type: maintenance",
    "perf": "type: maintenance",
    "dev": "type: maintenance",
}

# 作る・直すラベルの定義 (name -> (color, description))。色は次元ごとに揃える。
# `type:` は既存 3 枚の色をそのまま引き継ぐので、リネームしても見た目が変わらない。
LABEL_DEFINITIONS = {
    "type: bug": ("d73a4a", "動くはずのものが動かない"),
    "type: feature": ("a2eeef", "新しい機能・API の追加や変更"),
    "type: docs": ("0075ca", "ドキュメント・チュートリアル・生成物の記述"),
    "type: design": ("8b5cf6", "実装の前に方針を決める検討"),
    "type: maintenance": ("c5def5", "CI・テスト・リファクタなど保守作業"),
    "type: question": ("d876e3", "使い方・仕様についての質問"),
    TRIAGE_LABEL: ("fbca04", "自動でラベルを決められなかった (要トリアージ)"),
    "status: duplicate": ("cfd3d7", "既出"),
    "status: invalid": ("e4e669", "問題として成立していない"),
    "status: wontfix": ("ffffff", "対応しないと決めたもの"),
}

# 旧名 -> 新名。`gh label edit --name` はリネームであって作り直しではないので、
# 既に付いている Issue の付与はそのまま移る (203 件が該当)。
#
# `good first issue` / `help wanted` は入れていない: GitHub がこの 2 つを名前で
# 特別扱いしており (リポの Contribute ページ、good-first-issues API)、改名すると
# 外部からの貢献導線が切れる。`release:*` / `no-changelog` / `no-visual-change` も
# 対象外で、こちらはワークフローが名前で読んでいる。
RENAMES = {
    "bug": "type: bug",
    "enhancement": "type: feature",
    "documentation": "type: docs",
    "question": "type: question",
    "duplicate": "status: duplicate",
    "invalid": "status: invalid",
    "wontfix": "status: wontfix",
}


def parse_type(title: str) -> str | None:
    """タイトルの型を返す。Conventional Commits の形でなければ `None`。"""
    match = _SUBJECT.match(title.strip())
    if match is None:
        return None
    return match.group("type")


def label_for_title(title: str) -> str:
    """タイトルに付けるべきラベル。決められなければ `status: needs-triage`。

    知らない型 (`style` など) も triage に落ちる。黙って `maintenance` に
    寄せると、写像に足すべき型が増えたことに誰も気づけなくなる。
    """
    issue_type = parse_type(title)
    if issue_type is None:
        return TRIAGE_LABEL
    return LABEL_BY_TYPE.get(issue_type, TRIAGE_LABEL)


def _gh(args: list[str], repo: str | None = None) -> str:
    """`gh` を呼んで stdout を返す。失敗したら `SystemExit(1)`。"""
    command = ["gh", *args]
    if repo:
        command += ["--repo", repo]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"::error::gh の呼び出しに失敗: {' '.join(command)}", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
        raise SystemExit(1)
    return result.stdout


def sync_labels(repo: str | None, dry_run: bool) -> int:
    """ラベル体系を GitHub へ反映する (リネーム -> 作成の順)。"""
    existing = {
        label["name"] for label in json.loads(_gh(["label", "list", "--limit", "200", "--json", "name"], repo))
    }

    for old, new in RENAMES.items():
        if old not in existing:
            continue
        if new in existing:
            print(f"skip  rename {old!r} -> {new!r} (新名が既にある)")
            continue
        print(f"{'DRY ' if dry_run else ''}rename {old!r} -> {new!r}")
        if not dry_run:
            color, description = LABEL_DEFINITIONS[new]
            _gh(["label", "edit", old, "--name", new, "--color", color, "--description", description], repo)
        # dry-run でも帳簿は進める。ここを実行時だけにすると、リネームで手に入る
        # 名前を下の作成ループが「まだ無い」と読んで、予告にだけ create が並ぶ。
        # 予告が実際と食い違えば、実行前に確かめる意味が無くなる。
        existing.discard(old)
        existing.add(new)

    for name, (color, description) in LABEL_DEFINITIONS.items():
        if name in existing:
            continue
        print(f"{'DRY ' if dry_run else ''}create {name!r}")
        if not dry_run:
            _gh(["label", "create", name, "--color", color, "--description", description], repo)

    return 0


def backfill(repo: str | None, dry_run: bool, state: str) -> int:
    """無ラベルの Issue に写像を適用する。"""
    issues = json.loads(
        _gh(
            [
                "issue", "list",
                "--search", "no:label",
                "--state", state,
                "--limit", "500",
                "--json", "number,title",
            ],
            repo,
        )
    )
    if not issues:
        print("無ラベルの Issue はありません。")
        return 0

    counts: dict[str, int] = {}
    for issue in issues:
        label = label_for_title(issue["title"])
        counts[label] = counts.get(label, 0) + 1
        print(f"{'DRY ' if dry_run else ''}#{issue['number']:<5} {label:<22} {issue['title']}")
        if not dry_run:
            _gh(["issue", "edit", str(issue["number"]), "--add-label", label], repo)

    print(f"\n合計 {len(issues)} 件:")
    for label, count in sorted(counts.items(), key=lambda item: -item[1]):
        print(f"  {count:>4}  {label}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--title", help="このタイトルに付けるべきラベルを stdout に出す。")
    parser.add_argument("--backfill", action="store_true", help="無ラベルの Issue に一括で付ける。")
    parser.add_argument("--sync-labels", action="store_true", help="ラベル体系を GitHub へ反映する。")
    parser.add_argument("--repo", help="対象リポジトリ (既定: カレントのリポジトリ)。")
    parser.add_argument("--dry-run", action="store_true", help="実際には変更せず、何をするかだけ出す。")
    parser.add_argument(
        "--state",
        default="all",
        choices=("all", "open", "closed"),
        help="--backfill が対象にする状態 (既定: all — 過去分も検索・集計が揃うように)。",
    )
    args = parser.parse_args(argv)

    if args.title:
        print(label_for_title(args.title))
        return 0
    if args.sync_labels:
        return sync_labels(args.repo, args.dry_run)
    if args.backfill:
        return backfill(args.repo, args.dry_run, args.state)

    parser.error("--title / --backfill / --sync-labels のいずれかを指定してください。")


if __name__ == "__main__":
    sys.exit(main())
