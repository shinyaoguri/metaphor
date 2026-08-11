// @ts-check
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import tailwindcss from '@tailwindcss/vite';

// https://astro.build/config
export default defineConfig({
  site: 'https://shinyaoguri.github.io',
  base: '/metaphor',
  i18n: {
    defaultLocale: 'ja',
    locales: ['ja', 'en'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
  // MDX はチュートリアル本文（docs/tutorial/）用。いまの本文は素の Markdown だが、
  // 節に図やインタラクティブな作例を差し込みたくなったときに拡張子を .mdx へ
  // 変えるだけで済むよう、content collection のパターンごと最初から通してある。
  integrations: [mdx()],
  markdown: {
    // Astro 組み込みの Shiki。LP の CodeExample.astro は Tailwind クラスを手書きした
    // 擬似ハイライトだが、チュートリアルは本物のトークナイザで色を付ける。
    shikiConfig: {
      // サイトの配色（浅葱＋紙）に馴染む明るいテーマ。サイトは light 固定。
      theme: 'vitesse-light',
      wrap: false,
    },
  },
  vite: {
    plugins: [tailwindcss()],
    server: {
      // content collection の base が website/ の外（../docs/tutorial）にあるため、
      // dev サーバーがそこの資産（本文が参照する画像）を配信できるようにする。
      fs: { allow: ['..'] },
    },
  },
});
