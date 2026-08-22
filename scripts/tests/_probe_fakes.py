#!/usr/bin/env python3
"""撮影スクリプトのテストが共有する、偽の Probe つきスケッチ。

実物は GPU が要る（`swift run` で Metal を掴む）ので、撮影の**段取り**
—「いつ request.json を置き、いつ応答を待つか」— だけを確かめるための代役です。
`subprocess.Popen` の差し替え先として使い、`shots_common.ProbeCapture` が
CONTRACT.md 契約点 4 の producer 側をどう踏むかを、絵を撮らずに検査します。

置き場をここにしているのは、3 スクリプトの骨格が `shots_common` に 1 本化された
（#1024）のに、代役が 1 つのテストファイルの中にだけあると、他の検査が同じものを
書き足すことになるためです。
"""

from __future__ import annotations

import io
import json
import threading
from pathlib import Path


class FakeSketch:
    """`swift run <target>` の代わり。`request.json` に応えるだけの最小 Probe。

    **置かれたリクエストが何であっても同じように応える**ので、テストの主張
    （＝どのリクエストを、いつ置いたか）だけが結果を分ける。撮影側が下見を挟んでも
    挟まなくても素通しするため、直っていない実装はタイムアウトではなく主張の失敗で
    落ちる。
    """

    POLL_SEC = 0.01

    def __init__(
        self, probe_dir: Path, *, stdin: bool = False, write_png: bool = True
    ) -> None:
        self.probe_dir = probe_dir
        # 起動時点と終了時点の request.json。撮影側が起動後に置き直したかが分かる。
        self.request_at_launch = self._read_request()
        self.request_at_exit: dict | None = None
        self.returncode: int | None = None
        # `write_png=False` は失敗応答（frame.json だけが書かれる。契約点 4）。
        self.write_png = write_png
        self.stdin = StdinSink(probe_dir) if stdin else None
        self.stderr = None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    # --- subprocess.Popen として振る舞う ---------------------------------------

    def poll(self) -> int | None:
        return self.returncode

    def terminate(self) -> None:
        self.request_at_exit = self._read_request()
        self._stop.set()
        self.returncode = 0

    def kill(self) -> None:
        self.terminate()

    def wait(self, timeout: float | None = None) -> int | None:
        self._thread.join(timeout)
        return self.returncode

    # --- 最小 Probe -----------------------------------------------------------

    def _read_request(self) -> dict | None:
        path = self.probe_dir / "request.json"
        if not path.is_file():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def _serve(self) -> None:
        handled: set[str] = set()
        while not self._stop.wait(self.POLL_SEC):
            request = self._read_request()
            if request is None or request["id"] in handled:
                continue
            handled.add(request["id"])
            if (request.get("frames") or 1) >= 2:
                self._write_sequence(request)
            else:
                self._write_frame(request)

    def _write_frame(self, request: dict) -> None:
        current = self.probe_dir / "current"
        current.mkdir(parents=True, exist_ok=True)
        if self.write_png:
            (current / "frame.png").write_bytes(b"png")
        (current / "frame.json").write_text(
            json.dumps({"id": request["id"], "size": {"width": 480, "height": 360}}),
            encoding="utf-8",
        )

    def _write_sequence(self, request: dict) -> None:
        directory = self.probe_dir / "current/sequence"
        directory.mkdir(parents=True, exist_ok=True)
        frames = [
            {"index": index, "file": f"frame.{index:04d}.png"}
            for index in range(request["frames"])
        ]
        # 完了規約: sequence.json が最後（CONTRACT.md 契約点 4）。
        (directory / "sequence.json").write_text(
            json.dumps(
                {
                    "id": request["id"],
                    "frameCount": len(frames),
                    "every": request.get("every", 1),
                    "size": {"width": 480, "height": 360},
                    "frames": frames,
                }
            ),
            encoding="utf-8",
        )


class DeadSketch:
    """起動直後に落ちたスケッチ。撮影側が待ち続けずに諦めることの確認用。"""

    def __init__(self, message: str = "Fatal error: no Metal device") -> None:
        self.returncode = 1
        self.stdin = None
        self.stderr = io.StringIO(message)

    def poll(self) -> int:
        return self.returncode

    def terminate(self) -> None:
        pass

    def kill(self) -> None:
        pass

    def wait(self, timeout: float | None = None) -> int:
        return self.returncode


class StdinSink:
    """入力台本の届き先。**何が届いたか**と**そのとき絵が出ていたか**を記録する。

    起動直後（Metal パイプラインの構築中）に送ったイベントは stdin に溜まり、最初の
    フレームでまとめて処理される（＝軌跡の中間点が消える）。だから撮影側は下見の
    1 枚を待ってから流すことになっていて（#509 / #610）、守れているかは「行が届いた
    時点で frame.json が書かれていたか」で見分けられる。
    """

    def __init__(self, probe_dir: Path) -> None:
        self.probe_dir = probe_dir
        self.events: list[dict] = []
        # 各行が届いた時点で下見の応答が出ていたか。すべて True であるべき。
        self.after_first_frame: list[bool] = []
        self.closed = False

    def write(self, text: str) -> int:
        line = text.strip()
        if line:
            self.events.append(json.loads(line))
            self.after_first_frame.append(
                (self.probe_dir / "current/frame.json").is_file()
            )
        return len(text)

    def flush(self) -> None:
        pass

    def close(self) -> None:
        self.closed = True
