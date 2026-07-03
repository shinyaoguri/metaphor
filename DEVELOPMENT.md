# metaphor Development

このドキュメントは `metaphor` ライブラリ本体を開発する人向けです。

- `metaphor` を使ってスケッチを書く場合は、まず [README.md](README.md) の「60 秒ではじめる」を参照してください。
- ドキュメント全体の地図（誰が何を読むべきか）は [docs/README.md](docs/README.md) にあります。
- AI エージェントと保守する場合の起点は [CLAUDE.md](CLAUDE.md) です。

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

`make setup` は pre-push フック（生成物の鮮度チェックなど）も導入します。

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

テストは Swift Testing フレームワーク（`@Suite` / `@Test`）を使います。反復中は `swift test --filter <SuiteOrTestName>` で絞り、仕上げに `make test` を通してください。

## Running Examples

各 example は独立した Swift Package です。

```bash
cd Examples/Basics/Form/ShapePrimitives
swift run
```

カテゴリ構成と追加方法は [Examples/README.md](Examples/README.md) を参照してください。

## 生成物の管理（重要）

以下のファイルはチェックインされていますが**生成物**です。手で編集せず、入力を変えたら再生成してコミットします。pre-push フックと CI が陳腐化を検出します。

| 出力 | 入力 | 再生成コマンド |
|---|---|---|
| `llms.txt` | `Sources/**/*.swift`, `scripts/generate-llms-txt.py` | `make llms-txt` |
| `docs/ai/examples-index.{md,json}` | `Examples/**`, `scripts/generate-examples-index.py` | `make examples-index` |
| `Sources/MetaphorCore/Shaders/ShaderSources/*.txt` | `Shaders/Metal/*.metal`, `scripts/generate-shader-sources.py` | `python3 scripts/generate-shader-sources.py` |

- 生成器は**決定的**であること（全コレクションをソート）。非決定的出力は auto-fix bot が毎回 push する原因になります。
- AI 向けドキュメント（CLAUDE.md / docs/ai/）とコードの整合は `make ai-docs-check` で検証できます。ドキュメント・モジュール一覧・バージョンスニペットを変えたら実行してください。

## Syphon Framework Handling

- ローカル開発では `Frameworks/Syphon.xcframework` が存在する場合、`Package.swift` はローカルパスを使用します。
- SPM ユーザー向けには、`Package.swift` が GitHub Releases からビルド済み XCFramework を取得します。
- `Frameworks/Syphon.xcframework` は `make setup` で生成されます。
- Syphon に依存するのは `MetaphorSyphon` ターゲットだけです（[ADR-0001](docs/adr/0001-separate-syphon-into-its-own-target.md)）。

## Cross-Repo Contract

環境変数・stdin JSON Lines・Probe ファイル・Syphon pin など、[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) との実行時契約に触れる変更は、**両リポジトリの同時更新**が必要です。対象と変更ルールは [CONTRACT.md](CONTRACT.md) を参照し、`./scripts/check-contract.sh` が green であることを確認してください。

## Release Process

リリースは PR の `release:patch|minor|major` ラベル駆動です。手順の全体は [docs/releasing.md](docs/releasing.md) を参照してください。

release workflow は Syphon.xcframework をビルドして GitHub Release asset として公開し、`Package.swift` の binary target URL/checksum を更新します。

## Notes

- macOS 14.0+ / Apple Silicon / Swift 5.10+ を対象にしています。
- レンダリング挙動の検証は、目視ではなく `MetaphorTestSupport` によるピクセル / readback テストを優先してください。
- 実装のデバッグマップ・不変条件（トリプルバッファリング、compute→render 同期、Probe のゼロコスト規約など）は [docs/ai/README.md](docs/ai/README.md) にまとまっています。
