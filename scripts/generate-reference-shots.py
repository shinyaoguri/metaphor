#!/usr/bin/env python3
"""API リファレンス（DocC）の doc コメントに書いたスニペットを走らせ、実行結果を撮る。

`Sources/**/*.swift` の doc コメントに `<!-- reference-shot -->` の印を付けて書いた
```swift フェンスを集め、1 本ずつヘッドレスで実行し、Probe が書く
`.metaphor/probe/current/frame.png` を Gyazo へ上げて、返ってきた URL を
`docs/reference/images/manifest.json`（台帳）と **doc コメントの画像行**へ書き戻す。

    make reference-shots                      # 画像がまだ無いスニペットを撮る
    make reference-shots ARGS="--only circle"
    make reference-shots ARGS="--force --only circle"      # 撮り直す
    python3 scripts/generate-reference-shots.py --check    # 鮮度だけ調べる
    python3 scripts/generate-reference-shots.py --compile-only  # ビルドだけ（GPU 不要）

## なぜスニペットが doc コメントの中にあるのか（#531）

目標は p5.js の reference — **個別のメソッドごとに、その関数だけの短いコードと実行結果
が並ぶ**状態。p5.js は `@example` ブロックをリファレンスのソースに持ち、それがサイト上で
実行される。metaphor は Swift なのでブラウザ実行はできないが、コードがシンボルの説明の
一部として存在する点は同じにできる。`Examples/` に別置きすると、読者が見るページと素材が
離れ、どちらが正典か分からなくなる。

    /// 円を描画します。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// @Row {
    ///    @Column(size: 2) {
    ///       ![circle() の実行結果](https://i.gyazo.com/<hash>.png)
    ///    }
    ///    @Column(size: 3) {
    ///       ```swift
    ///       background(240)
    ///       circle(width / 2, height / 2, 200)
    ///       ```
    ///    }
    /// }

**印から下は生成物領域**で、`@Row` の骨組みも画像行もこのスクリプトが書く。人が書くのは
コードだけ。並べ方は p5.js に合わせて「絵が左・コードが右」を既定にし（狭い画面では DocC が
縦に折る）、横長の絵や行の長いコードは `shots.config.json` の `"layout": "stack"` で縦積みへ
逃がせる。

- **コードは人が書く（正典）／それ以外は生成物**（このスクリプトが書き戻す・手で書かない）
- スニペットは `draw()` の本体そのもの。背景も自分で塗る（自己完結。外部 URL では
  ダーク/Retina の出し分けが効かないため、配色をスケッチ側で固定する — ADR-0008）
- 印が HTML コメントなのは、**DocC が警告なく落とす**ことを実測で確かめたから。読者には
  見えず、機械には引っかかり、見出しの文言（英語化・#334）にも依存しない
- 説明用の無印 ```swift フェンスが `Sources/` には既に 30 箇所ほどある。印の有無で
  「撮る例」と「読ませるだけの例」を区別する

## 画像をリポジトリに置かない（ADR-0008）

画像の実体は Gyazo（`https://i.gyazo.com/<hash>.<ext>`）。DocC は WebP を**警告すら出さず
に落とす**ため、チュートリアル（ADR-0010）が容量問題を解いた手（アニメーション WebP）が
使えず、動きを見せる手段が実質 GIF しかない。GIF をリポジトリに積むと 253 本規模では
成立しないので、外部 URL を参照する。

アセットは不変・追記型。撮り直しは既存 URL の差し替えではなく新規アップロードで、本文と
台帳の URL を更新する（古い URL は消さない ＝ 過去のリビジョンを開けば当時の絵が出る）。

## ビルドは 1 パッケージ・1 スニペット 1 ターゲット

`.build/reference-shots/` に SwiftPM パッケージを 1 個生成し、スニペットごとに実行
ターゲットを並べる。`swift build` 1 回で全スニペットがコンパイルされ、依存解決も
metaphor 本体のビルドも 1 回で済む（スニペットごとにパッケージを作ると、その回数だけ
繰り返すことになる）。

副産物として **「リファレンスの例は必ずコンパイルできる」保証**が手に入る。`--compile-only`
は GPU もトークンも要らないので、per-PR の CI で走らせられる（p5.js の「例は実際に動く」に
相当するものを、Swift で用意できる唯一の形）。

## なぜ画像のバイト比較で鮮度を見ないか

GPU レンダリングの出力は環境（GPU・ドライバ・OS）でビット単位には一致しない。`--check` は
画像ではなく**スニペットと撮影設定の指紋**（`snippetHash`）を台帳と突き合わせる。これで
「コードを変えたのに画像を撮り直していない」だけを、GPU の無い CI ランナーでも検出できる。

台帳の `sha256` は鮮度判定には使わない。こちらは上げたバイト列そのものの指紋で、URL が
指す中身が入れ替わっていないことを後から確かめるためのもの。URL の生死は週次のワーク
フローが見る（scripts/check-image-urls.py）。

撮影とアップロードはローカルで行い、doc コメントと台帳をコミットする（CI では走らせない）。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shots_common import (  # noqa: E402
    ShotError,
    capture_provenance,
    drift_summary,
    file_sha256,
    image_size,
    upload_to_gyazo,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCES_DIR = REPO_ROOT / "Sources"
REFERENCE_DIR = REPO_ROOT / "docs/reference"
MANIFEST = REFERENCE_DIR / "images/manifest.json"
CONFIG = REFERENCE_DIR / "shots.config.json"

# 生成物の置き場。`.build/` はすでに gitignore 済みで、`make clean` で消えてよい
# （スニペットは doc コメントが正典なので、いつでも作り直せる）。
WORK_DIR = REPO_ROOT / ".build/reference-shots"
STAGING_DIR = WORK_DIR / "staging"

# 撮影対象であることの印。DocC は HTML コメントを警告なく落とすので読者には見えない。
MARKER = "<!-- reference-shot -->"

# doc コメントの中の画像行。alt を保ったまま URL だけ差し替えられるように分けて捕まえる。
IMAGE_LINE_RE = re.compile(
    r"^(?P<head>!\[(?P<alt>[^\]]*)\]\()(?P<target>[^)\s]+)(?P<tail>\))\s*$"
)

FENCE_OPEN = "```swift"
FENCE_CLOSE = "```"

# 本文での並べ方。既定は p5.js の reference と同じ「絵が左・コードが右」の横並び
# （`@Row` / `@Column` は symbol の doc コメントでも通ることを実測済み）。横長の絵や
# 行の長いコードは列に収まらないので、シンボル単位で `stack`（縦積み）へ逃がせる。
LAYOUTS = ("row", "stack")
DEFAULT_LAYOUT = "row"
# 列の幅の比。コード側を広く取る（絵は縮んでも読めるが、コードは折り返せない）。
ROW_IMAGE_SIZE = 1
ROW_CODE_SIZE = 2

# 横並びのときのコード 1 行の上限（文字数）。
#
# Swift-DocC-Render のコードブロックは**折り返しも内部スクロールもせず、行の長さぶんに
# 広がって列からはみ出す**（@Row の外でも同じなので DocC 側の性質）。はみ出したぶんは
# ページ側でも切り落とされ、読めなくなる。
#
# 一番狭くなるのは、DocC がまだ列を縦に折らないギリギリの幅。実測でこう決めた:
#
#   - 列が縦に折れるのは 735px 以下（`.row.with-columns` のメディアクエリ）
#   - 736px のとき本文は 576px、コード列はその 2/3 で約 371px
#   - 等幅フォントは 1 文字 9.03px、コードブロックの padding は左右 14px ずつ
#   - (371 - 28) / 9.03 ≒ 38 文字
#
# これを超えるものは、短く書き直すか `layout: "stack"` で縦積みへ逃がす。
MAX_ROW_LINE = 38

# 生成物領域に置いてよい骨組み。ここに無い行が紛れていたら、人が書いた文章を
# 消してしまう可能性があるので止める（印から下はスクリプトが所有する規約）。
SCAFFOLD_RE = re.compile(r"^(@Row\s*\{|@Column(\(size:\s*\d+\))?\s*\{|\}|)$")

# Gyazo の定数と上げ口は shots_common にある。

# 起動から frame.png が書かれるまでの待ち時間。初回はシェーダーのコンパイルが入る。
CAPTURE_TIMEOUT_SEC = 120.0
POLL_INTERVAL_SEC = 0.2

# 絵の既定サイズ。リファレンスは 1 シンボル 1 枚が縦に並ぶので、チュートリアル
# （640x360）より小さく取る。
DEFAULT_WIDTH = 480
DEFAULT_HEIGHT = 360

# 反転一致の警告（#985）。撮った絵を上下・左右に反転して PSNR を測り、これを超える
# ものを「反転しても実質同じ絵」＝**引数を間違えても同じ絵になる**とみなして警告する。
#
# しきい値は台帳の 58 点を実測して決めた（Gyazo の URL から落として sha256 照合。撮影は
# 決定的なので本番と同じ値になる — #586）。40 dB の上と下には実測の空白帯があり、
# 40 dB は 37.0 dB と 43.5 dB のあいだに落ちる:
#
#   - 40 dB 超は 6 点だけ。spotLight 98.8/94.0・pointLight 65.6/65.6・plane -/66.3・
#     cone -/49.4・directionalLight -/45.2・radialGradient 43.5/43.5（vflip/hflip）
#   - 次に高いのは strokeWeight の 37.0 dB で、そこから下は連続して散る
#   - #923 で直した ortho / perspective は、**直す前**が inf と 58.7 dB、**直した後**が
#     16.7 と 20.5 dB。40 dB は両者をきれいに分ける
#
# 真円や正方形を中央に描いた絵でも 33〜35 dB にしかならない（ラスタライズの半画素ずれ）。
# つまり 40 dB は「幾何的に対称」ではなく「画素の水準で反転と見分けが付かない」を拾う。
FLIP_PSNR_WARN_DB = 40.0

# 「反転しても同じ絵でよい」の申告。`vertical` は上下反転（vflip）、`horizontal` は
# 左右反転（hflip）に対して対称でよい、の意。
FLIPS = {"vertical": ("vflip", "上下"), "horizontal": ("hflip", "左右")}
SYMMETRIES = (*FLIPS, "both")

# 動きの既定値。GIF は WebP の 1 桁上のサイズになるので、フレーム数は控えめに。
MOTION_MAX_FRAMES = 64  # Probe 側のクランプ上限（CONTRACT.md 契約点 4）
MOTION_DEFAULTS = {"frames": 36, "every": 2, "fps": 15, "width": DEFAULT_WIDTH}
# 1 ファイルの上限。超えたら幅かフレーム数を落とす（ページを重くしない）。
MOTION_MAX_BYTES = 1500 * 1024


class Snippet:
    """doc コメントから拾った撮影対象 1 本。"""

    def __init__(
        self,
        path: Path,
        symbol: str,
        code: list[str],
        marker: int,
        block_end: int,
        indent: str,
    ) -> None:
        self.path = path
        self.rel = path.relative_to(REPO_ROOT).as_posix()
        self.symbol = symbol
        self.code = code
        # 印の行から doc コメントの終わりまでが生成物領域（0 起点・block_end は排他）。
        self.marker = marker
        self.block_end = block_end
        self.indent = indent

    @property
    def key(self) -> str:
        """台帳と設定のキー。ファイルまで含めてオーバーロード以外の衝突を防ぐ。"""
        return f"{self.rel}::{self.symbol}"

    @property
    def target(self) -> str:
        """生成パッケージでの実行ターゲット名（Swift の識別子として使える形）。

        オーバーロード（`rect(_:_:_:_:)` と `rect(_:_:_:_:_:)`）は別ターゲットになる必要が
        あるので、関数名だけでなく**引数の数と外部ラベル**まで名前に入れる。ここを関数名
        だけにすると `duplicate target named ...` で生成パッケージのビルドが落ちる。
        """
        stem = re.sub(r"[^0-9A-Za-z]+", "_", Path(self.rel).stem)
        base, _, params = self.symbol.partition("(")
        base = re.sub(r"[^0-9A-Za-z]+", "_", base).strip("_")
        args = [a for a in params.rstrip(")").split(":") if a]
        labels = [re.sub(r"[^0-9A-Za-z]+", "_", a).strip("_") for a in args if a != "_"]
        return "_".join(["Shot", stem, base, str(len(args)), *labels])

    def layout(self, config: dict) -> str:
        """本文での並べ方（`row` = 絵とコードを横並び / `stack` = 縦積み）。

        **撮影設定とは別に持つ**。レイアウトは絵に影響しないので `fingerprint()` には
        入れない（入れると、並べ方を変えただけで全点が stale になり、意味のない
        再撮影と再アップロードが走る）。
        """
        entry = config.get(self.key) or config.get(self.symbol) or {}
        layout = entry.get("layout", DEFAULT_LAYOUT)
        if layout not in LAYOUTS:
            raise ShotError(
                f"{self.key}: layout は {' / '.join(LAYOUTS)} のいずれか（{layout!r} が指定された）"
            )
        if layout == "row":
            too_long = [line for line in self.code if len(line) > MAX_ROW_LINE]
            if too_long:
                raise ShotError(
                    f"{self.key}: 横並びのコードは 1 行 {MAX_ROW_LINE} 文字までです"
                    f"（{len(too_long[0])} 文字の行があります）。短く書き直すか、"
                    f'shots.config.json に "layout": "stack" を指定してください:\n'
                    f"    {too_long[0]}"
                )
        return layout

    def symmetric(self, config: dict) -> str | None:
        """「反転しても同じ絵でよい」という申告（無ければ None）。

        **`layout` と同じく `settings()` の外で読みます**。`fingerprint()` の材料に
        入れてよいのは絵に影響する設定だけで、撮影の段取りだけを変える knob を混ぜると、
        その knob を足した日にも外した日にも全点の指紋が動きます（絵は 1 枚も変わって
        いないのに、台帳の移行か全点の撮り直しが要る。`settle` で実際に踏んだ — #784）。
        """
        entry = config.get(self.key) or config.get(self.symbol) or {}
        symmetric = entry.get("symmetric")
        if symmetric is None:
            return None
        if symmetric not in SYMMETRIES:
            raise ShotError(
                f"{self.key}: symmetric は {' / '.join(SYMMETRIES)} のいずれか"
                f"（{symmetric!r} が指定された）"
            )
        return symmetric

    def settings(self, config: dict) -> dict:
        """撮影設定（既定 + `shots.config.json` の上書き）を返す。

        **実時間の待ちは持ちません**（#784）。「絵が出来上がるのを待つ」つもりの
        `settle` 秒があった頃は、待っているあいだに進んだフレーム数が実行ごとに
        違い、`frameCount` で駆動する動きのスニペットが毎回別の絵になっていました。
        撮り始めを揃える方法は「起動前にリクエストを置いて frame 1 から撮る」しか
        なく（`capture()` 参照）、開始を遅らせる knob は非決定を持ち込むだけです。
        """
        entry = config.get(self.key) or config.get(self.symbol) or {}
        settings = {
            "width": entry.get("width", DEFAULT_WIDTH),
            "height": entry.get("height", DEFAULT_HEIGHT),
        }
        motion = entry.get("motion")
        if motion:
            merged = {**MOTION_DEFAULTS, **(motion if isinstance(motion, dict) else {})}
            merged["frames"] = min(int(merged["frames"]), MOTION_MAX_FRAMES)
            settings["motion"] = merged
        return settings

    def fingerprint(self, config: dict) -> str:
        """スニペットと撮影設定の指紋。どちらが変わっても撮り直しが要る。

        材料に入れてよいのは**絵に影響する設定だけ**です。`layout` を外しているのと
        同じ理由で（並べ方を変えただけで全点が stale になる）、撮影の段取りだけを
        変える knob をここへ混ぜてはいけません。混ぜると、その knob を足した日にも
        外した日にも全点の指紋が動き、絵が 1 枚も変わっていないのに台帳の移行か
        全点の撮り直しが要ります（実際に `settle` で踏んだ — #784）。
        """
        material = json.dumps(
            {"code": self.code, "settings": self.settings(config)},
            ensure_ascii=False,
            sort_keys=True,
        )
        return hashlib.sha256(material.encode("utf-8")).hexdigest()


# --- doc コメントからの抽出 ---------------------------------------------------


def doc_content(line: str) -> str | None:
    """doc コメント行の中身を返す（doc コメントでなければ None）。"""
    stripped = line.lstrip()
    if not stripped.startswith("///"):
        return None
    return stripped[3:].removeprefix(" ")


def swift_sources() -> list[Path]:
    """走査するソース。DocC カタログ（.docc）配下は Swift ではないので入らない。"""
    return sorted(
        path
        for path in SOURCES_DIR.rglob("*.swift")
        if ".build" not in path.parts and ".docc" not in str(path)
    )


def split_top_level(text: str) -> list[str]:
    """`,` で区切る。ただし括弧・角括弧・山括弧・文字列の内側は無視する。"""
    parts: list[str] = []
    depth = 0
    in_string = False
    current = ""
    for char in text:
        if in_string:
            current += char
            if char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            current += char
            continue
        if char in "([<{":
            depth += 1
        elif char in ")]>}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current)
            current = ""
            continue
        current += char
    if current.strip():
        parts.append(current)
    return parts


def parameter_labels(params: str) -> list[str]:
    """パラメータ列から外部ラベルを取り出す（`_ x: Float` → `_`）。"""
    labels: list[str] = []
    for part in split_top_level(params):
        head = part.split(":", 1)[0]
        # 属性（@escaping 等）は名前の前に付かないが、念のため落としておく
        tokens = [token for token in head.replace("`", "").split() if not token.startswith("@")]
        if not tokens:
            continue
        labels.append(tokens[0])
    return labels


def declaration_symbol(lines: list[str], start: int) -> str | None:
    """doc コメントの直後にある宣言から、DocC のページ名と同じ表記を作る。

    `public func circle(_ x: Float, _ y: Float, _ diameter: Float)` → `circle(_:_:_:)`
    プロパティは名前そのもの。オーバーロードはラベルで区別できる。
    """
    index = start
    while index < len(lines):
        stripped = lines[index].strip()
        # 属性・アクセス修飾子だけの行、空行、`//` のコメントは宣言の手前に挟まる
        if not stripped or stripped.startswith("@") or stripped.startswith("//"):
            index += 1
            continue
        break
    else:
        return None

    matched = re.search(r"\b(func|var|let|init|subscript)\b\s*(`?[A-Za-z_][A-Za-z0-9_]*`?)?", lines[index])
    if not matched:
        return None
    kind, name = matched.group(1), (matched.group(2) or "").strip("`")
    if kind in ("var", "let"):
        return name or None
    if kind == "init":
        name = "init"
    if not name:
        return None

    # 宣言は複数行にまたがることがある。括弧が閉じるまで読む。
    text = lines[index][matched.end(2) if matched.group(2) else matched.end(1):]
    depth = text.count("(") - text.count(")")
    cursor = index
    while depth > 0 and cursor + 1 < len(lines):
        cursor += 1
        text += lines[cursor]
        depth = text.count("(") - text.count(")")
    inner = text[text.find("(") + 1: text.rfind(")")] if "(" in text else ""
    labels = parameter_labels(inner)
    return f"{name}({''.join(label + ':' for label in labels)})"


def extract(path: Path) -> list[Snippet]:
    """1 ファイルから撮影対象を集める。"""
    lines = path.read_text(encoding="utf-8").split("\n")
    snippets: list[Snippet] = []
    index = 0
    while index < len(lines):
        if doc_content(lines[index]) is None:
            index += 1
            continue

        block_start = index
        while index < len(lines) and doc_content(lines[index]) is not None:
            index += 1
        block_end = index  # doc コメントの次の行

        marker = next(
            (
                line
                for line in range(block_start, block_end)
                if (doc_content(lines[line]) or "").strip() == MARKER
            ),
            None,
        )
        if marker is None:
            continue

        fence_start = next(
            (
                line
                for line in range(marker + 1, block_end)
                if (doc_content(lines[line]) or "").strip() == FENCE_OPEN
            ),
            None,
        )
        if fence_start is None:
            raise ShotError(
                f"{path.relative_to(REPO_ROOT)}:{marker + 1} の {MARKER} の後に "
                f"{FENCE_OPEN} フェンスが無い"
            )
        fence_end = next(
            (
                line
                for line in range(fence_start + 1, block_end)
                if (doc_content(lines[line]) or "").strip() == FENCE_CLOSE
            ),
            None,
        )
        if fence_end is None:
            raise ShotError(
                f"{path.relative_to(REPO_ROOT)}:{fence_start + 1} のフェンスが閉じていない"
            )

        code = dedent(
            [doc_content(lines[line]) or "" for line in range(fence_start + 1, fence_end)]
        )
        if not any(line.strip() for line in code):
            raise ShotError(
                f"{path.relative_to(REPO_ROOT)}:{fence_start + 1} のスニペットが空"
            )

        # 印から下はスクリプトが所有する。人が書いた文章が紛れていたら、書き戻しで
        # 消してしまう前に止める（コードと骨組みと画像行だけが許される）。
        for line in list(range(marker + 1, fence_start)) + list(range(fence_end + 1, block_end)):
            content = (doc_content(lines[line]) or "").strip()
            if SCAFFOLD_RE.match(content) or IMAGE_LINE_RE.match(content):
                continue
            raise ShotError(
                f"{path.relative_to(REPO_ROOT)}:{line + 1} — {MARKER} から下は生成物領域です。"
                f"説明は印より前に書いてください（{content[:40]!r}）"
            )

        symbol = declaration_symbol(lines, block_end)
        if symbol is None:
            raise ShotError(
                f"{path.relative_to(REPO_ROOT)}:{block_end + 1} の doc コメントに"
                "対応する宣言を読み取れなかった"
            )
        marker_line = lines[marker]
        indent = marker_line[: len(marker_line) - len(marker_line.lstrip())]
        snippets.append(Snippet(path, symbol, code, marker, block_end, indent))
    return snippets


def dedent(code: list[str]) -> list[str]:
    """コード行の共通インデントを外す。

    `@Column` の中に入るとフェンスごと字下げされるので、外さずに読み書きすると
    再実行のたびにインデントが積み増される。
    """
    widths = [len(line) - len(line.lstrip()) for line in code if line.strip()]
    margin = min(widths) if widths else 0
    return [line[margin:] if line.strip() else "" for line in code]


def collect(only: str | None = None) -> list[Snippet]:
    """全ソースから撮影対象を集める（`--only` は キー・シンボルの部分一致）。"""
    snippets: list[Snippet] = []
    seen: dict[str, Snippet] = {}
    for path in swift_sources():
        for snippet in extract(path):
            if snippet.key in seen:
                raise ShotError(
                    f"{snippet.key} が 2 回出てくる（同じファイルの同じシグネチャに"
                    "スニペットを 2 本置けない）"
                )
            seen[snippet.key] = snippet
            snippets.append(snippet)
    if only:
        snippets = [s for s in snippets if only in s.key or only in s.symbol]
    return snippets


# --- 生成パッケージ -----------------------------------------------------------


PACKAGE_HEADER = """// swift-tools-version: 5.10
// 生成物。scripts/generate-reference-shots.py が doc コメントのスニペットから作る。
import PackageDescription

