#!/usr/bin/env python3
"""Swift 6 strict concurrency 設定の取りこぼしを検出する（Issue #328 段階 4）。

`build-and-test` は `-warnings-as-errors` 付きでビルドするので、strict concurrency の
警告が入り込めばそこで落ちる。ただしそれは **設定が付いているターゲット** の話で、
新しいターゲットを追加したときに `swiftSettings: strictConcurrency` を書き忘れると、
警告がそもそも出ないまま静かにチェックの穴になる（`.enableUpcomingFeature` の綴りを
Swift 5.10 が黙って無視した件と同じ失敗の形）。

そこで「Swift ソースを持つ全ターゲットに StrictConcurrency 設定が付いている」ことを
マニフェスト（`swift package dump-package`）から機械的に確認する。
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEATURE = "StrictConcurrency"


def has_swift_sources(name: str, path: str | None) -> bool:
    """ターゲットが Swift ソースを持つか（C ターゲット等を対象外にするため）。"""
    for base in ([ROOT / path] if path else [ROOT / "Sources" / name, ROOT / "Tests" / name]):
        if base.is_dir() and any(base.rglob("*.swift")):
            return True
    return False


def enables_strict_concurrency(target: dict) -> bool:
    """StrictConcurrency が upcoming / experimental のどちらの綴りでも有効か。

    Package.swift はホストのツールチェーンに応じて綴りを振り分ける（Swift 6 以降は
    upcoming、Swift 5.10 は experimental）。どちらでも通す。
    """
    for setting in target.get("settings", []):
        if setting.get("tool") != "swift":
            continue
        kind = setting.get("kind", {})
        for key in ("enableUpcomingFeature", "enableExperimentalFeature"):
            payload = kind.get(key)
            if payload and FEATURE in json.dumps(payload):
                return True
    return False


def main() -> int:
    try:
        dump = subprocess.run(
            ["swift", "package", "dump-package"],
            cwd=ROOT, check=True, capture_output=True, text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"error: `swift package dump-package` に失敗しました: {error}", file=sys.stderr)
        return 1

    package = json.loads(dump)
    missing = []
    checked = 0
    for target in package.get("targets", []):
        name = target["name"]
        if target.get("type") == "binary":
            continue
        if not has_swift_sources(name, target.get("path")):
            continue  # C ターゲットなど
        checked += 1
        if not enables_strict_concurrency(target):
            missing.append(name)

    if missing:
        print(
            "error: 次のターゲットに `swiftSettings: strictConcurrency` がありません "
            "(Issue #328):",
            file=sys.stderr,
        )
        for name in sorted(missing):
            print(f"  - {name}", file=sys.stderr)
        print(
            "Package.swift でこれらのターゲットに設定を追加し、"
            "警告ゼロを両ツールチェーンで確認してください。",
            file=sys.stderr,
        )
        return 1

    print(f"strict concurrency: Swift ソースを持つ {checked} ターゲットすべてに設定あり。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
