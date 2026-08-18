# docs/ — ドキュメントの地図

[English](README.en.md) | **日本語**

metaphor のドキュメントは「誰が・何のために読むか」で分かれています。まずこの表から入ってください。

## 読者別の入口

| 読者 | 目的 | 読むもの |
|---|---|---|
| metaphor がはじめての人 | 順に読んで、作品を作れるようになる | [tutorial/](tutorial/)（<!-- tutorial-status: ja-status -->第 1 部〜第 10 部を公開中<!-- /tutorial-status --> — Epic [#483](https://github.com/shinyaoguri/metaphor/issues/483)） |
| スケッチを書く人 | metaphor で作品を作る | [README](../README.md) → [ai/for-sketch-authors.md](ai/for-sketch-authors.md) → [ai/examples-index.md](ai/examples-index.md) |
| Examples を掘りたい人 | 索引を引くのではなく、どの順に開くか知りたい | [Examples/LEARNING_PATH.md](../Examples/LEARNING_PATH.md)（英語。難度タグ付きの推奨順路） |
| Processing / p5.js から移る人 | 「Processing の X は metaphor では Y」を引く | [processing-migration-guide.md](processing-migration-guide.md)（英語。API 対応表・落とし穴集・未対応 API） |
| マイク・カメラを使うスケッチを書く人 | 権限ダイアログや拒否後の詰まりを解消する | [permissions.md](permissions.md)（英語。TCC の仕組みと復旧手順） |
| AI と一緒に作る人 | AI に観測させながら反復する | [README「AI と協調する」](../README.md#ai-と協調する観測--操作--反復) → [metaphor-cli の「AI と協調する」](https://github.com/shinyaoguri/metaphor-cli#ai-と協調する) → [ai/prompts/](ai/prompts/) |
| ライブラリ本体の開発者 | metaphor 自体を変更する | [DEVELOPMENT.md](../DEVELOPMENT.md) → [ai/README.md](ai/README.md)（実装デバッグ・不変条件） → [adr/](adr/) |
| AI エージェント | 本リポジトリで作業する | [CLAUDE.md](../CLAUDE.md)（起点） → 各ファイルへ委譲 |
| metaphor に依存する人 | バージョン指定の判断材料・何が壊れうるかを知る | [api-stability-policy.md](api-stability-policy.md)（英語）→ [CHANGELOG.md](../CHANGELOG.md) |
| クロスリポ変更を扱う人 | metaphor ⇄ metaphor-cli の契約に触れる | [CONTRACT.md](../CONTRACT.md) |
| リリース担当 | リリースを出す | [releasing.md](releasing.md) |
| リリース自動化を触る人 | 3 リポ（metaphor / metaphor-cli / homebrew-tap）の関係と自動連鎖を掴む | [release-pipeline.md](release-pipeline.md) |

## ディレクトリ構成

- **[tutorial/](tutorial/)** — 体系的チュートリアル（日本語ファースト・初心者向けの読み物）
  - [tutorial/README.md](tutorial/README.md) — 章立て・執筆規約・既存ドキュメントとの役割分担。本文は各部が `NN-slug.md` として追加される
  - 公開中の本文: <!-- tutorial-status: ja-links:tutorial/ -->[第 1 部 入門](tutorial/01-getting-started.md) / [第 2 部 2D を描く](tutorial/02-drawing-2d.md) / [第 3 部 動かす](tutorial/03-motion.md) / [第 4 部 入力を受ける](tutorial/04-input.md) / [第 5 部 3D へ](tutorial/05-3d.md) / [第 6 部 GPU を使う](tutorial/06-gpu.md) / [第 7 部 メディア](tutorial/07-media.md) / [第 8 部 外とつなぐ](tutorial/08-connect.md) / [第 9 部 作品にする](tutorial/09-artwork.md) / [第 10 部 AI と作る](tutorial/10-ai.md)<!-- /tutorial-status -->。website 版は [/tutorial/](https://shinyaoguri.github.io/metaphor/tutorial/)
- **[reference/](reference/)** — DocC の API リファレンスに載せる実行結果画像の規約
  - [reference/README.md](reference/README.md) — doc コメントへのスニペットの書き方・撮影（`make reference-shots`）・CI が見るもの
- **[ai/](ai/)** — AI 支援まわりのドキュメント一式
  - [ai/README.md](ai/README.md) — 実装デバッグ・拡張ノート（ライブラリ開発者と AI エージェント向け）
  - [ai/for-sketch-authors.md](ai/for-sketch-authors.md) — AI と一緒にスケッチを書く人向けガイド
  - [ai/install-scenarios.md](ai/install-scenarios.md) — インストール形態ごとの AI 支援の効き方
  - [ai/examples-index.md](ai/examples-index.md) / `.json` — 全サンプル索引（**生成物**。手で編集しない）
  - [ai/prompts/](ai/prompts/) — 用途別プロンプトテンプレート（audio-reactive / shader など）
- **[processing-migration-guide.md](processing-migration-guide.md)** — Processing / p5.js 移行ガイド（英語）。カテゴリ別 API 対応表、落とし穴集、未対応 API とロードマップへの導線
- **[permissions.md](permissions.md)** — マイク・カメラの TCC 権限（英語）。`swift run` バイナリでの権限要求の仕組み、拒否後の復旧手順、Info.plist の扱い
- **[api-stability-policy.md](api-stability-policy.md)** — API 安定性ポリシー（英語）。4 層のどこまでが公開 API か、ソース互換のみ（ABI 非保証）、deprecation 窓、描画結果 / Probe wire schema / stdin / 環境変数が SemVer のどこに載るか、1.0 までは breaking を minor で許容する規律（[ADR-0009](adr/0009-unfreeze-api-until-1-0.md)）
- **[adr/](adr/)** — Architecture Decision Records。設計判断の蓄積（append-only）。書き方は [adr/README.md](adr/README.md)
- **[design/](design/)** — 進行中 / 過去プロジェクトの設計ドキュメント。確定仕様は実装と [CONTRACT.md](../CONTRACT.md) が正
  - [design/roadmap-processing-unity.md](design/roadmap-processing-unity.md) — Processing / Unity ユーザー獲得ロードマップ（living document・Epic 一覧）
  - [design/live-tooling-params.md](design/live-tooling-params.md) — ライブツーリング基盤の設計。Parameter Store（A）と状態保持リロード（B）は producer / consumer とも実装済みで、インスペクタ（C）/ 往復レイテンシ（D）が叩き台（節ごとの状況は文書冒頭の表）
  - [design/v1-release-plan.md](design/v1-release-plan.md) — v1.0.0 リリース準備計画（readiness review・準備トラック・リリース条件）
- **[releasing.md](releasing.md)** — リリース手順（週次トレイン + `release:now` の express）+ CHANGELOG の昇格・リリースノート生成
- **[release-pipeline.md](release-pipeline.md)** — 3 リポジトリ（metaphor / metaphor-cli / homebrew-tap）の依存関係とリリース自動連鎖の全体地図。詳細は releasing.md / metaphor-cli 側 docs へ委譲

リポジトリルートには [CHANGELOG.md](../CHANGELOG.md)（利用者向けの変更履歴。Keep a Changelog 形式・英語。ユーザー影響のある PR は CHANGELOG.md ではなく [changelog.d/](../changelog.d/README.md) に 1 ファイル置き、リリース時に集約される）もあります。Examples 側には [Examples/LEARNING_PATH.md](../Examples/LEARNING_PATH.md)（英語。難度タグを使った「順に学ぶ」推奨順路）もあります。

## 英語化の対象境界（第 1 弾・Issue #286）

Processing / Unity ユーザー獲得の並行トラック（ロードマップ Epic I）として、英語ドキュメントは以下の境界で維持します:

- **英語で提供する**: [README.en.md](../README.en.md)（60 秒スタート・Getting Started を含む入口。README.md と相互リンク）、`Examples/**` のコード内コメント、`docs/ai/examples-index.md` の description（生成元の example メタデータは英語）、[docs/README.en.md](README.en.md)（本ページの英語版。Issue #337）、[permissions.md](permissions.md)・[Examples/LEARNING_PATH.md](../Examples/LEARNING_PATH.md)・[processing-migration-guide.md](processing-migration-guide.md)（新設・英語のみ）
- **日本語のまま**（翻訳しない）: [adr/](adr/) 全体（設計判断の記録。ADR 全訳は非目標）、[design/](design/)、[CLAUDE.md](../CLAUDE.md)・[ai/README.md](ai/README.md) などの開発者・エージェント向け内部ドキュメント
- **英語が正典・日本語は生成物**: API リファレンス（公開 API の doc コメントと `.docc` 記事）。英語版を `/reference/`、機械翻訳した日本語版を `/reference/ja/` へ並べます（[ADR-0011](adr/0011-docc-english-canon-japanese-generated.md)）。日本語は `docs/reference/i18n/ja.json` を当てた生成物なので**手で書きません**。doc コメント自体の英語化は [#334](https://github.com/shinyaoguri/metaphor/issues/334) が進行中で、訳の無い箇所は英語のまま出ます
- **今後の弾**: 第 3 弾 = website（#74）。着手時に起票
- **日本語ファースト・英語は後追い**: [tutorial/](tutorial/)（Epic [#483](https://github.com/shinyaoguri/metaphor/issues/483)）。<!-- tutorial-status: ja-translation -->英語版は [#548](https://github.com/shinyaoguri/metaphor/issues/548) で後追いします<!-- /tutorial-status -->。リファレンスとは向きが逆で、こちらは**本文が正典**なので機械翻訳では出しません

## 真実の在処（どれが正か）

| 知りたいこと | 正典 |
|---|---|
| 公開 API シグネチャ | [`llms.txt`](../llms.txt)（生成物） |
| チュートリアルの章立て・執筆規約 | [tutorial/README.md](tutorial/README.md) |
| リファレンスの実行結果画像の規約 | [reference/README.md](reference/README.md) |
| 設計判断の根拠 | [adr/](adr/) |
| 何が公開 API か・何が壊れうるか | [api-stability-policy.md](api-stability-policy.md) |
| metaphor ⇄ metaphor-cli の契約 | [CONTRACT.md](../CONTRACT.md) と `contract/*.schema.json` |
| 3 リポの関係とリリース連鎖の全体像 | [release-pipeline.md](release-pipeline.md) |
| コードの触り方・規約 | [CLAUDE.md](../CLAUDE.md) と [ai/README.md](ai/README.md) |
| セットアップ・ビルド | [DEVELOPMENT.md](../DEVELOPMENT.md) |
