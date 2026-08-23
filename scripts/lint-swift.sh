#!/bin/bash
# Swift のソースが .swift-format どおりに整形されているか検証する（--fix で整形する）。
#
# 32k LOC の Core を人間 + AI エージェントで保守する前提なのに、スタイル一貫性の
# 自動保証が無かった（Issue #333 / v1-release-plan.md の W2-8）。レビューで
# 「インデントが違う」を人が指摘するのは、指摘そのものが本題を押しのけるうえ、
# 指摘されなかった分だけ静かに散らばる。決定論的に落とす。
#
# ツールは Xcode 同梱の swift-format（xcrun で解決）。外部依存を増やさない方針と
# 整合し、CI の macOS ランナーにも Xcode と一緒に載っている。ruff のように
# バージョンを pin して venv へ隔離する形は採れない（ツールチェーンに従属する）
# ので、代わりに版を表示して「手元と CI で違う版だった」を後から追えるようにする。
#
# ## なぜ `swift-format lint` ではなく整形差分の検査なのか
#
# `lint --strict` を CI ゲートにすると、整形とは無関係のルール指摘（forEach を
# for ループへ、など）まで必須になる。Issue #333 は「1 PR で format のみ、他の
# 変更を混ぜない」を求めているので、導入時にそれらを潰すと目的が濁る。ここでは
# 「整形が .swift-format と一致しているか」だけを見て、残るルール指摘は別 Issue
# に切り出した。将来 lint も足すなら、このスクリプトに第 2 のモードを生やす。
#
# ## 対象から外すもの
#
# - `Examples/`: `Examples/**/Package.swift` は 343 本あり、整形すると
#   shots_common.py の source_hash が変わって実行結果画像 103 件と tutorial
#   パッケージ 10/10 が一斉に stale 化する（= GPU 再撮影が要る）。整形の PR に
#   画像差し替えを混ぜないため、Examples への適用は別 Issue へ分けた。
# - `BuiltinShaders+Generated.swift`: 生成物。整形すると
#   generate-shader-sources.py --check が CI と pre-push の両方で落ちる。
#
# 除外に `.swift-format-ignore` は使えない（swift-format 6.3.0 で実測。対象
# ディレクトリ直下・親のいずれに置いても無視されない）。ファイル先頭へ
# `// swift-format-ignore-file` を書く手もあるが、生成物にそれを入れるには
# 生成器のテンプレートを触ることになるので、対象リスト側で外す形にした。
# pathspec の `:(exclude)` なら git が解釈するので、パスの綴りは 1 か所で済む。
set -euo pipefail

cd "$(dirname "$0")/.."

FIX=0
if [ "${1:-}" = "--fix" ]; then
    FIX=1
elif [ $# -gt 0 ]; then
    echo "usage: $0 [--fix]" >&2
    exit 2
fi

if ! xcrun --find swift-format > /dev/null 2>&1; then
    echo "❌ swift-format が見つかりません（Xcode 16 以降に同梱されています）。" >&2
    echo "   xcode-select -p の指す Xcode を確認してください。" >&2
    exit 1
fi

# 版を残す。整形結果は版によって変わるので、「手元は緑・CI は赤」が起きたときに
# 最初に見る情報がログに無いと切り分けから始めることになる。
echo "swift-format $(xcrun swift-format --version) ($(xcrun --find swift-format))"

targets() {
    git ls-files -z '*.swift' \
        ':(exclude)Examples/**' \
        ':(exclude)Sources/MetaphorCore/Shaders/BuiltinShaders+Generated.swift'
}

if [ "$FIX" -eq 1 ]; then
    targets | xargs -0 xcrun swift-format format --parallel --in-place
    echo "✅ 整形しました（git diff で確認してください）。"
    exit 0
fi

# 検査は 1 ファイルずつ整形して原本と比べる。複数ファイルを渡すと swift-format は
# 結果を連結して stdout に出すため、まとめて比較する形にはできない。
unformatted=()
while IFS= read -r -d '' file; do
    if ! xcrun swift-format format "$file" | diff -q - "$file" > /dev/null 2>&1; then
        unformatted+=("$file")
    fi
done < <(targets)

if [ ${#unformatted[@]} -gt 0 ]; then
    echo "" >&2
    echo "❌ .swift-format どおりに整形されていないファイルが ${#unformatted[@]} 件あります:" >&2
    printf '    %s\n' "${unformatted[@]}" >&2
    echo "" >&2
    echo "次のコマンドで整形してコミットしてください:" >&2
    echo "" >&2
    echo "    make format" >&2
    echo "" >&2
    exit 1
fi

echo "✅ すべて .swift-format どおりに整形されています。"
