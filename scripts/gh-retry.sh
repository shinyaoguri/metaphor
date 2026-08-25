#!/usr/bin/env bash
#
# gh-retry.sh — `gh` の呼び出しを、一過性の失敗のときだけリトライして包む。
#
# Usage: scripts/gh-retry.sh <gh の引数...>
#   例: TITLE=$(scripts/gh-retry.sh pr view "$PR_NUMBER" --json title --jq '.title')
#       PR_JSON=$(scripts/gh-retry.sh pr view "$PR_NUMBER" --json title,labels)
#
# Env: GH_RETRY_ATTEMPTS — リトライ回数 (既定 3)。下の「リトライ回数と
#      バックオフ」の項を参照。
#
# 背景 (Issue #949 / #947 / #960): ci.yml の PR メタデータゲート 3 本は、タイトル・
# ラベル・本文を**イベントペイロードではなく実行時に API から引く**。これは意図的な
# 設計で、タイトルを直す / ラベルを貼る / 画像を足すだけで `gh run rerun --failed`
# が通る (再実行はペイロードを古いまま再生するので、payload 参照だと直したはずの
# 内容で落ち続ける)。捨てたくないのはこの性質の方で、足りないのは呼び出しの
# リトライだけだった。
#
# 2026-08-17 の GitHub 障害では、この 3 本が GraphQL の HTTP 503 を踏んで PR を
# 3 回連続で赤くした。中身は 1 バイトも悪くないのに `ci-gate` が failure になり、
# auto-merge が止まり、人手の `gh run rerun --failed` が要る。しかも rerun の API
# まで同じ障害で 503 を返すので「赤い → 再実行もできない」状態になった。
#
# 方針は 3 つ:
#
#   1. **一過性だけをリトライする**。HTTP ステータスが 4xx なら権限不足 (403)・
#      不在 (404)・引数の誤りといった定義的な失敗なので、待っても直らない ——
#      即座に落として原因を早く見せる (ci.yml の `permissions:` を書き落とすと
#      403 になる、という実例がワークフロー側のコメントに残っている)。待てば
#      直りうる 408 / 429 だけは 4xx でも例外扱いする。
#   2. **判別できないものはリトライ側に倒す**。無駄にリトライした場合の損は
#      数秒だが、リトライし損ねた場合の損は「無関係な PR が赤くなり人手が要る」
#      —— この非対称のぶんだけ安全側に寄せる。GraphQL のエラー (HTTP 200 +
#      errors 配列。gh は `GraphQL: ...` と出す) を定義的失敗に含めていないのも
#      同じ理由で、GitHub は一過性の内部エラーもこの形で返してくる。
#   3. **使い切ったら普通に落とす**。恒久的な障害と瞬断は区別できないので、
#      赤くする判断自体は変えない (黙って通さない)。
#
# リトライ回数とバックオフは既存の同型リトライ (check-contract-identity.sh /
# check-release-assets.sh) に揃えて 3 回・1s → 2s。
#
# 回数だけは呼び出し側が `GH_RETRY_ATTEMPTS` で増やせる (Issue #1006)。budget を
# 決めるのは呼び出しの重さではなく**やり直しの費用**で、両者は桁で違う:
#
#   - ci.yml の PR ゲートは、落ちても `gh run rerun --failed` で戻せる。既定の
#     3 回で十分で、伸ばしても人がボタンを押す回数は変わらない。
#   - release.yml の `gh pr view` 2 本は、CI を一周終えた後に来る。前者
#     (headRefOid) の時点で release ブランチ push と PR 作成が済んでいるので
#     単純な再実行は `gh pr create` が二重になって通らず、後者 (mergeCommit) は
#     **squash merge の後**なので再実行そのものが効かない (人手で `git tag` を
#     打つしかない)。ここで数秒余分に粘る損は、10 分超の CI に対して誤差。
#
# 既定を動かさないのは意図的で、増やしたい経路だけが宣言する (呼び出し側の
# `env:` を読めば、そこが「やり直しの効かない場所」だと分かる)。
#
# stdout は**呼び出し側がデータとして捕まえるチャンネル**なので、
#
#   - 成否が決まるまでバッファへ溜め、成功した attempt の分だけを一度に流す
#     (失敗した attempt が途中まで吐いた出力が `$(...)` に混ざらないように)
#   - 進捗・エラーの通知は必ず stderr へ書く (`::warning::` を stdout に書くと
#     捕まえた JSON を壊す)
#
# 呼び出し側は `set -euo pipefail` の下で `$(...)` に入れるだけでよく、
# 失敗はそのまま非ゼロで伝わる。
#
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <gh args...>" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "::error::gh CLI not found — cannot run 'gh $*'." >&2
  exit 2
fi

# 未指定・空は既定の 3 回。空を突っぱねないのは、`${{ }}` の展開が空になった
# だけでリリースを落とすより、既定へ戻して走り切る方が損が小さいため (budget は
# あくまで上乗せで、3 回でも動作としては正しい)。
#
# 一方 `=three` や `=0` は弾く。素通しすると `[ "$attempt" -lt "$ATTEMPTS" ]` が
# 算術エラーで転び、「gh が落ちた」のか「budget の指定を間違えた」のかが
# ログから読めなくなる。
ATTEMPTS="${GH_RETRY_ATTEMPTS:-3}"
case "$ATTEMPTS" in
  *[!0-9]* | 0)
    echo "::error::GH_RETRY_ATTEMPTS must be a positive integer (got '${GH_RETRY_ATTEMPTS-}')." >&2
    exit 2
    ;;
esac
readonly ATTEMPTS

out="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$out" "$err"' EXIT

status=0
attempt=0
code=""

while [ "$attempt" -lt "$ATTEMPTS" ]; do
  attempt=$((attempt + 1))

  status=0
  gh "$@" >"$out" 2>"$err" || status=$?

  if [ "$status" -eq 0 ]; then
    # gh 自身の警告 (deprecation 等) は握り潰さない。
    cat "$err" >&2
    cat "$out"
    exit 0
  fi

  # 失敗の理由は毎回そのまま見せる。ログを開かずに「外部障害か、こちらの
  # 間違いか」が読めることが、このゲートの運用コストを下げる要点。
  cat "$err" >&2

  # gh は HTTP ステータスを `HTTP 503: ...` とも `(HTTP 404)` とも出すので、
  # 区切りに依存せず 3 桁を拾う。最初の 1 件だけを見るのに `| head -1` を使わない
  # のは、pipefail 下で head が sed を SIGPIPE で落とし (exit 141)、`set -e` が
  # スクリプトごと止めてしまうため (check-release-assets.sh と同じ回避形)。
  codes="$(sed -n 's/.*HTTP \([0-9][0-9][0-9]\).*/\1/p' "$err")"
  code="${codes%%$'\n'*}"

  case "$code" in
    408 | 429 | "")
      # 待てば直る 4xx / ステータスの読めない失敗 (ネットワーク断・DNS・
      # GraphQL レベルのエラー) はリトライする。
      ;;
    4??)
      echo "::error::gh ${1:-} failed with HTTP ${code} — not a transient failure, not retrying." >&2
      exit "$status"
      ;;
  esac

  if [ "$attempt" -lt "$ATTEMPTS" ]; then
    echo "::warning::gh ${1:-} failed (attempt ${attempt}/${ATTEMPTS}${code:+, HTTP ${code}}); retrying in ${attempt}s." >&2
    sleep "$attempt"
  fi
done

echo "::error::gh ${1:-} failed after ${ATTEMPTS} attempts${code:+ (last: HTTP ${code})} — giving up." >&2
exit "$status"
