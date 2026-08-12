# website

metaphor のランディングページとチュートリアルを配信する [Astro](https://astro.build) プロジェクトです。ビルド結果は `.github/workflows/docs.yml` が DocC の出力と**並べて** GitHub Pages（`https://shinyaoguri.github.io/metaphor/`）へ公開します。

| パス | 中身 | 出どころ |
|---|---|---|
| `/` · `/en/` | ランディングページ | `src/components/*.astro` + `src/i18n/ui.ts`（ハードコード） |
| `/tutorial/` · `/en/tutorial/` | チュートリアル | **`docs/tutorial/`**（content collection として読み込み） |
| `/reference/documentation/metaphor/` | API リファレンス | DocC（`docs.yml` が `dist/reference/` へ丸ごと置く） |

2 つのサイトは**混ざりません**。Astro は `dist` のルート、DocC は `dist/reference/` 配下だけを使い、行き来はリンクで行います（ナビの「リファレンス」＝ `src/i18n/ui.ts` の `docsUrl`、DocC 側からはトップページの導線）。かつてはルートへ重ねていたため、コピー対象の列挙から漏れた `theme-settings.json` が公開されず配色が効かない不具合が出ていました（[#529](https://github.com/shinyaoguri/metaphor/issues/529)）。`/reference/` 配下は Astro が生成しないので、この種の衝突・取りこぼしは起きません。

## コマンド

```bash
npm ci
npm run dev      # http://localhost:4321/metaphor/
npm run build    # dist/ を生成（CI の website-build ジョブと同じ）
npm run preview  # dist/ をそのまま配信して確認する
```

## チュートリアルの読み込み方

本文の正本は **`docs/tutorial/`** です（GitHub 上でもそのまま読めることが要件のため）。website はコピーを持たず、`src/content.config.ts` の glob loader が `base: '../docs/tutorial'` を指して直接読みます。**本文を編集すればサイトに反映され、website 側での同期作業はありません。**

拾う対象は次の 2 つだけです。

- `docs/tutorial/NN-slug.md` — 部ごとに 1 ファイル（日本語）
- `docs/tutorial/en/NN-slug.md` — その英訳

数字 2 桁のプレフィックスをパターンで要求しているので、章立ての設計文書である `docs/tutorial/README.md` と画像置き場 `docs/tutorial/images/` は自動的に公開対象から外れます。サイト側の目次（サイドバーと `/tutorial/`）が README の章立てを置き換えます。

### frontmatter

正本は [`docs/tutorial/README.md`](../docs/tutorial/README.md) です。website 側のスキーマ（`src/content.config.ts`）はそれに追従します。

```yaml
---
title: 入門              # 部のタイトル（「第 N 部」は含めない）
part: 1                 # 部番号。並び順に使う（省略時はファイル名の数字で代用）
slug: getting-started   # URL に使う。ファイル名の slug と一致させる
description: この部で何ができるようになるか（1 文）
draft: true             # 執筆中は公開対象から外れる
---
```

章立ての順序はどこにもハードコードしていません。`part`（無ければファイル名の数字）で並ぶので、本文を追加するだけでサイドバーと前後のページ送りに載ります。本文が 0 件でもビルドは通り、`/tutorial/` は「準備中」の案内を出します。

### 画像

本文からの相対リンク（`![...](./images/01-getting-started/1-1-....png)`）で参照します。Astro が最適化して `dist/_astro/` へ出すので、website 側に画像を複製する必要はありません。

### コードブロック

Astro 組み込みの Shiki（テーマ `vitesse-light`）でハイライトします。ランディングページの `CodeExample.astro` は Tailwind クラスを手書きした擬似ハイライトですが、あちらは LP 専用の飾りなので踏襲しません。

### 英語版が無いとき

日本語ファースト（Epic [#483](https://github.com/shinyaoguri/metaphor/issues/483)）です。章立ての背骨は言語共通で、`docs/tutorial/en/` に対応するファイルが無い部は **UI は英語のまま日本語の本文を出し**、記事の頭で「English translation in progress」と明示します。英語側のリンクが切れないので、章立てが揃っている限り英訳は 1 部ずつ足していけます。

## 参照

- [docs/tutorial/README.md](../docs/tutorial/README.md) — 章立てと執筆規約（正本）
- [docs/README.md](../docs/README.md) — ドキュメント全体の地図
