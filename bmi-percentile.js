// ══════════════════════════════════════════════════════════════════
// BMI-for-age percentile/Z-score calculation — WHO 2007 Reference,
// full Box-Cox LMS method (not the band-interpolation shortcut used
// for height-for-age, since BMI's L parameter genuinely varies across
// this age range rather than staying near 1 — see who-bmi-reference-
// data.js header for why this distinction matters and how the source
// data was verified).
//
// The Box-Cox transform converts a raw measurement X into a Z-score
// using age-specific L (skewness), M (median), S (CV) parameters:
//   Z = ((X/M)^L - 1) / (L*S)         when L != 0
//   Z = ln(X/M) / S                    when L == 0 (limiting case)
//
// This is the standard method WHO and CDC both use for their official
// growth references — the same formula, just applied directly here
// instead of via the percentile-band shortcut.
// ══════════════════════════════════════════════════════════════════

(function (global) {

  // Re-use the same erf()/zToPercentile() approximation already defined
  // in growth-percentile.js if present, to avoid duplicating the same
  // numerical approximation in two places with potentially different
  // precision. Falls back to a local copy if that file wasn't loaded
  // (keeps this module independently usable).
  function getMathHelpers() {
    if (global.GrowthPercentileMath) return global.GrowthPercentileMath;
    function erf(x) {
      const sign = x < 0 ? -1 : 1;
      x = Math.abs(x);
      const a1=0.254829592,a2=-0.284496736,a3=1.421413741,a4=-1.453152027,a5=1.061405429,p=0.3275911;
      const t = 1.0/(1.0+p*x);
      const y = 1.0-(((((a5*t+a4)*t)+a3)*t+a2)*t+a1)*t*Math.exp(-x*x);
      return sign*y;
    }
    function zToPercentile(z) { return 50*(1+erf(z/Math.sqrt(2))); }
    return { erf, zToPercentile };
  }

  // Finds the two bracketing rows for the given age-in-months and
  // linearly interpolates L, M, S to that exact age. Same interpolation
  // pattern as growth-percentile.js's interpolateBands(), applied here
  // to the three LMS parameters instead of five percentile values.
  function interpolateLMS(table, ageMonths) {
    if (ageMonths <= table[0][0]) { const r = table[0]; return { L:r[1], M:r[2], S:r[3] }; }
    const last = table[table.length-1];
    if (ageMonths >= last[0]) return { L:last[1], M:last[2], S:last[3] };

    for (let i = 0; i < table.length - 1; i++) {
      const row0 = table[i], row1 = table[i+1];
      if (ageMonths >= row0[0] && ageMonths <= row1[0]) {
        const frac = (ageMonths - row0[0]) / (row1[0] - row0[0]);
        return {
          L: row0[1] + frac*(row1[1]-row0[1]),
          M: row0[2] + frac*(row1[2]-row0[2]),
          S: row0[3] + frac*(row1[3]-row0[3])
        };
      }
    }
    return { L:last[1], M:last[2], S:last[3] };
  }

  // The Box-Cox transform itself: raw BMI -> Z-score, given L/M/S at
  // this child's exact age.
  function bmiToZScore(bmi, L, M, S) {
    if (Math.abs(L) < 1e-9) return Math.log(bmi / M) / S;
    return (Math.pow(bmi / M, L) - 1) / (L * S);
  }

  // Main entry point: given BMI (kg/m²), age (decimal years), and sex,
  // returns { percentile, zScore, classification } using the WHO 2007
  // BMI-for-age reference. Returns null/outOfRange the same way
  // calculateHeightPercentile() does, for consistent handling in app.js.
  function calculateBMIPercentile(bmi, ageYears, biologicalSex) {
    if (typeof WHO_BMI_BOYS_5_19 === 'undefined') {
      console.warn('[bmi-percentile] WHO BMI reference data not loaded — include who-bmi-reference-data.js');
      return null;
    }
    const table = (biologicalSex === 'female') ? WHO_BMI_GIRLS_5_19 : WHO_BMI_BOYS_5_19;
    const minAgeYears = table[0][0] / 12, maxAgeYears = table[table.length-1][0] / 12;
    if (ageYears < minAgeYears || ageYears > maxAgeYears) {
      return { outOfRange: true, minAgeYears, maxAgeYears };
    }

    const { L, M, S } = interpolateLMS(table, ageYears * 12);
    const zScore = bmiToZScore(bmi, L, M, S);
    const { zToPercentile } = getMathHelpers();
    const percentile = zToPercentile(zScore);

    // WHO's own published clinical thresholds for this exact reference
    // (see FORMULAS.md citation): overweight > +1SD, obesity > +2SD,
    // thinness < -2SD, severe thinness < -3SD. These are WHO's stated
    // cutoffs, not invented categories.
    let classification;
    if (zScore > 2) classification = 'obesity';
    else if (zScore > 1) classification = 'overweight';
    else if (zScore < -3) classification = 'severe_thinness';
    else if (zScore < -2) classification = 'thinness';
    else classification = 'healthy_range';

    return { outOfRange: false, percentile, zScore, classification, lms: { L, M, S } };
  }

  global.calculateBMIPercentile = calculateBMIPercentile;
  global.BMIPercentileMath = { interpolateLMS, bmiToZScore, calculateBMIPercentile };

})(typeof window !== 'undefined' ? window : globalThis);
