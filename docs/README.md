# docs/ — ドキュメントの地図

metaphor のドキュメントは「誰が・何のために読むか」で分かれています。まずこの表から入ってください。

## 読者別の入口

| 読者 | 目的 | 読むもの |
|---|---|---|
| スケッチを書く人 | metaphor で作品を作る | [README](../README.md) → [ai/for-sketch-authors.md](ai/for-sketch-authors.md) → [ai/examples-index.md](ai/examples-index.md) |
| AI と一緒に作る人 | AI に観測させながら反復する | [README「AI と協調する」](../README.md#ai-と協調する観測--操作--反復) → [metaphor-cli の「AI と協調する」](https://github.com/shinyaoguri/metaphor-cli#ai-と協調する) → [ai/prompts/](ai/prompts/) |
| ライブラリ本体の開発者 | metaphor 自体を変更する | [DEVELOPMENT.md](../DEVELOPMENT.md) → [ai/README.md](ai/README.md)（実装デバッグ・不変条件） → [adr/](adr/) |
| AI エージェント | 本リポジトリで作業する | [CLAUDE.md](../CLAUDE.md)（起点） → 各ファイルへ委譲 |
| クロスリポ変更を扱う人 | metaphor ⇄ metaphor-cli の契約に触れる | [CONTRACT.md](../CONTRACT.md) |
| リリース担当 | リリースを出す | [releasing.md](releasing.md) |

## ディレクトリ構成

- **[ai/](ai/)** — AI 支援まわりのドキュメント一式
  - [ai/README.md](ai/README.md) — 実装デバッグ・拡張ノート（ライブラリ開発者と AI エージェント向け）
  - [ai/for-sketch-authors.md](ai/for-sketch-authors.md) — AI と一緒にスケッチを書く人向けガイド
  - [ai/install-scenarios.md](ai/install-scenarios.md) — インストール形態ごとの AI 支援の効き方
  - [ai/examples-index.md](ai/examples-index.md) / `.json` — 全サンプル索引（**生成物**。手で編集しない）
  - [ai/prompts/](ai/prompts/) — 用途別プロンプトテンプレート（audio-reactive / shader など）
- **[adr/](adr/)** — Architecture Decision Records。設計判断の蓄積（append-only）。書き方は [adr/README.md](adr/README.md)
- **[design/](design/)** — 進行中 / 過去プロジェクトの設計ドキュメント。確定仕様は実装と [CONTRACT.md](../CONTRACT.md) が正
- **[releasing.md](releasing.md)** — リリース手順（PR の `release:*` ラベル駆動）

## 真実の在処（どれが正か）

| 知りたいこと | 正典 |
|---|---|
| 公開 API シグネチャ | [`llms.txt`](../llms.txt)（生成物） |
| 設計判断の根拠 | [adr/](adr/) |
| metaphor ⇄ metaphor-cli の契約 | [CONTRACT.md](../CONTRACT.md) と `contract/*.schema.json` |
| コードの触り方・規約 | [CLAUDE.md](../CLAUDE.md) と [ai/README.md](ai/README.md) |
| セットアップ・ビルド | [DEVELOPMENT.md](../DEVELOPMENT.md) |
