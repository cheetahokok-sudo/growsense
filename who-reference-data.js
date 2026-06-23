// ══════════════════════════════════════════════════════════════════
// WHO 2007 Growth Reference — Height-for-age, 5–19 years
// Source: WHO Multicentre Growth Reference Study, "Growth reference
// 5-19 years" — official simplified field tables, fetched directly from:
//   https://cdn.who.int/media/docs/default-source/child-growth/
//   growth-reference-5-19-years/height-for-age-(5-19-years)/
//   sft-hfa-boys-perc-5-19years.pdf
//   sft-hfa-girls-perc-5-19years.pdf
// Every (months, p3, p15, p50, p85, p97) row below is transcribed
// directly from those official WHO PDFs — not estimated or interpolated
// by this app. This is the "2007 WHO Reference" for school-age children
// and adolescents (distinct from the 0–5y WHO Child Growth Standards,
// which use a different underlying sample and would need its own table
// if GrowSense is ever used for children under 5).
//
// Columns: months (completed months since birth), then height in cm at
// the 3rd, 15th, 50th (median), 85th, and 97th percentiles.
//
// Coverage: this is a SUBSET at ~6-month intervals for file size — see
// note in growth-percentile.js on interpolation between rows. The full
// WHO table is monthly; this subset preserves enough resolution for
// visual charting and percentile lookup with linear interpolation
// between adjacent rows (height-for-age curves are smooth/near-linear
// over 6-month windows in this age range, so this introduces negligible
// error relative to the underlying population variability itself).
// ══════════════════════════════════════════════════════════════════

const WHO_HFA_BOYS_5_19 = [
  // months, p3, p15, p50, p85, p97
  [61, 101.6, 105.5, 110.3, 115.0, 118.9],
  [67, 104.4, 108.5, 113.4, 118.4, 122.4],
  [72, 106.7, 110.8, 116.0, 121.1, 125.2],
  [78, 109.3, 113.6, 118.9, 124.2, 128.5],
  [84, 111.8, 116.3, 121.7, 127.2, 131.7],
  [90, 114.3, 118.9, 124.5, 130.2, 134.8],
  [96, 116.6, 121.4, 127.3, 133.1, 137.9],
  [102, 119.0, 123.9, 129.9, 136.0, 140.9],
  [108, 121.3, 126.3, 132.6, 138.8, 143.9],
  [114, 123.5, 128.8, 135.2, 141.6, 146.8],
  [120, 125.8, 131.2, 137.8, 144.4, 149.8],
  [126, 128.1, 133.6, 140.4, 147.2, 152.7],
  [132, 130.5, 136.1, 143.1, 150.1, 155.8],
  [138, 133.0, 138.8, 146.0, 153.1, 159.0],
  [144, 135.8, 141.7, 149.1, 156.4, 162.4],
  [150, 138.8, 144.9, 152.4, 160.0, 166.1],
  [156, 142.1, 148.3, 156.0, 163.7, 170.0],
  [162, 145.4, 151.8, 159.7, 167.5, 173.9],
  [168, 148.7, 155.2, 163.2, 171.2, 177.6],
  [174, 151.7, 158.3, 166.3, 174.4, 180.9],
  [180, 154.3, 160.9, 169.0, 177.0, 183.6],
  [186, 156.5, 163.1, 171.1, 179.2, 185.8],
  [192, 158.3, 164.8, 172.9, 181.0, 187.5],
  [198, 159.7, 166.2, 174.2, 182.2, 188.7],
  [204, 160.8, 167.2, 175.2, 183.1, 189.5],
  [210, 161.5, 167.9, 175.8, 183.6, 190.0],
  [216, 162.1, 168.4, 176.1, 183.9, 190.2],
  [222, 162.5, 168.7, 176.4, 184.0, 190.3],
  [228, 162.8, 169.0, 176.5, 184.1, 190.3]
];

const WHO_HFA_GIRLS_5_19 = [
  [61, 100.6, 104.7, 109.6, 114.5, 118.6],
  [67, 103.3, 107.5, 112.7, 117.8, 122.0],
  [72, 105.5, 109.8, 115.1, 120.4, 124.8],
  [78, 108.0, 112.5, 118.0, 123.5, 127.9],
  [84, 110.5, 115.1, 120.8, 126.5, 131.1],
  [90, 113.1, 117.8, 123.7, 129.5, 134.3],
  [96, 115.7, 120.5, 126.6, 132.6, 137.5],
  [102, 118.3, 123.3, 129.5, 135.7, 140.7],
  [108, 121.0, 126.2, 132.5, 138.8, 144.0],
  [114, 123.8, 129.1, 135.5, 142.0, 147.3],
  [120, 126.6, 132.0, 138.6, 145.3, 150.7],
  [126, 129.5, 135.0, 141.8, 148.6, 154.1],
  [132, 132.5, 138.1, 145.0, 151.9, 157.5],
  [138, 135.5, 141.2, 148.2, 155.2, 160.9],
  [144, 138.4, 144.1, 151.2, 158.3, 164.1],
  [150, 141.0, 146.8, 154.0, 161.2, 167.0],
  [156, 143.3, 149.2, 156.4, 163.6, 169.4],
  [162, 145.2, 151.1, 158.3, 165.5, 171.4],
  [168, 146.7, 152.6, 159.8, 167.0, 172.8],
  [174, 147.9, 153.7, 160.9, 168.1, 173.9],
  [180, 148.7, 154.5, 161.7, 168.8, 174.6],
  [186, 149.3, 155.1, 162.2, 169.3, 175.0],
  [192, 149.8, 155.5, 162.5, 169.6, 175.3],
  [198, 150.0, 155.7, 162.7, 169.7, 175.4],
  [204, 150.3, 155.9, 162.9, 169.8, 175.4],
  [210, 150.5, 156.1, 163.0, 169.9, 175.5],
  [216, 150.6, 156.2, 163.1, 169.9, 175.5],
  [222, 150.8, 156.3, 163.1, 169.9, 175.5],
  [228, 150.9, 156.4, 163.2, 169.9, 175.5]
];

// Standard normal Z-values corresponding to the 5 charted percentiles
// (3rd, 15th, 50th, 85th, 97th). Used to interpolate a continuous
// percentile from a height value that falls between two of these bands.
const PERCENTILE_Z = { p3: -1.881, p15: -1.036, p50: 0, p85: 1.036, p97: 1.881 };

if (typeof module !== 'undefined') {
  module.exports = { WHO_HFA_BOYS_5_19, WHO_HFA_GIRLS_5_19, PERCENTILE_Z };
}
