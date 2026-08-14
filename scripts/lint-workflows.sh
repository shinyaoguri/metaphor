#!/bin/bash
# GitHub Actions ワークフローを actionlint で検証する。
#
# `.github/workflows/*.yml` は per-PR の CI では一切検証されず、構文エラーや
# 式の書き間違い（`steps.x.outputs.y` の typo、shell の quoting など）は
# 「そのワークフローが次に走ったとき」まで見つからなかった（Issue #460）。
# release.yml / release-train.yml / release-on-merge.yml は PR では走らない
# （dispatch / schedule / pull_request:closed）ため、壊れていても気付くのは
# 「リリースが出ない」「トレインが発車しない」という形になる。
#
# CI からもローカルからも同じバージョン・同じ設定で走らせるため、実体は
# このスクリプト 1 本にまとめてある（ci.yml と `make lint-workflows` の
# 両方がこれを呼ぶ）。
set -euo pipefail

cd "$(dirname "$0")/.."

# 更新は dependabot ではなく手動。lint の指摘が増減してある日突然 CI が赤く
# なるのを避ける（check-jsonschema のピン留めと同じ方針）。
# 上げるときは checksums.txt から SHA256 も一緒に差し替えること:
#   curl -fsSL https://github.com/rhysd/actionlint/releases/download/v<ver>/actionlint_<ver>_checksums.txt
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_SHA256_DARWIN_ARM64="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"

TOOLS_DIR=".build/tools"
PINNED_BIN="${TOOLS_DIR}/actionlint-${ACTIONLINT_VERSION}"

# actionlint は shellcheck が PATH にあれば `run:` の中身も検証する（実際に
# この仕組みを入れたとき release.yml の SC2086 を捕まえた）。有無で結果が
# 変わるので、CI では REQUIRE_SHELLCHECK=1 を渡して「必ず shellcheck 込み」に
# 固定する。手元では敷居を上げず、警告だけ出して続行する。
if command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck: $(shellcheck --version | awk '/^version:/ {print $2}') (run: の中身も検証されます)"
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
    echo "::error::shellcheck not found. actionlint の shellcheck 連携が無効になり、run: の中身が検証されません。"
    exit 1
else
    echo "warning: shellcheck が見つかりません。run: の中身は検証されません（CI では検証されます）。" >&2
fi

resolve_actionlint() {
    # 結果は標準出力ではなくグローバル変数 ACTIONLINT に入れる。
    # `ACTIONLINT="$(resolve_actionlint)"` と書くと関数がコマンド置換の
    # **サブシェル**で走り、中の `exit` はそのサブシェルを終えるだけで
    # 呼び出し元は止まらない。実際それでチェックサム不一致を検知しても
    # actionlint が実行されてしまっていた（この形に直して検証済み）。

    # 手元に入っている actionlint がピンと同じバージョンならそれを使う
    # （brew install actionlint を無駄にしない）。
    if command -v actionlint >/dev/null 2>&1; then
        local installed
        installed="$(actionlint -version | head -1)"
        if [ "$installed" = "$ACTIONLINT_VERSION" ]; then
            ACTIONLINT="$(command -v actionlint)"
            return
        fi
        echo "note: actionlint ${installed} が PATH にありますが、ピンは ${ACTIONLINT_VERSION} です。ピン版を使います。" >&2
    fi

    if [ -x "$PINNED_BIN" ]; then
        ACTIONLINT="$PINNED_BIN"
        return
    fi

    local arch
    arch="$(uname -m)"
    if [ "$(uname -s)" != "Darwin" ] || [ "$arch" != "arm64" ]; then
        echo "::error::このスクリプトは macOS / Apple Silicon 専用です（uname: $(uname -s) ${arch}）。" >&2
        echo "他の環境では actionlint ${ACTIONLINT_VERSION} を手で入れて PATH に通してください。" >&2
        exit 1
    fi

    local tarball url
    mkdir -p "$TOOLS_DIR"
    tarball="${TOOLS_DIR}/actionlint-${ACTIONLINT_VERSION}.tar.gz"
    url="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"
    echo "Downloading actionlint ${ACTIONLINT_VERSION}..."
    curl -fsSL -o "$tarball" "$url"
    # 配布物の改竄・取り違えをここで止める（落として即実行するため）。
    # `set -e` に頼らず明示的に分岐して、壊れた tarball を残さない。
    if ! echo "${ACTIONLINT_SHA256_DARWIN_ARM64}  ${tarball}" | shasum -a 256 -c -; then
        echo "::error::actionlint ${ACTIONLINT_VERSION} のチェックサムが一致しません。配布物を破棄しました。" >&2
        rm -f "$tarball"
        exit 1
    fi
    tar -xzf "$tarball" -C "$TOOLS_DIR" actionlint
    mv "${TOOLS_DIR}/actionlint" "$PINNED_BIN"
    rm -f "$tarball"
    ACTIONLINT="$PINNED_BIN"
}

ACTIONLINT=""
resolve_actionlint
echo "actionlint: ${ACTIONLINT} ($("$ACTIONLINT" -version | head -1))"
echo

# 設定（false positive の抑制）は .github/actionlint.yaml。CI とローカルで
# 同じ結果になるよう、フラグではなく設定ファイル側に寄せてある。
exec "$ACTIONLINT" -oneline "$@"
