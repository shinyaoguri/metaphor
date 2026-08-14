#!/usr/bin/env bash
#
# 依存更新 PR（dependabot）を「最新 main にマージした状態」で手元検証する。
#
# PR 自身の CI は PR head だけを見る。ルールセットの
# strict_required_status_checks_policy は off（docs/releasing.md）なので、
# main が先に進んでいても BEHIND のまま merge できる — その代わり、個別に
# green な PR 同士の意味的な衝突（例: website 側の改修と astro の bump）は
# merge 後の push CI まで表に出ない。このスクリプトはその一手前に、
# 使い捨ての worktree で origin/main + PR head を合成し、PR が触った領域に
# 対応する検証だけを回す。
#
# 呼び出し元の作業ツリー・ローカルブランチ・HEAD には触れない（検証は
# $TMPDIR の worktree で完結し、終了時に必ず片付ける）。そのため手元の作業を
# 中断せずに実行でき、Claude の権限プロンプトもこの 1 コマンドで済む。
#
# Usage:
#   ./scripts/verify-dep-pr.sh <pr-number>                # 差分から領域を判定
#   ./scripts/verify-dep-pr.sh <pr-number> --only website # 領域を指定して強制
#   ./scripts/verify-dep-pr.sh --ref <git-ref> --only website
#
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
}

PR=""
REF=""
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) PR="$1"; shift ;;
  esac
done

if [ -z "$PR" ] && [ -z "$REF" ]; then
  usage >&2
  exit 2
fi

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaphor-dep-verify-XXXXXX")
WT="$TMPROOT/wt"
FETCHED_REF=""

cleanup() {
  git worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf "$TMPROOT"
  if [ -n "$FETCHED_REF" ]; then
    git update-ref -d "$FETCHED_REF" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> fetching origin/main"
git fetch -q origin main

if [ -n "$PR" ]; then
  FETCHED_REF="refs/dep-verify/pr-$PR"
  echo "==> fetching pull/$PR/head"
  git fetch -q --force origin "pull/$PR/head:$FETCHED_REF"
  TARGET="$FETCHED_REF"
else
  TARGET="$REF"
fi

git rev-parse --verify --quiet "$TARGET^{commit}" >/dev/null || {
  echo "no such ref: $TARGET" >&2
  exit 2
}

# 使い捨ての worktree に PR head を出し、そこへ origin/main を取り込む。
# detached HEAD なので、この merge commit はどのブランチにも残らない。
echo "==> merging origin/main into $TARGET (throwaway worktree)"
git worktree add -q --detach "$WT" "$TARGET"
if ! git -C "$WT" \
  -c user.name="dep-verify" -c user.email="dep-verify@localhost" \
  merge --no-edit -q origin/main; then
  echo "MERGE CONFLICT: $TARGET と origin/main は手で解決が要ります" >&2
  exit 1
fi

# PR が触った領域を、マージベースからの差分で決める。
if [ -z "$ONLY" ]; then
  base=$(git merge-base origin/main "$TARGET")
  changed=$(git diff --name-only "$base" "$TARGET")
  areas=""
  # website は本文のコピーを持たず、リポジトリルートの docs/tutorial/ を content
  # collection として直接読む（ADR-0010、Issue #554）。`website/` だけ見ていると
  # 本文側の変更でビルドが壊れる PR を取りこぼす。
  if grep -qE '^(website/|docs/tutorial/)' <<<"$changed"; then areas="$areas website"; fi
  if grep -q '^\.github/workflows/' <<<"$changed"; then areas="$areas workflows"; fi
  if grep -qE '^(Sources/|Package\.swift|Vendor/)' <<<"$changed"; then areas="$areas swift"; fi
else
  areas="$ONLY"
fi

if [ -z "${areas// /}" ]; then
  echo "==> 検証対象の領域なし（website / workflows / swift のいずれも触っていません）"
  exit 0
fi

echo "==> areas:$areas"
status=0

for area in $areas; do
  case "$area" in
    website)
      # CI の website-build ジョブと同じコマンド（.github/workflows/ci.yml）。
      echo "==> [website] npm ci && npm run build"
      if ( cd "$WT/website" && npm ci && npm run build ); then
        echo "==> [website] OK"
      else
        echo "==> [website] FAILED" >&2
        status=1
      fi
      ;;
    workflows)
      # ワークフローの妥当性は手元では確かめられない（actionlint も PyYAML も
      # 前提にしない）。runner だけは Node 版縛りのある actions/* bump で効くので
      # 出しておき、判断材料にする。あとは PR の checks が正。
      echo "==> [workflows] ローカル検証は無し（PR の checks が正）。runner 一覧:"
      grep -h "runs-on:" "$WT"/.github/workflows/*.yml | sed 's/^[[:space:]]*/    /' | sort -u
      ;;
    swift)
      # Syphon.xcframework が要るので worktree では回せない（make setup 相当が
      # 走ってしまう）。ライブラリ側は手元のセットアップ済みツリーで見る。
      echo "==> [swift] このスクリプトの対象外。手元で make ci-check を回してください"
      ;;
    *)
      echo "unknown area: $area" >&2
      status=2
      ;;
  esac
done

exit $status
