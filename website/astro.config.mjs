// @ts-check
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import tailwindcss from '@tailwindcss/vite';
import { remarkTutorialImages } from './src/plugins/remark-tutorial-images.mjs';

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
  // チュートリアルの画像は Gyazo に置き、本文は絶対 URL で指す（ADR-0010）。
  // ここに載せたホストの画像だけを Astro が**ビルド時に取得して最適化し、
  // dist/ へ配置する**（載せ忘れると素通しになり、配信サイズも遅延読み込みも
  // 失われるのに、見た目は正しいまま = 気付けない）。
  image: {
    remotePatterns: [{ protocol: 'https', hostname: 'i.gyazo.com' }],
  },
  // 取得結果のキャッシュ。既定は node_modules/.astro だが、CI は毎回 npm ci で
  // node_modules を作り直すため、そのままでは毎ビルド全点を取り直すことになる。
  // 外へ出して actions/cache の対象にする（.github/workflows/docs.yml）。
  //
  // 注意: ここには画像（assets/）だけでなく **content collection の描画済み HTML**
  // （data-store.json）も入る。その鮮度は本文のファイルと content.config.ts だけで
  // 決まり、**remark プラグインを直しても古い HTML が出続ける**（config digest は
  // 関数を null に潰すので差が出ない）。CI はこのディレクトリを restore-keys 付きで
  // 復元するため、本文を触らない website だけの変更が公開サイトへ出ないことになる。
  // package.json の prebuild で毎回消している（描画は 25 ページで 1 秒強、画像の
  // キャッシュは別ディレクトリなので効き続ける）。
  cacheDir: './.astro-cache',
  markdown: {
    // 台帳（images/manifest.json）を正に、本文の画像へ縦横を焼き込み、動きの証跡
    // には印を付ける。前者は Astro がリモート画像の寸法を取りに行くのを止め（毎
    // ビルド 65 回のラウンドトリップが消え、ビルドの成否が外部サービスに繋がら
    // なくなる。レイアウトシフトの防止にもなる）、後者は prefers-reduced-motion の
    // 読者に動くほうを出さないために使う。
    remarkPlugins: [remarkTutorialImages],
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
