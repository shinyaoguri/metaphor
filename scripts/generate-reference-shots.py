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
    /// ```swift
    /// background(240)
    /// circle(width / 2, height / 2, 200)
    /// ```
    ///
    /// ![circle() の実行結果](https://i.gyazo.com/<hash>.png)

- **コードは人が書く（正典）／画像行は生成物**（このスクリプトが書き戻す・手で書かない）
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

from shots_common import ShotError, image_size  # noqa: E402

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

GYAZO_UPLOAD_URL = "https://upload.gyazo.com/api/upload"
GYAZO_HOST = "i.gyazo.com"
# トークンは 1Password から都度読む（平文の環境変数として常駐させない）。
GYAZO_TOKEN_REF = os.environ.get(
    "GYAZO_TOKEN_REF", "op://Automation/Gyazo API/credential"
)

# 起動から frame.png が書かれるまでの待ち時間。初回はシェーダーのコンパイルが入る。
CAPTURE_TIMEOUT_SEC = 120.0
POLL_INTERVAL_SEC = 0.2
# 動くスケッチで、下見のあと本番のリクエストを置くまでの待ち。
SETTLE_SEC = 1.0

# 絵の既定サイズ。リファレンスは 1 シンボル 1 枚が縦に並ぶので、チュートリアル
# （640x360）より小さく取る。
DEFAULT_WIDTH = 480
DEFAULT_HEIGHT = 360

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
        fence_end: int,
        image_line: int | None,
        indent: str,
    ) -> None:
        self.path = path
        self.rel = path.relative_to(REPO_ROOT).as_posix()
        self.symbol = symbol
        self.code = code
        self.fence_end = fence_end  # 閉じフェンスの行番号（0 起点）
        self.image_line = image_line  # 既にある画像行（無ければ None）
        self.indent = indent

    @property
    def key(self) -> str:
        """台帳と設定のキー。ファイルまで含めてオーバーロード以外の衝突を防ぐ。"""
        return f"{self.rel}::{self.symbol}"

    @property
    def target(self) -> str:
        """生成パッケージでの実行ターゲット名（Swift の識別子として使える形）。"""
        stem = re.sub(r"[^0-9A-Za-z]+", "_", Path(self.rel).stem)
        name = re.sub(r"[^0-9A-Za-z]+", "_", self.symbol).strip("_")
        return f"Shot_{stem}_{name}"

    def settings(self, config: dict) -> dict:
        """撮影設定（既定 + `shots.config.json` の上書き）を返す。"""
        entry = config.get(self.key) or config.get(self.symbol) or {}
        settings = {
            "width": entry.get("width", DEFAULT_WIDTH),
            "height": entry.get("height", DEFAULT_HEIGHT),
            "settle": entry.get("settle", SETTLE_SEC),
        }
        motion = entry.get("motion")
        if motion:
            merged = {**MOTION_DEFAULTS, **(motion if isinstance(motion, dict) else {})}
            merged["frames"] = min(int(merged["frames"]), MOTION_MAX_FRAMES)
            settings["motion"] = merged
        return settings

    def fingerprint(self, config: dict) -> str:
        """スニペットと撮影設定の指紋。どちらが変わっても撮り直しが要る。"""
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

        code = [doc_content(lines[line]) or "" for line in range(fence_start + 1, fence_end)]
        if not any(line.strip() for line in code):
            raise ShotError(
                f"{path.relative_to(REPO_ROOT)}:{fence_start + 1} のスニペットが空"
            )

        # フェンスの後、最初の中身のある行が画像行ならそれを更新する。無ければ後で挿す。
        image_line = None
        for line in range(fence_end + 1, block_end):
            content = (doc_content(lines[line]) or "").strip()
            if not content:
                continue
            if IMAGE_LINE_RE.match(content):
                image_line = line
            break

        symbol = declaration_symbol(lines, block_end)
        if symbol is None:
            raise ShotError(
                f"{path.relative_to(REPO_ROOT)}:{block_end + 1} の doc コメントに"
                "対応する宣言を読み取れなかった"
            )
        indent = lines[fence_start][: len(lines[fence_start]) - len(lines[fence_start].lstrip())]
        snippets.append(Snippet(path, symbol, code, fence_end, image_line, indent))
    return snippets


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


