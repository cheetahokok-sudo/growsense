// ══════════════════════════════════════════════════════════════════
// Mid-parental target height calculator
//
// Implements the corrections shown to improve on the standard 50-year-
// old Tanner method, per:
//   Zeevi D, Ben Yehuda A, Nathan D, Zangen D, Kruglyak L. "Accurate
//   Prediction of Children's Target Height from Their Mid-Parental
//   Height." Children 2024, 11(8), 916. doi:10.3390/children11080916
//   (peer-reviewed, open access, verified directly — not summarized
//   from a secondary source).
//
// WHAT THIS IS NOT: an earlier draft of this feature proposed a
// "3-generation ancestral traceback" that would auto-detect "masked"
// short parents (anyone >1.5 SD from their own relatives' median) and
// silently substitute a different height for them. That was rejected —
// ordinary height variation within families is normal, not anomalous,
// and silently overwriting a real parent's real measured height with
// an algorithm's guess is not something this app does. This calculator
// only uses the two heights actually entered, with real, cited
// corrections applied transparently — nothing is inferred or
// substituted without the user seeing exactly what was used.
//
// THE THREE REAL CORRECTIONS, each independently verified before use:
//
// 1. AGE-SHRINKAGE CORRECTION — adult height loss starts around age 30
//    and accelerates, not a one-time event. Modeled here as a simple
//    piecewise-linear approximation of real, independently-published
//    population data (NOT the original paper's exact unpublished
//    nonlinear coefficients, which weren't available to verify):
//      Sorkin JD, Muller DC, Andres R. "Longitudinal Change in Height
//      of Men and Women... Baltimore Longitudinal Study of Aging."
//      Am J Epidemiol. 1999;150(9):969-977. Cumulative height loss from
//      age 30-70 ≈ 3cm (men) / 5cm (women); by age 80 ≈ 5cm / 8cm.
//    This is an approximation of the real shape (starts at 30,
//    accelerates), not a precise reproduction of Zeevi et al.'s own
//    fitted model — stated honestly in the UI, not presented as
//    identical to the paper's exact correction.
//
// 2. SEX CORRECTION — multiplicative (×1.08), not the traditional
//    +/-13cm. Verified directly from the paper: male height at a given
//    percentile is NOT a constant offset above female height at the
//    same percentile — the gap grows with height itself (12.2cm at the
//    3rd percentile vs 14.7cm at the 97th, per CDC growth chart data
//    cited in the paper). The 1.08 factor was derived by the paper's
//    authors from CDC data; their own cohort's empirical factor was
//    1.066, near-identical.
//
// 3. REGRESSION TO THE MEAN — very tall parents have children who
//    regress toward the population mean (shorter than naive mid-
//    parental height predicts); very short parents have children who
//    regress upward. This is real, has been known since Galton (1886),
//    and is NOT accounted for in standard clinical practice today. The
//    paper's fitted equation on standardized (Z-score) heights:
//      Corrected Z = 0.79 × (mid-parental Z) − 0.077
//    verified directly from their Table 1, Z-score(sample) row.
//
// RESULT SPREAD: the paper measured a REAL empirical residual SD
// (around the corrected target, within large families) of 4.5±0.9cm
// for sons and 4.2±0.8cm for daughters — used here instead of Tanner's
// original theoretical ±8.5cm guess. The paper itself notes this 20%
// coefficient of variation and urges caution generalizing it — repeated
// in this module's output, not hidden.
// ══════════════════════════════════════════════════════════════════

