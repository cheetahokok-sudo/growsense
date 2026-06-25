// ══════════════════════════════════════════════════════════════════
// Thai national growth reference — APPROXIMATE VALUES, READ BY EYE
// FROM CHART IMAGES/PDFS. NOT VERIFIED DATA. Read this whole comment
// before touching this file.
//
// Source: printed growth chart PDFs ("Boys/Girls aged 2-19 years:
// Height and Weight" and "...Weight for Height," Thai Society for
// Pediatric Endocrinology, 2022), citing "WHO Growth Standard for
// children aged 2-5 years, 2006" and "National Growth References for
// children aged 5-19 years, 2020, Bureau of Nutrition, Department of
// Health, Ministry of Public Health" as underlying data.
//
// WHY THIS IS LOWER-CONFIDENCE THAN EVERY OTHER DATASET IN THIS APP:
// every other reference table in GrowSense (who-reference-data.js,
// who-bmi-reference-data.js, who-reference-data-0-5.js) was transcribed
// from an official numeric source (a real L/M/S table) and independently
// verified — cross-checked against secondary sources, internal formula
// consistency confirmed to within ~0.05 units. This file has none of
// that. The numbers below were estimated by reading curve positions
// against printed gridlines — there is no official numeric table behind
// these specific values, and repeated searching did not turn up an open,
// structured Thai national LMS dataset to verify against. Treat these
// as a rough approximation for visual comparison only, not a clinically
// precise reference. Real precision would require the actual numeric
// table from the Thai Ministry of Public Health or the Thai Society
// for Pediatric Endocrinology directly.
//
// 2026-06-24 UPDATE #2 — independent corroboration check: a third party
// supplied a Python script ("growth_curve_engine.py") claiming to
// encode TSPE 2022 / Thai National Growth References 2020 height
// anchor points, reconstructed via PCHIP interpolation + Gaussian-sigma
// percentile-band expansion. This was actually run and checked, not
// just read: its Z-score constants are correct (verified against
// scipy.stats.norm.ppf), its output passes the same structural checks
// applied to data in this file (zero percentile-ordering violations,
// zero age-monotonicity violations across 205 sampled points), and its
// age-2 boundary value (87.8cm boys, 86.5cm girls P50) matches this
// project's own independently-verified WHO 2-5y data (87.82cm boys,
// 86.42cm girls, from who-reference-data-0-5.js) to within 0.1-0.2cm.
// Comparing its anchor points directly against the eye-read values in
// this file at 8 overlapping ages gave an average absolute difference
// of 1.09cm (boys P50), growing slightly at older ages (up to 2.5cm at
// age 13). This is treated as corroborating evidence that the values in
// this file are in a reasonable range — NOT as independent verification
// of either source, since the script's own anchor values have no
// stated extraction method or citation trail and could themselves be
// another estimate of the same uncertain thing rather than a true
// numeric source. Two unverified estimates agreeing is reassuring, not
// equivalent to one verified source. The values in this file were NOT
// changed based on this comparison.
//
// abandoned: the source PDFs (re-supplied as cleaner vector files rather
// than photographed images) do contain real embedded curve coordinate
// data, and an attempt was made to programmatically decode it (axis
// calibration from gridline/label positions, then mapping each curve
// object to its percentile label). That attempt produced internally
// contradictory results that couldn't be resolved with confidence after
// substantial effort — curve-to-label matching kept producing physically
// impossible values (height decreasing with age) depending on which
// matching heuristic was used, suggesting either an error in the
// decoding approach or a chart-construction quirk (e.g. height/weight
// panels sharing object indices in a way not yet understood) that
// wasn't pinned down. Per the project's standing rule of not shipping
// numbers that fail internal consistency checks, that approach was
// abandoned in favor of continuing with the eye-read method below,
// which has a known, stated error profile rather than an unresolved one.
// If revisiting this later: the PDFs do have real vector curve data
// (confirmed: `page.curves` in pdfplumber, ~14 wide curves per page,
// plain lineto path segments, not Bezier) — a fresh, careful attempt
// with more rigorous curve-to-label verification (e.g. checking
// monotonicity in age AND realistic magnitude at every candidate match,
// not just label-proximity) could likely succeed where this attempt
// didn't.
//
// Only 3 percentile lines (3rd/50th/97th) were extracted per chart, not
// all 7 shown (P3/P10/P25/P50/P75/P90/P97) — deliberately, to limit how
// much could be misread given the lower-precision method.
//
// Sanity-checked only at the level of: P3 < P50 < P97 at every age/
// height, and values don't decrease as age/height increases. NOT
// independently verified against any secondary source, because no such
// source was found.
// ══════════════════════════════════════════════════════════════════

