# GrowSense — Wearables & Biosensors Data Architecture

Programming schematic for multi-device biometric ingestion. Status: Fitbit/Google
Health is **live**; everything below the line is the **target schema** to build as
each provider is wired. Design goal: adding a provider is an Edge Function + a
registry entry (`lib/wearables.dart`) + a normalization mapping — never a rewrite.

---

## 1. What exists today (live)

```
Google OAuth  ──►  Edge Fn: google-health-auth  ──►  google_health_connections
(consent)          (code → tokens, server-side)      (access/refresh tokens, per child)
                                                            │
Edge Fn: google-health-sync  ◄── "Sync now" (Flutter/PWA) ─┘
     │  pulls Fitbit sleep (last N nights)
     ▼
daily_sleep  (already has: total_sleep_min, deep_sleep_min, rem_sleep_min,
              hrv_ms, wake_count, sleep_efficiency_score, data_source)
```

- Tokens never reach the client. Flutter reads the safe view
  `google_health_connection_status` (no tokens) and calls the two Edge Functions.
- Sleep normalizes into the existing `daily_sleep` row for that `log_date`, so the
  readiness score and Analytics trends consume wearable data with zero extra wiring.

---

## 2. Generalize connections: `wearable_connections`

Replace the Google-specific table with a provider-agnostic one (keep the Google
table as a view/alias during migration):

```sql
wearable_connections (
  connection_id   uuid pk,
  child_id        uuid  → children,
  parent_id       uuid  → user_accounts,
  provider        text,          -- 'fitbit' | 'whoop' | 'oura' | 'apple_health'
                                 --  | 'dexcom' | 'libre' | 'lingo' | 'muse' | ...
  external_user_id text,         -- provider's account id
  account_label   text,          -- email / handle shown to the parent
  access_token    text,          -- encrypted at rest; server-only (RLS: no select)
  refresh_token   text,
  token_expires_at timestamptz,
  scope           text,
  status          text,          -- 'active' | 'expired' | 'revoked'
  last_sync_at    timestamptz,
  last_sync_status text,
  last_sync_error text,
  created_at      timestamptz default now(),
  unique (child_id, provider)
)
-- Safe view for the client (mirrors google_health_connection_status):
wearable_connection_status  = wearable_connections MINUS the two token columns.
```

`lib/wearables.dart` already enumerates every provider + the `BioStream`s it
contributes, so the sync layer knows each provider's normalization target.

---

## 3. Two ingestion shapes

Biometrics split cleanly into **daily summaries** and **high-frequency series**.

### 3a. Daily summaries → keep in `daily_sleep` (+ a sibling for cardio)

Bands/rings/watches (Fitbit, WHOOP, Oura, Apple, Garmin) produce one row per night /
per day. Sleep already fits `daily_sleep`. Add a light sibling for daytime cardio
so HRV/resting-HR/steps have a home without bloating `daily_sleep`:

```sql
daily_biometrics (
  child_id, log_date,
  resting_hr_bpm  int,
  hrv_ms          numeric,      -- overnight/morning HRV
  steps           int,
  active_minutes  int,
  spo2_pct        numeric,
  skin_temp_delta numeric,      -- Oura-style temp deviation
  recovery_score  int,          -- WHOOP recovery / Oura readiness
  data_source     text,         -- provider id
  primary key (child_id, log_date)
)
```

### 3b. High-frequency series → `biometric_readings` (CGM, EEG, raw HR)

CGM emits a reading every 1–5 min; EEG headbands emit sleep-stage epochs. These are
time-series, not daily rows — a single generic table with a typed value keeps it
open-ended:

```sql
biometric_readings (
  reading_id   bigint pk,
  child_id     uuid → children,
  provider     text,           -- 'dexcom' | 'libre' | 'lingo' | 'muse' | 'frenz'
  metric       text,           -- 'glucose_mgdl' | 'eeg_stage' | 'heart_rate' | ...
  recorded_at  timestamptz,    -- exact sample time
  value_num    numeric,        -- e.g. 112  (glucose mg/dL)  OR  stage code 0–4
  value_text   text,           -- e.g. 'rem' | 'deep' | 'light' | 'wake' (EEG)
  meta         jsonb,          -- trend arrow, rate-of-change, signal quality, etc.
  index (child_id, provider, metric, recorded_at)
)
-- Roll-ups (nightly deep/REM minutes from EEG; daily glucose time-in-range) are
-- computed by a scheduled job into daily_sleep / daily_biometrics for fast charts.
```

---

## 4. Per-category integration notes

| Category | Providers | Auth | Cadence | Normalizes to |
|---|---|---|---|---|
| Bands / watches | Fitbit✅, WHOOP, Garmin | OAuth2 + provider API | nightly/daily | `daily_sleep`, `daily_biometrics` |
| Smart ring | Oura | OAuth2 (Oura API v2) | nightly | `daily_sleep`, `daily_biometrics` (+ temp) |
| Phone/watch hub | Apple Health, Samsung Health | **native SDK** (HealthKit / Health Connect) — needs the native iOS/Android build, not web | on-device | `daily_sleep`, `daily_biometrics` |
| CGM | Dexcom (API v3), FreeStyle Libre (LibreView), Lingo | OAuth2 | 1–5 min samples | `biometric_readings` (metric=`glucose_mgdl`) → daily time-in-range roll-up |
| EEG sleep | Muse, FRENZ/Dreem | OAuth2 or file import | 30-s epochs | `biometric_readings` (metric=`eeg_stage`) → nightly deep/REM minutes → `daily_sleep` |

**Why glucose matters here:** CGM gives metabolic context (post-meal spikes, overnight
stability) that interacts with sleep quality and the growth-hormone axis — surfaced as
"time in range" and overnight stability, never as a diagnosis.

**Why EEG matters here:** EEG is the gold standard for sleep staging. The growth model
already weights the first deep-sleep cycle (where most GH is released); EEG replaces the
wrist-estimated deep/REM minutes in `daily_sleep` with measured ones — a straight
accuracy upgrade to an input the model already consumes.

---

## 5. Client contract (already in place)

`lib/wearables.dart` — provider registry (`WearableProvider`, `BioStream`,
`DeviceCategory`), the single source the Devices screen renders from.
`AppState.loadWearableStatus()` / `syncFitbit()` / `connectFitbitWithCode()` — the
live Fitbit path. New providers add: an Edge Function pair (auth+sync), a status flip
in the registry, and a normalization mapping into §3.

---

## 6. Prerequisite for live connect from the Flutter app

The Google OAuth client currently authorizes redirect to the **PWA** root. To let the
Flutter app (`/growsense/app/`) complete the round-trip, add that URL as an authorized
redirect URI in the Google Cloud console. Until then: **status + sync work** from the
Flutter app against tokens already stored server-side; **initial connect** is done in
the web app. (`googleHealthRedirectUri` in `lib/wearables.dart` is already set to the
Flutter URL, ready for when the URI is registered.)