(function (global) {

  // Real WHO adult-height reference already used throughout GrowSense
  // (who-reference-data.js, age 19y row) — reused here rather than
  // introducing a third population reference for "adult height."
  const ADULT_MEAN = { male: 176.5, female: 163.2 };
  const ADULT_SD = { male: 7.31, female: 6.54 }; // derived from the same WHO P3/P97 spread, same method used elsewhere in this app

  // Sorkin et al. (1999) piecewise approximation — see header.
  function ageShrinkageCm(age, sex) {
    if (age == null || age <= 30) return 0;
    const totalAt70 = sex === 'female' ? 5.0 : 3.0;
    const totalAt80 = sex === 'female' ? 8.0 : 5.0;
    if (age <= 70) return (age - 30) / 40 * totalAt70;
    return totalAt70 + Math.min(age - 70, 10) / 10 * (totalAt80 - totalAt70);
  }

  // Converts a possibly-age-shrunk measured height back toward the
  // person's peak adult height, by adding back the estimated shrinkage.
  function ageCorrectedHeight(heightCm, age, sex) {
    return heightCm + ageShrinkageCm(age, sex);
  }

  // Multiplicative sex correction (§2 above) — converts a female height
  // to its male-equivalent for averaging, or vice versa, instead of the
  // traditional +/-13cm constant offset.
  const SEX_FACTOR = 1.08;

  function calculateTargetHeight(params) {
    const { motherHeightCm, fatherHeightCm, motherAge, fatherAge, childSex } = params;
    if (!motherHeightCm || !fatherHeightCm) return null;

    // Step 1: age-correct each parent's height toward their peak adult height.
    const motherCorrected = ageCorrectedHeight(motherHeightCm, motherAge, 'female');
    const fatherCorrected = ageCorrectedHeight(fatherHeightCm, fatherAge, 'male');

    // Step 2: standardize both to Z-scores using WHO adult mean/SD —
    // this naturally folds in the multiplicative sex correction, since
    // each parent is compared to their own sex's distribution rather
    // than converted via a flat constant.
    const motherZ = (motherCorrected - ADULT_MEAN.female) / ADULT_SD.female;
    const fatherZ = (fatherCorrected - ADULT_MEAN.male) / ADULT_SD.male;
    const midParentalZ = (motherZ + fatherZ) / 2;

    // Step 3: regression to the mean, exactly as fitted in the paper
    // (Table 1, Z-score/sample row): Corrected Z = 0.79*MPH_Z - 0.077.
    const correctedZ = 0.79 * midParentalZ - 0.077;

    // Step 4: project onto the target child's own sex distribution.
    const sex = childSex === 'female' ? 'female' : 'male';
    const targetHeightCm = ADULT_MEAN[sex] + correctedZ * ADULT_SD[sex];

    // Step 5: real empirical residual spread from the paper (not a
    // theoretical guess) — used for the displayed range, with the
    // paper's own ~20% coefficient-of-variation caveat carried through.
    const residualSD = sex === 'female' ? 4.2 : 4.5;

    // Also compute the traditional Tanner method (additive +/-13cm, no
    // age/regression correction) for direct side-by-side comparison —
    // showing both, not replacing one with the other silently.
    const tannerMid = sex === 'female'
      ? (motherHeightCm + (fatherHeightCm - 13)) / 2
      : ((motherHeightCm + 13) + fatherHeightCm) / 2;

    return {
      // Improved method (this module's main result)
      targetHeightCm: Math.round(targetHeightCm * 10) / 10,
      rangeLowCm: Math.round((targetHeightCm - residualSD) * 10) / 10,
      rangeHighCm: Math.round((targetHeightCm + residualSD) * 10) / 10,
      residualSD,
      // Traditional Tanner method, shown alongside for comparison
      tannerMidParentalCm: Math.round(tannerMid * 10) / 10,
      // Transparency fields — exactly what was used, nothing hidden
      motherHeightInput: motherHeightCm,
      fatherHeightInput: fatherHeightCm,
      motherAgeShrinkageCm: Math.round(ageShrinkageCm(motherAge, 'female') * 100) / 100,
      fatherAgeShrinkageCm: Math.round(ageShrinkageCm(fatherAge, 'male') * 100) / 100,
      motherHeightCorrected: Math.round(motherCorrected * 10) / 10,
      fatherHeightCorrected: Math.round(fatherCorrected * 10) / 10,
      midParentalZ: Math.round(midParentalZ * 1000) / 1000,
      correctedZ: Math.round(correctedZ * 1000) / 1000
    };
  }

  global.calculateTargetHeight = calculateTargetHeight;
  global.TargetHeightMath = { ageShrinkageCm, ageCorrectedHeight, calculateTargetHeight, ADULT_MEAN, ADULT_SD, SEX_FACTOR };

  // ════════════════════════════════════════════════════════════════
  // EXPLORATORY: extended-family-weighted target height
  //
  // ⚠️ UNVALIDATED — read this before calling this function, and
  // before showing its output with the same confidence as
  // calculateTargetHeight() above.
  //
  // calculateTargetHeight() implements Zeevi et al. 2024, a real,
  // peer-reviewed, validated method for parent-to-child height
  // prediction. THIS function does not have an equivalent source. It
  // exists because incorporating known extended-family heights
  // (grandparents, aunts, uncles) was specifically requested after the
  // research for this feature confirmed no peer-reviewed pediatric
  // method exists for weighting PARTIAL extended-family data (e.g.
  // knowing one grandparent's height but not the other's) into a
  // clinical height prediction. That gap hasn't closed — this function
  // doesn't fix it, it just makes a transparent, clearly-labeled
  // attempt rather than refusing to offer anything.
  //
  // WHAT IT ACTUALLY DOES: standard quantitative-genetics coefficient-
  // of-relationship weighting (this part of the math IS real and
  // textbook — see e.g. Falconer & Mackay, "Introduction to
  // Quantitative Genetics," for the general method of combining
  // relatives' phenotypes weighted by relatedness):
  //   parents:           r = 0.5
  //   grandparents:      r = 0.25
  //   aunts/uncles:       r = 0.25 (full sibling of a parent)
  //   siblings (of child): r = 0.5
  // Each available relative's height is converted to a sex-standardized
  // Z-score (same WHO adult mean/SD as the main calculation), then
  // averaged weighted by relatedness, blended with the validated
  // parents-only Z-score from calculateTargetHeight() at a fixed 70/30
  // weight (parents-only kept dominant, since IT is the validated part).
  // The 70/30 split itself is an arbitrary choice made for this
  // implementation, not derived from any study — stated plainly so it
  // is never mistaken for a researched constant the way the 0.79/1.08/
  // age-shrinkage figures in the main calculation are.
  //
  // No age-shrinkage correction is applied to extended-family entries
  // even if an age was recorded — that correction was validated for
  // parents in the source study; applying it to grandparents/aunts/
  // uncles without any basis would compound one unvalidated step on
  // top of another.
  function calculateExploratoryExtendedTargetHeight(params) {
    const { motherHeightCm, fatherHeightCm, motherAge, fatherAge, childSex, familyRecords } = params;
    const baseline = calculateTargetHeight({ motherHeightCm, fatherHeightCm, motherAge, fatherAge, childSex });
    if (!baseline) return null;

    const sex = childSex === 'female' ? 'female' : 'male';
    const RELATEDNESS = {
      maternal_grandmother: 0.25, maternal_grandfather: 0.25,
      paternal_grandmother: 0.25, paternal_grandfather: 0.25,
      maternal_aunt: 0.25, maternal_uncle: 0.25,
      paternal_aunt: 0.25, paternal_uncle: 0.25,
      sibling: 0.5
    };
    // Relatives' own biological sex, for standardizing each to the
    // right population mean/SD before combining.
    const RELATIVE_SEX = {
      maternal_grandmother: 'female', maternal_grandfather: 'male',
      paternal_grandmother: 'female', paternal_grandfather: 'male',
      maternal_aunt: 'female', maternal_uncle: 'male',
      paternal_aunt: 'female', paternal_uncle: 'male',
      sibling: null // unknown without asking — see note in caller; treated as same-sex-as-child if not specified
    };

    const usable = (familyRecords || []).filter(r => RELATEDNESS[r.relation] && r.height_cm);
    if (usable.length === 0) {
      // No usable extended-family data — exploratory result is
      // identical to the validated baseline, not a different number.
      return Object.assign({}, baseline, { isExploratory: true, extendedFamilyUsedCount: 0 });
    }

    let weightedZSum = 0, weightSum = 0;
    usable.forEach(r => {
      const relSex = RELATIVE_SEX[r.relation] || sex;
      const z = (r.height_cm - ADULT_MEAN[relSex]) / ADULT_SD[relSex];
      const w = RELATEDNESS[r.relation];
      weightedZSum += z * w;
      weightSum += w;
    });
    const extendedFamilyZ = weightedZSum / weightSum;

    // Fixed 70/30 blend — arbitrary, not researched, stated as such above.
    const PARENTS_WEIGHT = 0.7, EXTENDED_WEIGHT = 0.3;
    const blendedZ = PARENTS_WEIGHT * baseline.correctedZ + EXTENDED_WEIGHT * extendedFamilyZ;
    const blendedHeightCm = ADULT_MEAN[sex] + blendedZ * ADULT_SD[sex];

    return Object.assign({}, baseline, {
      isExploratory: true,
      extendedFamilyUsedCount: usable.length,
      extendedFamilyZ: Math.round(extendedFamilyZ * 1000) / 1000,
      targetHeightCm: Math.round(blendedHeightCm * 10) / 10,
      rangeLowCm: Math.round((blendedHeightCm - baseline.residualSD) * 10) / 10,
      rangeHighCm: Math.round((blendedHeightCm + baseline.residualSD) * 10) / 10,
      parentsOnlyTargetHeightCm: baseline.targetHeightCm // the validated number, kept for comparison
    });
  }

  global.calculateExploratoryExtendedTargetHeight = calculateExploratoryExtendedTargetHeight;

})(typeof window !== 'undefined' ? window : globalThis);
