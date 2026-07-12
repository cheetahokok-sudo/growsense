// @ts-check
import { defineConfig } from 'astro/config';

// The blog lives under growsense.life/blog/. Astro owns ONLY this subtree,
// emits plain static .html at the same URLs the hand-built pages use, and
// writes into ./dist for the PoC (later: outDir '../blog' to go live).
export default defineConfig({
  site: 'https://www.growsense.life',
  base: '/blog',
  outDir: './dist',
  trailingSlash: 'ignore',
  build: {
    // file → /blog/why-children-grow-faster.html (matches current URLs),
    // not directory-style /blog/why-children-grow-faster/index.html
    format: 'file',
    assets: '_assets',
    // Inline the CSS into each page so every .html is self-contained (matches
    // the hand-built pages) → cutover is just copying .html, no _assets folder.
    inlineStylesheets: 'always',
  },
  markdown: {
    gfm: true, // GitHub-flavored: footnotes drive the references list
  },
});
