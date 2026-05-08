# metaphor Development

このドキュメントは `metaphor` ライブラリ本体を開発する人向けです。

`metaphor` を使ってスケッチを書く場合は、まず [README.md](README.md) の Quick Start を参照してください。

## Repository Setup

サブモジュールごとクローンし、ローカル開発用の Syphon.xcframework をビルドします。

```bash
git clone --recursive https://github.com/shinyaoguri/metaphor.git
cd metaphor
make setup
```

既にクローン済みの場合:

```bash
git submodule update --init --recursive
make setup
```

## Build Commands

```bash
make setup      # サブモジュール初期化 + Syphon.xcframework ビルド
make build      # swift build
make test       # swift test
make clean      # ビルド成果物をクリーン
make check      # セットアップ状態を確認
make docs       # DocC ドキュメントをビルド
make llms-txt   # AI-readable API reference を生成
```

## Running Examples

各 example は独立した Swift Package です。

```bash
cd Examples/Basics/Form/ShapePrimitives
swift run
```

## Syphon Framework Handling

- ローカル開発では `Frameworks/Syphon.xcframework` が存在する場合、`Package.swift` はローカルパスを使用します。
- SPMユーザー向けには、`Package.swift` が GitHub Releases からビルド済み XCFramework を取得します。
- `Frameworks/Syphon.xcframework` は `make setup` で生成されます。

## Release Process

このリポジトリの release workflow は、Syphon.xcframework をビルドし、GitHub Release asset として公開し、`Package.swift` の binary target URL/checksum を更新します。

通常は GitHub Actions の Release workflow から bump 種別を選んで実行します。

手動でタグを扱う場合:

```bash
git tag v0.X.X
git push origin v0.X.X
```

## Notes

- macOS 14.0+ / Swift 5.10+ を対象にしています。
- 新規テストは既存 target のテストスタイルに合わせて追加してください。
- API概要は `llms.txt` にも生成されています。
