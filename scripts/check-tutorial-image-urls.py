#!/usr/bin/env python3
"""チュートリアルの画像 URL がまだ生きているかを調べる（ADR-0010 / Issue #511）。

画像の実体は Gyazo にあり、リポジトリが持つのは本文と台帳
（`docs/tutorial/images/manifest.json`）の URL だけ。ローカルアセットなら
「ファイルが無い」はビルドの警告として出るが、外部 URL は**死んでも本文の変換も
サイトのビルドも成功してしまう**（ADR-0008 が挙げた Negative そのもの）。
だから死活は別に見張る。

per-PR の CI ではなく週次で走らせる（.github/workflows/asset-health.yml）。
ネットワークの一時的な不調で PR を止めないため、かつ URL が死ぬのは
「誰かが Gyazo 側で消したとき」だけで、PR の内容とは無関係だから。

    python3 scripts/check-tutorial-image-urls.py            # 台帳の全 URL
    python3 scripts/check-tutorial-image-urls.py --verbose  # 生きている URL も出す

台帳に URL がまだ無い（＝外部化していない）節は黙って飛ばす。移行の前でも途中でも
このスクリプトが誤って赤くならないようにするため。
"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "docs/tutorial/images/manifest.json"

TIMEOUT_SEC = 60
ATTEMPTS = 3


def ledger_urls() -> list[tuple[str, str]]:
    """台帳が指している URL を `(節, URL)` で返す（静止画・動きの証跡の順）。"""
    if not MANIFEST.is_file():
        return []
    shots = json.loads(MANIFEST.read_text(encoding="utf-8")).get("shots", {})
    urls: list[tuple[str, str]] = []
    for ref, entry in sorted(shots.items()):
        if entry.get("url"):
            urls.append((ref, entry["url"]))
        motion = entry.get("motion") or {}
        if motion.get("url"):
            urls.append((ref, motion["url"]))
    return urls


def probe(url: str) -> tuple[bool, str]:
    """URL が生きているかを調べる。`(生きているか, 説明)` を返す。

    HEAD ではなく先頭 1 バイトだけの GET を使う（CDN によっては HEAD を
    受け付けない）。一時的な不調で週次を赤くしないよう数回試す。
    """
    detail = "no response"
    for attempt in range(1, ATTEMPTS + 1):
        request = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SEC) as response:
                if response.status in (200, 206):
                    return True, str(response.status)
                detail = f"HTTP {response.status}"
        except urllib.error.HTTPError as exc:
            detail = f"HTTP {exc.code}"
            if exc.code in (401, 403, 404, 410):
                return False, detail  # 消えている。再試行しても変わらない
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            detail = f"{type(exc).__name__}: {exc}"
        if attempt < ATTEMPTS:
            continue
    return False, detail


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verbose", action="store_true", help="生きている URL も 1 行ずつ出す"
    )
    args = parser.parse_args()

    urls = ledger_urls()
    if not urls:
        print("OK: 台帳に外部の画像 URL がまだ無い（何も調べることが無い）")
        return 0

    dead: list[tuple[str, str, str]] = []
    for ref, url in urls:
        alive, detail = probe(url)
        if alive:
            if args.verbose:
                print(f"OK    {ref}  {url}")
        else:
            print(f"FAIL  {ref}  {url} ({detail})")
            print(f"::error::{ref} の画像が取得できない（{detail}）: {url}")
            dead.append((ref, url, detail))

    if dead:
        print()
        print(f"チュートリアルの画像 {len(dead)} 件が取得できませんでした。")
        print(
            "アセットは不変・追記型なので、生きている URL が消えるのは"
            "Gyazo 側で削除されたときだけです（ADR-0010）。撮り直して上げ直します:"
        )
        print("  make tutorial-shots ARGS=\"--only <節> --force\"")
        return 1

    print(f"OK: 台帳の画像 {len(urls)} 件すべてが生きている")
    return 0


if __name__ == "__main__":
    sys.exit(main())
