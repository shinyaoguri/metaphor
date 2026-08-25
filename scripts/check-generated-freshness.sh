#!/bin/sh
#
# check-generated-freshness.sh — 生成物が入力に追随しているかを検査する「実体」。
#
# Usage:
#   scripts/check-generated-freshness.sh [--label LABEL] --all
#   scripts/check-generated-freshness.sh [--label LABEL] CHECK...
#
#   CHECK: llms | index | shaders | tutorial | reference | status | format
#
# 呼び出し側は 3 つ:
#
#   - scripts/hooks/pre-push      push する range を見て「どれを鳴らすか」を選び、
#                                 選んだ検査名だけを渡す（毎回全部走らせると
#                                 `make llms-txt` のビルドが毎 push に乗るため）
#   - scripts/signed-commit.py    pre-push を通らない経路。`--all` で全部走らせる
#   - make freshness-check        手元で 1 コマンド。`make ci-check` からも呼ばれる
#
# **トリガー判定はここに持たない**（Issue #978）。持たせようとすると呼び出し側の
# 事情が食い違うため:
#
#   * pre-push が見るのは push する **range**（`base..local_sha`）。マージで陳腐化
#     した生成物もここに乗る。実例として #786 のレーンは `git merge origin/main` で
#     llms.txt が古くなり、pre-push が正しく止めた（#972）
#   * signed-commit.py が見られるのは **作業ツリー**だけ。上のマージ由来の陳腐化は
#     `git status --porcelain` に出ないので、同じトリガーを共有すると肝心のケースを
#     取りこぼす
#   * リリース経路の変更セット（release.yml の BUMP_PATHS）には
#     `Sources/MetaphorCore/Core/MetaphorVersion.swift` が入る。これは llms.txt の
#     入力（`Sources/**/*.swift`）そのものなので、変更パスから起動する作りにすると
#     runner で `make llms-txt` = `swift build` が丸ごと走る
#
# なので共有するのは**検査の本体だけ**で、「どれを鳴らすか」は呼び出し側が決める。
# llms.txt の入力リストが scripts/changed-llms-inputs.sh の一箇所に居る（#995）
# という取り決めも、そのまま pre-push 側に残る。
#
# 検査の中身と復旧手順のメッセージはここが正本。CI（.github/workflows/ci.yml）は
# 同じ検査をサーバー側で独立に走らせる — こちらは失敗を手元へ早めるためのもので、
# 新しい規則は導入していない。

set -eu

cd "$(dirname "$0")/.."

ALL_CHECKS='llms index shaders tutorial reference status format'

# **Examples の実行結果画像（`generate-example-shots.py --check`）はここに無い。**
# 埋め忘れではなく、`.github/workflows/asset-health.yml` の週次ジョブが持っている
# （Issue #1161）。
#
# 費用が理由ではない — 検査は 0.08 秒・GPU 不要で、reference / tutorial より軽い。
# 分けているのは**落ちたときに人が取れる行動**が違うため:
#
#   * ここに並ぶ 7 本は、落ちても再生成コマンド 1 本で直る（機械が決めた 1 つの正解が
#     あり、差分をそのままコミットすればよい）
#   * example の画像は `make example-shots ARGS="--only <パス> --force"` = GPU での
#     撮り直しになる。対象はどれも動くスケッチなので撮るたびに別の絵になり、退行か
#     意図した変更かは機械では判別できない（#586）。**人の目視レビューが要る**
#
# per-PR の必須ゲートに載せると、`Examples/` に触れただけの PR が「自分が入れていない
# 指摘」で止まる（pre-push の冒頭が名指ししている失敗モード）。週次なら溜まりっぱなしは
# 防げて、無関係なレーンは止めない。
#
# なお `origin: processing`（原典由来）の 156 件は指紋を持たないので、検査する側の
# `stale_entries()` が既に対象外にしている（`test_a_processing_image_never_goes_stale`）。

usage() {
    cat <<'USAGE'
usage: scripts/check-generated-freshness.sh [--label LABEL] (--all | CHECK...)

  CHECK   llms | index | shaders | tutorial | reference | status | format
  --all   上の全部を（この順で）走らせる
  --label 出力の接頭辞（既定: [freshness]）
USAGE
}

label='[freshness]'
checks=''

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all)
            checks="$checks $ALL_CHECKS"
            ;;
        --label)
            shift
            if [ "$#" -eq 0 ]; then
                echo "--label needs a value" >&2
                usage >&2
                exit 2
            fi
            label="$1"
            ;;
        --label=*)
            label="${1#--label=}"
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            checks="$checks $1"
            ;;
    esac
    shift
done

if [ -z "$(printf '%s' "$checks" | tr -d ' ')" ]; then
    echo "no checks requested" >&2
    usage >&2
    exit 2
fi

for name in $checks; do
    case " $ALL_CHECKS " in
        *" $name "*) ;;
        *)
            echo "unknown check: $name" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# 要求されたか（順序は ALL_CHECKS 側が決める。呼び出し側の並びや重複には依存しない）
