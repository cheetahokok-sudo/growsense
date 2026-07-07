// Regenerates assets/locales/*.json from the PWA's locales/ folder —
// which stays the single source of truth for shared strings — merged
// with tool/flutter_extra_keys.json for Flutter-only strings.
// Run from flutter_app/:  node tool/sync_locales.js
const fs = require('fs');
const path = require('path');

const srcDir = path.join(__dirname, '..', '..', 'locales');
const outDir = path.join(__dirname, '..', 'assets', 'locales');
const extras = JSON.parse(
    fs.readFileSync(path.join(__dirname, 'flutter_extra_keys.json'), 'utf8'));

fs.mkdirSync(outDir, { recursive: true });

const langs = fs.readdirSync(srcDir).filter(f => f.endsWith('.json'));
for (const file of langs) {
  const code = path.basename(file, '.json');
  const base = JSON.parse(fs.readFileSync(path.join(srcDir, file), 'utf8'));
  delete base._meta;
  let added = 0;
  for (const [key, translations] of Object.entries(extras)) {
    if (key === '_comment') continue;
    const value = translations[code] ?? translations.en;
    if (value != null) { base[key] = value; added++; }
  }
  fs.writeFileSync(path.join(outDir, file), JSON.stringify(base, null, 1));
  console.log(`${code}: ${Object.keys(base).length} keys (${added} flutter extras)`);
}
