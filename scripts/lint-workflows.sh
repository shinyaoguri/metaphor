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
#
# actionlint は shellcheck があると `run:` の中身も検証する（この仕組みを
# 入れたとき release.yml の SC2086 を実際に捕まえた）。ところが GitHub の
# macOS ランナーには shellcheck が入っていないので、**両方**をピンして落とす。
# 「あれば使う」にすると CI とローカルで検証範囲が変わり、CI が黙って緩くなる。
#
# 上げるときは SHA256 も一緒に差し替えること:
#   curl -fsSL https://github.com/rhysd/actionlint/releases/download/v<ver>/actionlint_<ver>_checksums.txt
#   curl -fsSL <shellcheck tarball url> | shasum -a 256
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_SHA256="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"
SHELLCHECK_VERSION="0.11.0"
SHELLCHECK_SHA256="339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f"

TOOLS_DIR=".build/tools"

require_darwin_arm64() {
    if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
        echo "::error::このスクリプトは macOS / Apple Silicon 専用です（uname: $(uname -s) $(uname -m)）。" >&2
        echo "他の環境では actionlint ${ACTIONLINT_VERSION} と shellcheck ${SHELLCHECK_VERSION} を手で入れて PATH に通してください。" >&2
        exit 1
    fi
}

# fetch_tool <url> <expected sha256> <path inside the tarball> <strip> <destination>
#
# <strip> は tar --strip-components に渡す値（tarball が bin を直に持つなら 0、
# <name>/<bin> のように 1 段包んでいるなら 1）。
#
# NOTE: この関数も、これを呼ぶ resolve_* も、結果をグローバル変数へ書いて
# 返す。`X="$(resolve_x)"` と書くと関数がコマンド置換の**サブシェル**で走り、
# 中の `exit` はそのサブシェルを終えるだけで呼び出し元は止まらない。初版が
# その形で、チェックサム不一致を検知しても後続が実行されてしまっていた。
fetch_tool() {
    local url=$1 expected=$2 member=$3 strip=$4 dest=$5
    local tarball="${dest}.tar.gz"
    mkdir -p "$TOOLS_DIR"
    echo "Downloading $(basename "$dest")..."
    curl -fsSL -o "$tarball" "$url"
    # 落として即実行するので、配布物の改竄・取り違えをここで止める。
    # `set -e` に頼らず明示的に分岐して、壊れた tarball を残さない。
    if ! echo "${expected}  ${tarball}" | shasum -a 256 -c -; then
        echo "::error::$(basename "$dest") のチェックサムが一致しません。配布物を破棄しました。" >&2
        rm -f "$tarball"
        exit 1
    fi
    tar -xzf "$tarball" -C "$TOOLS_DIR" --strip-components="$strip" "$member"
    mv "${TOOLS_DIR}/$(basename "$member")" "$dest"
    rm -f "$tarball"
}

SHELLCHECK=""
resolve_shellcheck() {
    local pinned="${TOOLS_DIR}/shellcheck-${SHELLCHECK_VERSION}"
    if command -v shellcheck >/dev/null 2>&1 \
        && [ "$(shellcheck --version | awk '/^version:/ {print $2}')" = "$SHELLCHECK_VERSION" ]; then
        SHELLCHECK="$(command -v shellcheck)"
        return
    fi
    if [ ! -x "$pinned" ]; then
        require_darwin_arm64
        fetch_tool \
            "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.darwin.aarch64.tar.gz" \
            "$SHELLCHECK_SHA256" \
            "shellcheck-v${SHELLCHECK_VERSION}/shellcheck" 1 \
            "$pinned"
    fi
    SHELLCHECK="$pinned"
}

ACTIONLINT=""
resolve_actionlint() {
    local pinned="${TOOLS_DIR}/actionlint-${ACTIONLINT_VERSION}"
    # 手元に入っている actionlint がピンと同じバージョンならそれを使う
    # （brew install actionlint を無駄にしない）。
    if command -v actionlint >/dev/null 2>&1 \
        && [ "$(actionlint -version | head -1)" = "$ACTIONLINT_VERSION" ]; then
        ACTIONLINT="$(command -v actionlint)"
        return
    fi
    if [ ! -x "$pinned" ]; then
        require_darwin_arm64
        fetch_tool \
            "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz" \
            "$ACTIONLINT_SHA256" \
            "actionlint" 0 \
            "$pinned"
    fi
    ACTIONLINT="$pinned"
}

resolve_shellcheck
resolve_actionlint
echo "shellcheck: ${SHELLCHECK} ($("$SHELLCHECK" --version | awk '/^version:/ {print $2}'))"
echo "actionlint: ${ACTIONLINT} ($("$ACTIONLINT" -version | head -1))"
echo

# 設定（false positive の抑制）は .github/actionlint.yaml。CI とローカルで
# 同じ結果になるよう、フラグではなく設定ファイル側に寄せてある。
exec "$ACTIONLINT" -oneline -shellcheck "$SHELLCHECK" "$@"
