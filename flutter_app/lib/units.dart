// ══════════════════════════════════════════════════════════════════
// Unit preference helpers — metric (default, all target markets) vs
// imperial (US families). DISPLAY-level only: everything is stored in
// metric (cm/kg), matching the Supabase schema and WHO references;
// imperial entry is converted to metric before save. Growth charts
// stay metric — WHO percentile charts are a metric clinical artifact.
// ══════════════════════════════════════════════════════════════════

const cmPerInch = 2.54;
const lbPerKg = 2.2046226218;

/// 'metric' | 'imperial'
String formatHeight(double cm, String units, {int decimals = 1}) {
  if (units != 'imperial') return '${cm.toStringAsFixed(decimals)} cm';
  final totalIn = cm / cmPerInch;
  final ft = totalIn ~/ 12;
  final inches = totalIn - ft * 12;
  return "$ft'${inches.toStringAsFixed(decimals)}\"";
}

String formatWeight(double kg, String units, {int decimals = 1}) {
  if (units != 'imperial') return '${kg.toStringAsFixed(decimals)} kg';
  return '${(kg * lbPerKg).toStringAsFixed(decimals)} lb';
}

/// Unit suffix for entry fields.
String heightUnitLabel(String units) => units == 'imperial' ? 'in' : 'cm';
String weightUnitLabel(String units) => units == 'imperial' ? 'lb' : 'kg';

/// Entry-field value → canonical metric for storage.
double entryToCm(double value, String units) =>
    units == 'imperial' ? value * cmPerInch : value;
double entryToKg(double value, String units) =>
    units == 'imperial' ? value / lbPerKg : value;

/// Canonical metric → entry-field display value.
double cmToEntry(double cm, String units) =>
    units == 'imperial' ? cm / cmPerInch : cm;
double kgToEntry(double kg, String units) =>
    units == 'imperial' ? kg * lbPerKg : kg;
