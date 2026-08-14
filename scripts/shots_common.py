#!/usr/bin/env python3
"""スケッチの実行結果画像を撮るスクリプトが共有する部品。

チュートリアル（`generate-tutorial-shots.py`）と Examples
（`generate-example-shots.py`）で共通なのは 2 つだけです。

- **撮影時のソースの指紋**（`source_hash`）— 「コードを変えたのに画像が古い」を
  検出する仕組みの土台。ここを 2 実装持つと、片側だけ検出が弱る（#505）
- **画像の縦横**（`image_size`）— 台帳に実寸を持たせるため

画像の置き場は用途で違います（チュートリアルは Gyazo = ADR-0010、Examples は
リポジトリ内）。撮り方・台帳・本文の書き換えも用途ごとに違うので、各スクリプトが
持ちます。
"""

from __future__ import annotations

import hashlib
from pathlib import Path

# 指紋の材料から外すもの。ビルド生成物・IDE 設定・Probe の作業ディレクトリ・
# Finder のメタデータで、いずれも絵には影響しない（すべて gitignore 済み）。
EXCLUDED_NAMES = {".build", ".swiftpm", ".metaphor", ".DS_Store"}


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
