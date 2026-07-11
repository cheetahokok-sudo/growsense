// ══════════════════════════════════════════════════════════════════
// Wearable & sensor provider registry.
//
// One data-driven catalogue of every device GrowSense integrates or
// plans to. Adding a provider is a config entry here, not a rewrite —
// the Devices screen renders straight from this list, grouped by
// category, and each provider declares which biometric streams it
// contributes so the ingestion layer knows where its data normalizes.
//
// Status today:
//   • Fitbit / Google Health — LIVE (OAuth + google-health-sync Edge
//     Function; sleep incl. deep/REM/HRV lands in daily_sleep).
//   • Everyone else — PLANNED: the connection UI and the target data
//     shape are defined (see docs/WEARABLES_SCHEMATIC.md) so wiring a
//     new provider is an Edge Function + a status flip here.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'theme.dart';

/// What kind of device it is — drives grouping on the Devices screen.
enum DeviceCategory { band, ring, watch, cgm, eeg }

/// Which normalized biometric streams a provider contributes. These map
/// to the ingestion targets in the schematic (daily_sleep today;
/// biometric_readings / glucose_readings once those tables land).
enum BioStream { sleep, sleepStages, hrv, restingHr, steps, activity, glucose, eegSleep, spo2, temperature }

enum ProviderStatus { live, planned }

class WearableProvider {
  final String id;
  final String name;
  final String vendor;
  final DeviceCategory category;
  final ProviderStatus status;
  final Color brand;
  final String emoji;
  final List<BioStream> streams;
  final String note; // one-line parent-facing description

  const WearableProvider({
    required this.id,
    required this.name,
    required this.vendor,
    required this.category,
    required this.status,
    required this.brand,
    required this.emoji,
    required this.streams,
    required this.note,
  });
}

const wearableProviders = <WearableProvider>[
  // ── Bands & watches (activity + sleep) ──
  WearableProvider(
    id: 'fitbit',
    name: 'Fitbit / Google Health',
    vendor: 'Google',
    category: DeviceCategory.band,
    status: ProviderStatus.live,
    brand: Color(0xFF00B0B9),
    emoji: '⌚',
    streams: [
      BioStream.sleep,
      BioStream.sleepStages,
      BioStream.hrv,
      BioStream.restingHr,
      BioStream.steps,
    ],
    note: 'Syncs nightly sleep — including deep, REM, and HRV — into the growth model.',
  ),
  WearableProvider(
    id: 'apple_health',
    name: 'Apple Health',
    vendor: 'Apple',
    category: DeviceCategory.watch,
    status: ProviderStatus.planned,
    brand: Color(0xFF111111),
    emoji: '🍎',
    streams: [
      BioStream.sleep,
      BioStream.sleepStages,
      BioStream.hrv,
      BioStream.restingHr,
      BioStream.steps,
      BioStream.activity,
    ],
    note: 'Apple Watch sleep, HRV, and activity via HealthKit (needs the native iOS build).',
  ),
  WearableProvider(
    id: 'whoop',
    name: 'WHOOP',
    vendor: 'WHOOP',
    category: DeviceCategory.band,
    status: ProviderStatus.planned,
    brand: Color(0xFF222222),
    emoji: '🔴',
    streams: [
      BioStream.sleep,
      BioStream.sleepStages,
      BioStream.hrv,
      BioStream.restingHr,
      BioStream.activity,
    ],
    note: 'Recovery, strain, and detailed sleep staging via the WHOOP API.',
  ),
  WearableProvider(
    id: 'oura',
    name: 'Oura Ring',
    vendor: 'Oura',
    category: DeviceCategory.ring,
    status: ProviderStatus.planned,
    brand: Color(0xFF4A4A6A),
    emoji: '💍',
    streams: [
      BioStream.sleep,
      BioStream.sleepStages,
      BioStream.hrv,
      BioStream.restingHr,
      BioStream.temperature,
    ],
    note: 'Ring-based sleep, HRV, resting heart rate, and body temperature trend.',
  ),
  WearableProvider(
    id: 'garmin',
    name: 'Garmin',
    vendor: 'Garmin',
    category: DeviceCategory.watch,
    status: ProviderStatus.planned,
    brand: Color(0xFF007CC3),
    emoji: '🧭',
    streams: [BioStream.sleep, BioStream.hrv, BioStream.steps, BioStream.activity],
    note: 'Sleep and activity from Garmin Connect.',
  ),
  WearableProvider(
    id: 'samsung_health',
    name: 'Samsung Health',
    vendor: 'Samsung',
    category: DeviceCategory.watch,
    status: ProviderStatus.planned,
    brand: Color(0xFF1428A0),
    emoji: '📱',
    streams: [BioStream.sleep, BioStream.hrv, BioStream.steps],
    note: 'Galaxy Watch sleep and activity (Health Connect on Android).',
  ),

  // ── Continuous glucose monitors ──
  WearableProvider(
    id: 'dexcom',
    name: 'Dexcom',
    vendor: 'Dexcom',
    category: DeviceCategory.cgm,
    status: ProviderStatus.planned,
    brand: Color(0xFF00A950),
    emoji: '🩸',
    streams: [BioStream.glucose],
    note: 'Continuous glucose (5-min readings) via the Dexcom API — for metabolic context.',
  ),
  WearableProvider(
    id: 'libre',
    name: 'FreeStyle Libre',
    vendor: 'Abbott',
    category: DeviceCategory.cgm,
    status: ProviderStatus.planned,
    brand: Color(0xFFFFB300),
    emoji: '🩸',
    streams: [BioStream.glucose],
    note: 'Abbott Libre glucose trends via LibreView.',
  ),
  WearableProvider(
    id: 'lingo',
    name: 'Lingo',
    vendor: 'Abbott',
    category: DeviceCategory.cgm,
    status: ProviderStatus.planned,
    brand: Color(0xFF6A2C91),
    emoji: '🩸',
    streams: [BioStream.glucose],
    note: 'Abbott Lingo consumer glucose biosensor.',
  ),

  // ── EEG sleep headbands ──
  WearableProvider(
    id: 'muse',
    name: 'Muse (EEG)',
    vendor: 'Interaxon',
    category: DeviceCategory.eeg,
    status: ProviderStatus.planned,
    brand: Color(0xFF2E7D6F),
    emoji: '🧠',
    streams: [BioStream.eegSleep, BioStream.sleepStages],
    note: 'EEG-based sleep staging — the gold standard for the deep-sleep growth-hormone window.',
  ),
  WearableProvider(
    id: 'frenz',
    name: 'FRENZ / Dreem (EEG)',
    vendor: 'EEG headband',
    category: DeviceCategory.eeg,
    status: ProviderStatus.planned,
    brand: Color(0xFF3949AB),
    emoji: '🧠',
    streams: [BioStream.eegSleep, BioStream.sleepStages],
    note: 'Research-grade EEG sleep staging from a headband.',
  ),
];

