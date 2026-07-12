// Copies the built static pages into ../blog (served by GitHub Pages from the
// repo root). Copies ONLY .html — hero images and other assets already in
// blog/ are left untouched. Run via `npm run deploy` (astro build + this).
import { readdirSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';

const SRC = './dist';
const DEST = '../blog';

const pages = readdirSync(SRC).filter((f) => f.endsWith('.html'));
for (const f of pages) {
  copyFileSync(join(SRC, f), join(DEST, f));
  console.log('→ blog/' + f);
}
console.log(`Copied ${pages.length} page(s) into ${DEST}. Hero images left in place.`);
