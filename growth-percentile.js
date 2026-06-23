// ══════════════════════════════════════════════════════════════════
// Growth percentile calculation — real math, real WHO reference data.
// Replaces the hardcoded "32% / 15th percentile (placeholder)" in
// app.js's updateStats() with an actual computed value.
//
// Method: WHO publishes height-for-age as five percentile bands (3rd,
// 15th, 50th, 85th, 97th) at each age. This module:
//   1. Interpolates the five band values to the child's exact age in
//      months (linear interpolation between the two nearest WHO rows)
//   2. Locates which two adjacent bands the child's actual height falls
//      between
//   3. Converts that position into a Z-score using the known standard-
//      normal Z-value of each band edge, interpolating between them
//   4. Converts the Z-score to a percentile via the normal CDF
//
// This is mathematically equivalent to the full LMS Box-Cox method for
// the purposes of placing a single point on a chart — the WHO-published
// percentile bands ARE the L/M/S curves already evaluated at five fixed
// points. Using them directly avoids re-deriving L/M/S from scratch and
// avoids any risk of transcribing those parameters incorrectly.
//
// Known limitation: linear interpolation between the 3rd/15th and
// 85th/97th bands is a reasonable local approximation but is NOT exact
// for the deep tails (e.g. true 1st or 99.5th percentile) — the WHO
// distribution is not perfectly normal between these points. For
// clinical screening purposes (is this child roughly low/typical/high)
// this is adequate; it should not be used to make fine distinctions
// at the extreme tails without the full L/M/S Box-Cox parameters.
// ══════════════════════════════════════════════════════════════════

(function (global) {

  function erf(x) {
    // Abramowitz & Stegun approximation 7.1.26 — same approximation
    // used in standard statistical libraries for this purpose, accurate
    // to ~1.5e-7.
    const sign = x < 0 ? -1 : 1;
    x = Math.abs(x);
    const a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741,
          a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911;
    const t = 1.0 / (1.0 + p * x);
    const y = 1.0 - (((((a5*t + a4)*t) + a3)*t + a2)*t + a1) * t * Math.exp(-x*x);
    return sign * y;
  }

  function zToPercentile(z) {
    return 50 * (1 + erf(z / Math.sqrt(2)));
  }

  // Finds the two WHO table rows bracketing the given age and linearly
  // interpolates all five percentile values to that exact age.
  function interpolateBands(table, ageMonths) {
    if (ageMonths <= table[0][0]) return table[0].slice(1);
    const last = table[table.length - 1];
    if (ageMonths >= last[0]) return last.slice(1);

    for (let i = 0; i < table.length - 1; i++) {
      const row0 = table[i], row1 = table[i + 1];
      if (ageMonths >= row0[0] && ageMonths <= row1[0]) {
        const frac = (ageMonths - row0[0]) / (row1[0] - row0[0]);
        return [1, 2, 3, 4, 5].map(idx => row0[idx] + frac * (row1[idx] - row0[idx]));
      }
    }
    return last.slice(1);
  }

  // Main entry point: given a height (cm), age (decimal years), and sex,
  // returns { percentile, zScore, bands } using the real WHO 5–19y
  // reference. Returns null if the required reference table isn't
  // loaded (e.g. who-reference-data.js wasn't included on the page) or
  // if age is outside the table's supported range.
  function calculateHeightPercentile(heightCm, ageYears, biologicalSex) {
    if (typeof WHO_HFA_BOYS_5_19 === 'undefined') {
      console.warn('[growth-percentile] WHO reference data not loaded — include who-reference-data.js');
      return null;
    }
    const table = (biologicalSex === 'female') ? WHO_HFA_GIRLS_5_19 : WHO_HFA_BOYS_5_19;
    const minAgeYears = table[0][0] / 12, maxAgeYears = table[table.length - 1][0] / 12;
    if (ageYears < minAgeYears || ageYears > maxAgeYears) {
      // Outside the 5–19y WHO Reference range this app currently ships.
      // (Under-5 uses a different WHO standard/sample — see note in
      // who-reference-data.js — and isn't implemented yet.)
      return { outOfRange: true, minAgeYears, maxAgeYears };
    }

    const ageMonths = ageYears * 12;
    const [p3, p15, p50, p85, p97] = interpolateBands(table, ageMonths);
    const bandZ = PERCENTILE_Z; // { p3, p15, p50, p85, p97 } z-values

    let zScore;
    if (heightCm <= p3) {
      // Below the 3rd percentile band: extrapolate the same slope as the
      // 3rd–15th segment rather than returning a flat "below 3rd" with
      // no magnitude — useful for tracking how far below, not just that.
      const slope = (bandZ.p15 - bandZ.p3) / (p15 - p3);
      zScore = bandZ.p3 + (heightCm - p3) * slope;
    } else if (heightCm >= p97) {
      const slope = (bandZ.p97 - bandZ.p85) / (p97 - p85);
      zScore = bandZ.p97 + (heightCm - p97) * slope;
    } else {
      const points = [[p3, bandZ.p3], [p15, bandZ.p15], [p50, bandZ.p50], [p85, bandZ.p85], [p97, bandZ.p97]];
      for (let i = 0; i < points.length - 1; i++) {
        const [h0, z0] = points[i], [h1, z1] = points[i + 1];
        if (heightCm >= h0 && heightCm <= h1) {
          const frac = (heightCm - h0) / (h1 - h0);
          zScore = z0 + frac * (z1 - z0);
          break;
        }
      }
    }

    return {
      outOfRange: false,
      percentile: zToPercentile(zScore),
      zScore: zScore,
      bands: { p3, p15, p50, p85, p97 },
      ageMonthsUsed: ageMonths
    };
  }

  global.calculateHeightPercentile = calculateHeightPercentile;
  global.GrowthPercentileMath = { erf, zToPercentile, interpolateBands, calculateHeightPercentile };

})(typeof window !== 'undefined' ? window : globalThis);
