#!/usr/bin/env python3
"""Examples/Tutorial/** を実際に走らせ、実行結果画像を撮り直す。

各節のスケッチを `METAPHOR_PROBE=1 METAPHOR_VIEWER=1` で起動し、Probe が書く
`.metaphor/probe/current/frame.png` を
`docs/tutorial/images/{部番号}-{部スラッグ}/{節番号}-{節スラッグ}.png` へ配置する。
手で撮ったスクリーンショットは置かない（Issue #486 / docs/tutorial/README.md）。

    make tutorial-shots                     # 参照されている全節を撮り直す
    make tutorial-shots ARGS="--only 01-GettingStarted/03-SketchSkeleton"
    python3 scripts/generate-tutorial-shots.py --check   # 鮮度だけ調べる

## 動きが要る節（#507）

イージング・パーティクル・入力のように**静止画では正誤を判定できない**節は、
`docs/tutorial/images/motion.json` に登録すると Probe の連続キャプチャ
（CONTRACT.md 契約点 4 の `frames >= 2`）で撮り、静止画に加えて

- `kind: "webp"` — アニメーション WebP `{節}.webp`（`img2webp` が要る）
- `kind: "sheet"` — コンタクトシート `{節}.sheet.png`（Probe が合成したもの）

を置く。GIF ではなく WebP なのは、同じ絵で 1 桁小さく、`![](...)` のまま
GitHub でも website でも動くため。mp4 は GitHub の Markdown が相対パスの
動画を再生しないので採らない。

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

## なぜ PNG のバイト比較で鮮度を見ないか

GPU レンダリングの出力は環境（GPU・ドライバ・OS）でビット単位には一致しない。
撮り直すたびに差分が出るので、`--check` は画像そのものではなく
`docs/tutorial/images/manifest.json` に記録した**撮影時のソースのハッシュ**と
現在のソースを突き合わせる。これで「コードを変えたのに画像を撮り直していない」
という実際に起きるドリフトだけを、GPU の無い CI ランナーでも検出できる。

撮影自体はローカルで行いコミットする（CI では走らせない）。
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

REPO_ROOT = Path(__file__).resolve().parent.parent
CODE_DIR = REPO_ROOT / "Examples/Tutorial"
DOCS_DIR = REPO_ROOT / "docs/tutorial"
IMAGES_DIR = DOCS_DIR / "images"
MANIFEST = IMAGES_DIR / "manifest.json"
# 動きの証跡が要る節の設定（手書きの正典。manifest.json は生成物なので分ける）。
MOTION_CONFIG = IMAGES_DIR / "motion.json"

# 埋め込みマーカー（generate-tutorial-snippets.py と同じ書式）。本文が参照して
# いる節 = 画像が要る節、と定義する。
SNIPPET_RE = re.compile(r"^<!-- tutorial-snippet:\s*(?P<ref>\S+)\s*-->$")

# 指紋の材料から外すもの。ビルド生成物・IDE 設定・Probe の作業ディレクトリ・
# Finder のメタデータで、いずれも絵には影響しない（すべて gitignore 済み）。
EXCLUDED_NAMES = {".build", ".swiftpm", ".metaphor", ".DS_Store"}

# 起動から frame.png が書かれるまでの待ち時間。初回はシェーダーのコンパイルが
# 入るぶん遅い。
CAPTURE_TIMEOUT_SEC = 90.0
POLL_INTERVAL_SEC = 0.2

# 撮影用の入力台本（#509）。パッケージ直下に置くと起動後に stdin へ流す。
INPUT_SCRIPT_NAME = "probe-input.jsonl"
# 撮らない節の申告（#544）。パッケージ直下に置くと撮影も鮮度検査も飛ばす。
NO_CAPTURE_NAME = "no-capture.txt"
# 1 行送るごとに空ける間隔。60fps の 2 フレームぶん空けて、1 フレームに複数の
# イベントがまとめて届く（＝軌跡の中間点が失われる）のを避ける。
INPUT_INTERVAL_SEC = 0.033
# 最後のイベントが描画に反映されるまでの猶予。この後に request.json を置く。
INPUT_SETTLE_SEC = 0.6
# 下見の 1 枚が撮れてから流し始めるまでの間。フレームレートが落ち着くのを待つ。
INPUT_LEAD_SEC = 0.3

# 動きの証跡の既定値と上限（docs/tutorial/README.md の規約と対）。
MOTION_KINDS = ("webp", "sheet")
MOTION_MAX_FRAMES = 64  # Probe 側のクランプ上限（CONTRACT.md 契約点 4）
MOTION_DEFAULTS = {"frames": MOTION_MAX_FRAMES, "every": 4, "fps": 15, "width": 720}
# 1 ファイルの上限。超えたら幅かフレーム数を落とす（リポジトリを太らせない）。
MOTION_MAX_BYTES = 500 * 1024


class ShotError(Exception):
    """撮影も検証もできない構成（利用者が直す必要がある）。"""


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


def source_files(package_dir: Path) -> list[Path]:
    """指紋の材料。Swift だけでなくリソースも含める（#505）。"""
    files = []
    for path in package_dir.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(package_dir)
        if EXCLUDED_NAMES.intersection(relative.parts):
            continue
        files.append(path)
    return sorted(files, key=lambda p: p.relative_to(package_dir).as_posix())


