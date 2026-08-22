#!/usr/bin/env python3
"""Examples/** を実際に走らせ、実行結果画像を撮る。

各 example を `METAPHOR_PROBE=1 METAPHOR_VIEWER=1` で起動し、Probe が書く
`.metaphor/probe/current/frame.png` を `Examples/<...>/<Name>.png` へ置く。
台帳は `docs/ai/examples-shots.json`。

    make example-shots                          # 画像がまだ無い example を撮る
    make example-shots ARGS="--only Examples/Topics/Vectors"
    make example-shots ARGS="--compare --only Examples/Basics/Form"
    make example-shots ARGS="--check"           # 鮮度だけ調べる（撮影しない）

## 画像はリポジトリに置く（チュートリアルと違うところ）

チュートリアルの画像は Gyazo へ出した（ADR-0010）。あちらは本文の点数が多く、website の
ビルドに直結するため。Examples のスクリーンショットは**開発者と AI エージェントがその場で
見られること**のほうが効くので、`Examples/<...>/<Name>.png` に置いたままにする。撮影は
640x360 前後なので、原典由来の 1280x720（平均 115 KiB）より軽い。

## 2 つの出所（origin）

台帳の各エントリは `origin` を持つ。

- `processing` — Processing 原典から移植初日に持ち込んだ 162 枚（コミット a7a7a4b）。
  **metaphor が描いた絵ではない**ので鮮度判定の対象外。撮影時のソースが分からず、
  指紋を持てないため（#501）
- `captured` — このスクリプトが撮ったもの。`sourceHash` を持ち、`--check` が
  「コードを変えたのに画像が古い」を検出する

既定では**画像がまだ無い example だけ**を撮る。原典由来の絵は人が選んだ良い瞬間で、
機械が撮った任意の 1 枚より強いことが多いため、一括では置き換えない。個別に差し替える
ときは `--only` で対象を絞って `--force` を付ける。

## 撮り方の既定 —「絵が完成してから撮る」

1 フレーム目は真っ黒・初期姿勢になる example が多い（#501 の実測で Koch と
LoadDisplayOBJ は contentFraction 0、Flocking は 0.001）。そこで:

- ソースに `noLoop()` がある → 起動**前**に `request.json` を置いて 1 枚撮る。
  起動後に置いても、描くのは最初の 1 フレームだけなので処理する機会が来ない
- 無い（動く example） → まず**下見**のリクエストで描画ループが回ったことを確かめ、
  少し待ってから**本番**のリクエストを置く。第 6 部（#543）で GPU の節に使った手と同じ

待ち時間の既定は `SETTLE_SEC`。足りない example は
`docs/ai/examples-shots.config.json` に `{"<パス>": {"settle": 秒}}` で書く
（台帳は生成物なので、手書きの設定とは分ける）。

## release ビルドで撮る example（#727）

撮影は既定で debug ビルド。**画面に fps を出す example だけ**は同じ設定ファイルに
`{"release": true}` を書いて `swift build -c release` / `swift run -c release` で撮る。
debug の数字を焼くと、利用者が `swift run -c release` で見る数字と別物になるため
（`Examples/Demos/Performance/**` の HUD は 3 秒ごとにしか更新しないので、`settle` も
あわせて 3 秒超にする）。全 262 本を release にはしない — 1 本あたり +17 秒（実測
26.3 秒 vs 9.1 秒）で、全体では 1 時間以上増えるのに、絵の確認には効かない。

## 入力が要る example（#509 / #610）

マウス・キーボードで絵が決まる example は、入力が無いと「原点 = 画面左上に描かれた
見切れた絵」しか撮れない。パッケージ直下に `probe-input.jsonl`（JSON Lines）を置くと、
下見のあとに**その内容を stdin へ流してから**本番の 1 枚を撮る。ヘッドレス起動では
`InputInjectionPlugin` が自動登録され、stdin の入力イベント（CONTRACT.md 契約点 3）を
受け取るので、cli を挟まずに入力を再現できる。書式と送り方はチュートリアル側と同じ
（`shots_common.parse_input_script`、規約は docs/tutorial/README.md）。

待ち時間は台本の `{"wait": ミリ秒}` が持つ（`settle` は使わない）。入力を流し終えてから
撮るので、撮り直しても同じ絵になる。代わりに `noLoop()` のスケッチとは両立しない
（起動後に置いた request を処理する機会が来ない）ので、両方あるときはエラーにする。

## 撮らない example

- パッケージ直下に `no-capture.txt` があるもの（#544 と同じ規約。理由を 1 行書く）
- 索引の `status` が `supported` でないもの（stub / obsolete）

## なぜ画像のバイト比較で鮮度を見ないか

GPU レンダリングの出力は環境（GPU・ドライバ・OS）でビット単位には一致しない。撮り直す
たびに差分が出るので、`--check` は画像そのものではなく**撮影時のソースの指紋**と現在の
ソースを突き合わせる（`source_fingerprint`）。これで GPU の無い CI ランナーでも判定できる。

指紋の材料は**入力だけ**で、出力（`<Name>.png`）は外す。画像はパッケージ直下に置くので、
そのまま採ると出力が入力の指紋に混ざり、画像を差し替えただけで「ソースが変わった」と
報告してしまう（#820）。
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shots_common import (  # noqa: E402
    INPUT_SCRIPT_NAME,
    ShotError,
    capture_provenance,
    drift_summary,
    image_size,
    load_input_script,
    no_capture_reason,
    probe_capture,
    source_hash,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
EXAMPLES_DIR = REPO_ROOT / "Examples"
INDEX = REPO_ROOT / "docs/ai/examples-index.json"
MANIFEST = REPO_ROOT / "docs/ai/examples-shots.json"
# 撮り方の例外（手書きの正典。台帳は生成物なので分ける）。
CONFIG = REPO_ROOT / "docs/ai/examples-shots.config.json"
# 突き合わせ（--compare）の出力。リポジトリには残さない。
COMPARE_DIR = REPO_ROOT / ".build/example-shots"

ORIGIN_PROCESSING = "processing"
ORIGIN_CAPTURED = "captured"

# 起動から frame.png が書かれるまでの待ち時間。初回はシェーダーのコンパイルが入る。
CAPTURE_TIMEOUT_SEC = 120.0
POLL_INTERVAL_SEC = 0.2
# 下見の 1 枚が撮れてから本番のリクエストを置くまでの間（= 絵が出来上がるのを待つ）。
SETTLE_SEC = 1.5

# 撮らない申告（#544）。パッケージ直下に置く（入力台本 INPUT_SCRIPT_NAME は
# shots_common が持つ。撮らない申告ではなく「こう撮る」という指定なので分ける）。

# `noLoop()` の呼び出し。コメント行は数えない（絵が止まるかどうかの判定なので、
# 実際に呼んでいる行だけを見る）。
NO_LOOP_RE = re.compile(r"^[^/]*\bnoLoop\s*\(", re.MULTILINE)

# 突き合わせシートの体裁（1 セル = 原典を上・実撮影を下に縦並び）。
COMPARE_CELL = (400, 225)
COMPARE_TILE = (3, 2)


def load_index() -> list[dict]:
    """索引（生成物）から、撮影対象になりうる example を返す。"""
    if not INDEX.is_file():
        raise ShotError(f"{INDEX.relative_to(REPO_ROOT)} が無い。make examples-index を先に")
    data = json.loads(INDEX.read_text(encoding="utf-8"))
    entries = [
        entry
        for entry in data.get("examples", [])
        # Tutorial は generate-tutorial-shots.py の持ち場。stub / obsolete は撮らない。
        if entry.get("status") == "supported"
        and not entry.get("path", "").startswith("Examples/Tutorial/")
    ]
    return sorted(entries, key=lambda e: e["path"])


def package_dir_for(path: str) -> Path:
    return REPO_ROOT / path


def image_path_for(path: str) -> Path:
    """実行結果画像の置き場。既存の 162 枚と同じ `<ディレクトリ名>.png`。"""
    package = package_dir_for(path)
    return package / f"{package.name}.png"


def source_fingerprint(path: str) -> str:
    """撮影時のソースの指紋。

    実行結果画像はパッケージ直下（`image_path_for`）に置くので、そのまま指紋を採ると
    **出力が入力の指紋に混ざる**。画像だけを差し替えただけで `--check` が
    「ソースが変わった」と言い出すので、材料から外す（#820）。
    """
    return source_hash(package_dir_for(path), exclude=[image_path_for(path)])



def uses_no_loop(package: Path) -> bool:
    """スケッチが `noLoop()` を呼ぶか。撮り方（下見が要るか）がこれで決まる。"""
    for source in sorted(package.rglob("*.swift")):
        if ".build" in source.parts:
            continue
        if NO_LOOP_RE.search(source.read_text(encoding="utf-8", errors="ignore")):
            return True
    return False


def input_script_for(package: Path, path: str, still: bool) -> list[dict] | None:
    """入力台本があれば読む（#509 / #610）。無ければ None。

    `noLoop()` のスケッチとは両立しない。入力は起動後に流すが、止まったスケッチには
    その後の request を処理する機会が来ないため、黙って入力なしで撮る代わりに落とす。
    """
    events = load_input_script(package, path)
    if events is not None and still:
        raise ShotError(
            f"'{path}' は {INPUT_SCRIPT_NAME} と noLoop() の両方を持つ（両立しない）。"
            "入力は起動後に流すが、止まったスケッチはその後の request を処理しない"
        )
    return events


def load_config() -> dict[str, dict]:
    """撮り方の例外（手書き）。無ければ空。"""
    if not CONFIG.is_file():
        return {}
    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    settings = data.get("settings", data)
    if not isinstance(settings, dict):
        raise ShotError(f"{CONFIG.name} は {{パス: {{settle: 秒}}}} の形で書く")
    return settings


def settle_for(path: str, config: dict[str, dict]) -> float:
    entry = config.get(path) or {}
    settle = entry.get("settle", SETTLE_SEC)
    if not isinstance(settle, (int, float)) or settle < 0:
        raise ShotError(f"{CONFIG.name} の '{path}' の settle が数値でない: {settle!r}")
    return float(settle)


def release_for(path: str, config: dict[str, dict]) -> bool:
    """release ビルドで撮る申告があるか（既定は debug / #727）。"""
    entry = config.get(path) or {}
    release = entry.get("release", False)
    # "yes" や 1 を真と読むと、申告したつもりが黙って debug のままになる。
    if not isinstance(release, bool):
        raise ShotError(f"{CONFIG.name} の '{path}' の release が true/false でない: {release!r}")
    return release


