// Generates /sitemap.xml and /robots.txt at the REPO ROOT (GitHub Pages serves
// from there, so they must live at growsense.life/sitemap.xml — not under
// /blog/). Run via `npm run deploy`, after astro build + copy-to-blog.
//
// Why hand-rolled rather than @astrojs/sitemap: Astro owns only the /blog
// subtree (base: '/blog'), so its sitemap would cover neither the marketing
// pages at the root nor emit the per-URL hreflang alternates we need. Our
// translations are `slug.th.html` siblings, not a locale directory, which the
// integration has no way to pair up.
//
// /app/ is deliberately excluded: it's an authenticated Flutter SPA, so a
// crawler only ever sees a loading shell. Nothing to index.
import { readdirSync, writeFileSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const ORIGIN = 'https://www.growsense.life';
const DIST = './dist';
const ARTICLES = './src/content/articles';
const LANG_LABEL = { en: 'en', th: 'th', zh: 'zh' };

/** Last content change, from git (falls back to mtime on a dirty/shallow tree). */
function lastmod(file) {
  try {
    const iso = execFileSync('git', ['log', '-1', '--format=%cI', '--', file], {
      encoding: 'utf8',
    }).trim();
    if (iso) return iso.slice(0, 10);
  } catch {
    /* not a git tree — fall through */
  }
  try {
    return statSync(file).mtime.toISOString().slice(0, 10);
  } catch {
    return new Date().toISOString().slice(0, 10);
  }
}

// Group built pages by base slug: foo.html + foo.th.html + foo.zh.html → one
// entry with three hreflang alternates pointing at each other.
const pages = readdirSync(DIST).filter((f) => f.endsWith('.html'));
const groups = new Map();
for (const file of pages) {
  const m = file.match(/^(.+?)(?:\.(th|zh))?\.html$/);
  if (!m) continue;
  const [, slug, lang = 'en'] = m;
  if (!groups.has(slug)) groups.set(slug, {});
  groups.get(slug)[lang] = file;
}

const urls = [];

// Marketing root. index.html is the homepage; the legal/support pages are thin
// but legitimate, and a crawler finding them beats it guessing.
for (const [loc, file, prio] of [
  ['/', '../index.html', '1.0'],
  ['/privacy.html', '../privacy.html', '0.3'],
  ['/terms.html', '../terms.html', '0.3'],
  ['/support.html', '../support.html', '0.3'],
]) {
  urls.push({ loc: ORIGIN + loc, lastmod: lastmod(file), priority: prio, alts: null });
}

for (const [slug, byLang] of groups) {
  const isHub = slug === 'index';
  // Every language of this page points at every other (including itself), which
  // is what Google requires for hreflang to be honoured — plus x-default → EN.
  const alts = Object.entries(byLang).map(([lang, file]) => ({
    lang: LANG_LABEL[lang] ?? lang,
    href: `${ORIGIN}/blog/${file}`,
  }));
  const enHref = byLang.en ? `${ORIGIN}/blog/${byLang.en}` : alts[0].href;

  for (const [lang, file] of Object.entries(byLang)) {
    const src = join(ARTICLES, `${slug}${lang === 'en' ? '' : '.' + lang}.md`);
    urls.push({
      loc: `${ORIGIN}/blog/${file}`,
      lastmod: lastmod(src),
      priority: isHub ? '0.9' : '0.8',
      alts: alts.length > 1 ? { list: alts, xDefault: enHref } : null,
    });
  }
}

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
${urls
  .map(
    (u) => `  <url>
    <loc>${u.loc}</loc>
    <lastmod>${u.lastmod}</lastmod>
    <priority>${u.priority}</priority>${
      u.alts
        ? '\n' +
          u.alts.list
            .map(
              (a) =>
                `    <xhtml:link rel="alternate" hreflang="${a.lang}" href="${a.href}"/>`,
            )
            .join('\n') +
          `\n    <xhtml:link rel="alternate" hreflang="x-default" href="${u.alts.xDefault}"/>`
        : ''
    }
  </url>`,
  )
  .join('\n')}
</urlset>
`;

const robots = `# https://www.growsense.life
User-agent: *
Allow: /

# Authenticated Flutter SPA — a crawler only ever sees a loading shell.
Disallow: /app/

Sitemap: ${ORIGIN}/sitemap.xml
`;

writeFileSync('../sitemap.xml', xml);
writeFileSync('../robots.txt', robots);
console.log(`Wrote sitemap.xml (${urls.length} URLs) + robots.txt to repo root.`);
