import { getCollection, type CollectionEntry } from 'astro:content';
import { base, defaultLang, languages, type Lang } from '../i18n/ui';

export type TutorialEntry = CollectionEntry<'tutorial'>;

/** サイドバー・ページ送り・一覧が共通で扱う「1 部」の表現。 */
export interface TutorialPart {
  /** URL に出る部のスラッグ。数字プレフィックスを外したもの（`getting-started`）。 */
  slug: string;
  /** 並び順。frontmatter の `part` があればそれ、無ければファイル名の数字。 */
  order: number;
  /** 表示するタイトル（フォールバック時は表示中の本文＝日本語のもの）。 */
  title: string;
  description?: string;
  /** 実際に描画するエントリ。要求された言語が無ければ既定言語のものが入る。 */
  entry: TutorialEntry;
  /** 要求された言語の本文が存在したか。false なら翻訳待ちの告知を出す。 */
  translated: boolean;
  /** その言語での URL。 */
  href: string;
}

/** `/tutorial/` 一覧の URL。ja はルート、en は `/en/` 配下。 */
export function tutorialIndexHref(lang: Lang): string {
  return lang === defaultLang ? `${base}/tutorial/` : `${base}/${lang}/tutorial/`;
}

/** 部のページ URL。 */
export function tutorialHref(lang: Lang, slug: string): string {
  return `${tutorialIndexHref(lang)}${slug}/`;
}

/**
 * エントリ ID を言語・スラッグ・並び順に分解する。
 *
 * ID は base（`docs/tutorial`）からの相対パスなので、
 * `01-getting-started` か `en/01-getting-started` の形になる。
 */
function parseEntry(entry: TutorialEntry): { lang: Lang; slug: string; order: number } {
  const segments = entry.id.split('/');
  const head = segments.length > 1 ? segments[0] : undefined;
  const lang = (languages as readonly string[]).includes(head ?? '')
    ? (head as Lang)
    : defaultLang;
  const fileName = segments[segments.length - 1] ?? entry.id;
  const match = /^(\d+)-(.+)$/.exec(fileName);
  // frontmatter が正で、無ければファイル名から補う（規約上は両者が一致する）。
  // 数字プレフィックスは glob のパターンで強制しているので match は必ず取れるが、
  // 取れなかった場合もファイル名をそのままスラッグとして扱って落とさない。
  const order = entry.data.part ?? (match ? Number(match[1]) : Number.MAX_SAFE_INTEGER);
  const slug = entry.data.slug ?? (match ? match[2]! : fileName);
  return { lang, slug, order };
}

/**
 * 指定言語で読める部を、章立ての順に返す。
 *
 * 並び順はハードコードせず、frontmatter の `part` か、無ければファイル名の
 * 数字プレフィックスから決める。本文が増えても自動で並ぶ。
 *
 * 日本語ファースト（Epic #483）なので、章立ての背骨は言語によらず共通で、
 * 英語版が無い部は日本語の本文をそのまま出して `translated: false` を立てる
 * （英語 UI のまま日本語本文を出し、記事の頭で翻訳準備中であることを明示する）。
 */
export async function getTutorialParts(lang: Lang): Promise<TutorialPart[]> {
  const entries = await getCollection('tutorial', ({ data }) => data.draft !== true);

  const bySlug = new Map<string, { order: number; variants: Partial<Record<Lang, TutorialEntry>> }>();
  for (const entry of entries) {
    const { lang: entryLang, slug, order } = parseEntry(entry);
    const bucket = bySlug.get(slug) ?? { order, variants: {} };
    // 並び順は既定言語の番号を正とする（訳が古い番号のままでも章立ては崩れない）。
    if (entryLang === defaultLang || !bySlug.has(slug)) bucket.order = order;
    bucket.variants[entryLang] = entry;
    bySlug.set(slug, bucket);
  }

  return [...bySlug.entries()]
    .map(([slug, { order, variants }]) => {
      const translatedEntry = variants[lang];
      const entry = translatedEntry ?? variants[defaultLang] ?? Object.values(variants)[0]!;
      return {
        slug,
        order,
        title: entry.data.title,
        description: entry.data.description,
        entry,
        translated: translatedEntry !== undefined,
        href: tutorialHref(lang, slug),
      } satisfies TutorialPart;
    })
    .sort((a, b) => a.order - b.order || a.slug.localeCompare(b.slug));
}

/**
 * その本文の GitHub 上の URL（「GitHub で編集する」導線）。
 *
 * `filePath` は Astro のプロジェクトルート（website/）からの相対パスなので、
 * リポジトリルート相対に直してから blob URL を作る。
 */
export function sourceUrlFor(entry: TutorialEntry): string {
  const filePath = entry.filePath ?? '';
  const repoRelative = filePath.replace(/^(\.\.\/)+/, '');
  return `https://github.com/shinyaoguri/metaphor/blob/main/${repoRelative}`;
}

/** `[...slug].astro` の getStaticPaths 用。本文 0 件なら空配列を返す。 */
export async function tutorialStaticPaths(lang: Lang) {
  const parts = await getTutorialParts(lang);
  return parts.map((part, index) => ({
    params: { slug: part.slug },
    props: {
      lang,
      part,
      parts,
      prev: index > 0 ? parts[index - 1] : undefined,
      next: index < parts.length - 1 ? parts[index + 1] : undefined,
    },
  }));
}
