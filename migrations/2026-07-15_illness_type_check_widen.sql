-- ════════════════════════════════════════════════════════════════════
-- Widen illness_events.illness_type CHECK to accept the Flutter app's
-- richer illness taxonomy (2026-07-15).
--
-- WHY: the original CHECK (created with the table in the Supabase
-- dashboard) only allows the PWA's 9 coarse ids:
--   fever, cold_respiratory, ear_infection, stomach_gi, flu,
--   skin_rash, injury, hospitalization, other
-- The Flutter app ships a richer reference (assets/illness_reference
-- .json) whose ids are: fever, cold, flu, rsv, covid, gastroenteritis,
-- hfmd, strep, asthma_flare, ear, skin, injury, hospital, other.
-- Any Flutter log with a non-overlapping id (e.g. skin, hospital)
-- failed with: new row for relation "illness_events" violates check
-- constraint — found in exploratory testing on TestFlight build #3.
--
-- FIX DIRECTION: widen the DB constraint (union of both sets) instead
-- of squashing Flutter ids down, because (a) the richer taxonomy is
-- better clinical data — RSV/COVID/HFMD/strep matter in our markets,
-- (b) both read paths already fall back to the raw id for labels, and
-- (c) the already-submitted iOS build #3 becomes fully functional with
-- no rebuild.
--
-- Idempotent: drops whatever CHECK currently guards illness_type
-- (name unknown — table wasn't created from a repo migration), then
-- adds the widened one under a stable name.
-- ════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.illness_events'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%illness_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.illness_events DROP CONSTRAINT %I', c.conname);
  END LOOP;

  EXECUTE $sql$
    ALTER TABLE public.illness_events
      ADD CONSTRAINT illness_events_illness_type_check
      CHECK (illness_type IN (
        -- PWA (legacy, keep valid)
        'fever', 'cold_respiratory', 'ear_infection', 'stomach_gi',
        'flu', 'skin_rash', 'injury', 'hospitalization', 'other',
        -- Flutter illness_reference.json (richer taxonomy)
        'cold', 'rsv', 'covid', 'gastroenteritis', 'hfmd', 'strep',
        'asthma_flare', 'ear', 'skin', 'hospital'
      ))
  $sql$;
END $$;

-- Verify:
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conrelid = 'public.illness_events'::regclass AND contype = 'c';
