#!/usr/bin/env python3
"""スケッチの実行結果画像を撮るスクリプトが共有する部品。

チュートリアル（`generate-tutorial-shots.py`）・Examples
（`generate-example-shots.py`）・DocC リファレンス（`generate-reference-shots.py`）で
共通なのは次のものです。

- **撮影時のソースの指紋**（`source_hash`）— 「コードを変えたのに画像が古い」を
  検出する仕組みの土台。ここを 2 実装持つと、片側だけ検出が弱る（#505）
- **撮影時の来歴**（`capture_provenance` / `drift_summary`）— 指紋が拾えない
  ライブラリ本体の変更を、あとから「撮影後に実装が N 回変わっている」と言うため
  （#586）。リファレンス（`generate-reference-shots.py`）は指紋こそ別実装ですが、
  同じ穴を持つのでここだけは共有します
- **画像の縦横**（`image_size`）— 台帳に実寸を持たせるため
- **入力台本**（`probe-input.jsonl` の読み取りと送出）— マウス・キーボードが要る
  スケッチを撮るための唯一の経路。規約（#509）が 1 つなので実装も 1 つにする（#610）
- **Gyazo への上げ口**（`gyazo_token` / `upload_to_gyazo` ほか）— チュートリアルと
  DocC リファレンスが使う。トークンの読み方という**変わりうる 1 点**を 2 実装持って
  いたせいで、`op read` から `secret-read` へ移すときに片方が取り残された
- **Probe の応答の読み方**（`current_frame` / `sequence_manifest`）と**撮影の骨格**
  （`probe_capture`）— どちらも CONTRACT.md 契約点 4 そのもの。読み方は consumer 規約、
  骨格は producer 側の手順（いつ request を置き、どう待ち、どう後片付けするか）で、
  3 実装あると cli 側が wire format を変えた日に 1 つだけ直る（#1024）

画像の置き場は用途で違います（チュートリアルと DocC リファレンスは Gyazo =
ADR-0010 / ADR-0008、Examples はリポジトリ内）。**上げ口は共通でも、撮り方・台帳・
本文の書き換えは用途ごとに違う**ので、そちらは各スクリプトが持ちます。
"""

from __future__ import annotations

import contextlib
import functools
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from collections.abc import Iterable, Iterator
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


def source_files(package_dir: Path, *, exclude: Iterable[Path] = ()) -> list[Path]:
    """指紋の材料。Swift だけでなくリソースも含める（#505）。

    `exclude` には**このパッケージが生む出力**を渡す（実行結果画像など）。無い
    パスを渡しても害はないので、呼び出し側は置き場を知っていればよい。
    """
    dropped = {path.resolve() for path in exclude}
    files = []
    for path in package_dir.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(package_dir)
        if EXCLUDED_NAMES.intersection(relative.parts):
            continue
        if path.resolve() in dropped:
            continue
        files.append(path)
    return sorted(files, key=lambda p: p.relative_to(package_dir).as_posix())


def source_hash(package_dir: Path, *, exclude: Iterable[Path] = ()) -> str:
    """パッケージのソースとリソースから決まる指紋。撮り直しの要否はこれで判定する。

    絵を変えうるものはすべて材料にする。Swift だけを見ていた頃は、同梱画像や
    シェーダーを差し替えても `--check` が「最新」と答えていた（#505）。

    **材料はパッケージ配下の入力だけ**です。

    - `Package.swift` が path 依存で参照する metaphor 本体（`Sources/`）は入りません。
      ライブラリの実装だけが変わって絵が変わっても、この指紋は動かない（#586）。
      そこは `capture_provenance` が残す来歴で補います
    - **出力も入りません**。実行結果画像をパッケージ直下に置く Examples では、
      黙っていると画像自身が材料に入り、画像を差し替えただけで「ソースが変わった」に
      なってしまう。出力の置き場を知っている呼び出し側が `exclude` で外す（#820）
    """
    digest = hashlib.sha256()
    for path in source_files(package_dir, exclude=exclude):
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


