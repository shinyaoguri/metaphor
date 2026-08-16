#!/usr/bin/env python3
"""スケッチの実行結果画像を撮るスクリプトが共有する部品。

チュートリアル（`generate-tutorial-shots.py`）と Examples
（`generate-example-shots.py`）で共通なのは 4 つです。

- **撮影時のソースの指紋**（`source_hash`）— 「コードを変えたのに画像が古い」を
  検出する仕組みの土台。ここを 2 実装持つと、片側だけ検出が弱る（#505）
- **撮影時の来歴**（`capture_provenance` / `drift_summary`）— 指紋が拾えない
  ライブラリ本体の変更を、あとから「撮影後に実装が N 回変わっている」と言うため
  （#586）。リファレンス（`generate-reference-shots.py`）は指紋こそ別実装ですが、
  同じ穴を持つのでここだけは共有します
- **画像の縦横**（`image_size`）— 台帳に実寸を持たせるため
- **入力台本**（`probe-input.jsonl` の読み取りと送出）— マウス・キーボードが要る
  スケッチを撮るための唯一の経路。規約（#509）が 1 つなので実装も 1 つにする（#610）

画像の置き場は用途で違います（チュートリアルは Gyazo = ADR-0010、Examples は
リポジトリ内）。撮り方・台帳・本文の書き換えも用途ごとに違うので、各スクリプトが
持ちます。
"""

from __future__ import annotations

import functools
import hashlib
import json
import subprocess
import time
from collections.abc import Iterable
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

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
    if data[:6] in (b"GIF87a", b"GIF89a"):  # 論理画面記述子の先頭 4 バイト
        # リファレンス（DocC）の動きは GIF になる。DocC は WebP を無言で落とすため
        # WebP を使えない（ADR-0008）。
        return (
            int.from_bytes(data[6:8], "little"),
            int.from_bytes(data[8:10], "little"),
        )
    raise ShotError(f"{path.name} の縦横を読めない（PNG / WebP / GIF のみ対応）")


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

    **材料はパッケージ配下だけ**で、`Package.swift` が path 依存で参照する
    metaphor 本体（`Sources/`）は入りません。ライブラリの実装だけが変わって絵が
    変わっても、この指紋は動かない（#586）。そこは `capture_provenance` が残す
    来歴で補います。
    """
    digest = hashlib.sha256()
    for path in source_files(package_dir):
        digest.update(path.relative_to(package_dir).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _git(args: list[str], repo_root: Path) -> str | None:
    """リポジトリに対して git を引く。引けなければ None（撮影も検査も止めない）。"""
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:  # git が無い環境（撮影はできるので黙って諦める）
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def capture_provenance(repo_root: Path | None = None) -> dict | None:
    """撮影した実装を指す来歴。`{"commit": "<sha>", "dirty": bool}`。

    指紋（`source_hash` / リファレンスの `snippetHash`）はスケッチ側しか見ないので、
    ライブラリ本体だけが変わって絵が変わっても検出できません（#586）。せめて
    「どの実装で撮ったか」を台帳に残しておけば、あとから「撮影後に `Sources/` が
    N 回変わっている」と言えます。

    `dirty` は撮影時に `Sources/` へ未コミットの変更があったかどうか。撮影は
    ローカルで行うので、直している最中に撮ることは普通にあります。その場合
    commit だけでは実装を特定できないので、そう記録します。

    git が引けなければ None（呼び出し側は台帳に書かない）。
    """
    commit = _git(["rev-parse", "HEAD"], repo_root or REPO_ROOT)
    if not commit:
        return None
    status = _git(["status", "--porcelain", "--", "Sources"], repo_root or REPO_ROOT)
    return {"commit": commit, "dirty": bool(status)}


@functools.lru_cache(maxsize=None)
def implementation_drift(commit: str, repo_root: Path | None = None) -> int | None:
    """撮影時の commit から HEAD までに `Sources/` を触ったコミット数。

    履歴に無い commit（浅い clone、まだ push していないローカル commit、別ブランチ
    で撮ったもの）では数えられないので None を返します。**数えられないことは
    「変わっていない」ではない**ので、呼び出し側は None を「不明」として扱います。
    """
    counted = _git(
        ["rev-list", "--count", f"{commit}..HEAD", "--", "Sources"],
        repo_root or REPO_ROOT,
    )
    if counted is None or not counted.isdigit():
        return None
    return int(counted)


def drift_summary(
    entries: Iterable[dict | None],
    what: str,
    repo_root: Path | None = None,
) -> list[str]:
    """来歴を「撮影後に実装が変わっている点数」の要約に畳む（#586）。

    点ごとに 1 行出すと 300 行を超えてオオカミ少年になるので、要約だけ返します。
    返すのは表示用の行のリストで、`--check` の合否には**混ぜません** — 実装が
    変わっても絵が変わったとは限らず、描画に触るあらゆる PR を画像の撮り直しで
    止めることになるためです。言うことが無ければ空リスト。

    `what` はその検査が実際に見ているもの（「スケッチと撮影設定」など）。保証して
    いない範囲を読む側へ正確に伝えるために、呼び出し側が自分の言葉で渡します。
    """
    total = 0
    unknown = 0
    dirty = 0
    drifted: list[int] = []
    for entry in entries:
        total += 1
        provenance = (entry or {}).get("provenance") or {}
        commit = provenance.get("commit")
        if not commit:
            unknown += 1
            continue
        if provenance.get("dirty"):
            dirty += 1
        count = implementation_drift(commit, repo_root or REPO_ROOT)
        if count is None:
            unknown += 1
        elif count > 0:
            drifted.append(count)

    if not drifted and not unknown and not dirty:
        return []

    # 未コミットの変更があるまま撮ったものは、隔たりが 0 でも撮影時の実装を commit
    # から復元できない。「撮影後に変わっていない」がそのまま「同じ絵になる」を
    # 意味しないので、他に言うことが無くても伝える。
    dirty_part = f"{dirty} 点は Sources/ に未コミットの変更がある状態で撮られている"
    parts = []
    if drifted:
        parts.append(f"{len(drifted)} 点は撮影後に Sources/ が変わっている（最大 {max(drifted)} コミット）")
    if unknown:
        parts.append(f"{unknown} 点は撮影時の来歴が未記録（次に撮り直したときに入る）")
    if dirty and not parts:
        parts.append(dirty_part)
    lines = [f"note: {total} 点中、{'／'.join(parts)}。"]
    if dirty and dirty_part not in parts:
        lines.append(f"      うち {dirty_part}。")
    lines.append(
        f"      この検査が見ているのは {what} だけで、ライブラリ実装の変更は見ていない（#586）。"
    )
    return lines


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
