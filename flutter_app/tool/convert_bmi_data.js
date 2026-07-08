// Regenerates assets/who_bmi_reference.json from the PWA's
// who-bmi-reference-data.js (the source of truth — real WHO 2007
// BMI-for-age L/M/S tables). Run from flutter_app/:
//   node tool/convert_bmi_data.js
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', '..', 'who-bmi-reference-data.js');
const out = path.join(__dirname, '..', 'assets', 'who_bmi_reference.json');

const code = fs.readFileSync(src, 'utf8');
const sandbox = new Function(
  'module',
  code + '\nreturn { WHO_BMI_BOYS_5_19, WHO_BMI_GIRLS_5_19 };'
);
const data = sandbox({ exports: {} });

if (!data.WHO_BMI_BOYS_5_19?.length || !data.WHO_BMI_GIRLS_5_19?.length) {
  console.error('BMI tables not found');
  process.exit(1);
}
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify({
  bmi_boys_5_19: data.WHO_BMI_BOYS_5_19,
  bmi_girls_5_19: data.WHO_BMI_GIRLS_5_19,
}, null, 0));
console.log(`Wrote ${data.WHO_BMI_BOYS_5_19.length}+${data.WHO_BMI_GIRLS_5_19.length} LMS rows to ${out}`);