# --- Probe の応答を読む -------------------------------------------------------


def current_frame(output_dir: Path, request_id: str) -> dict | None:
    """単一フレームの応答が来ていれば `frame.json` の中身を返す。

    consumer 規約（CONTRACT.md 契約点 4）どおり **id 一致**で見る。ファイルの有無だけで
    見ると、下見のリクエストへの応答を本番の応答と取り違える。

    これは契約の読み方そのものなので、実装は 1 つでなければならない。3 スクリプトが
    各々持っていた時期があり、cli 側が wire format を変えたときに 1 つだけ直る形に
    なっていた（#1021 で Gyazo のトークンに起きたのと同じ構図）。
    """
    frame_json = output_dir / "frame.json"
    if not frame_json.is_file():
        return None
    try:
        data = json.loads(frame_json.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None  # 書き込み途中を読んだ。次のポーリングで見直す
    return data if data.get("id") == request_id else None


# 撮らない申告（#544）。パッケージ直下に置くと撮影も鮮度検査も飛ばす。
NO_CAPTURE_NAME = "no-capture.txt"


def no_capture_reason(package_dir: Path, ref: str) -> str | None:
    """「撮らない」と申告していれば、その理由を返す（申告が無ければ None）。

    音・カメラ・ML は実行環境で絵が変わり、ヘッドレスでは権限も降りない。理由を
    **書かせる**のは、あとから読む人が「撮り忘れ」と区別できるようにするため。だから
    空の申告は黙って通さず止める（緩く受けると、書き忘れが撮り忘れと同じ顔で残る）。
    """
    path = package_dir / NO_CAPTURE_NAME
    if not path.is_file():
        return None
    reason = " ".join(path.read_text(encoding="utf-8").split())
    if not reason:
        raise ShotError(f"'{ref}' の {NO_CAPTURE_NAME} に撮らない理由が書かれていない")
    return reason


# --- 外部コマンド ---------------------------------------------------------------


def run_capturing(command: list[str], what: str, *, cwd: Path | None = None) -> str:
    """コマンドを走らせ、成功したら stdout を返す。失敗は `ShotError`。

    出力を捨てずに抱えるのは、失敗したときに何が起きたかを添えるため（ビルドの
    エラーは stdout 側に出ることがある）。

    `cwd` を渡せる口があるのは、**どこで走らせるかが結果を変える**コマンドがあるため
    （`swift build` は cwd の Package.swift を見る。省略するとリポジトリ直下の
    metaphor 本体をビルドしてしまい、撮る対象がビルドされないまま素通りする）。
    """
    result = subprocess.run(command, capture_output=True, text=True, cwd=cwd)
    if result.returncode != 0:
        raise ShotError(f"{what}に失敗した:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def run_or_raise(command: list[str], what: str, *, cwd: Path | None = None) -> None:
    """戻り値の要らない `run_capturing`。"""
    run_capturing(command, what, cwd=cwd)


# --- Probe を起動して撮る -------------------------------------------------------
#
# 「probe ディレクトリを掃除して request を置き、起動して、応答を待って、後片付け
# する」という骨格は、3 スクリプトのどれでも同じです。ここは CONTRACT.md 契約点 4 の
# **producer 側の手順**そのもの（いつ request を置くか・完了をどう判定するか・落ちた
# スケッチをどう諦めるか）なので、実装が 3 つあると「片方だけ直る」が起きます（#1024）。
#
# 用途で本当に違うのは骨格ではなく段取り — 下見を挟むか、連番で撮るか、ビルドを
# 自分で持つか — なので、**順番は呼び出し側が書き、契約に触れる操作はこのクラスの
# メソッド越しにだけ行う**形にしています。

# 応答を待つあいだのポーリング間隔。タイムアウトは用途で違う（撮る前にビルドを挟む
# かどうかで妥当な上限が変わる）ので、呼び出し側が渡す。
POLL_INTERVAL_SEC = 0.2
# terminate してから kill に切り替えるまで。
TERMINATE_GRACE_SEC = 10.0


def sequence_manifest(sequence_dir: Path, request_id: str) -> dict | None:
    """連続キャプチャが完了していれば `sequence.json` の中身を返す。

    consumer 規約（CONTRACT.md 契約点 4）どおり「manifest が存在し、id がリクエストと
    一致し、frames の数が frameCount と揃っている」で ready と見る。`current_frame` と
    同じく契約の読み方そのものなので、実装は 1 つでなければならない。
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


class ProbeCapture:
    """Probe を有効にしたスケッチを 1 回走らせて撮る、その 1 回ぶんの持ち物。

    `probe_capture()` から受け取って使う。呼ぶ順は用途ごとに違うが、どの順でも

    1. `place_request()` で撮ってほしいものを置く（**起動前**。理由は下記）
    2. `start()` で走らせる
    3. `wait_still()` / `wait_sequence()` で応答を待つ

    が芯で、動くスケッチはこのあいだに `warmup()` と `send_input()` が挟まる。
    """

    def __init__(
        self,
        *,
        ref: str,
        cwd: Path,
        timeout: float,
        poll_interval: float = POLL_INTERVAL_SEC,
    ) -> None:
        self.ref = ref  # 失敗を伝えるときの呼び名（節・example のパス・シンボル）
        self.cwd = Path(cwd)
        self.timeout = timeout
        self.poll_interval = poll_interval
        self.probe_dir = self.cwd / ".metaphor/probe"
        self.output_dir = self.probe_dir / "current"
        self.sequence_dir = self.output_dir / "sequence"
        self.frame_png = self.output_dir / "frame.png"
        self.process: subprocess.Popen | None = None
        self._requested = False

    # --- 段取り -------------------------------------------------------------

    def prepare(self) -> None:
        """前回の残骸を消して出力先を作る（`probe_capture()` が入口で呼ぶ）。"""
        shutil.rmtree(self.probe_dir, ignore_errors=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def build(self, command: list[str]) -> None:
        """撮る前に、**撮る対象のパッケージで**ビルドする。失敗は出力ごと `ShotError`。

        `cwd` を渡し忘れると `swift build` はリポジトリ直下の metaphor 本体を建てて
        成功し、対象がビルドされないまま `swift run` へ進む（そちらが結局ビルドするので
        絵は出るが、ビルドの失敗がここではなく「起動したのに終了した」として出る）。

        リファレンスのように事前に一括ビルドしてある用途では呼ばない。
        """
        run_or_raise(command, f"'{self.ref}' のビルド", cwd=self.cwd)

    def place_request(self, payload: dict) -> None:
        """撮ってほしいものを置く（契約点 4: tmp へ書いて rename でアトミックに）。"""
        tmp = self.probe_dir / "request.json.tmp"
        tmp.write_text(json.dumps(payload), encoding="utf-8")
        tmp.replace(self.probe_dir / "request.json")
        self._requested = True

    def start(self, command: list[str], *, stdin: bool = False) -> subprocess.Popen:
        """ヘッドレス（`METAPHOR_VIEWER=1`）で Probe つきに走らせる。

        **1 通も置かずに起動することは許さない**。noLoop のスケッチは最初の 1
        フレームしか描かないので起動後に置いても処理する機会が来ず、動くスケッチも
        置くまでに進んだフレーム数が実行ごとに変わって撮り始めの位相がぶれる
        （#784）。順番そのものは呼び出し側が書くので、守れているかはここで見る。

        `stdin` は入力台本を流す経路（#610）。要らない用途では開かない。
        """
        if not self._requested:
            raise ShotError(
                f"'{self.ref}' を request.json を置く前に起動しようとした"
                "（起動後に置くと撮り始めが実行ごとに変わる。#784）"
            )
        env = dict(os.environ)
        env["METAPHOR_PROBE"] = "1"
        env["METAPHOR_VIEWER"] = "1"  # ヘッドレス（ウィンドウを開かない）
        self.process = subprocess.Popen(
            command,
            cwd=self.cwd,
            env=env,
            stdin=subprocess.PIPE if stdin else None,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        return self.process

    # --- 応答を待つ ---------------------------------------------------------

    def _fail_if_dead(self) -> None:
        """走らせたものが死んでいたら、タイムアウトを待たずに理由ごと諦める。"""
        process = self.process
        if process is None or process.poll() is None:
            return
        stderr = (process.stderr.read() if process.stderr else "") or ""
        raise ShotError(
            f"'{self.ref}' が画像を書く前に終了した（exit {process.returncode}）"
            f"\n{stderr[-2000:]}"
        )

    def wait_for(self, what: str, poll) -> dict:
        """`poll()` が応答を返すまで待つ（返り値が None の間は待ち続ける）。"""
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            answer = poll()
            if answer is not None:
                return answer
            self._fail_if_dead()
            time.sleep(self.poll_interval)
        raise ShotError(
            f"'{self.ref}' が {self.timeout:.0f} 秒以内に {what} を書かなかった"
        )

    def warmup(self, request_id: str) -> dict:
        """下見の 1 枚を待つ。**描画ループが回り始めてから**次へ進むため。

        起動直後（Metal パイプラインの構築中）に送った入力は stdin に溜まり、最初の
        フレームでまとめて処理される（＝軌跡の中間点が消え、1 フレームに集約された
        線が 1 本だけ残る）。本番のリクエストを置き直すのもこれを待ってから。
        """
        return self.wait_for(
            f"frame.json（下見 id={request_id}）",
            lambda: current_frame(self.output_dir, request_id),
        )

    def send_input(self, events: list[dict]) -> None:
        """入力台本を流す（`warmup()` を待ってから呼ぶ）。"""
        if self.process is None:
            raise ShotError(f"'{self.ref}' をまだ起動していない（入力を流せない）")
        send_input_script(self.process, events, self.ref)

    def wait_still(self, request_id: str) -> dict:
        """単一フレームの応答を待って `frame.json` の中身を返す。

        id が一致する `frame.json` に PNG が伴わないのは失敗応答（契約点 4）。撮れて
        いないことを黙って進めると、直前の絵を撮ったことにしてしまう。
        """
        metadata = self.wait_for(
            "frame.png", lambda: current_frame(self.output_dir, request_id)
        )
        if not self.frame_png.is_file():
            warnings = "; ".join(metadata.get("warnings") or []) or "理由の申告なし"
            raise ShotError(f"'{self.ref}' の撮影が失敗応答を返した: {warnings}")
        return metadata

    def wait_sequence(self, request_id: str) -> dict:
        """連続キャプチャの完了を待つ（完了規約: `sequence.json` が最後に書かれる）。"""
        return self.wait_for(
            "sequence.json", lambda: sequence_manifest(self.sequence_dir, request_id)
        )

    # --- 後片付け -----------------------------------------------------------

    def close(self) -> None:
        """スケッチを終わらせて probe ディレクトリを消す（成否によらず必ず通る）。"""
        process = self.process
        if process is not None:
            stdin = process.stdin
            if stdin is not None and not stdin.closed:
                try:
                    stdin.close()
                except BrokenPipeError:
                    pass
            process.terminate()
            try:
                process.wait(timeout=TERMINATE_GRACE_SEC)
            except subprocess.TimeoutExpired:
                process.kill()
        shutil.rmtree(self.probe_dir, ignore_errors=True)


@contextlib.contextmanager
def probe_capture(
    *,
    ref: str,
    cwd: Path,
    timeout: float,
    poll_interval: float = POLL_INTERVAL_SEC,
) -> Iterator[ProbeCapture]:
    """撮影 1 回ぶんを囲む。抜けるときに必ずスケッチを終わらせて掃除する。

    掃除を出口 1 か所に集めてあるので、**ビルドに失敗して抜けても** request.json が
    残らない（3 実装あった頃は、ビルド失敗の経路だけ掃除を通らなかった）。
    """
    session = ProbeCapture(
        ref=ref, cwd=cwd, timeout=timeout, poll_interval=poll_interval
    )
    session.prepare()
    try:
        yield session
    finally:
        session.close()


# --- Gyazo -------------------------------------------------------------------
#
# 画像の実体は Gyazo に置き、リポジトリは URL だけを持つ（DocC リファレンスは
# ADR-0008、チュートリアルは ADR-0010）。上げる経路をここ 1 か所に集めているのは、
# **2 実装あると片方だけ直るから**。実際そうなった: トークンの読み口を `op read` から
# `secret-read` へ移したとき、同じ関数のコピーがもう 1 つあることに気付かず、
# チュートリアル側だけが古い読み方のまま残った。

GYAZO_UPLOAD_URL = "https://upload.gyazo.com/api/upload"
GYAZO_HOST = "i.gyazo.com"
# トークンは都度読む（平文の環境変数として常駐させない）。環境変数に持たせてよいのは
# 参照文字列だけで、値ではない。
GYAZO_TOKEN_REF = os.environ.get(
    "GYAZO_TOKEN_REF", "op://Automation/Gyazo API/credential"
)

_GYAZO_TOKEN: list[str] = []


def gyazo_token() -> str:
    """Gyazo のアクセストークンを 1 度だけ読む。

    正本は 1Password で、読み口は `secret-read`（低権限の秘密だけを macOS Keychain へ
    キャッシュするラッパー）。キャッシュが効くので **1Password がロックされていても
    止まらない**。

    `secret-read` が無い環境では `op read` に落ちる。そちらはロック中に承認待ちで
    返らない（実測で 2 分以上ハングした）ので、落ちたことは黙らず 1 度だけ知らせる。

    `--check` / `--compile-only` からは決して呼ばない（CI にトークンは無い）。
    """
    if _GYAZO_TOKEN:
        return _GYAZO_TOKEN[0]

    reader = shutil.which("secret-read")
    if reader is not None:
        command = [reader, GYAZO_TOKEN_REF]
    elif shutil.which("op") is not None:
        print(
            "警告: secret-read が見つからないので op read で読みます"
            "（1Password がロックされていると承認待ちで止まります）。",
            file=sys.stderr,
        )
        command = ["op", "read", GYAZO_TOKEN_REF]
    else:
        raise ShotError(
            "Gyazo のトークンを読む手段が無い。画像のアップロードにはトークンが要ります"
            "（setup リポジトリの bin/ を PATH へ通すか、brew install 1password-cli）"
        )

    result = subprocess.run(command, capture_output=True, text=True)
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
        # 形式が変換されたら本文や DocC での見え方が変わる。黙って進めない。
        raise ShotError(f"Gyazo が別の形式で返した（{expected_suffix} を上げたのに {url}）")
    return url


def file_sha256(path: Path) -> str:
    """上げたバイト列の指紋。URL が指す中身が入れ替わっていないことの確認用。"""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def upload_to_gyazo(path: Path, title: str) -> str:
    """画像を Gyazo へ上げて URL を返す。

    アセットは不変・追記型なので、既にある URL を差し替えることはしない。撮り直しは
    常に新しい URL になり、古い URL は過去のリビジョンのために残る。
    """
    token = gyazo_token()
    result = subprocess.run(
        [
            "curl", "-sS", "--fail", "--retry", "3", "--retry-delay", "2",
            "-F", f"access_token={token}",
            "-F", f"imagedata=@{path}",
            "-F", f"title={title}",
            GYAZO_UPLOAD_URL,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        # コマンド列にはトークンが入っているので、決してそのまま出さない。
        raise ShotError(
            f"'{title}' の {path.name} をアップロードできなかった"
            f"（curl exit {result.returncode}）:\n{result.stderr.strip()[-500:]}"
        )
    return gyazo_url_from_response(result.stdout, path.suffix)
