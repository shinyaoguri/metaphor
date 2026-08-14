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
locking — the mutation has no force mode).

`--dry-run` prints what would be sent instead of sending it, which is the only
way to exercise this outside a real release.
"""

import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path

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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--branch", required=True, help="Branch to commit onto.")
    parser.add_argument(
        "--expected-head",
        required=True,
        help="SHA the branch must currently point at.",
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
        "--dry-run",
        action="store_true",
        help="Print what would be sent instead of sending it.",
    )
    args = parser.parse_args(argv)

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
        expected_head=args.expected_head,
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