// Height-for-age, 2-19 years. Columns: age (whole years), P3, P50, P97 (cm).
const THAI_HFA_BOYS_APPROX = [
  [2, 83, 88, 94],
  [3, 91, 96, 102],
  [4, 97, 103, 110],
  [5, 103, 110, 117],
  [6, 108, 116, 123],
  [7, 113, 121, 129],
  [8, 118, 127, 135],
  [9, 122, 132, 141],
  [10, 126, 137, 147],
  [11, 130, 142, 154],
  [12, 134, 148, 162],
  [13, 140, 156, 171],
  [14, 147, 163, 177],
  [15, 152, 168, 180],
  [16, 155, 171, 182],
  [17, 157, 172, 183],
  [18, 158, 173, 183],
  [19, 159, 173, 184]
];

const THAI_HFA_GIRLS_APPROX = [
  [2, 81, 87, 93],
  [3, 89, 95, 101],
  [4, 96, 102, 109],
  [5, 101, 108, 115],
  [6, 107, 114, 121],
  [7, 111, 119, 127],
  [8, 116, 124, 133],
  [9, 121, 130, 140],
  [10, 125, 136, 148],
  [11, 130, 143, 156],
  [12, 136, 150, 163],
  [13, 141, 155, 167],
  [14, 144, 157, 169],
  [15, 146, 158, 169],
  [16, 147, 159, 169],
  [17, 147, 159, 169],
  [18, 147, 159, 169],
  [19, 147, 159, 169]
];

// Weight-FOR-HEIGHT, 2-19 years (a different indicator from weight-for-
// AGE or BMI-for-age — this maps weight against the child's own height,
// not their age, so it's usable as a quick screening lens independent
// of exact age, and is the traditional tool for acute malnutrition
// ("wasting") screening). Read from "Boys/Girls aged 2-19 years: Weight
// for Height" charts, same source/caveats as above.
// Columns: height (cm, every 10cm), P3, P50, P97 (weight in kg).
const THAI_WFH_BOYS_APPROX = [
  [90, 11, 14, 16],
  [100, 14.5, 18, 21.5],
  [110, 18.5, 23, 27.5],
  [120, 23, 28.5, 34],
  [130, 28, 35, 42],
  [140, 33.5, 42.5, 51],
  [150, 39, 49, 60],
  [160, 44, 56, 69],
  [170, 48, 62, 77],
  [180, 51, 65, 81]
];

const THAI_WFH_GIRLS_APPROX = [
  [90, 11, 14, 16.5],
  [100, 14.5, 18.5, 22],
  [110, 19, 24, 28.5],
  [120, 24, 30.5, 36.5],
  [130, 29.5, 37.5, 45.5],
  [140, 34.5, 44, 54],
  [150, 38.5, 49.5, 61],
  [160, 41.5, 53.5, 67.5],
  [170, 44.5, 56.5, 76]
];

if (typeof module !== 'undefined') {
  module.exports = {
    THAI_HFA_BOYS_APPROX, THAI_HFA_GIRLS_APPROX,
    THAI_WFH_BOYS_APPROX, THAI_WFH_GIRLS_APPROX
  };
}
