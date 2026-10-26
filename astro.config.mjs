// @ts-check
import { defineConfig } from 'astro/config';

import node from '@astrojs/node';
import tailwindcss from '@tailwindcss/vite';

// Smart HR is an authenticated admin tool: every route renders on demand so
// nothing with employee data is ever baked into a static file.
export default defineConfig({
  output: 'server',

  adapter: node({
    mode: 'standalone',
  }),

  vite: {
    plugins: [tailwindcss()],
  },
});
