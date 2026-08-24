#!/usr/bin/env python3
"""Commit the working tree's changes through GitHub's API, so the commit is signed.

The `main protection` ruleset requires signed commits (added 2026-08-04). The
release workflow builds its version-bump commit on a runner as
`github-actions[bot]`, which has no signing key: a plain `git commit` +
`git push` produces an **unsigned** commit, and GitHub then refuses to merge the
release PR — "the base branch policy prohibits the merge" — after the Syphon
build and a full CI run have already happened. That is how v0.9.0 failed on
2026-08-10.

Commits created through the GraphQL `createCommitOnBranch` mutation are signed
by GitHub itself. Routing the release commit through it clears the rule without
opening a ruleset bypass for Actions (which would let Actions skip *every* rule,
not just this one).

The workflow keeps editing files exactly as before — `sed`, `changelog.py`, all
of it. Only the commit-and-push step changes: this script reads what changed
from `git status --porcelain` and sends it as one signed commit.

    signed-commit.py --repo owner/name --branch release/v0.9.0 \
        --expected-head <sha> --message "Release v0.9.0"

`--expected-head` is the SHA the branch is expected to point at; GitHub rejects
the mutation if someone else moved the branch in the meantime (optimistic
locking — the mutation has no force mode). It is normalized through
`git rev-parse`, so `HEAD`, a branch name or a short SHA all work — the API
itself only accepts the full 40-character form (Issue #981).

`--dry-run` prints what would be sent instead of sending it, which is the only
way to exercise this outside a real release.

**このスクリプトは pre-push フックを一切通りません。** `git push` ではなく GraphQL
へ直接投げるためで、署名は外れません（GitHub 自身が署名し、ブランチ保護のルール
セットもサーバー側で独立に効く）。外れるのは **pre-push が担っていた生成物の鮮度
検査だけ**です（Issue #978）。実際 2026-08-18 の docs 一掃バッチでは 1Password の
SSH エージェントがハングして本スクリプトが復旧手段になり、鮮度検査を通らない経路で
22 コミットが main へ入りました（CI が拾ったので実害は出ませんでしたが、ローカルの
歯止めはゼロでした）。「使う前に手で検査する」という文書ルールは、**本スクリプトを
使う状況＝署名系が壊れているときほど守られません**。

そこで送信の前に `scripts/check-generated-freshness.sh --all` を走らせ、陳腐化して
いたら **1 バイトも送らずに** abort します。降りられるのは `--skip-freshness` を
明示したときだけです。

いま降りているのは release.yml だけで、理由は 2 つあります。runner の変更セット
（`BUMP_PATHS`）には `Sources/MetaphorCore/Core/MetaphorVersion.swift` が入るので
llms.txt の検査が起動して `make llms-txt` = `swift build` が丸ごと乗ること、そして
リリースブランチの PR で CI が同じ検査を独立に回すことです。

`--dry-run` は何も送らないので、鮮度検査も走りません。
"""

import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path

# pre-push が呼ぶのと同じ実体。あちらは push する range から必要な検査だけを選べる
# が、この経路が見られるのは作業ツリーだけなので、変更パスから絞ると `git merge
# origin/main` 由来の陳腐化（#786 / #972）を取りこぼす。だから `--all`。
FRESHNESS_SCRIPT = "scripts/check-generated-freshness.sh"

MUTATION = """
mutation($input: CreateCommitOnBranchInput!) {
  createCommitOnBranch(input: $input) {
    commit { oid }
  }
}
"""


def parse_porcelain(text: str) -> tuple[list[str], list[str]]:
    """Split `git status --porcelain` output into (additions, deletions).

    Only the paths matter, not which side of the index they sit on: the release
    workflow never staged anything, and `createCommitOnBranch` takes the final
    content either way. A rename arrives as `R  old -> new`, which is a deletion
    of the old path plus an addition of the new one.
    """
    additions: list[str] = []
    deletions: list[str] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        status, path = line[:2], line[3:]
        if " -> " in path:  # rename or copy
            old, new = path.split(" -> ", 1)
            deletions.append(_unquote(old))
            additions.append(_unquote(new))
            continue
        path = _unquote(path)
        # 'D' in either column means the file is gone from the working tree.
        if "D" in status:
            deletions.append(path)
        else:
            additions.append(path)
    return sorted(set(additions)), sorted(set(deletions))


def _unquote(path: str) -> str:
    """git quotes paths containing special characters; undo that."""
    if path.startswith('"') and path.endswith('"'):
        return path[1:-1].encode().decode("unicode_escape")
    return path


def build_payload(
    repo: str,
    branch: str,
    expected_head: str,
    message: str,
    additions: list[tuple[str, str]],
    deletions: list[str],
) -> dict:
    """Assemble the GraphQL request body.

    `message` is split into headline and body on the first blank line, matching
    how `git commit -m` treats a multi-line message.
    """
    headline, _, body = message.partition("\n\n")
    commit_message: dict[str, str] = {"headline": headline.strip()}
    if body.strip():
        commit_message["body"] = body.strip()
    return {
        "query": MUTATION,
        "variables": {
            "input": {
                "branch": {
                    "repositoryNameWithOwner": repo,
                    "branchName": branch,
                },
                "expectedHeadOid": expected_head,
                "message": commit_message,
                "fileChanges": {
                    "additions": [
                        {"path": path, "contents": contents}
                        for path, contents in additions
                    ],
                    "deletions": [{"path": path} for path in deletions],
                },
            }
        },
    }


