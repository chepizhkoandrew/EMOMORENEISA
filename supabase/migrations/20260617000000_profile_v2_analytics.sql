-- Professor Madrid — Profile v2 + Analytics Layer
-- Migration: 20260617000000_profile_v2_analytics.sql
--
-- What this adds:
--   1. Enriched student profile columns (word bank, phrase bank, error log,
--      session summaries, weak/mastered areas, personal context)
--   2. analyst_events table — one row per assistant turn, written by iOS
--      background analyst task. Source of truth for all analytics and nightly jobs.
--   3. profile_updates audit log — every profile field change with source + reason.

-- ─── 1. profiles: new enriched columns ──────────────────────────────────────

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS word_bank         JSONB    DEFAULT '[]';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phrase_bank        JSONB    DEFAULT '[]';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS error_log          JSONB    DEFAULT '[]';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS session_summaries  JSONB    DEFAULT '[]';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS weak_areas         TEXT[]   DEFAULT '{}';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS mastered_areas     TEXT[]   DEFAULT '{}';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS life_notes         TEXT     DEFAULT '';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS hobbies            TEXT[]   DEFAULT '{}';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS why_learning       TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS practice_style     TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS target_level       TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS exercise_history   TEXT[]   DEFAULT '{}';

-- ─── 2. analyst_events ──────────────────────────────────────────────────────
--
-- Written by the iOS ProfileAnalystService after every assistant message turn.
-- Contains the raw exchange and the full structured JSON the extraction LLM produced.
-- Used for:
--   - Debugging (what did the analyst extract from this conversation?)
--   - Nightly batch jobs (reprocess, aggregate, update profiles server-side)
--   - Analytics dashboards (vocabulary growth, error rates, engagement)
--   - Regression testing (did a prompt change break extraction quality?)

CREATE TABLE IF NOT EXISTS analyst_events (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id        UUID        NOT NULL REFERENCES sessions(id)   ON DELETE CASCADE,
  message_id        UUID        NOT NULL,
  user_message      TEXT,
  tutor_reply       TEXT        NOT NULL,

  -- Full JSON result from the extraction prompt.
  -- Schema defined in docs/data-models.md (ExtractionResult)
  extracted         JSONB       NOT NULL DEFAULT '{}',

  -- Denormalized columns for fast analytics queries (no JSON parsing needed)
  words_count       INT         GENERATED ALWAYS AS (
                                  jsonb_array_length(COALESCE(extracted->'words_introduced', '[]'::jsonb))
                                ) STORED,
  phrases_count     INT         GENERATED ALWAYS AS (
                                  jsonb_array_length(COALESCE(extracted->'phrases_introduced', '[]'::jsonb))
                                ) STORED,
  errors_count      INT         GENERATED ALWAYS AS (
                                  jsonb_array_length(COALESCE(extracted->'errors_corrected', '[]'::jsonb))
                                ) STORED,
  has_life_fact     BOOLEAN     GENERATED ALWAYS AS (
                                  extracted->>'student_life_fact' IS NOT NULL
                                  AND extracted->>'student_life_fact' != 'null'
                                ) STORED,

  processed_at      TIMESTAMPTZ DEFAULT NOW(),
  analyst_version   TEXT        DEFAULT 'v1'
);

CREATE INDEX IF NOT EXISTS analyst_events_user_id_idx      ON analyst_events(user_id);
CREATE INDEX IF NOT EXISTS analyst_events_session_id_idx   ON analyst_events(session_id);
CREATE INDEX IF NOT EXISTS analyst_events_processed_at_idx ON analyst_events(processed_at DESC);

ALTER TABLE analyst_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "analyst_events_owner" ON analyst_events
  FOR ALL USING (auth.uid() = user_id);

-- Service role used by Edge Functions and nightly cron jobs
CREATE POLICY "analyst_events_service" ON analyst_events
  FOR ALL TO service_role USING (true);

-- ─── 3. profile_updates audit log ────────────────────────────────────────────
--
-- Every change to the student profile is recorded here with:
--   - who changed it (source)
--   - what changed (field_changed)
--   - what it was before / after
--   - which analyst event triggered it (if applicable)
--
-- This lets us:
--   - Audit profile drift over time
--   - Roll back incorrect extractions
--   - Measure how fast the profile fills up

CREATE TABLE IF NOT EXISTS profile_updates (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source            TEXT        NOT NULL CHECK (source IN (
                                  'ios_analyst',
                                  'nightly_job',
                                  'session_summary',
                                  'manual'
                                )),
  field_changed     TEXT        NOT NULL,
  previous_value    JSONB,
  new_value         JSONB,
  trigger_event_id  UUID        REFERENCES analyst_events(id),
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS profile_updates_user_id_idx    ON profile_updates(user_id);
CREATE INDEX IF NOT EXISTS profile_updates_created_at_idx ON profile_updates(created_at DESC);

ALTER TABLE profile_updates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profile_updates_owner" ON profile_updates
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "profile_updates_service" ON profile_updates
  FOR ALL TO service_role USING (true);
