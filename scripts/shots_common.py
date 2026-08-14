#!/usr/bin/env python3
"""スケッチの実行結果画像を撮るスクリプトが共有する部品。

チュートリアル（`generate-tutorial-shots.py`）と Examples
（`generate-example-shots.py`）で共通なのは 3 つです。

- **撮影時のソースの指紋**（`source_hash`）— 「コードを変えたのに画像が古い」を
  検出する仕組みの土台。ここを 2 実装持つと、片側だけ検出が弱る（#505）
- **画像の縦横**（`image_size`）— 台帳に実寸を持たせるため
- **入力台本**（`probe-input.jsonl` の読み取りと送出）— マウス・キーボードが要る
  スケッチを撮るための唯一の経路。規約（#509）が 1 つなので実装も 1 つにする（#610）

画像の置き場は用途で違います（チュートリアルは Gyazo = ADR-0010、Examples は
リポジトリ内）。撮り方・台帳・本文の書き換えも用途ごとに違うので、各スクリプトが
持ちます。
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import time
from pathlib import Path

# 指紋の材料から外すもの。ビルド生成物・IDE 設定・Probe の作業ディレクトリ・
# Finder のメタデータで、いずれも絵には影響しない（すべて gitignore 済み）。
EXCLUDED_NAMES = {".build", ".swiftpm", ".metaphor", ".DS_Store"}

# 撮影用の入力台本（#509）。パッケージ直下に置くと起動後に stdin へ流す。
INPUT_SCRIPT_NAME = "probe-input.jsonl"
# 1 行送るごとに空ける間隔。60fps の 2 フレームぶん空けて、1 フレームに複数の
# イベントがまとめて届く（＝軌跡の中間点が失われる）のを避ける。
INPUT_INTERVAL_SEC = 0.033
# 最後のイベントが描画に反映されるまでの猶予。この後に request.json を置く。
INPUT_SETTLE_SEC = 0.6
# 下見の 1 枚が撮れてから流し始めるまでの間。フレームレートが落ち着くのを待つ。
INPUT_LEAD_SEC = 0.3


class ShotError(Exception):
    """撮影も検証もできない構成（利用者が直す必要がある）。"""


def image_size(path: Path) -> tuple[int, int]:
    """画像の縦横を、ヘッダだけ読んで返す（PNG / WebP）。

    台帳に実寸を持たせるためのもの。チュートリアルでは website がこれを本文へ
    焼き込み、Astro が寸法を知るために毎ビルド全点へフェッチを飛ばすのを止める
    （ADR-0010 の Follow-up）。外部コマンドにも追加の依存にも頼らないので、撮影と
    同じ経路で確実に得られる。
    """
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        return (
            int.from_bytes(data[16:20], "big"),
            int.from_bytes(data[20:24], "big"),
        )
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        chunk, payload = data[12:16], data[20:]
        if chunk == b"VP8X":  # 拡張形式（アニメーションはこれ）。canvas は 1 始まり
            return (
                int.from_bytes(payload[4:7], "little") + 1,
                int.from_bytes(payload[7:10], "little") + 1,
            )
        if chunk == b"VP8 ":  # lossy。キーフレームヘッダの 14 bit ずつ
            return (
                int.from_bytes(payload[6:8], "little") & 0x3FFF,
                int.from_bytes(payload[8:10], "little") & 0x3FFF,
            )
        if chunk == b"VP8L":  # lossless。signature の次に 14 bit ずつ（1 始まり）
            bits = int.from_bytes(payload[1:5], "little")
            return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
    raise ShotError(f"{path.name} の縦横を読めない（PNG / WebP のみ対応）")


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


def load_input_script(package_dir: Path, ref: str) -> list[dict] | None:
    """パッケージに入力台本があれば読む（無ければ None）。"""
    path = package_dir / INPUT_SCRIPT_NAME
    if not path.is_file():
        return None
    return parse_input_script(path.read_text(encoding="utf-8"), ref)


def send_input_script(process: subprocess.Popen, events: list[dict], ref: str) -> None:
    """台本を stdin へ流す。流し終えるまで戻らない。

    受け側はヘッドレス起動（`METAPHOR_VIEWER=1`）で自動登録される
    `InputInjectionPlugin`（CONTRACT.md 契約点 3）。呼ぶ前に**描画ループが回って
    いること**を確かめておく（起動直後に送ると stdin に溜まり、最初のフレームで
    まとめて処理されて軌跡の中間点が消える）。
    """
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
