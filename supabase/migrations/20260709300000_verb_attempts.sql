-- The verb-conjugation quiz previously threw away every result: no table, no
-- local persistence, no analytics event. Results vanished the moment a round
-- ended or the app was backgrounded. This table is the Supabase mirror of
-- the local SwiftData VerbAttempt model — one row per word attempt, written
-- the moment a cell is marked correct/missed, including partial/abandoned
-- rounds. Local SwiftData is the source of truth for the on-device stats
-- screen; this is the backup/future cross-device-analysis mirror, following
-- the same pattern as `sessions`.

CREATE TABLE IF NOT EXISTS verb_attempts (
  id                   UUID        PRIMARY KEY,
  user_id              UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  round_id             UUID        NOT NULL,
  verb_infinitive      TEXT        NOT NULL,
  verb_type            TEXT        NOT NULL,
  pronoun              TEXT        NOT NULL,
  tense                TEXT        NOT NULL,
  expected_conjugation TEXT        NOT NULL,
  user_transcript      TEXT        NOT NULL DEFAULT '',
  correct              BOOLEAN     NOT NULL,
  is_joker             BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS verb_attempts_user_id_idx ON verb_attempts(user_id);
CREATE INDEX IF NOT EXISTS verb_attempts_round_id_idx ON verb_attempts(round_id);

ALTER TABLE verb_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS verb_attempts_owner ON verb_attempts;
CREATE POLICY verb_attempts_owner ON verb_attempts
  FOR ALL USING (auth.uid() = user_id);
