// @ts-check
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

// https://astro.build/config
export default defineConfig({
  site: 'https://shinyaoguri.github.io',
  base: '/metaphor',
  vite: {
    plugins: [tailwindcss()],
  },
});
