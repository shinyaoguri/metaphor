#!/usr/bin/env python3
"""使い捨てリポジトリのための、外の設定から密封した `git`（Issue #979 / #974）。

`scripts/tests/` のいくつかは一時ディレクトリを `git init` して履歴を積む。ところが
**使い捨てのリポジトリも開発機のグローバル設定を継ぐ**ので、コミット署名を設定した
マシンではテスト中のコミットまで署名を要求される。

    commit.gpgsign = true / gpg.format = ssh / user.signingkey = …

署名の実体（1Password のような SSH エージェント、あるいは鍵ファイル）に手が届かな
ければ `git commit` は exit 128 で落ち、承認プロンプト待ちに入れば**そのまま返って
こない**。落ちるのは「この履歴からどの bump が導けるか」「撮影後にソースが動いたか」
を見るテストで、署名はその関心事ではない。CI は素の runner で署名設定が無いため常に
green — つまりこの差は CI からは永久に見えず、手元でだけ赤くなる。

密封は署名だけを個別に上書きするのではなく、`GIT_CONFIG_GLOBAL` /
`GIT_CONFIG_SYSTEM` を `os.devnull` に向けて行う。**まだ誰も上書きを思いついていない
設定まで一度に締め出せる**からで、`init.defaultBranch`・`core.excludesFile`・
`tag.forceSignAnnotated`・`[include]` の連鎖などが該当する。身元は同じ環境の
`GIT_AUTHOR_*` / `GIT_COMMITTER_*` から与えるので、一時リポジトリ側に
`git config user.name` を打つ必要が無く、**`user.name` を一度も設定していないマシン
でも**通る。

締め出すのは global / system の**設定ファイル**であって、`~/.config/git/ignore` の
ような設定を経由しない既定パスまでは覆わない。対象はテストが作る使い捨てリポジトリ
だけで、リポジトリ本体のコミット署名運用（全コミット Verified）には影響しない。
"""

from __future__ import annotations

import os
import subprocess
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

# `.invalid` は RFC 6761 が「解決されないこと」を保証する予約 TLD。取り違えて外へ
# 出ても誰にも届かない。
_SEAL = {
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
    "GIT_AUTHOR_NAME": "metaphor tests",
    "GIT_AUTHOR_EMAIL": "tests@example.invalid",
    "GIT_COMMITTER_NAME": "metaphor tests",
    "GIT_COMMITTER_EMAIL": "tests@example.invalid",
}


def hermetic_env(**overrides: str) -> dict[str, str]:
    """外の git 設定を締め出した環境（`os.environ` に密封を重ねたもの）。

    `subprocess.run(..., env=hermetic_env())` の形で、git を直接呼ぶ以外の経路
    （テスト対象のシェルスクリプトを起動する等）にも同じ密封を渡せる。
    """
    return {**os.environ, **_SEAL, **overrides}


@contextmanager
def hermetic_environ() -> Iterator[None]:
    """`os.environ` 自体を密封する（テスト対象が内側で git を呼ぶとき用）。

    `env=` を渡せるのは自分で起動するプロセスだけ。テスト対象の関数が中で
    `subprocess.run(["git", ...])` する場合は、その子プロセスが継ぐのは
    `os.environ` なので、こちらでまとめて被せる。
    """
    saved = {key: os.environ.get(key) for key in _SEAL}
    os.environ.update(_SEAL)
    try:
        yield
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def git(*args: str, cwd: Path | str | None = None) -> str:
    """密封した環境で git を走らせ、stdout をそのまま返す（失敗したら送出）。"""
    return subprocess.run(
        ["git", *args],
        cwd=None if cwd is None else str(cwd),
        env=hermetic_env(),
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def init_repo(repo: Path, branch: str = "main") -> Path:
    """`repo` を（必要なら作って）`branch` の上に `git init` する。

    ブランチ名を明示するのは、既定名が `init.defaultBranch` 由来だから — 密封した
    時点で開発機の既定は届かなくなり、git 組み込みの既定（`master` + 警告）に落ちる。
    テストがブランチ名を当てにするなら、ここで決めておくのが筋。
    """
    repo.mkdir(parents=True, exist_ok=True)
    git("init", "-q", "-b", branch, cwd=repo)
    return repo