def source_hash(package_dir: Path) -> str:
    """パッケージのソースとリソースから決まる指紋。撮り直しの要否はこれで判定する。

    絵を変えうるものはすべて材料にする。Swift だけを見ていた頃は、同梱画像や
    シェーダーを差し替えても `--check` が「最新」と答えていた（#505）。
    """
    digest = hashlib.sha256()
    for path in source_files(package_dir):
        digest.update(path.relative_to(package_dir).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def image_path_for(ref: str) -> Path:
    part, section = ref.split("/", 1)
    return IMAGES_DIR / part / f"{section}.png"


def motion_path_for(ref: str, kind: str) -> Path:
    """動きの証跡の置き場。静止画 `{節}.png` の隣に並べる。"""
    part, section = ref.split("/", 1)
    suffix = "webp" if kind == "webp" else "sheet.png"
    return IMAGES_DIR / part / f"{section}.{suffix}"


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


def parse_input_script(text: str, ref: str) -> list[dict]:
    """撮影用の入力台本を、送る順のイベント列に直す。

    `t` を持つ行は stdin へ送るイベント、`wait` だけの行は待ち時間。`//` の行と
    空行は台本に意図を書くためのもので読み飛ばす。
    """
    events: list[dict] = []
    for number, raw in enumerate(text.split("\n"), start=1):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ShotError(
                f"'{ref}' の {INPUT_SCRIPT_NAME} {number} 行目が JSON として読めない: {exc}"
            ) from exc
        if not isinstance(event, dict):
            raise ShotError(
                f"'{ref}' の {INPUT_SCRIPT_NAME} {number} 行目はオブジェクトである必要がある"
            )
        if "t" in event:
            events.append(event)
            continue
        wait = event.get("wait")
        if not isinstance(wait, (int, float)) or isinstance(wait, bool) or wait < 0:
            raise ShotError(
                f"'{ref}' の {INPUT_SCRIPT_NAME} {number} 行目は 't' か "
                f"'wait'（0 以上のミリ秒）を持つ必要がある: {line}"
            )
        events.append({"wait": wait})
    if not events:
        raise ShotError(f"'{ref}' の {INPUT_SCRIPT_NAME} にイベントが 1 つも無い")
    return events


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


def load_input_script(package_dir: Path, ref: str) -> list[dict] | None:
    """節に入力台本があれば読む（無ければ None）。"""
    path = package_dir / INPUT_SCRIPT_NAME
    if not path.is_file():
        return None
    return parse_input_script(path.read_text(encoding="utf-8"), ref)


def send_input_script(process: subprocess.Popen, events: list[dict], ref: str) -> None:
    """台本を stdin へ流す。流し終えるまで戻らない。"""
    stdin = process.stdin
    if stdin is None:  # 呼び出し側が PIPE で開いていない（起こらないはず）
        raise ShotError(f"'{ref}' の stdin が開いていない")
    time.sleep(INPUT_LEAD_SEC)
    for event in events:
        if process.poll() is not None:
            raise ShotError(f"'{ref}' が入力の途中で終了した（exit {process.returncode}）")
        if "wait" in event:
            time.sleep(event["wait"] / 1000)
            continue
        try:
            stdin.write(json.dumps(event) + "\n")
            stdin.flush()
        except BrokenPipeError as exc:
            raise ShotError(f"'{ref}' が stdin を閉じた（入力を受け取れていない）") from exc
        time.sleep(INPUT_INTERVAL_SEC)
    time.sleep(INPUT_SETTLE_SEC)


def load_manifest() -> dict:
    if not MANIFEST.is_file():
        return {}
    return json.loads(MANIFEST.read_text(encoding="utf-8")).get("shots", {})


def save_manifest(shots: dict) -> None:
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "comment": (
            "Generated by scripts/generate-tutorial-shots.py. "
            "sourceHash is the fingerprint of the sketch the image was taken from."
        ),
        "shots": dict(sorted(shots.items())),
    }
    MANIFEST.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def capture(ref: str, motion: dict | None = None) -> dict:
    """1 節ぶん撮る。撮れた画像の manifest エントリを返す。

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

        destination = image_path_for(ref)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if motion:
            entry = collect_sequence(ref, sequence_dir, ready, motion, destination)
        else:
            shutil.copyfile(frame_png, destination)
            # motion.json から外された節の古い証跡を残さない。
            for kind in MOTION_KINDS:
                motion_path_for(ref, kind).unlink(missing_ok=True)
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

    return {"sourceHash": source_hash(package_dir), **entry}


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

    output = motion_path_for(ref, motion["kind"])
    # kind を切り替えたときに前の形式のファイルを置き去りにしない。
    for kind in MOTION_KINDS:
        if kind != motion["kind"]:
            motion_path_for(ref, kind).unlink(missing_ok=True)
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
    return {
        "width": size.get("width"),
        "height": size.get("height"),
        "motion": {**motion, "file": output.name, "bytes": written},
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


def check(refs: list[str], shots: dict, motions: dict[str, dict] | None = None) -> list[str]:
    """撮り直しが要る節を返す（画像が無い / ソースが変わった / 設定が変わった）。"""
    motions = motions or {}
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
            if recorded is not None or image_path_for(ref).is_file():
                stale.append(f"{ref}: {NO_CAPTURE_NAME} があるのに画像が残っている")
            continue
        if recorded is None:
            stale.append(f"{ref}: 画像がまだ無い")
            continue
        if not image_path_for(ref).is_file():
            stale.append(f"{ref}: manifest にあるが画像ファイルが無い")
            continue
        if recorded.get("sourceHash") != source_hash(package_dir):
            stale.append(f"{ref}: 撮影後にスケッチが変わった")
            continue
        recorded_motion = recorded.get("motion")
        if motion_settings(motion) != motion_settings(recorded_motion):
            stale.append(f"{ref}: motion.json の設定が撮影時と違う")
        elif motion and not motion_path_for(ref, motion["kind"]).is_file():
            stale.append(f"{ref}: 動きの証跡のファイルが無い")
    return stale


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="撮らずに鮮度だけ調べる（撮り直しが要れば exit 1）",
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

        if args.check:
            stale = check(refs, shots, motions)
            if not stale:
                skipped = [r for r in refs if no_capture_reason(CODE_DIR / r, r)]
                aside = f"（うち {len(skipped)} 節は {NO_CAPTURE_NAME} で撮らない）" if skipped else ""
                print(f"OK: 参照されている {len(refs)} 節すべてに最新の画像がある{aside}")
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
            image_path_for(ref).unlink(missing_ok=True)
            for kind in MOTION_KINDS:
                motion_path_for(ref, kind).unlink(missing_ok=True)
            shots.pop(ref, None)
        if skipped:
            save_manifest(shots)
        if not targets:
            print(f"OK: 参照されている {len(refs)} 節すべてに最新の画像がある")
            return 0

        for ref in targets:
            print(f"capturing {ref}")
            motion = motions.get(ref)
            shots[ref] = capture(ref, motion)
            print(f"  -> {image_path_for(ref).relative_to(REPO_ROOT)}")
            if motion:
                path = motion_path_for(ref, motion["kind"])
                size = path.stat().st_size / 1024
                print(f"  -> {path.relative_to(REPO_ROOT)} ({size:.0f}KB)")
        save_manifest(shots)
        print(f"\n{len(targets)} 節を撮り直しました。")
    except ShotError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
