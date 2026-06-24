// ══════════════════════════════════════════════════════════════════
// WHO Child Growth Standards (0-5 years) — percentile/Z-score calculation
// for both height-for-age and BMI-for-age, using the real Box-Cox LMS
// formula throughout (this dataset has genuine L/M/S for both indicators,
// unlike the 5-19y height-for-age dataset which only has percentile
// bands — see who-reference-data.js vs who-reference-data-0-5.js).
//
// THE MEASUREMENT-METHOD SWITCH (read this before changing anything):
// WHO's 0-5y standards split at 24 months because the measurement
// technique changes — recumbent length (lying down) before 2 years,
// standing height after. WHO's own documented conversion is:
//   standing height = recumbent length − 0.7 cm
// This module expects the caller to say which measurement TYPE was
// actually taken (not just the child's age), and converts to whichever
// table's expected type before doing the lookup — see measurementType
// param below. Getting this backwards silently shifts the result by
// 0.7cm, which is small but not negligible at this age, and matters
// for SGA catch-up monitoring specifically, where small differences in
// the early months are exactly what's being watched closely.
// ══════════════════════════════════════════════════════════════════

(function (global) {

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

  function boxCoxZScore(value, L, M, S) {
    if (Math.abs(L) < 1e-9) return Math.log(value / M) / S;
    return (Math.pow(value / M, L) - 1) / (L * S);
  }

  // Picks the right table for height, applying the 0.7cm conversion if
  // the measurement type doesn't match what that age band's table
  // expects. measurementType: 'recumbent' or 'standing'. If omitted,
  // assumes the conventional method for the age (recumbent under 2,
  // standing 2 and over) and applies no conversion — same default
  // behavior as just using the "right" table for age with no correction.
  function resolveHeightTableAndValue(heightCm, ageMonths, biologicalSex, measurementType) {
    const isUnder2 = ageMonths < 24;
    const sex = (biologicalSex === 'female') ? 'girls' : 'boys';
    const table0_2 = sex === 'girls' ? WHO_HFA_GIRLS_0_2 : WHO_HFA_BOYS_0_2;
    const table2_5 = sex === 'girls' ? WHO_HFA_GIRLS_2_5 : WHO_HFA_BOYS_2_5;

    let table = isUnder2 ? table0_2 : table2_5;
    let value = heightCm;

    if (measurementType === 'standing' && isUnder2) {
      // Standing measurement on a child whose age band expects recumbent
      // length — convert standing -> length per WHO's documented constant.
      value = heightCm + 0.7;
    } else if (measurementType === 'recumbent' && !isUnder2) {
      // Recumbent measurement on a child whose age band expects standing
      // height — convert length -> standing height.
      value = heightCm - 0.7;
    }
    // If measurementType is omitted or already matches the age band's
    // convention, value is used as-is with no conversion.

    return { table, value };
  }

  // Main entry: height-for-age, 0-5 years. ageMonths must be < 60 (the
  // caller — app.js — should route to the 5-19y module for older ages;
  // this module returns outOfRange rather than silently extrapolating
  // if called outside 0-5y).
  function calculateHeightPercentile0to5(heightCm, ageMonths, biologicalSex, measurementType) {
    if (typeof WHO_HFA_BOYS_0_2 === 'undefined') {
      console.warn('[growth-percentile-0-5] WHO 0-5y reference data not loaded — include who-reference-data-0-5.js');
      return null;
    }
    if (ageMonths < 0 || ageMonths > 60) {
      return { outOfRange: true, minAgeMonths: 0, maxAgeMonths: 60 };
    }

    const { table, value } = resolveHeightTableAndValue(heightCm, ageMonths, biologicalSex, measurementType);
    const { L, M, S } = interpolateLMS(table, ageMonths);
    const zScore = boxCoxZScore(value, L, M, S);
    const { zToPercentile } = getMathHelpers();

    return {
      outOfRange: false,
      percentile: zToPercentile(zScore),
      zScore,
      lms: { L, M, S },
      convertedValue: value,  // the value actually used after any 0.7cm conversion, for transparency/debugging
      tableUsed: ageMonths < 24 ? '0-2y (length)' : '2-5y (height)'
    };
  }

  // BMI-for-age, 0-5 years. BMI itself doesn't need the 0.7cm conversion
  // applied to it directly — but the HEIGHT used to compute that BMI
  // does, per WHO's own note ("change height to length... BEFORE
  // calculating BMI"). This function expects the caller to have already
  // computed BMI correctly (i.e. having applied any needed height
  // conversion before dividing by height² — see saveDay()/addMeasurement()
  // for where that should happen) and just does the percentile lookup.
  function calculateBMIPercentile0to5(bmi, ageMonths, biologicalSex) {
    if (typeof WHO_BMI_0_5_BOYS_0_2 === 'undefined') {
      console.warn('[growth-percentile-0-5] WHO 0-5y BMI reference data not loaded — include who-reference-data-0-5.js');
      return null;
    }
    if (ageMonths < 0 || ageMonths > 60) {
      return { outOfRange: true, minAgeMonths: 0, maxAgeMonths: 60 };
    }

    const isUnder2 = ageMonths < 24;
    const sex = (biologicalSex === 'female') ? 'girls' : 'boys';
    const table = isUnder2
      ? (sex === 'girls' ? WHO_BMI_0_5_GIRLS_0_2 : WHO_BMI_0_5_BOYS_0_2)
      : (sex === 'girls' ? WHO_BMI_0_5_GIRLS_2_5 : WHO_BMI_0_5_BOYS_2_5);

    const { L, M, S } = interpolateLMS(table, ageMonths);
    const zScore = boxCoxZScore(bmi, L, M, S);
    const { zToPercentile } = getMathHelpers();
    const percentile = zToPercentile(zScore);

    // Same WHO-stated thresholds as the 5-19y module, for consistency —
    // these cutoffs are the same +1SD/+2SD/-2SD/-3SD definitions WHO
    // uses across both the 0-5y standards and the 5-19y reference.
    let classification;
    if (zScore > 2) classification = 'obesity';
    else if (zScore > 1) classification = 'overweight';
    else if (zScore < -3) classification = 'severe_thinness';
    else if (zScore < -2) classification = 'thinness';
    else classification = 'healthy_range';

    return {
      outOfRange: false,
      percentile, zScore, classification,
      lms: { L, M, S },
      tableUsed: isUnder2 ? '0-2y' : '2-5y'
    };
  }

  // Derives the same 5 percentile bands (3rd/15th/50th/85th/97th) the
  // chart code already knows how to render, computed directly from the
  // real interpolated L/M/S at this exact age — not a separate
  // approximation, just the inverse Box-Cox transform evaluated at the
  // same 5 standard-normal Z-values used everywhere else in this app
  // (PERCENTILE_Z, defined in who-reference-data.js). Returns
  // [p3, p15, p50, p85, p97] in that order, matching interpolateBands()'s
  // return shape in growth-percentile.js so chart code can treat both
  // datasets the same way.
  function lmsToValue(L, M, S, z) {
    if (Math.abs(L) < 1e-9) return M * Math.exp(S * z);
    return M * Math.pow(1 + L * S * z, 1 / L);
  }

  function deriveBandsFromLMS(table, ageMonths) {
    const { L, M, S } = interpolateLMS(table, ageMonths);
    const z = (typeof PERCENTILE_Z !== 'undefined') ? PERCENTILE_Z : { p3:-1.881, p15:-1.036, p50:0, p85:1.036, p97:1.881 };
    return [
      lmsToValue(L, M, S, z.p3),
      lmsToValue(L, M, S, z.p15),
      lmsToValue(L, M, S, z.p50),
      lmsToValue(L, M, S, z.p85),
      lmsToValue(L, M, S, z.p97)
    ];
  }

  // Picks the right height table for a given age/sex, WITHOUT applying
  // any measurement-method conversion — for chart-band rendering, where
  // we want the reference curve itself, not a specific child's converted
  // measurement. (Use resolveHeightTableAndValue() instead when you have
  // an actual measurement to convert.)
  function heightTableFor(ageMonths, biologicalSex) {
    const sex = (biologicalSex === 'female') ? 'girls' : 'boys';
    return ageMonths < 24
      ? (sex === 'girls' ? WHO_HFA_GIRLS_0_2 : WHO_HFA_BOYS_0_2)
      : (sex === 'girls' ? WHO_HFA_GIRLS_2_5 : WHO_HFA_BOYS_2_5);
  }

  function bmiTableFor(ageMonths, biologicalSex) {
    const sex = (biologicalSex === 'female') ? 'girls' : 'boys';
    return ageMonths < 24
      ? (sex === 'girls' ? WHO_BMI_0_5_GIRLS_0_2 : WHO_BMI_0_5_BOYS_0_2)
      : (sex === 'girls' ? WHO_BMI_0_5_GIRLS_2_5 : WHO_BMI_0_5_BOYS_2_5);
  }

  global.calculateHeightPercentile0to5 = calculateHeightPercentile0to5;
  global.calculateBMIPercentile0to5 = calculateBMIPercentile0to5;
  global.GrowthPercentile0to5Math = {
    interpolateLMS, boxCoxZScore, resolveHeightTableAndValue,
    calculateHeightPercentile0to5, calculateBMIPercentile0to5,
    deriveBandsFromLMS, heightTableFor, bmiTableFor
  };

})(typeof window !== 'undefined' ? window : globalThis);