def swift_command(verb: str, release: bool) -> list[str]:
    """`swift build` / `swift run` のコマンド列。

    申告があれば**両方**に `-c release` を渡す。ビルドだけ release にしても、
    走らせるのが debug バイナリなら画面の数字は変わらない。
    """
    return ["swift", verb, *(["-c", "release"] if release else [])]


def load_manifest() -> dict:
    if not MANIFEST.is_file():
        return {}
    return json.loads(MANIFEST.read_text(encoding="utf-8")).get("shots", {})


def save_manifest(shots: dict) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(
        json.dumps(
            {
                "comment": (
                    "Generated by scripts/generate-example-shots.py. "
                    "origin=processing は Processing 原典から持ち込んだ画像で鮮度判定の対象外、"
                    "origin=captured はこのスクリプトが撮ったもので sourceHash を持つ。"
                ),
                "shots": {path: shots[path] for path in sorted(shots)},
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def adopted(entries: list[dict], shots: dict) -> dict:
    """台帳を実態に合わせた写しを返す（保存はしない）。

    - 画像があるのに台帳に無い → 原典由来（`processing`）として迎え入れる
    - 台帳にあるのに画像が無い → 落とす
    """
    updated = {path: dict(entry) for path, entry in shots.items()}
    known = {entry["path"] for entry in entries}
    for entry in entries:
        path = entry["path"]
        image = image_path_for(path)
        if image.is_file() and path not in updated:
            width, height = image_size(image)
            updated[path] = {
                "origin": ORIGIN_PROCESSING,
                "width": width,
                "height": height,
            }
        elif not image.is_file() and path in updated:
            del updated[path]
    for path in list(updated):
        if path not in known:
            del updated[path]
    return updated


def stale_entries(entries: list[dict], shots: dict) -> list[str]:
    """撮り直しが要るものを、理由つきで返す（origin=captured だけが対象）。"""
    stale = []
    for entry in entries:
        path = entry["path"]
        recorded = shots.get(path)
        if not recorded or recorded.get("origin") != ORIGIN_CAPTURED:
            continue
        package = package_dir_for(path)
        if no_capture_reason(package, path):
            continue
        if not image_path_for(path).is_file():
            stale.append(f"{path}（画像が無い）")
        elif recorded.get("sourceHash") != source_fingerprint(path):
            stale.append(f"{path}（撮影後にソースが変わった）")
    return stale



def capture(path: str, destination: Path, settle: float, release: bool = False) -> dict:
    """example を 1 本撮って、台帳のエントリを返す。"""
    package = package_dir_for(path)
    if not (package / "Package.swift").is_file():
        raise ShotError(f"'{path}' に Package.swift が無い")

    request_id = f"example-shot-{package.name}"
    warmup_id = f"{request_id}-warmup"
    request = {"id": request_id, "label": package.name, "scale": 1.0}
    still = uses_no_loop(package)
    input_script = input_script_for(package, path, still)

    with probe_capture(
        ref=path,
        cwd=package,
        timeout=CAPTURE_TIMEOUT_SEC,
        poll_interval=POLL_INTERVAL_SEC,
    ) as probe:
        # noLoop のスケッチは起動前に置いた 1 通しか処理できない。動くスケッチは
        # 下見を先に置き、絵が出来上がってから本番を置く。
        probe.place_request(
            request
            if still
            else {"id": warmup_id, "label": f"{package.name} (warmup)", "scale": 1.0}
        )
        probe.build(swift_command("build", release))
        probe.start(swift_command("run", release), stdin=True)

        if not still:
            probe.warmup(warmup_id)
            if input_script is not None:
                # 待ちは台本の {"wait": ミリ秒} が持つので settle は使わない。
                print(f"  input {len(input_script)} events", flush=True)
                probe.send_input(input_script)
            else:
                time.sleep(settle)
            probe.place_request(request)

        metadata = probe.wait_still(request_id)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(probe.frame_png, destination)

    size = metadata.get("size", {})
    entry = {
        "origin": ORIGIN_CAPTURED,
        "sourceHash": source_fingerprint(path),
    }
    # 画面に焼かれた数字（fps）は build configuration で変わるので、既定から外れた
    # ものだけ来歴として残す（#727）。debug は既定なので書かない。
    if release:
        entry["build"] = "release"
    # 指紋はパッケージ配下しか見ないので、ライブラリ本体の変更は拾えない（#586）。
    # 撮った実装を来歴として残し、あとから隔たりを数えられるようにする。
    provenance = capture_provenance(REPO_ROOT)
    if provenance:
        entry["provenance"] = provenance
    return {
        **entry,
        "width": size.get("width"),
        "height": size.get("height"),
        "frame": metadata.get("frame"),
    }


def run_ffmpeg(command: list[str], what: str) -> None:
    if shutil.which("ffmpeg") is None:
        raise ShotError("ffmpeg が見つからない（--compare のシート作成に要る）")
    result = subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *command], capture_output=True, text=True)
    if result.returncode != 0:
        raise ShotError(f"{what} を作れなかった:\n{result.stderr.strip()[-500:]}")


def compare(paths: list[str], config: dict[str, dict]) -> list[Path]:
    """原典画像と実撮影を縦並びにしたコンタクトシートを作る。

    リポジトリの画像は書き換えない。目で見て「原典が実態とずれていないか」を
    判断するための道具（#501）。
    """
    shutil.rmtree(COMPARE_DIR, ignore_errors=True)
    pairs_dir = COMPARE_DIR / "pairs"
    pairs_dir.mkdir(parents=True)

    order: list[str] = []
    for index, path in enumerate(paths, start=1):
        package = package_dir_for(path)
        original = image_path_for(path)
        shot = COMPARE_DIR / "shots" / f"{package.name}.png"
        print(f"capturing {path}", flush=True)
        capture(path, shot, settle_for(path, config), release_for(path, config))
        cell = f"{index:03d}-{package.name}.png"
        width, height = COMPARE_CELL
        run_ffmpeg(
            [
                "-i", str(original), "-i", str(shot),
                "-filter_complex",
                f"[0:v]scale={width}:{height},setsar=1[a];"
                f"[1:v]scale={width}:{height},setsar=1[b];[a][b]vstack=inputs=2",
                str(pairs_dir / cell),
            ],
            f"'{path}' の比較ペア",
        )
        order.append(cell)

    columns, rows = COMPARE_TILE
    sheets = -(-len(order) // (columns * rows))
    run_ffmpeg(
        [
            "-pattern_type", "glob", "-i", str(pairs_dir / "*.png"),
            "-filter_complex", f"tile={columns}x{rows}:padding=6:margin=6:color=0xcccccc",
            "-frames:v", str(sheets), str(COMPARE_DIR / "sheet-%d.png"),
        ],
        "コンタクトシート",
    )
    print("\n並び順（各セルは上が原典・下が実撮影）:")
    for cell in order:
        print(f"  {cell[:-4]}")
    return sorted(COMPARE_DIR.glob("sheet-*.png"))


def selected(entries: list[dict], only: str | None) -> list[dict]:
    if not only:
        return entries
    prefix = only.rstrip("/")
    chosen = [e for e in entries if e["path"] == prefix or e["path"].startswith(prefix + "/")]
    if not chosen:
        raise ShotError(f"'{only}' に当てはまる example が索引に無い")
    return chosen


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="鮮度だけ調べる（撮影しない）")
    parser.add_argument("--only", help="対象を絞る（Examples/... のパス。前方一致）")
    parser.add_argument(
        "--force",
        action="store_true",
        help="画像がある example も撮り直す（--only と併用する）",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="画像がある example を撮って原典と並べたシートを作る（画像は書き換えない）",
    )
    args = parser.parse_args()

    try:
        # 台帳は常に全件で作る（--only で絞ったときに、範囲外のエントリを落とさない）。
        everything = load_index()
        entries = selected(everything, args.only)
        shots = adopted(everything, load_manifest())

        if args.compare:
            targets = [e["path"] for e in entries if image_path_for(e["path"]).is_file()]
            skipped = [
                e["path"] for e in entries
                if no_capture_reason(package_dir_for(e["path"]), e["path"])
            ]
            targets = [p for p in targets if p not in skipped]
            if not targets:
                print("画像のある example が対象に無い（--only を広げてください）")
                return 0
            sheets = compare(targets, load_config())
            print(f"\n{len(targets)} 本を突き合わせました:")
            for sheet in sheets:
                print(f"  {sheet.relative_to(REPO_ROOT)}")
            return 0

        if args.check:
            stale = stale_entries(entries, shots)
            if shots != load_manifest():
                print(
                    "error: 台帳が実態とずれている（画像の追加・削除が反映されていない）",
                    file=sys.stderr,
                )
                print("  make example-shots で更新してください", file=sys.stderr)
                return 1
            if stale:
                print("error: 実行結果画像が古い:", file=sys.stderr)
                for line in stale:
                    print(f"  - {line}", file=sys.stderr)
                print(
                    '\n  make example-shots ARGS="--only <パス> --force" で撮り直してください'
                    "（GPU が要るのでローカルで実行します）",
                    file=sys.stderr,
                )
                return 1
            missing = [
                e["path"] for e in entries
                if not image_path_for(e["path"]).is_file()
                and not no_capture_reason(package_dir_for(e["path"]), e["path"])
            ]
            # 「すべて最新」とは書かない。見ているのは撮影したものの
            # ソースだけで、ライブラリ実装の変更は含まない（#586）。
            captured = [
                shots[e["path"]]
                for e in entries
                if shots.get(e["path"], {}).get("origin") == ORIGIN_CAPTURED
            ]
            aside = (
                f"（原典由来の {len(entries) - len(captured)} 本は鮮度判定の対象外）"
                if len(captured) != len(entries)
                else ""
            )
            print(
                f"OK: {len(entries)} 本のうち、このスクリプトが撮った {len(captured)} 本は"
                f"ソースが撮影時から変わっていない{aside}"
            )
            for line in drift_summary(captured, "example のソース", REPO_ROOT):
                print(line)
            if missing:
                print(f"（画像がまだ無い example が {len(missing)} 本。make example-shots で撮れます）")
            return 0

        if args.force and not args.only:
            raise ShotError("--force は --only と併用してください（162 枚の一括上書きを避けるため）")

        # 撮る前に台帳を実態へ合わせておく。初回（台帳がまだ無いとき）に原典由来の
        # 162 枚を迎え入れるのも、中断後の再開も、この 1 行で同じ操作になる。
        save_manifest(shots)

        config = load_config()
        targets = []
        for entry in entries:
            path = entry["path"]
            package = package_dir_for(path)
            reason = no_capture_reason(package, path)
            if reason:
                if args.only:
                    print(f"skipping {path}（{reason}）")
                continue
            if image_path_for(path).is_file() and not args.force:
                continue
            targets.append(path)

        if not targets:
            print(f"OK: 対象 {len(entries)} 本に撮るものは無い")
            save_manifest(shots)
            return 0

        for index, path in enumerate(targets, start=1):
            release = release_for(path, config)
            note = "（release ビルド）" if release else ""
            print(f"[{index}/{len(targets)}] capturing {path}{note}", flush=True)
            image = image_path_for(path)
            shots[path] = capture(path, image, settle_for(path, config), release)
            # 1 本ずつ台帳を確定させる。中断しても済んだぶんは整合したまま残る。
            save_manifest(shots)
            size = image.stat().st_size
            print(f"  -> {image.relative_to(REPO_ROOT)}（{size / 1024:.0f} KiB）")
        print(f"\n{len(targets)} 本を撮りました。")
    except ShotError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