let package = Package(
    name: "ReferenceShots",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../.."),
    ],
    targets: [
"""

PACKAGE_FOOTER = """    ]
)
"""

SKETCH_TEMPLATE = """// 生成物。正典は {rel} の doc コメント。
import metaphor

@main
final class {target}: Sketch {{
    var config: SketchConfig {{
        SketchConfig(width: {width}, height: {height}, title: "{symbol}")
    }}

    func setup() {{
{setup}
    }}

    func draw() {{
{body}
    }}
}}
"""


def write_package(snippets: list[Snippet], config: dict) -> None:
    """スニペットを SwiftPM パッケージへ展開する（毎回作り直す）。"""
    sources = WORK_DIR / "Sources"
    shutil.rmtree(sources, ignore_errors=True)
    targets = []
    for snippet in snippets:
        settings = snippet.settings(config)
        # 静止画は noLoop で「1 フレーム描いて止まる」状態にする。動きは回し続ける。
        setup = "" if settings.get("motion") else "        noLoop()"
        body = "\n".join(
            f"        {line}" if line.strip() else "" for line in snippet.code
        )
        directory = sources / snippet.target
        directory.mkdir(parents=True, exist_ok=True)
        # main.swift という名前にすると top-level code 扱いになり @main と衝突する。
        (directory / f"{snippet.target}.swift").write_text(
            SKETCH_TEMPLATE.format(
                rel=snippet.rel,
                target=snippet.target,
                symbol=snippet.symbol.replace('"', ""),
                width=settings["width"],
                height=settings["height"],
                setup=setup,
                body=body,
            ),
            encoding="utf-8",
        )
        targets.append(
            f'        .executableTarget(\n'
            f'            name: "{snippet.target}",\n'
            f'            dependencies: [.product(name: "metaphor", package: "metaphor")],\n'
            f'            path: "Sources/{snippet.target}"\n'
            f'        ),\n'
        )
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    (WORK_DIR / "Package.swift").write_text(
        PACKAGE_HEADER + "".join(targets) + PACKAGE_FOOTER, encoding="utf-8"
    )


def build_package(snippets: list[Snippet]) -> None:
    """生成パッケージをビルドする（＝ 全スニペットのコンパイル検証）。"""
    print(f"  building {len(snippets)} snippet(s) ...", flush=True)
    result = subprocess.run(
        ["swift", "build"], cwd=WORK_DIR, capture_output=True, text=True
    )
    if result.returncode != 0:
        raise ShotError(
            "スニペットのビルドに失敗した（doc コメントのコードを直してください）:\n"
            f"{result.stdout[-3000:]}\n{result.stderr[-3000:]}"
        )


# --- 撮影 ---------------------------------------------------------------------


def current_frame(output_dir: Path, request_id: str) -> dict | None:
    """撮影が終わっていれば `frame.json` の中身を返す（CONTRACT.md 契約点 4）。"""
    metadata = output_dir / "frame.json"
    if not metadata.is_file():
        return None
    try:
        data = json.loads(metadata.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None  # 書き込み途中を読んだ。次のポーリングで見直す
    return data if data.get("id") == request_id else None


def sequence_manifest(sequence_dir: Path, request_id: str) -> dict | None:
    """連続キャプチャが完了していれば `sequence.json` の中身を返す。"""
    manifest = sequence_dir / "sequence.json"
    if not manifest.is_file():
        return None
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    if data.get("id") != request_id:
        return None
    frames = data.get("frames")
    if not isinstance(frames, list) or len(frames) != data.get("frameCount"):
        return None
    return data


def capture(snippet: Snippet, settings: dict, symmetric: str | None = None) -> dict:
    """スニペット 1 本を走らせて撮り、台帳のエントリ（URL 抜き）を返す。

    `symmetric` は「反転しても同じ絵でよい」の申告（`Snippet.symmetric`）。撮った絵が
    反転と一致しすぎていないかの検査（#985）を黙らせるために渡す。
    """
    probe_dir = WORK_DIR / ".metaphor/probe"
    output_dir = probe_dir / "current"
    shutil.rmtree(probe_dir, ignore_errors=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    motion = settings.get("motion")
    request_id = f"reference-shot-{snippet.target}"
    request = {"id": request_id, "label": snippet.symbol, "scale": 1.0}
    if motion:
        request["frames"] = motion["frames"]
        request["every"] = motion["every"]

    # リクエストは静止画も動きも**起動前**に置く。
    #
    # 静止画（noLoop）は最初の 1 フレームしか描かないので、起動後に置いても処理する
    # 機会が来ません。動きは起動後でも処理はされますが、置くまでに進んだフレーム数が
    # 実行ごとに変わるため、`Float(frameCount)` で駆動するスニペットは毎回違う位相
    # から撮れてしまいます（#784。撮り直すたびに別の GIF になり、#781 の鮮度照合が
    # 成り立たない）。起動前に置けば Probe は最初の `pre()` で受け取るので、撮り始め
    # のフレームが常に同じになります。
    #
    # 「数フレーム走らせてから撮りたい」は、この経路では**決定的にできません**
    # （待ちを秒で測るしかなく、それが上のずれの原因）。要るならスニペット側で
    # `frameCount` から作ってください。
    tmp = probe_dir / "request.json.tmp"
    tmp.write_text(json.dumps(request), encoding="utf-8")
    tmp.replace(probe_dir / "request.json")  # 契約点 4: アトミックに置く

    env = dict(os.environ)
    env["METAPHOR_PROBE"] = "1"
    env["METAPHOR_VIEWER"] = "1"  # ヘッドレス（ウィンドウを開かない）
    print(f"  running  {snippet.symbol} ...", flush=True)
    process = subprocess.Popen(
        ["swift", "run", snippet.target],
        cwd=WORK_DIR,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    sequence_dir = output_dir / "sequence"
    entry: dict = {}

    def fail_if_dead() -> None:
        if process.poll() is None:
            return
        stderr = (process.stderr.read() if process.stderr else "") or ""
        raise ShotError(
            f"'{snippet.symbol}' が画像を書く前に終了した（exit {process.returncode}）"
            f"\n{stderr[-2000:]}"
        )

    def wait_for(what: str, poll) -> dict:
        deadline = time.monotonic() + CAPTURE_TIMEOUT_SEC
        while time.monotonic() < deadline:
            answer = poll()
            if answer is not None:
                return answer
            fail_if_dead()
            time.sleep(POLL_INTERVAL_SEC)
        raise ShotError(
            f"'{snippet.symbol}' が {CAPTURE_TIMEOUT_SEC:.0f} 秒以内に {what} を書かなかった"
        )

    try:
        still = STAGING_DIR / f"{snippet.target}.png"
        still.parent.mkdir(parents=True, exist_ok=True)
        if motion:
            # 完了規約: sequence.json が最後に書かれる（CONTRACT.md 契約点 4）。
            ready = wait_for(
                "sequence.json", lambda: sequence_manifest(sequence_dir, request_id)
            )
            entry = collect_sequence(snippet, sequence_dir, ready, motion, still)
        else:
            metadata = wait_for(
                "frame.png", lambda: current_frame(output_dir, request_id)
            )
            frame_png = output_dir / "frame.png"
            if not frame_png.is_file():
                # id が一致する frame.json に PNG が伴わないのは失敗応答（契約点 4）。
                warnings = "; ".join(metadata.get("warnings") or []) or "理由の申告なし"
                raise ShotError(f"'{snippet.symbol}' の撮影が失敗応答を返した: {warnings}")
            shutil.copyfile(frame_png, still)
            size = metadata.get("size", {})
            entry = {"width": size.get("width"), "height": size.get("height")}
        # 動きの側も代表静止画を同じ `still` に書くので、ここ 1 箇所で両方を通せる。
        for warning in symmetry_warnings(snippet, still, symmetric):
            print(warning, flush=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        shutil.rmtree(probe_dir, ignore_errors=True)
    return entry


def collect_sequence(
    snippet: Snippet, sequence_dir: Path, manifest: dict, motion: dict, still: Path
) -> dict:
    """連続キャプチャの出力から、代表静止画と GIF を作る。"""
    frames = [sequence_dir / frame["file"] for frame in manifest["frames"]]
    missing = [path.name for path in frames if not path.is_file()]
    if missing:
        raise ShotError(
            f"'{snippet.symbol}' のフレームが欠けている: {', '.join(missing[:3])}"
        )

    # 代表静止画は真ん中のフレーム（動きが載らない閲覧環境のための 1 枚）。
    shutil.copyfile(frames[len(frames) // 2], still)

    output = STAGING_DIR / f"{snippet.target}.gif"
    render_gif(snippet, frames, output, motion, manifest)

    written = output.stat().st_size
    if written > MOTION_MAX_BYTES:
        output.unlink()
        raise ShotError(
            f"'{snippet.symbol}' の GIF が {written / 1024:.0f}KB で上限"
            f"（{MOTION_MAX_BYTES // 1024}KB）を超えた。"
            "shots.config.json の width か frames を落としてください"
        )
    size = manifest.get("size", {})
    gif_width, gif_height = image_size(output)
    return {
        "width": size.get("width"),
        "height": size.get("height"),
        "motion": {
            **motion,
            "bytes": written,
            "outputWidth": gif_width,
            "outputHeight": gif_height,
        },
    }


def render_gif(
    snippet: Snippet, frames: list[Path], output: Path, motion: dict, manifest: dict
) -> None:
    """連番 PNG からアニメーション GIF を書く。

    DocC は WebP を無言で落とすので、動きを `![]()` で見せる手段は GIF だけ（ADR-0008）。
    パレット最適化を挟むのは、既定の 256 色量子化だとグラデーションが帯になるため。
    """
    if shutil.which("ffmpeg") is None:
        raise ShotError("ffmpeg が見つからない（GIF の生成に要る）。brew install ffmpeg で入ります")

    source_width = manifest.get("size", {}).get("width") or 0
    width = motion["width"]
    scale = f"scale={width}:-1:flags=lanczos," if 0 < width < source_width else ""

    # 連番へ並べ直してから渡す。Probe の出力名（frame.NNNN.png）に ffmpeg の入力
    # パターンを合わせると、命名が変わった日に無言で 1 枚だけの GIF になる。
    work = Path(tempfile.mkdtemp(prefix="reference-shots-"))
    try:
        for index, path in enumerate(frames):
            shutil.copyfile(path, work / f"{index:04d}.png")
        run_or_raise(
            [
                "ffmpeg", "-loglevel", "error", "-y",
                "-framerate", str(motion["fps"]),
                "-start_number", "0",
                "-i", str(work / "%04d.png"),
                "-vf",
                f"{scale}split[a][b];[a]palettegen=stats_mode=diff[p];"
                "[b][p]paletteuse=dither=bayer",
                "-loop", "0",
                str(output),
            ],
            f"'{snippet.symbol}' の GIF 生成",
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def run_or_raise(command: list[str], what: str) -> None:
    run_capturing(command, what)


def run_capturing(command: list[str], what: str) -> str:
    """コマンドを走らせ、stdout と stderr を繋いで返す。"""
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise ShotError(f"{what}に失敗した:\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


# --- 反転一致の検査（#985）----------------------------------------------------

# ffmpeg の psnr フィルタが最後に出す 1 行。完全一致のときは `average:inf`。
PSNR_AVERAGE_RE = re.compile(r"\baverage:(\S+)")


def flip_psnr(still: Path, flip: str) -> float | None:
    """`still` と、それを `flip`（vflip / hflip）したものの PSNR（dB）。測れなければ None。

    ffmpeg は撮影の側（GIF 生成）で既に要るので依存は増えないが、**python テストだけを
    回す CI のステップには入っていない**（`.github/workflows/ci.yml` の
    `Test generator scripts` は ffmpeg を入れない）。有無の判定をここに置くことで、
    `symmetry_warnings()` から見た計測経路は **この関数 1 つだけ**になり、テストは
    これを差し替えるだけで判定ロジックを確かめられる。

    psnr の要約は info で出るため `-loglevel error` にはできない
    （`-nostats` で進捗行だけ黙らせる）。
    """
    if shutil.which("ffmpeg") is None:
        return None
    output = run_capturing(
        [
            "ffmpeg", "-hide_banner", "-nostats",
            "-i", str(still), "-i", str(still),
            "-lavfi", f"[1]{flip}[flipped];[0][flipped]psnr",
            "-f", "null", "-",
        ],
        f"{still.name} の {flip} との PSNR 計測",
    )
    matched = PSNR_AVERAGE_RE.search(output)
    if not matched:
        raise ShotError(f"ffmpeg の PSNR 出力を読み取れなかった:\n{output[-1000:]}")
    return float("inf") if matched.group(1) == "inf" else float(matched.group(1))


def symmetry_warnings(
    snippet: Snippet, still: Path, symmetric: str | None, measure=None
) -> list[str]:
    """撮った絵が上下・左右反転と一致しすぎていないか調べ、警告文を返す（#985）。

    「向きを決める引数」を説明するページなのに反転しても同じ絵 ＝ **引数を間違えても
    同じ絵になる**ということで、その絵は向きの誤りを写せていません。#923 の `ortho` /
    `perspective` がそれでした。これは**絵を見比べても発見できない**（撮り直したのに
    sha256 と Gyazo URL が完全に同一だった、という副次的な観察から分かった）ので、
    撮影のたびに機械で拾います。

    **エラーにはしません**。対称なのが正しい絵（`radialGradient`、真円、正方形）は普通に
    あり、撮影を止めると意図して対称な絵を出したいときに作業が詰まります。分かっている
    ものは `shots.config.json` の `"symmetric"` で軸ごとに黙らせられます。

    **測れなかったときは黙りません。** ffmpeg が無い環境では検査ごと飛ばしますが、
    その旨を note として返します。警告を出すための仕組みが、測れないときに無言で
    「異常なし」と見分けが付かなくなるのが一番危ないためです。

    `measure` は計測の差し替え口です（既定は `flip_psnr`。ffmpeg の有無もそちらが持つ）。
    """
    if measure is None:
        measure = flip_psnr
    warnings: list[str] = []
    for axis, (flip, label) in FLIPS.items():
        if symmetric in (axis, "both"):
            continue
        value = measure(still, flip)
        if value is None:
            return [
                f"  note     {snippet.symbol} の反転一致検査を飛ばした"
                "（ffmpeg が無いので PSNR を測れない）"
            ]
        if value <= FLIP_PSNR_WARN_DB:
            continue
        shown = "完全一致" if value == float("inf") else f"PSNR {value:.1f} dB"
        warnings.append(
            f"  warning  {snippet.symbol} の絵は{label}反転と見分けが付きません"
            f"（{shown} > {FLIP_PSNR_WARN_DB:.0f} dB）。向きを決める引数があるなら、"
            f"それを間違えても同じ絵になっているおそれがあります。対称で正しいなら "
            f'docs/reference/shots.config.json に "symmetric": "{axis}" を書いてください'
        )
    return warnings


# --- Gyazo -------------------------------------------------------------------
#
# 上げ口そのもの（トークンの読み方・curl・応答の検証）は shots_common に置いてある。
# ここに残すのは、リファレンス固有の「中身が同じなら上げ直さない」だけ。


def upload(path: Path, snippet: Snippet, recorded: dict | None) -> tuple[str, str]:
    """画像を上げて `(url, sha256)` を返す。中身が同じなら上げ直さない。

    アップロードだけが失敗した直後の再実行を速く済ませるためで、Gyazo 側に同じ絵の
    URL が増えても害は無い（台帳が最新を指していればよい）。
    """
    digest = file_sha256(path)
    if recorded and recorded.get("sha256") == digest and recorded.get("url"):
        return recorded["url"], digest
    return upload_to_gyazo(path, f"metaphor reference {snippet.symbol}"), digest


def publish(snippet: Snippet, entry: dict, recorded: dict | None) -> dict:
    """撮った画像を Gyazo へ上げ、台帳のエントリに URL と指紋を書き入れる。"""
    still = STAGING_DIR / f"{snippet.target}.png"
    url, digest = upload(still, snippet, recorded)
    published = {**entry, "url": url, "sha256": digest}
    if entry.get("motion"):
        gif = STAGING_DIR / f"{snippet.target}.gif"
        motion_url, motion_digest = upload(
            gif, snippet, (recorded or {}).get("motion")
        )
        published["motion"] = {**entry["motion"], "url": motion_url, "sha256": motion_digest}
    return published


# --- 台帳と書き戻し -----------------------------------------------------------


def load_manifest() -> dict:
    if not MANIFEST.is_file():
        return {}
    return json.loads(MANIFEST.read_text(encoding="utf-8")).get("shots", {})


def save_manifest(shots: dict) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "comment": (
            "Generated by scripts/generate-reference-shots.py. snippetHash is the "
            "fingerprint of the doc-comment snippet the image was taken from; "
            "url/sha256 are the immutable asset the reference points at (ADR-0008). "
            "Assets are append-only: a retake gets a new URL, old URLs stay alive so "
            "past revisions keep rendering."
        ),
        "shots": dict(sorted(shots.items())),
    }
    MANIFEST.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def load_config() -> dict:
    if not CONFIG.is_file():
        return {}
    return json.loads(CONFIG.read_text(encoding="utf-8")).get("shots", {})


def expected_targets(entry: dict) -> list[str]:
    """本文に出す URL を返す。

    動きがあるときは **GIF だけ**を出す（静止画は台帳に残す）。同じ絵を静止画と動きで
    2 枚並べても情報が増えず、横並びの列が縦に伸びるだけなので。
    """
    motion = entry.get("motion") or {}
    if motion.get("url"):
        return [motion["url"]]
    return [entry["url"]] if entry.get("url") else []


def rewrite_sources(snippets: list[Snippet], shots: dict, config: dict) -> list[Path]:
    """印から下（生成物領域）を、レイアウトに沿った形で書き直す。

    URL の文字列一致ではなく**印の位置**で対応づけるので、初回・撮り直し・レイアウト
    変更・途中で中断したあとの再実行が、すべて同じべき等な操作になる。人が書いた
    コードは行単位でそのまま入れ直す。
    """
    touched: list[Path] = []
    by_path: dict[Path, list[Snippet]] = {}
    for snippet in snippets:
        by_path.setdefault(snippet.path, []).append(snippet)

    for path, items in by_path.items():
        lines = path.read_text(encoding="utf-8").split("\n")
        changed = False
        # 行番号がずれないよう、後ろから書き換える。
        for snippet in sorted(items, key=lambda s: s.marker, reverse=True):
            entry = shots.get(snippet.key)
            targets = expected_targets(entry) if entry else []
            if not targets:
                continue  # まだ撮っていない（人が書いた素のフェンスのまま置いておく）
            replacement = render_region(snippet, targets, snippet.layout(config))
            if lines[snippet.marker + 1: snippet.block_end] == replacement:
                continue
            lines[snippet.marker + 1: snippet.block_end] = replacement
            changed = True
        if changed:
            path.write_text("\n".join(lines), encoding="utf-8")
            touched.append(path)
    return touched


def render_region(snippet: Snippet, targets: list[str], layout: str) -> list[str]:
    """生成物領域（印の次の行から doc コメントの終わりまで）の中身を組み立てる。"""
    def doc(text: str = "") -> str:
        return f"{snippet.indent}///{' ' + text if text else ''}"

    def images(level: int) -> list[str]:
        pad = "   " * level
        return [doc(pad + image_markup(snippet, url, index))
                for index, url in enumerate(targets)]

    def code(level: int) -> list[str]:
        pad = "   " * level
        return [
            doc(pad + FENCE_OPEN),
            *[doc(pad + line) if line else doc() for line in snippet.code],
            doc(pad + FENCE_CLOSE),
        ]

    if layout == "row":
        # p5.js の reference と同じ「絵が左・コードが右」。狭い画面では DocC 側が縦に折る。
        return [
            doc(),
            doc("@Row {"),
            doc(f"   @Column(size: {ROW_IMAGE_SIZE}) {{"),
            *images(2),
            doc("   }"),
            doc(f"   @Column(size: {ROW_CODE_SIZE}) {{"),
            *code(2),
            doc("   }"),
            doc("}"),
        ]
    return [doc(), *code(0), doc(), *images(0)]


def image_markup(snippet: Snippet, url: str, index: int) -> str:
    """画像 1 枚ぶんの Markdown（`@Image` は外部 URL を解決できないので `![]()`）。"""
    moving = url.endswith(".gif")
    alt = f"{snippet.symbol} の実行結果（動き）" if moving else f"{snippet.symbol} の実行結果"
    if index > 0:
        alt = f"{alt} {index + 1}"
    return f"![{alt}]({url})"


def region_image_targets(lines: list[str], snippet: Snippet) -> list[str]:
    """生成物領域に実際に書かれている画像 URL を、出てくる順に返す。"""
    found: list[str] = []
    for index in range(snippet.marker + 1, snippet.block_end):
        matched = IMAGE_LINE_RE.match((doc_content(lines[index]) or "").strip())
        if matched:
            found.append(matched.group("target"))
    return found


# --- 検査 ---------------------------------------------------------------------


def prune_orphans(shots: dict, snippets: list[Snippet], prune: bool) -> None:
    """台帳から、もう存在しないスニペットのエントリを落とす（URL は Gyazo に残る）。

    `--only` で絞っているときは**掃除しない**。視界の外にあるだけのエントリを
    「消えたスニペット」と取り違えると、他のシンボルの URL を台帳ごと失う
    （＝撮り直しが全点の再アップロードになる）。
    """
    if not prune:
        return
    orphans = set(shots) - {snippet.key for snippet in snippets}
    for orphan in orphans:
        del shots[orphan]
    if orphans:
        print(f"  pruned   {len(orphans)} 件の孤児エントリ")
    save_manifest(shots)


def check(snippets: list[Snippet], shots: dict, config: dict) -> int:
    """撮影も通信もせず、台帳と doc コメントの突き合わせだけで鮮度を見る。"""
    problems: list[str] = []
    for snippet in snippets:
        entry = shots.get(snippet.key)
        if not entry or not entry.get("url"):
            problems.append(f"{snippet.key}: 画像がまだ無い（make reference-shots）")
            continue
        if entry.get("snippetHash") != snippet.fingerprint(config):
            problems.append(
                f"{snippet.key}: スニペットか撮影設定が変わったのに画像が古い"
                f"（make reference-shots ARGS=\"--force --only {snippet.symbol}\"）"
            )
        wants_motion = bool(snippet.settings(config).get("motion"))
        has_motion = bool((entry.get("motion") or {}).get("url"))
        if wants_motion != has_motion:
            problems.append(
                f"{snippet.key}: 動きの設定と台帳が食い違っている"
                f"（設定={wants_motion} / 台帳={has_motion}）"
            )
        lines = snippet.path.read_text(encoding="utf-8").split("\n")
        if region_image_targets(lines, snippet) != expected_targets(entry):
            problems.append(
                f"{snippet.key}: doc コメントの画像 URL が台帳と違う"
                "（make reference-shots で書き戻せます）"
            )
        # レイアウトを変えたあと書き戻していない、も同じ経路で捕まえる。
        region = lines[snippet.marker + 1: snippet.block_end]
        if region != render_region(snippet, expected_targets(entry), snippet.layout(config)):
            problems.append(
                f"{snippet.key}: 本文の並べ方が layout の指定と違う"
                "（make reference-shots で書き戻せます）"
            )

    keys = {snippet.key for snippet in snippets}
    for orphan in sorted(set(shots) - keys):
        problems.append(
            f"{orphan}: 台帳にあるがスニペットが無い（make reference-shots で掃除されます）"
        )

    if problems:
        print("リファレンスの実行結果画像が古い / 足りない:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    # 「最新です」とは書かない。見ているのはスニペットと撮影設定だけで、ライブラリ
    # 実装の変更は含まない（#586）。
    print(
        f"リファレンス {len(snippets)} 本すべてで、"
        "スニペットと撮影設定は撮影時から変わっていません"
    )
    for line in drift_summary(
        (shots[snippet.key] for snippet in snippets if snippet.key in shots),
        "スニペットと撮影設定",
        REPO_ROOT,
    ):
        print(line)
    return 0


# --- 実行 ---------------------------------------------------------------------


def shoot(
    snippets: list[Snippet], shots: dict, config: dict, force: bool, prune: bool
) -> int:
    """撮影 → アップロード → 台帳 → doc コメントの書き戻し。"""
    write_package(snippets, config)
    build_package(snippets)

    pending = [
        snippet
        for snippet in snippets
        if force
        or not shots.get(snippet.key, {}).get("url")
        or shots[snippet.key].get("snippetHash") != snippet.fingerprint(config)
    ]
    if not pending:
        print("撮り直しの要るスニペットはありません")
    for snippet in pending:
        settings = snippet.settings(config)
        recorded = shots.get(snippet.key)
        entry = capture(snippet, settings, snippet.symmetric(config))
        entry = publish(snippet, entry, recorded)
        fingerprint = {
            "symbol": snippet.symbol,
            "snippetHash": snippet.fingerprint(config),
        }
        # snippetHash はスニペットと撮影設定しか見ないので、実装が変わって絵が
        # 変わっても動かない（#586）。撮った実装を来歴として残す。
        provenance = capture_provenance(REPO_ROOT)
        if provenance:
            fingerprint["provenance"] = provenance
        shots[snippet.key] = {**fingerprint, **entry}
        save_manifest(shots)  # 1 本ごとに保存する（中断しても撮り直しにならない）
        print(f"  shot     {snippet.symbol} -> {entry['url']}", flush=True)

    prune_orphans(shots, snippets, prune)

    touched = rewrite_sources(snippets, shots, config)
    for path in touched:
        print(f"  updated  {path.relative_to(REPO_ROOT)}")
    shutil.rmtree(STAGING_DIR, ignore_errors=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="鮮度だけ調べる（撮らない）")
    parser.add_argument(
        "--compile-only", action="store_true", help="スニペットのビルドだけ通す（GPU 不要）"
    )
    parser.add_argument("--list", action="store_true", help="撮影対象を並べる")
    parser.add_argument("--only", help="キー・シンボルの部分一致で絞る")
    parser.add_argument("--force", action="store_true", help="鮮度に関わらず撮り直す")
    args = parser.parse_args()

    try:
        snippets = collect(args.only)
        config = load_config()
        if args.list:
            for snippet in snippets:
                motion = "motion" if snippet.settings(config).get("motion") else "still"
                print(f"{snippet.key}\t{motion}")
            return 0
        if args.compile_only:
            write_package(snippets, config)
            build_package(snippets)
            print(f"スニペット {len(snippets)} 本のコンパイルを確認しました")
            return 0
        shots = load_manifest()
        if args.check:
            if args.only:
                # 絞ったまま孤児を報告すると毎回赤くなるので、全体を見る。
                snippets = collect(None)
            return check(snippets, shots, config)
        return shoot(snippets, shots, config, args.force, prune=not args.only)
    except ShotError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
