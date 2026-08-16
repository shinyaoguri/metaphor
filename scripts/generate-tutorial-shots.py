#!/usr/bin/env python3
"""Examples/Tutorial/** を実際に走らせ、実行結果画像を撮り直して Gyazo へ上げる。

各節のスケッチを `METAPHOR_PROBE=1 METAPHOR_VIEWER=1` で起動し、Probe が書く
`.metaphor/probe/current/frame.png` を Gyazo へアップロードして、返ってきた URL を
`docs/tutorial/images/manifest.json`（台帳）と本文の `![](...)` に書き戻す。
手で撮ったスクリーンショットは置かない（Issue #486 / docs/tutorial/README.md）。

    make tutorial-shots                     # 参照されている全節を撮り直す
    make tutorial-shots ARGS="--only 01-GettingStarted/03-SketchSkeleton"
    python3 scripts/generate-tutorial-shots.py --check   # 鮮度だけ調べる

## 画像をリポジトリに置かない（ADR-0010）

画像の実体は Gyazo（`https://i.gyazo.com/<hash>.<ext>`）に置き、Git で管理するのは
**本文と台帳（URL + content hash）だけ**にする。アセットは不変・追記型で、撮り直しは
既存 URL の差し替えではなく新規アップロードとして扱い、本文と台帳の URL を更新する。
古い URL は消さない（過去のリビジョンをそのまま開けば当時の絵が出る）。

台帳が「どの節がどの URL を指すか」の正本なので、本文の書き換えは文字列置換ではなく
**節の構造から位置を決めて台帳の URL で上書きする**（`rewrite_docs`）。初回の外部化・
撮り直し・途中で中断したあとの再実行が、すべて同じべき等な操作になる。

アップロードには 1Password 上の Gyazo トークンが要るため、撮影と同じくローカルでのみ
行う。`--check` はネットワークにもトークンにも触れず、台帳と本文の突き合わせだけで
鮮度を判定する（CI で走るのはこちら）。URL の生死は週次のワークフローが見る
（scripts/check-image-urls.py）。

## 動きが要る節（#507）

イージング・パーティクル・入力のように**静止画では正誤を判定できない**節は、
`docs/tutorial/images/motion.json` に登録すると Probe の連続キャプチャ
（CONTRACT.md 契約点 4 の `frames >= 2`）で撮り、静止画に加えて

- `kind: "webp"` — アニメーション WebP（`img2webp` が要る）
- `kind: "sheet"` — コンタクトシート（Probe が合成したもの）

を上げる。GIF ではなく WebP なのは、同じ絵で 1 桁小さく、`![](...)` のまま GitHub でも
website でも動くため（Gyazo はアニメーション WebP をそのまま受け取り、バイト列を変えず
に配信する）。mp4 は GitHub の Markdown が再生しないので採らない。

## 入力が要る節（#509）

マウス・キーボードを扱う節は、入力が無いと絵が出来上がらない。パッケージ直下に
`probe-input.jsonl` を置くと、スケッチを起動した後に**その内容を stdin へ流してから**
撮る。ヘッドレス起動では `InputInjectionPlugin` が自動登録され、stdin の JSON Lines
（CONTRACT.md 契約点 3）を入力として受け取るため、cli を挟まずに入力を再現できる。

    {"t":"mouseMove","x":120,"y":80}
    {"t":"mouseDown","x":120,"y":80,"button":0}
    {"wait":120}

- `t` を持つ行はそのまま送る。`t` を持たない `{"wait": ミリ秒}` の行は待つだけで送らない
- `//` で始まる行と空行は無視する（台本に意図を書けるようにするため）
- `mouseUp` / `keyUp` を送らずに終えれば「押されている状態」の絵が撮れる
- 撮影は**入力を流し終えてから**始まるので、撮り直しても同じ絵になる。代わりに
  `noLoop()` のスケッチとは両立しない（起動後に置いた request を処理する機会が無い）

## 撮れない節（#544）

音・カメラ・機械学習のように、**実行環境に依存して絵が決まらない**節がある。マイクが
無音なら何も動かず、カメラの映像は撮る場所によって変わり、どちらもヘッドレス起動では
TCC の権限が降りないこともある。この種の節はパッケージ直下に `no-capture.txt` を置き、
撮らない理由を 1 行書く。撮影も鮮度検査も飛ばし、本文は画像の代わりに「何が起きるか」を
文章で書く（docs/tutorial/README.md の「実行結果の画像」）。

## なぜ画像のバイト比較で鮮度を見ないか

GPU レンダリングの出力は環境（GPU・ドライバ・OS）でビット単位には一致しない。
撮り直すたびに差分が出るので、`--check` は画像そのものではなく
`docs/tutorial/images/manifest.json` に記録した**撮影時のソースのハッシュ**と
現在のソースを突き合わせる。これで「コードを変えたのに画像を撮り直していない」
という実際に起きるドリフトだけを、GPU の無い CI ランナーでも検出できる。

台帳の `sha256` は鮮度判定には使わない（用途が違う）。こちらは**上げたバイト列そのもの
の指紋**で、URL が指す中身が入れ替わっていないことを後から確かめるためのもの。

撮影とアップロードはローカルで行い、本文と台帳をコミットする（CI では走らせない）。
"""

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
# 「撮影時のソースの指紋」「画像の縦横」「入力台本」は Examples 側
# （generate-example-shots.py）と共通。実装を 2 つ持つと、片側だけ鮮度検出が
# 弱り（#505）、片側だけ入力を流せない（#610）。
from shots_common import (  # noqa: E402
    INPUT_SCRIPT_NAME,
    ShotError,
    capture_provenance,
    drift_summary,
    image_size,
    load_input_script,
    send_input_script,
    source_files,
    source_hash,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
CODE_DIR = REPO_ROOT / "Examples/Tutorial"
DOCS_DIR = REPO_ROOT / "docs/tutorial"
IMAGES_DIR = DOCS_DIR / "images"
MANIFEST = IMAGES_DIR / "manifest.json"
# 動きの証跡が要る節の設定（手書きの正典。manifest.json は生成物なので分ける）。
MOTION_CONFIG = IMAGES_DIR / "motion.json"
# 撮った画像の一時置き場。上げ終われば用済みなので gitignore 済みの .build/ に置く。
STAGING_DIR = REPO_ROOT / ".build/tutorial-shots"

# 埋め込みマーカー（generate-tutorial-snippets.py と同じ書式）。本文が参照して
# いる節 = 画像が要る節、と定義する。
SNIPPET_RE = re.compile(r"^<!-- tutorial-snippet:\s*(?P<ref>\S+)\s*-->$")
# 本文の画像行。alt を保ったまま target だけ差し替えられるように分けて捕まえる。
# 独立した 1 行だけを見る（文中に混ぜた画像は本文の規約で認めていない）。
IMAGE_LINE_RE = re.compile(
    r"^(?P<head>!\[(?P<alt>[^\]]*)\]\()(?P<target>[^)\s]+)(?P<tail>\))\s*$"
)

# 画像の実体の置き場（ADR-0010）。チュートリアルの本文だけが外部 URL を指す
# （Examples の画像はリポジトリ内に置くので、この経路を使わない）。
GYAZO_UPLOAD_URL = "https://upload.gyazo.com/api/upload"
GYAZO_HOST = "i.gyazo.com"
# トークンは 1Password から都度読む（平文の環境変数として常駐させない）。参照先を
# 環境変数で差し替えられるようにしておくのは DEVELOPMENT.md の手順と同じ流儀。
GYAZO_TOKEN_REF = os.environ.get(
    "GYAZO_TOKEN_REF", "op://Automation/Gyazo API/credential"
)

# 起動から frame.png が書かれるまでの待ち時間。初回はシェーダーのコンパイルが
# 入るぶん遅い。
CAPTURE_TIMEOUT_SEC = 90.0
POLL_INTERVAL_SEC = 0.2

# 撮らない節の申告（#544）。パッケージ直下に置くと撮影も鮮度検査も飛ばす。
NO_CAPTURE_NAME = "no-capture.txt"

# 動きの証跡の既定値と上限（docs/tutorial/README.md の規約と対）。
MOTION_KINDS = ("webp", "sheet")
MOTION_MAX_FRAMES = 64  # Probe 側のクランプ上限（CONTRACT.md 契約点 4）
MOTION_DEFAULTS = {"frames": MOTION_MAX_FRAMES, "every": 4, "fps": 15, "width": 720}
# 1 ファイルの上限。超えたら幅かフレーム数を落とす（リポジトリを太らせない）。
MOTION_MAX_BYTES = 500 * 1024


def referenced_refs() -> list[str]:
    """docs/tutorial/*.md が埋め込んでいる節を、登場順・重複排除で返す。"""
    refs: list[str] = []
    for doc in sorted(DOCS_DIR.glob("*.md")):
        if doc.name == "README.md":
            continue
        for line in doc.read_text(encoding="utf-8").split("\n"):
            matched = SNIPPET_RE.match(line)
            if matched and matched.group("ref") not in refs:
                refs.append(matched.group("ref"))
    return refs


def image_path_for(ref: str) -> Path:
    part, section = ref.split("/", 1)
    return IMAGES_DIR / part / f"{section}.png"


def motion_path_for(ref: str, kind: str) -> Path:
    """動きの証跡の置き場。静止画 `{節}.png` の隣に並べる。"""
    part, section = ref.split("/", 1)
    suffix = motion_suffix(kind)
    return IMAGES_DIR / part / f"{section}.{suffix}"


def motion_suffix(kind: str) -> str:
    return "webp" if kind == "webp" else "sheet.png"


def staging_path_for(ref: str, kind: str | None = None) -> Path:
    """撮った直後の置き場（アップロード前）。リポジトリには残さない。"""
    part, section = ref.split("/", 1)
    suffix = motion_suffix(kind) if kind else "png"
    return STAGING_DIR / part / f"{section}.{suffix}"


def file_sha256(path: Path) -> str:
    """上げたバイト列の指紋。URL の中身が入れ替わっていないことを後から確かめる。"""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


_GYAZO_TOKEN: list[str] = []


def gyazo_token() -> str:
    """1Password から Gyazo のアクセストークンを 1 度だけ読む。

    `--check` からは決して呼ばない（CI にはトークンが無いため）。
    """
    if _GYAZO_TOKEN:
        return _GYAZO_TOKEN[0]
    if shutil.which("op") is None:
        raise ShotError(
            "1Password CLI（op）が見つからない。画像のアップロードにはトークンが要る。"
            "brew install 1password-cli で入ります"
        )
    result = subprocess.run(
        ["op", "read", GYAZO_TOKEN_REF], capture_output=True, text=True
    )
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
    """Upload API の応答から URL を取り出して検証する（組み立てだけを切り出す）。"""
    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ShotError(f"Gyazo の応答が JSON として読めない: {body[:200]}") from exc
    url = data.get("url")
    if not isinstance(url, str) or not url.startswith(f"https://{GYAZO_HOST}/"):
        raise ShotError(f"Gyazo の応答に想定した URL が無い: {body[:200]}")
    if not url.endswith(expected_suffix):
        # 形式が変換されたら本文の見え方が変わる。黙って進めない。
        raise ShotError(
            f"Gyazo が別の形式で返した（{expected_suffix} を上げたのに {url}）"
        )
    return url


def upload_to_gyazo(path: Path, ref: str) -> str:
    """画像を Gyazo へ上げて URL を返す。

    アセットは不変・追記型なので、既にある URL を差し替えることはしない。
    撮り直しは常に新しい URL になり、古い URL は過去のリビジョンのために残る。
    """
    token = gyazo_token()
    result = subprocess.run(
        [
            "curl", "-sS", "--fail", "--retry", "3", "--retry-delay", "2",
            "-F", f"access_token={token}",
            "-F", f"imagedata=@{path}",
            "-F", f"title=metaphor tutorial {ref}",
            GYAZO_UPLOAD_URL,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        # コマンド列にはトークンが入っているので、決してそのまま出さない。
        raise ShotError(
            f"'{ref}' の {path.name} をアップロードできなかった"
            f"（curl exit {result.returncode}）:\n{result.stderr.strip()[-500:]}"
        )
    return gyazo_url_from_response(result.stdout, path.suffix)


def upload_asset(ref: str, path: Path, recorded: dict | None) -> tuple[str, str]:
    """画像を上げて `(url, sha256)` を返す。中身が同じなら上げ直さない。

    アップロードだけが失敗した直後の再実行を速く済ませるためで、Gyazo 側に同じ絵の
    URL が増えても害は無い（台帳が最新を指していればよい）。
    """
    digest = file_sha256(path)
    if recorded and recorded.get("sha256") == digest and recorded.get("url"):
        return recorded["url"], digest
    return upload_to_gyazo(path, ref), digest


def doc_paths() -> list[Path]:
    """本文のファイル。翻訳（#548）も同じ台帳から書き換えるので最初から見る。"""
    docs = [doc for doc in sorted(DOCS_DIR.glob("*.md")) if doc.name != "README.md"]
    return docs + sorted(DOCS_DIR.glob("en/*.md"))


def doc_image_lines(text: str, doc_name: str) -> dict[str, list[int]]:
    """本文の「どの節のどの行が画像か」を、節の構造から決める（ref -> 行番号）。

    URL の文字列一致ではなく位置で対応づけるのは、途中で中断しても自己修復できる
    ようにするため。文字列置換だと、本文と台帳のどちらが新しいか分からなくなった
    時点で置換のキーを失う。
    """
    sections: list[dict] = []
    current: dict | None = None
    for index, line in enumerate(text.split("\n")):
        if line.startswith("## "):
            current = {"ref": None, "images": [], "line": index + 1}
            sections.append(current)
        matched = SNIPPET_RE.match(line)
        if matched:
            if current is None:
                continue  # 節の外のマーカー。画像の対応づけには使えないので見ない
            ref = matched.group("ref")
            if current["ref"] not in (None, ref):
                raise ShotError(
                    f"{doc_name} {current['line']} 行目の節が 2 つの節を埋め込んでいる"
                    f"（{current['ref']} と {ref}）"
                )
            current["ref"] = ref
        if IMAGE_LINE_RE.match(line):
            if current is None:
                raise ShotError(f"{doc_name} {index + 1} 行目の画像が節の外にある")
            current["images"].append(index)

    lines: dict[str, list[int]] = {}
    for section in sections:
        if not section["images"]:
            continue
        if section["ref"] is None:
            raise ShotError(
                f"{doc_name} {section['line']} 行目の節に画像があるが、"
                "どの節のものか（埋め込みマーカー）が無い"
            )
        if section["ref"] in lines:
            raise ShotError(f"{doc_name} が '{section['ref']}' を 2 つの節で使っている")
        if len(section["images"]) > 2:
            raise ShotError(
                f"{doc_name} の '{section['ref']}' に画像が "
                f"{len(section['images'])} 本ある（静止画と動きの証跡で最大 2 本）"
            )
        lines[section["ref"]] = section["images"]
    return lines


def body_image_targets() -> dict[str, list[tuple[str, list[str]]]]:
    """本文が実際に指している画像。ref -> [(ファイル名, target 列)]。"""
    targets: dict[str, list[tuple[str, list[str]]]] = {}
    for doc in doc_paths():
        text = doc.read_text(encoding="utf-8")
        lines = text.split("\n")
        for ref, indices in doc_image_lines(text, doc.name).items():
            found = [IMAGE_LINE_RE.match(lines[i]).group("target") for i in indices]
            targets.setdefault(ref, []).append((doc.name, found))
    return targets


def expected_targets(entry: dict) -> list[str]:
    """台帳が定める、その節の画像 URL（静止画、動きの証跡の順）。"""
    urls = [entry["url"]]
    motion = entry.get("motion") or {}
    if motion.get("url"):
        urls.append(motion["url"])
    return urls


def rewrite_docs(shots: dict) -> list[Path]:
    """台帳を正として本文の画像 URL を上書きする。書き換えたファイルを返す。

    まだ外部化していない節（台帳に URL が無い）は触らない。移行の途中でも本文が
    壊れないようにするため。
    """
    changed: list[Path] = []
    for doc in doc_paths():
        text = doc.read_text(encoding="utf-8")
        lines = text.split("\n")
        dirty = False
        for ref, indices in doc_image_lines(text, doc.name).items():
            entry = shots.get(ref)
            if not entry or not entry.get("url"):
                continue
            urls = expected_targets(entry)
            if len(indices) != len(urls):
                raise ShotError(
                    f"{doc.name} の '{ref}' は画像行が {len(indices)} 本だが、"
                    f"台帳の画像は {len(urls)} 本"
                    "（本文か motion.json のどちらかを直してください）"
                )
            for index, url in zip(indices, urls):
                matched = IMAGE_LINE_RE.match(lines[index])
                if matched.group("target") == url:
                    continue
                lines[index] = f"{matched.group('head')}{url}{matched.group('tail')}"
                dirty = True
        if dirty:
            doc.write_text("\n".join(lines), encoding="utf-8")
            changed.append(doc)
    return changed


def load_motion_config() -> dict[str, dict]:
    """節ごとの動きの証跡の設定を、既定値で埋めて返す（手で書くファイル）。"""
    if not MOTION_CONFIG.is_file():
        return {}
    try:
        raw = json.loads(MOTION_CONFIG.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ShotError(f"{MOTION_CONFIG.name} が JSON として読めない: {exc}") from exc

    sections = raw.get("sections", {})
    if not isinstance(sections, dict):
        raise ShotError(f"{MOTION_CONFIG.name} の 'sections' はオブジェクトである必要がある")

    config: dict[str, dict] = {}
    for ref, entry in sections.items():
        if not isinstance(entry, dict):
            raise ShotError(f"{MOTION_CONFIG.name} の '{ref}' はオブジェクトである必要がある")
        kind = entry.get("kind")
        if kind not in MOTION_KINDS:
            raise ShotError(
                f"'{ref}' の kind '{kind}' は未対応（{' / '.join(MOTION_KINDS)}）"
            )
        settings = {"kind": kind}
        for name, default in MOTION_DEFAULTS.items():
            value = entry.get(name, default)
            if not isinstance(value, int) or isinstance(value, bool):
                raise ShotError(f"'{ref}' の {name} は整数である必要がある: {value!r}")
            settings[name] = value
        # quality を書くと lossy 固定、書かなければ img2webp の mixed に任せる。
        quality = entry.get("quality")
        if quality is not None and (
            not isinstance(quality, int) or isinstance(quality, bool)
            or not 0 <= quality <= 100
        ):
            raise ShotError(f"'{ref}' の quality は 0..100 の整数である必要がある")
        settings["quality"] = quality

        if not 2 <= settings["frames"] <= MOTION_MAX_FRAMES:
            raise ShotError(
                f"'{ref}' の frames は 2..{MOTION_MAX_FRAMES}"
                f"（Probe の上限）である必要がある: {settings['frames']}"
            )
        if settings["every"] < 1:
            raise ShotError(f"'{ref}' の every は 1 以上である必要がある")
        if not 1 <= settings["fps"] <= 60:
            raise ShotError(f"'{ref}' の fps は 1..60 である必要がある")
        if settings["width"] < 1:
            raise ShotError(f"'{ref}' の width は 1 以上である必要がある")
        config[ref] = settings
    return config


def webp_command(frame_paths: list[Path], output: Path, fps: int, quality) -> list[str]:
    """`img2webp` の引数列。組み立てだけを切り出してテストできるようにする。"""
    delay_ms = max(1, round(1000 / fps))
    command = ["img2webp", "-loop", "0"]
    if quality is None:
        # フレームごとに lossy / lossless を選ばせる。実測ではこれが最小だった。
        command.append("-mixed")
    else:
        command += ["-lossy", "-q", str(quality)]
    command += ["-d", str(delay_ms)]
    command += [str(path) for path in frame_paths]
    command += ["-o", str(output)]
    return command


def no_capture_reason(package_dir: Path, ref: str) -> str | None:
    """節が「撮らない」と申告していれば、その理由を返す（申告が無ければ None）。

    音・カメラ・ML の節は実行環境で絵が変わり、ヘッドレスでは権限も降りない。
    理由を書かせるのは、あとから読む人が「撮り忘れ」と区別できるようにするため。
    """
    path = package_dir / NO_CAPTURE_NAME
    if not path.is_file():
        return None
    reason = " ".join(path.read_text(encoding="utf-8").split())
    if not reason:
        raise ShotError(f"'{ref}' の {NO_CAPTURE_NAME} に撮らない理由が書かれていない")
    return reason


def load_manifest() -> dict:
    if not MANIFEST.is_file():
        return {}
    return json.loads(MANIFEST.read_text(encoding="utf-8")).get("shots", {})


def save_manifest(shots: dict) -> None:
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "comment": (
            "Generated by scripts/generate-tutorial-shots.py. "
            "sourceHash is the fingerprint of the sketch the image was taken from; "
            "url/sha256 are the immutable asset the docs point at (ADR-0010). "
            "Assets are append-only: a retake gets a new URL, old URLs stay alive "
            "so past revisions keep rendering."
        ),
        "shots": dict(sorted(shots.items())),
    }
    MANIFEST.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def capture(ref: str, motion: dict | None = None, recorded: dict | None = None) -> dict:
    """1 節ぶん撮って Gyazo へ上げ、台帳のエントリを返す。

    `motion` を渡すと Probe の連続キャプチャで撮り、静止画に加えて動きの証跡
    （WebP かコンタクトシート）も作る。
    """
    package_dir = CODE_DIR / ref
    if not (package_dir / "Package.swift").is_file():
        raise ShotError(f"'{ref}' に対応する SwiftPM パッケージが無い")

    probe_dir = package_dir / ".metaphor/probe"
    output_dir = probe_dir / "current"
    shutil.rmtree(probe_dir, ignore_errors=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    input_script = load_input_script(package_dir, ref)

    request_id = f"tutorial-shot-{ref}"
    # 入力台本がある節では、まず 1 枚撮らせて「描画ループが回っている」ことを
    # 確かめてから入力を流す（後述）。その下見用のリクエストと本番を id で分ける。
    warmup_id = f"{request_id}-warmup"
    request = {"id": request_id, "label": ref, "scale": 1.0}
    if motion:
        request["frames"] = motion["frames"]
        request["every"] = motion["every"]

    def place_request(payload: dict) -> None:
        tmp = probe_dir / "request.json.tmp"
        tmp.write_text(json.dumps(payload), encoding="utf-8")
        tmp.replace(probe_dir / "request.json")  # 契約点 4: アトミックに置く

    # リクエストは**起動前**に置く。noLoop のスケッチは最初の 1 フレームしか
    # 描かないため、起動後に置いても処理する機会が来ない。
    # 入力台本がある節は、代わりに下見用のリクエストを置く（本番は入力を
    # 流し終えてから。#509）。
    place_request(
        {"id": warmup_id, "label": f"{ref} (warmup)", "scale": 1.0}
        if input_script is not None
        else request
    )

    print(f"  building {ref} ...", flush=True)
    build = subprocess.run(
        ["swift", "build"], cwd=package_dir, capture_output=True, text=True
    )
    if build.returncode != 0:
        raise ShotError(f"'{ref}' のビルドに失敗した:\n{build.stdout}\n{build.stderr}")

    env = dict(os.environ)
    env["METAPHOR_PROBE"] = "1"
    env["METAPHOR_VIEWER"] = "1"  # ヘッドレス（ウィンドウを開かない）

    print(f"  running  {ref} ...", flush=True)
    process = subprocess.Popen(
        ["swift", "run"],
        cwd=package_dir,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    sequence_dir = output_dir / "sequence"
    frame_png = output_dir / "frame.png"
    entry: dict = {}
    ready: dict | None = None

    def fail_if_dead() -> None:
        if process.poll() is None:
            return
        stderr = (process.stderr.read() if process.stderr else "") or ""
        raise ShotError(
            f"'{ref}' が画像を書く前に終了した（exit {process.returncode}）\n{stderr[-2000:]}"
        )

    def wait_for(what: str, poll) -> dict:
        """`poll()` が応答を返すまで待つ（返り値が None の間は待ち続ける）。"""
        deadline = time.monotonic() + CAPTURE_TIMEOUT_SEC
        while time.monotonic() < deadline:
            answer = poll()
            if answer is not None:
                return answer
            fail_if_dead()
            time.sleep(POLL_INTERVAL_SEC)
        raise ShotError(
            f"'{ref}' が {CAPTURE_TIMEOUT_SEC:.0f} 秒以内に {what} を書かなかった"
        )

    try:
        if input_script is not None:
            # 下見の 1 枚を待つ。**描画ループが回り始めてから入力を流す**ため。
            # 起動直後（Metal パイプラインの構築中）に送ったイベントは stdin に
            # 溜まり、最初のフレームでまとめて処理されてしまう（＝軌跡の中間点が
            # 消え、1 フレームに集約された線が 1 本だけ残る）。
            wait_for(f"frame.json（下見 id={warmup_id}）",
                     lambda: current_frame(output_dir, warmup_id))
            print(f"  input    {ref} ({len(input_script)} events) ...", flush=True)
            send_input_script(process, input_script, ref)
            place_request(request)

        if motion:
            # 完了規約: sequence.json が最後に書かれる（CONTRACT.md 契約点 4）。
            ready = wait_for("sequence.json", lambda: sequence_manifest(sequence_dir, request_id))
        else:
            metadata = wait_for("frame.png", lambda: current_frame(output_dir, request_id))
            if not frame_png.is_file():
                # id が一致する frame.json に PNG が伴わないのは失敗応答（契約点 4）。
                warnings = "; ".join(metadata.get("warnings") or []) or "理由の申告なし"
                raise ShotError(f"'{ref}' の撮影が失敗応答を返した: {warnings}")

        still = staging_path_for(ref)
        still.parent.mkdir(parents=True, exist_ok=True)
        if motion:
            entry = collect_sequence(ref, sequence_dir, ready, motion, still)
        else:
            shutil.copyfile(frame_png, still)
            size = metadata.get("size", {})
            entry = {
                "width": size.get("width"),
                "height": size.get("height"),
                "frame": metadata.get("frame"),
            }
    finally:
        if process.stdin is not None and not process.stdin.closed:
            try:
                process.stdin.close()
            except BrokenPipeError:
                pass
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        shutil.rmtree(probe_dir, ignore_errors=True)

    entry = publish(ref, entry, motion, recorded)
    fingerprint = {"sourceHash": source_hash(package_dir)}
    # 指紋はパッケージ配下しか見ないので、ライブラリ本体の変更は拾えない（#586）。
    # せめて「どの実装で撮ったか」を残し、あとから隔たりを数えられるようにする。
    provenance = capture_provenance(REPO_ROOT)
    if provenance:
        fingerprint["provenance"] = provenance
    return {**fingerprint, **entry}


def publish(
    ref: str, entry: dict, motion: dict | None, recorded: dict | None
) -> dict:
    """撮った画像を Gyazo へ上げ、台帳のエントリに URL と指紋を書き入れる。"""
    still = staging_path_for(ref)
    url, digest = upload_asset(ref, still, recorded)
    published = {**entry, "url": url, "sha256": digest}
    if motion:
        path = staging_path_for(ref, motion["kind"])
        motion_url, motion_digest = upload_asset(
            ref, path, (recorded or {}).get("motion")
        )
        published["motion"] = {
            **published["motion"],
            "url": motion_url,
            "sha256": motion_digest,
        }
    retire_local_files(ref)
    return published


def retire_local_files(ref: str) -> None:
    """リポジトリに残っている古い画像を片付ける（実体は Gyazo にある。ADR-0010）。"""
    image_path_for(ref).unlink(missing_ok=True)
    for kind in MOTION_KINDS:
        motion_path_for(ref, kind).unlink(missing_ok=True)


def current_frame(output_dir: Path, request_id: str) -> dict | None:
    """単一フレームの応答が来ていれば `frame.json` の中身を返す。

    consumer 規約（CONTRACT.md 契約点 4）どおり **id 一致**で見る。ファイルの
    有無だけで見ると、下見のリクエストへの応答を本番の応答と取り違える。
    """
    frame_json = output_dir / "frame.json"
    if not frame_json.is_file():
        return None
    try:
        data = json.loads(frame_json.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None  # 書き込み途中を読んだ。次のポーリングで見直す
    if data.get("id") != request_id:
        return None
    return data


def sequence_manifest(sequence_dir: Path, request_id: str) -> dict | None:
    """連続キャプチャが完了していれば `sequence.json` の中身を返す。

    consumer 規約（CONTRACT.md 契約点 4）どおり「manifest が存在し、id が
    リクエストと一致し、frames の数が frameCount と揃っている」で ready と見る。
    """
    manifest = sequence_dir / "sequence.json"
    if not manifest.is_file():
        return None
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None  # 書き込み途中を読んだ。次のポーリングで見直す
    if data.get("id") != request_id:
        return None
    frames = data.get("frames")
    if not isinstance(frames, list) or len(frames) != data.get("frameCount"):
        return None
    return data


def collect_sequence(
    ref: str, sequence_dir: Path, manifest: dict, motion: dict, still: Path
) -> dict:
    """連続キャプチャの出力から、代表静止画と動きの証跡を作る。"""
    frames = [sequence_dir / frame["file"] for frame in manifest["frames"]]
    missing = [path.name for path in frames if not path.is_file()]
    if missing:
        raise ShotError(f"'{ref}' のフレームが欠けている: {', '.join(missing[:3])}")

    # 代表静止画は真ん中のフレーム。動きの節でも本文の頭に 1 枚置けるようにする。
    shutil.copyfile(frames[len(frames) // 2], still)

    output = staging_path_for(ref, motion["kind"])
    output.parent.mkdir(parents=True, exist_ok=True)
    if motion["kind"] == "sheet":
        sheet = manifest.get("contactSheet")
        if not sheet or not (sequence_dir / sheet).is_file():
            raise ShotError(f"'{ref}' のコンタクトシートが出ていない")
        shutil.copyfile(sequence_dir / sheet, output)
    else:
        render_webp(ref, frames, output, motion, manifest)

    size = manifest.get("size", {})
    written = output.stat().st_size
    if written > MOTION_MAX_BYTES:
        output.unlink()
        raise ShotError(
            f"'{ref}' の {output.name} が {written / 1024:.0f}KB で上限"
            f"（{MOTION_MAX_BYTES // 1024}KB）を超えた。"
            "motion.json の width か frames を落としてください"
        )
    # motion の width は「上限の指定」なので、実際に書けた縦横は別に記録する
    # （website がこれを本文へ焼き込む）。
    motion_width, motion_height = image_size(output)
    return {
        "width": size.get("width"),
        "height": size.get("height"),
        "motion": {
            **motion,
            "bytes": written,
            "outputWidth": motion_width,
            "outputHeight": motion_height,
        },
    }


def render_webp(
    ref: str, frames: list[Path], output: Path, motion: dict, manifest: dict
) -> None:
    """連番 PNG からアニメーション WebP を書く。"""
    if shutil.which("img2webp") is None:
        raise ShotError(
            "img2webp が見つからない（動きの証跡の生成に要る）。"
            "brew install webp で入ります"
        )

    source_width = manifest.get("size", {}).get("width") or 0
    work = Path(tempfile.mkdtemp(prefix="tutorial-shots-"))
    try:
        if 0 < motion["width"] < source_width:
            # 上限より大きいときだけ縮める（拡大はしない）。
            scaled = []
            for path in frames:
                target = work / path.name
                run_or_raise(
                    ["sips", "--resampleWidth", str(motion["width"]),
                     str(path), "--out", str(target)],
                    f"'{ref}' のフレーム縮小",
                )
                scaled.append(target)
            frames = scaled
        run_or_raise(
            webp_command(frames, output, motion["fps"], motion["quality"]),
            f"'{ref}' の WebP 生成",
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def run_or_raise(command: list[str], what: str) -> None:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise ShotError(f"{what}に失敗した:\n{result.stdout}\n{result.stderr}")


def motion_settings(entry: dict | None) -> dict | None:
    """比較に使う設定だけを取り出す（file / bytes は撮影結果なので外す）。"""
    if entry is None:
        return None
    keys = ("kind", *MOTION_DEFAULTS.keys(), "quality")
    return {key: entry.get(key) for key in keys}


def check(
    refs: list[str],
    shots: dict,
    motions: dict[str, dict] | None = None,
    body: dict[str, list[tuple[str, list[str]]]] | None = None,
) -> list[str]:
    """撮り直しが要る節を返す（画像が無い / ソースが変わった / 設定が変わった）。

    ネットワークにもトークンにも触れない（CI で走る）。外部化済みの節は本文の URL が
    台帳と揃っているかまで見るが、URL の生死は見ない（週次のワークフローの担当）。
    """
    motions = motions or {}
    if body is None:
        body = body_image_targets()
    stale: list[str] = []
    for ref in refs:
        package_dir = CODE_DIR / ref
        if not (package_dir / "Package.swift").is_file():
            raise ShotError(f"'{ref}' に対応する SwiftPM パッケージが無い")
        recorded = shots.get(ref)
        motion = motions.get(ref)
        if no_capture_reason(package_dir, ref) is not None:
            # 撮らないと申告した節（#544）。動きの証跡との併記は矛盾なので止める。
            if motion is not None:
                raise ShotError(
                    f"'{ref}' は {NO_CAPTURE_NAME} があるのに "
                    f"{MOTION_CONFIG.name} にも登録されている"
                )
            if recorded is not None or image_path_for(ref).is_file() or body.get(ref):
                stale.append(f"{ref}: {NO_CAPTURE_NAME} があるのに画像が残っている")
            continue
        if recorded is None:
            stale.append(f"{ref}: 画像がまだ無い")
            continue
        if not recorded.get("url"):
            stale.append(f"{ref}: 台帳に URL が無い（撮り直して上げ直してください）")
            continue
        stale += external_stale(ref, package_dir, recorded, motion, body)
    return stale


def report_drift(shots: dict, refs: list[str]) -> None:
    """「撮影後に実装が変わっている節がいくつあるか」を要約して伝える（#586）。

    合否には混ぜない。実装が変わっても絵が変わったとは限らず、描画に触るあらゆる
    PR を画像の撮り直しで止めることになるため。
    """
    for line in drift_summary(
        (shots.get(ref) for ref in refs if ref in shots),
        "スケッチと撮影設定",
        REPO_ROOT,
    ):
        print(line)


def external_stale(
    ref: str,
    package_dir: Path,
    recorded: dict,
    motion: dict | None,
    body: dict[str, list[tuple[str, list[str]]]],
) -> list[str]:
    """外部ストレージへ移した節の鮮度（ADR-0010）。台帳と本文だけで判定する。"""
    if recorded.get("sourceHash") != source_hash(package_dir):
        return [f"{ref}: 撮影後にスケッチが変わった"]
    if motion_settings(motion) != motion_settings(recorded.get("motion")):
        return [f"{ref}: motion.json の設定が撮影時と違う"]
    if motion and not (recorded.get("motion") or {}).get("url"):
        return [f"{ref}: 動きの証跡が台帳に無い"]
    urls = expected_targets(recorded)
    references = body.get(ref)
    if not references:
        return [f"{ref}: 台帳にあるが本文が画像を参照していない"]
    return [
        f"{doc_name}: '{ref}' の画像 URL が台帳と違う"
        for doc_name, found in references
        if found != urls
    ]


def migrate_existing(refs: list[str], shots: dict, motions: dict[str, dict]) -> list[str]:
    """リポジトリに残っている画像を、撮り直さずにそのまま外部ストレージへ移す。

    GPU の出力はビット単位で再現しないので、撮り直すと中身の変わらない差分が全節に
    出る。移行では上げ直すだけにして、いまの絵をそのまま引き継ぐ。
    """
    moved: list[str] = []
    for ref in refs:
        recorded = shots.get(ref)
        if recorded is None or recorded.get("url"):
            continue  # 撮っていない節と、移行済みの節は触らない
        still = image_path_for(ref)
        if not still.is_file():
            raise ShotError(
                f"'{ref}' は台帳にあるが画像ファイルが無い（--only で撮り直してください）"
            )
        print(f"migrating {ref}")
        entry = dict(recorded)
        entry["url"], entry["sha256"] = upload_asset(ref, still, recorded)
        motion = motions.get(ref)
        if motion:
            path = motion_path_for(ref, motion["kind"])
            if not path.is_file():
                raise ShotError(f"'{ref}' の動きの証跡（{path.name}）が無い")
            url, digest = upload_asset(ref, path, recorded.get("motion"))
            settings = {
                key: value
                for key, value in (recorded.get("motion") or motion).items()
                if key != "file"  # 実体はもう手元に無いのでファイル名は持たない
            }
            entry["motion"] = {
                **settings,
                "bytes": path.stat().st_size,
                "url": url,
                "sha256": digest,
            }
        shots[ref] = entry
        retire_local_files(ref)
        # 1 節ずつ台帳と本文を確定させる。中断しても済んだ節は整合したまま残る。
        save_manifest(shots)
        rewrite_docs(shots)
        for url in expected_targets(entry):
            print(f"  -> {url}")
        moved.append(ref)
    return moved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="撮らずに鮮度だけ調べる（撮り直しが要れば exit 1）",
    )
    parser.add_argument(
        "--migrate-existing",
        action="store_true",
        help="リポジトリに残っている画像を撮り直さずに外部ストレージへ移す（ADR-0010）",
    )
    parser.add_argument(
        "--only",
        metavar="REF",
        help="この節だけ撮る（例 01-GettingStarted/03-SketchSkeleton）",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="ソースが変わっていない節も撮り直す",
    )
    args = parser.parse_args()

    try:
        refs = referenced_refs()
        if args.only:
            if args.only not in refs:
                print(
                    f"warning: '{args.only}' は docs/tutorial/*.md から参照されていない",
                    file=sys.stderr,
                )
            refs = [args.only]

        shots = load_manifest()
        motions = load_motion_config()
        unknown = sorted(set(motions) - set(referenced_refs()))
        if unknown:
            raise ShotError(
                f"{MOTION_CONFIG.name} が参照されていない節を指している: "
                f"{', '.join(unknown)}"
            )

        if args.migrate_existing:
            moved = migrate_existing(refs, shots, motions)
            if not moved:
                print("OK: リポジトリに残っている画像は無い（全節が外部ストレージ）")
                return 0
            print(f"\n{len(moved)} 節を外部ストレージへ移しました。")
            return 0

        if args.check:
            stale = check(refs, shots, motions)
            if not stale:
                skipped = [r for r in refs if no_capture_reason(CODE_DIR / r, r)]
                aside = f"（うち {len(skipped)} 節は {NO_CAPTURE_NAME} で撮らない）" if skipped else ""
                # 「最新の画像がある」とは書かない。見ているのはスケッチと撮影設定
                # だけで、ライブラリ実装の変更は含まない（#586）。
                print(
                    f"OK: 参照されている {len(refs)} 節すべてで、"
                    f"スケッチと撮影設定は撮影時から変わっていない{aside}"
                )
                report_drift(shots, refs)
                return 0
            print("error: 実行結果画像が古い:", file=sys.stderr)
            for line in stale:
                print(f"  - {line}", file=sys.stderr)
            print(
                "\n  make tutorial-shots で撮り直してコミットしてください"
                "（GPU が要るのでローカルで実行します）",
                file=sys.stderr,
            )
            return 1

        targets = refs if args.force else [r for r in refs if check([r], shots, motions)]
        # 撮らないと申告した節（#544）は撮影対象から外し、以前撮った画像が残って
        # いれば片付ける。--force でも撮らない。
        skipped = [r for r in targets if no_capture_reason(CODE_DIR / r, r)]
        targets = [r for r in targets if r not in skipped]
        for ref in skipped:
            print(f"skipping {ref}（{no_capture_reason(CODE_DIR / ref, ref)}）")
            retire_local_files(ref)
            shots.pop(ref, None)
        if skipped:
            save_manifest(shots)
        if not targets:
            print(
                f"OK: 参照されている {len(refs)} 節すべてで、"
                "スケッチと撮影設定は撮影時から変わっていない"
            )
            report_drift(shots, refs)
            return 0

        for ref in targets:
            print(f"capturing {ref}")
            motion = motions.get(ref)
            shots[ref] = capture(ref, motion, shots.get(ref))
            # 1 節ずつ台帳と本文を確定させる。中断しても済んだ節は整合したまま残る。
            save_manifest(shots)
            rewrite_docs(shots)
            for url in expected_targets(shots[ref]):
                print(f"  -> {url}")
        print(f"\n{len(targets)} 節を撮り直しました。")
    except ShotError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
