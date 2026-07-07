// Regenerates assets/food_reference.json from the PWA's
// food-reference-data.js — which stays the single source of truth.
// Run from flutter_app/:  node tool/convert_food_data.js
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', '..', 'food-reference-data.js');
const out = path.join(__dirname, '..', 'assets', 'food_reference.json');

const code = fs.readFileSync(src, 'utf8');
// The file is a browser script (const FOOD_REFERENCE_DATA = [...]);
// evaluate it and pull the array out.
const sandbox = new Function(code + '\nreturn FOOD_REFERENCE_DATA;');
const data = sandbox();

if (!Array.isArray(data) || data.length === 0) {
  console.error('FOOD_REFERENCE_DATA not found or empty');
  process.exit(1);
}
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(data, null, 1));
console.log(`Wrote ${data.length} foods to ${out}`);