const deviceCategoryLabel = {
  DeviceCategory.band: 'Bands & watches',
  DeviceCategory.ring: 'Smart rings',
  DeviceCategory.watch: 'Watches & phones',
  DeviceCategory.cgm: 'Glucose sensors (CGM)',
  DeviceCategory.eeg: 'EEG sleep',
};

const bioStreamLabel = {
  BioStream.sleep: 'Sleep',
  BioStream.sleepStages: 'Sleep stages',
  BioStream.hrv: 'HRV',
  BioStream.restingHr: 'Resting HR',
  BioStream.steps: 'Steps',
  BioStream.activity: 'Activity',
  BioStream.glucose: 'Glucose',
  BioStream.eegSleep: 'EEG sleep',
  BioStream.spo2: 'SpO₂',
  BioStream.temperature: 'Temperature',
};

// ── Fitbit / Google Health OAuth (web) ──────────────────────────────
// Mirrors the PWA's flow. NOTE: the Google OAuth client must list the
// Flutter app URL as an authorized redirect URI for the round-trip to
// complete from here; until then, connect via the web app. Status and
// sync below work today against the already-stored server-side tokens.

const googleHealthClientId =
    '703084084864-g9vctf4sfaufjdqklmq4a11qsi3epk48.apps.googleusercontent.com';
const googleHealthRedirectUri =
    'https://www.growsense.life/app/';
const googleHealthScopes =
    'openid email https://www.googleapis.com/auth/googlehealth.sleep.readonly';

Uri buildFitbitAuthUrl(String childId, String csrf) =>
    Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
      queryParameters: {
        'client_id': googleHealthClientId,
        'redirect_uri': googleHealthRedirectUri,
        'response_type': 'code',
        'scope': googleHealthScopes,
        'access_type': 'offline',
        'prompt': 'consent',
        'state': '$childId:$csrf',
      },
    );

Color deviceCategoryColor(DeviceCategory c) => switch (c) {
      DeviceCategory.cgm => GsColors.flag,
      DeviceCategory.eeg => GsColors.measured,
      _ => GsColors.accent,
    };