def encode_file(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def check_freshness(repo_root: Path) -> int:
    """Run the pre-push freshness checks against `repo_root`; 0 means fresh.

    Output goes straight to this process's stderr/stdout: the recovery commands
    the script prints are the whole point, and swallowing them would leave the
    caller with an exit code and no instructions.

    A missing script is an error, not a skip. Degrading silently to "no checks"
    is precisely the failure this gate exists to close (#978).
    """
    script = repo_root / FRESHNESS_SCRIPT
    if not script.is_file():
        print(
            f"::error::{script} not found — cannot verify that generated "
            "artifacts are up to date. Pass --skip-freshness to commit anyway.",
            file=sys.stderr,
        )
        return 1
    return subprocess.run(
        [str(script), "--label", "[signed-commit]", "--all"], cwd=str(repo_root)
    ).returncode


def resolve_head(ref: str, repo_root: Path) -> str:
    """Expand `ref` to the full 40-character SHA `expectedHeadOid` requires.

    That field is a `GitObjectID`: a short SHA, a branch name or `HEAD` comes
    back as `Could not coerce value "077bd06" to GitObjectID` — and only after
    every file has been read and base64-encoded and the request has gone out, so
    the log reads like a rejected commit rather than a bad argument (Issue #981).
    `git rev-parse` settles it here instead, before anything is uploaded.

    Deliberately without `--verify`. `release.yml` already hands over a full SHA
    it read from the checkout (`BASE_SHA=$(git rev-parse HEAD)`), so a stricter
    check buys the release path nothing; meanwhile a plain `rev-parse` echoes a
    40-character SHA back even when that object is not present locally, which is
    what a caller reading the branch head from the API would pass. Existence is
    checked where it matters anyway — the mutation rejects a head that does not
    match.
    """
    return subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", ref],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--branch", required=True, help="Branch to commit onto.")
    parser.add_argument(
        "--expected-head",
        required=True,
        help=(
            "Revision the branch must currently point at. Expanded through "
            "`git rev-parse`, so `HEAD`, a branch name or a short SHA all work."
        ),
    )
    parser.add_argument("--message", required=True, help="Commit message.")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="Working tree to read changes from (default: cwd).",
    )
    parser.add_argument(
        "--path",
        action="append",
        dest="paths",
        default=None,
        help=(
            "Limit to these paths (repeatable). Without it the whole tree is "
            "committed, which on a CI runner would sweep up build output that "
            "merely happens not to be ignored."
        ),
    )
    parser.add_argument(
        "--skip-freshness",
        action="store_true",
        help=(
            "Skip the generated-artifact freshness checks. Only release.yml "
            "passes this — see the module docstring for why."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be sent instead of sending it.",
    )
    args = parser.parse_args(argv)

    # Before a single file is read: a bad ref here is an argument mistake, and
    # it should read as one instead of as a rejected mutation.
    try:
        expected_head = resolve_head(args.expected_head, args.repo_root)
    except subprocess.CalledProcessError as exc:
        print(
            f"::error::--expected-head {args.expected_head!r} is not a revision "
            f"in {args.repo_root}: {exc.stderr.strip()}",
            file=sys.stderr,
        )
        return 1

    # Before the change set is read: the checks regenerate llms.txt and the
    # examples index in place, so a stale tree has to be caught (and aborted on)
    # while `git status` still reflects what the author actually meant to send.
    if not args.skip_freshness and not args.dry_run:
        freshness = check_freshness(args.repo_root)
        if freshness != 0:
            print(
                "::error::Generated artifacts are stale — nothing was sent. "
                "Regenerate and commit them, or pass --skip-freshness.",
                file=sys.stderr,
            )
            return freshness

    command = ["git", "-C", str(args.repo_root), "status", "--porcelain"]
    if args.paths:
        command += ["--", *args.paths]
    porcelain = subprocess.run(
        command, check=True, capture_output=True, text=True
    ).stdout
    additions, deletions = parse_porcelain(porcelain)
    if not additions and not deletions:
        print("::error::Nothing to commit — no working-tree changes.", file=sys.stderr)
        return 1

    payload = build_payload(
        repo=args.repo,
        branch=args.branch,
        expected_head=expected_head,
        message=args.message,
        additions=[(p, encode_file(args.repo_root / p)) for p in additions],
        deletions=deletions,
    )

    for path in additions:
        print(f"  + {path}", file=sys.stderr)
    for path in deletions:
        print(f"  - {path}", file=sys.stderr)

    if args.dry_run:
        print(json.dumps(payload["variables"]["input"]["fileChanges"], indent=2))
        return 0

    result = subprocess.run(
        ["gh", "api", "graphql", "--input", "-"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"::error::createCommitOnBranch failed: {result.stderr}", file=sys.stderr)
        return result.returncode
    response = json.loads(result.stdout)
    # GraphQL reports failures in a 200 response, so a zero exit is not enough.
    if response.get("errors"):
        print(f"::error::createCommitOnBranch: {response['errors']}", file=sys.stderr)
        return 1
    oid = response["data"]["createCommitOnBranch"]["commit"]["oid"]
    print(oid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
