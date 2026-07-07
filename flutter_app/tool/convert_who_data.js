// Regenerates assets/who_reference.json from the PWA's
// who-reference-data.js — which stays the single source of truth
// (transcribed directly from official WHO 2007 field tables).
// Run from flutter_app/:  node tool/convert_who_data.js
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', '..', 'who-reference-data.js');
const out = path.join(__dirname, '..', 'assets', 'who_reference.json');

const code = fs.readFileSync(src, 'utf8');
const sandbox = new Function(
  'module',
  code + '\nreturn { WHO_HFA_BOYS_5_19, WHO_HFA_GIRLS_5_19, PERCENTILE_Z };'
);
const data = sandbox({ exports: {} });

if (!data.WHO_HFA_BOYS_5_19?.length || !data.WHO_HFA_GIRLS_5_19?.length) {
  console.error('WHO tables not found');
  process.exit(1);
}
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify({
  hfa_boys_5_19: data.WHO_HFA_BOYS_5_19,
  hfa_girls_5_19: data.WHO_HFA_GIRLS_5_19,
  percentile_z: data.PERCENTILE_Z,
}, null, 1));
console.log(`Wrote ${data.WHO_HFA_BOYS_5_19.length}+${data.WHO_HFA_GIRLS_5_19.length} rows to ${out}`);