wants() {
    case " $checks " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- llms.txt staleness check -------------------------------------------------
if wants llms; then
    echo "$label llms.txt inputs changed — verifying it is up to date..."
    llms_log="$(mktemp)"
    if ! make llms-txt >"$llms_log" 2>&1; then
        echo "$label ❌ make llms-txt failed. Fix the build and re-push." >&2
        echo "$label --- make llms-txt output (tail) ---" >&2
        tail -40 "$llms_log" >&2
        rm -f "$llms_log"
        exit 1
    fi
    rm -f "$llms_log"
    if ! git diff --quiet llms.txt 2>/dev/null; then
        echo "$label ❌ llms.txt is stale. Regenerated for you — review and commit:" >&2
        echo "" >&2
        echo "    git add llms.txt && git commit --amend --no-edit  # or a new commit" >&2
        echo "    git push" >&2
        echo "" >&2
        exit 1
    fi
    echo "$label ✅ llms.txt is up to date."
fi

# --- examples index staleness check ------------------------------------------
if wants index; then
    echo "$label Examples/ or generator changed — verifying examples index is up to date..."
    if ! python3 scripts/generate-examples-index.py >/dev/null 2>&1; then
        echo "$label ❌ generate-examples-index.py failed." >&2
        exit 1
    fi
    if ! git diff --quiet docs/ai/examples-index.md docs/ai/examples-index.json 2>/dev/null; then
        echo "$label ❌ examples index is stale. Regenerated for you — review and commit:" >&2
        echo "" >&2
        echo "    git add docs/ai/examples-index.md docs/ai/examples-index.json" >&2
        echo "    git commit --amend --no-edit  # or a new commit" >&2
        echo "    git push" >&2
        echo "" >&2
        exit 1
    fi
    echo "$label ✅ examples index is up to date."
fi

# --- shader sources staleness check -------------------------------------------
if wants shaders; then
    echo "$label Shaders changed — verifying generated shader sources are up to date..."
    if ! python3 scripts/generate-shader-sources.py --check; then
        echo "$label ❌ Generated shader sources are stale (canonical is Metal/*.metal and Metal/*.h)." >&2
        echo "$label Regenerate and commit:" >&2
        echo "" >&2
        echo "    python3 scripts/generate-shader-sources.py" >&2
        echo "    git add Sources/MetaphorCore/Shaders/ShaderSources Sources/MetaphorCore/Shaders/BuiltinShaders+Generated.swift" >&2
        echo "    git commit --amend --no-edit  # or a new commit" >&2
        echo "" >&2
        exit 1
    fi
    echo "$label ✅ shader sources are up to date."
fi

# --- tutorial snippets staleness check ----------------------------------------
if wants tutorial; then
    echo "$label Tutorial code or prose changed — verifying embedded snippets..."
    if ! python3 scripts/generate-tutorial-snippets.py --check; then
        echo "$label ❌ docs/tutorial の埋め込みが古い（正典は Examples/Tutorial/**）。" >&2
        echo "$label 再生成してコミットしてください:" >&2
        echo "" >&2
        echo "    python3 scripts/generate-tutorial-snippets.py" >&2
        echo "    git add docs/tutorial" >&2
        echo "    git commit --amend --no-edit  # or a new commit" >&2
        echo "" >&2
        exit 1
    fi
    echo "$label ✅ tutorial snippets are up to date."

    echo "$label Verifying tutorial result images are up to date..."
    if ! python3 scripts/generate-tutorial-shots.py --check; then
        echo "$label ❌ docs/tutorial/images が古い。撮り直してコミットしてください:" >&2
        echo "" >&2
        echo "    make tutorial-shots" >&2
        echo "    git add docs/tutorial/images" >&2
        echo "" >&2
        exit 1
    fi
fi

# --- reference result images staleness check ----------------------------------
if wants reference; then
    echo "$label Sources or reference config changed — verifying reference result images..."
    if ! python3 scripts/generate-reference-shots.py --check; then
        echo "$label ❌ doc コメントの実行結果画像が古い（正典はスニペット）。" >&2
        echo "$label 撮り直してコミットしてください（GPU と Gyazo トークンが要ります）:" >&2
        echo "" >&2
        echo "    make reference-shots" >&2
        echo "    git add Sources docs/reference/images/manifest.json" >&2
        echo "" >&2
        echo "$label （CI の必須ゲートと同じ検査です。ここで止めるのは早く気付くため）" >&2
        exit 1
    fi
    echo "$label ✅ reference result images are up to date."
fi

# --- tutorial publication status check ----------------------------------------
if wants status; then
    echo "$label Tutorial prose or an entry doc changed — verifying publication status..."
    if ! python3 scripts/generate-tutorial-status.py --check; then
        echo "$label ❌ 公開状況の案内が古い（正典は docs/tutorial/*.md の frontmatter）。" >&2
        echo "$label 再生成してコミットしてください:" >&2
        echo "" >&2
        echo "    python3 scripts/generate-tutorial-status.py" >&2
        echo "    git add README.md README.en.md docs/README.md docs/README.en.md Examples/README.md" >&2
        echo "    git commit --amend --no-edit  # or a new commit" >&2
        echo "" >&2
        exit 1
    fi
    echo "$label ✅ tutorial publication status is up to date."
fi

# --- swift-format check -------------------------------------------------------
if wants format; then
    echo "$label Swift sources or .swift-format changed — verifying formatting..."
    if ! ./scripts/lint-swift.sh >/dev/null; then
        echo "$label ❌ .swift-format どおりに整形されていないファイルがある。" >&2
        echo "$label 整形してコミットしてください:" >&2
        echo "" >&2
        echo "    make format" >&2
        echo "" >&2
        echo "$label 対象の一覧は make lint-swift で出ます。" >&2
        exit 1
    fi
    echo "$label ✅ Swift sources are formatted."
fi

exit 0
