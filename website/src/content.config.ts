import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

/**
 * チュートリアル本文の正典は website ではなく `docs/tutorial/` です
 * （GitHub 上でもそのまま読める Markdown であること自体が要件のため）。
 * website はコピーを持たず、リポジトリルートの `docs/tutorial/` を
 * content collection として直接読み込みます。
 *
 * 拾う対象は `NN-slug.md`（部ごとに 1 ファイル）と、その英訳
 * `en/NN-slug.md` だけです。数字 2 桁のプレフィックスを要求することで、
 * 章立て・執筆規約の設計文書である `docs/tutorial/README.md` と、
 * 画像置き場 `docs/tutorial/images/` は自然に公開対象から外れます
 * （目次はサイト側 — サイドバーと /tutorial/ — が担います）。
 *
 * 本文がまだ 1 本も無い状態（0 件）でもビルドが通ることが要件です。
 */
const tutorial = defineCollection({
  loader: glob({
    base: '../docs/tutorial',
    pattern: ['[0-9][0-9]-*.{md,mdx}', 'en/[0-9][0-9]-*.{md,mdx}'],
    // ID はファイルパス（拡張子なし）そのもの。既定の生成規則は frontmatter の
    // `slug` を優先するため、`NN-slug.md` と `en/NN-slug.md` が同じ ID になって
    // 一方が他方を上書きしてしまう（日本語の部が英訳に差し替わる）。
    generateId: ({ entry }) => entry.replace(/\.mdx?$/, ''),
  }),
  // frontmatter の規約は `docs/tutorial/README.md` が正本（#484 / #485 で確定）。
  // ここはそれに追従するだけで、website 側で独自の必須項目を増やしません。
  schema: z.object({
    /** 部のタイトル。「第 N 部」は含めません。 */
    title: z.string(),
    /**
     * 部番号。サイドバー・一覧の並び順に使います。
     * 省略時はファイル名の数字プレフィックス（`03-...` → 3）から補います
     * （章立てをハードコードせず、本文が増えても自動で並ぶようにするため）。
     */
    part: z.number().int().positive().optional(),
    /** URL に使うスラッグ。ファイル名 `NN-slug.md` の slug と一致させます。 */
    slug: z.string().optional(),
    /** この部で何ができるようになるか（1 文）。一覧と meta description に出ます。 */
    description: z.string().optional(),
    /** 執筆中は true。公開対象から外れます。 */
    draft: z.boolean().optional(),
  }),
});

export const collections = { tutorial };