def capture(snippet: Snippet, settings: dict) -> dict:
    """スニペット 1 本を走らせて撮り、台帳のエントリ（URL 抜き）を返す。"""
    probe_dir = WORK_DIR / ".metaphor/probe"
    output_dir = probe_dir / "current"
    shutil.rmtree(probe_dir, ignore_errors=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    motion = settings.get("motion")
    request_id = f"reference-shot-{snippet.target}"
    warmup_id = f"{request_id}-warmup"
    request = {"id": request_id, "label": snippet.symbol, "scale": 1.0}
    if motion:
        request["frames"] = motion["frames"]
        request["every"] = motion["every"]

    def place_request(payload: dict) -> None:
        tmp = probe_dir / "request.json.tmp"
        tmp.write_text(json.dumps(payload), encoding="utf-8")
        tmp.replace(probe_dir / "request.json")  # 契約点 4: アトミックに置く

    # 静止画は noLoop なので、起動**前**に置いた 1 通しか処理する機会が無い。
    # 動きは下見を先に置き、描画ループが回ってから本番を置く。
    place_request(
        {"id": warmup_id, "label": f"{snippet.symbol} (warmup)", "scale": 1.0}
        if motion
        else request
    )

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
            wait_for(
                f"frame.json（下見 id={warmup_id}）",
                lambda: current_frame(output_dir, warmup_id),
            )
            time.sleep(settings["settle"])
            place_request(request)
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
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise ShotError(f"{what}に失敗した:\n{result.stdout}\n{result.stderr}")


# --- Gyazo -------------------------------------------------------------------


_GYAZO_TOKEN: list[str] = []


def gyazo_token() -> str:
    """1Password から Gyazo のアクセストークンを 1 度だけ読む。

    `--check` / `--compile-only` からは決して呼ばない（CI にはトークンが無い）。
    """
    if _GYAZO_TOKEN:
        return _GYAZO_TOKEN[0]
    if shutil.which("op") is None:
        raise ShotError(
            "1Password CLI（op）が見つからない。画像のアップロードにはトークンが要る。"
            "brew install 1password-cli で入ります"
        )
    result = subprocess.run(["op", "read", GYAZO_TOKEN_REF], capture_output=True, text=True)
    if result.returncode != 0:
        raise ShotError(
            f"Gyazo のトークンを読めなかった（{GYAZO_TOKEN_REF}）:\n{result.stderr.strip()}"
        )
    token = result.stdout.strip()
    if not token:
        raise ShotError(f"Gyazo のトークンが空だった（{GYAZO_TOKEN_REF}）")
    _GYAZO_TOKEN.append(token)
    return token


def gyazo_url_from_response(body: str, expected_suffix: str) -> str:
    """Upload API の応答から URL を取り出して検証する。"""
    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ShotError(f"Gyazo の応答が JSON として読めない: {body[:200]}") from exc
    url = data.get("url")
    if not isinstance(url, str) or not url.startswith(f"https://{GYAZO_HOST}/"):
        raise ShotError(f"Gyazo の応答に想定した URL が無い: {body[:200]}")
    if not url.endswith(expected_suffix):
        # 形式が変換されたら DocC での見え方が変わる。黙って進めない。
        raise ShotError(f"Gyazo が別の形式で返した（{expected_suffix} を上げたのに {url}）")
    return url


def file_sha256(path: Path) -> str:
    """上げたバイト列の指紋。URL が指す中身が入れ替わっていないことの確認用。"""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def upload(path: Path, snippet: Snippet, recorded: dict | None) -> tuple[str, str]:
    """画像を上げて `(url, sha256)` を返す。中身が同じなら上げ直さない。

    アップロードだけが失敗した直後の再実行を速く済ませるためで、Gyazo 側に同じ絵の
    URL が増えても害は無い（台帳が最新を指していればよい）。
    """
    digest = file_sha256(path)
    if recorded and recorded.get("sha256") == digest and recorded.get("url"):
        return recorded["url"], digest
    token = gyazo_token()
    result = subprocess.run(
        [
            "curl", "-sS", "--fail", "--retry", "3", "--retry-delay", "2",
            "-F", f"access_token={token}",
            "-F", f"imagedata=@{path}",
            "-F", f"title=metaphor reference {snippet.symbol}",
            GYAZO_UPLOAD_URL,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        # コマンド列にはトークンが入っているので、決してそのまま出さない。
        raise ShotError(
            f"'{snippet.symbol}' の {path.name} をアップロードできなかった"
            f"（curl exit {result.returncode}）:\n{result.stderr.strip()[-500:]}"
        )
    return gyazo_url_from_response(result.stdout, path.suffix), digest


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
    """台帳が指す URL を、doc コメントに並ぶ順（静止画 → 動き）で返す。"""
    targets = [entry["url"]] if entry.get("url") else []
    motion = entry.get("motion") or {}
    if motion.get("url"):
        targets.append(motion["url"])
    return targets


def rewrite_sources(snippets: list[Snippet], shots: dict) -> list[Path]:
    """doc コメントの画像行を台帳の URL で上書きする（無ければ挿す）。

    URL の文字列一致ではなく**フェンスの位置**で対応づけるので、初回・撮り直し・途中で
    中断したあとの再実行が、すべて同じべき等な操作になる。
    """
    touched: list[Path] = []
    by_path: dict[Path, list[Snippet]] = {}
    for snippet in snippets:
        by_path.setdefault(snippet.path, []).append(snippet)

    for path, items in by_path.items():
        lines = path.read_text(encoding="utf-8").split("\n")
        changed = False
        # 行番号がずれないよう、後ろから書き換える。
        for snippet in sorted(items, key=lambda s: s.fence_end, reverse=True):
            entry = shots.get(snippet.key)
            targets = expected_targets(entry) if entry else []
            if not targets:
                continue
            existing = existing_image_lines(lines, snippet)
            replacement = [
                image_line(snippet, url, index) for index, url in enumerate(targets)
            ]
            if existing:
                start, end = existing[0], existing[-1] + 1
            else:
                start = end = snippet.fence_end + 1
                replacement = [f"{snippet.indent}///"] + replacement
            if lines[start:end] == replacement:
                continue
            lines[start:end] = replacement
            changed = True
        if changed:
            path.write_text("\n".join(lines), encoding="utf-8")
            touched.append(path)
    return touched


def existing_image_lines(lines: list[str], snippet: Snippet) -> list[int]:
    """フェンスの後に並んでいる画像行の行番号を返す（無ければ空）。"""
    found: list[int] = []
    index = snippet.fence_end + 1
    while index < len(lines):
        content = doc_content(lines[index])
        if content is None:
            break
        stripped = content.strip()
        if not stripped:
            if found:
                break  # 画像行の並びが終わった
            index += 1
            continue
        if IMAGE_LINE_RE.match(stripped):
            found.append(index)
            index += 1
            continue
        break
    return found


def image_line(snippet: Snippet, url: str, index: int) -> str:
    """画像行を組み立てる（静止画が 1 本目、動きが 2 本目）。"""
    alt = f"{snippet.symbol} の実行結果（動き）" if index == 1 else f"{snippet.symbol} の実行結果"
    return f"{snippet.indent}/// ![{alt}]({url})"


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
        found = [
            (doc_content(lines[line]) or "").strip()
            for line in existing_image_lines(lines, snippet)
        ]
        targets = [IMAGE_LINE_RE.match(line).group("target") for line in found]
        if targets != expected_targets(entry):
            problems.append(
                f"{snippet.key}: doc コメントの画像 URL が台帳と違う"
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
    print(f"リファレンスの実行結果画像は最新です（{len(snippets)} 本）")
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
        entry = capture(snippet, settings)
        entry = publish(snippet, entry, recorded)
        shots[snippet.key] = {
            "symbol": snippet.symbol,
            "snippetHash": snippet.fingerprint(config),
            **entry,
        }
        save_manifest(shots)  # 1 本ごとに保存する（中断しても撮り直しにならない）
        print(f"  shot     {snippet.symbol} -> {entry['url']}", flush=True)

    prune_orphans(shots, snippets, prune)

    touched = rewrite_sources(snippets, shots)
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
