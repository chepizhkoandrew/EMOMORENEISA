-- Backend-owned record of every onboarding-quiz synthesis. Previously the
-- server computed this (via Gemini) but only ever handed it back to the
-- client to persist — the backend itself never remembered anything. This
-- table is written directly by /v1/onboarding/synthesize (server/src/index.js)
-- using the service-role client, independent of whether the client's own
-- write (profiles.onboarding_profile) ever completes. Deliberately a
-- separate table rather than another write into profiles.onboarding_profile:
-- that column's exact JSON shape is a private contract of the iOS client's
-- Swift Codable model (verified: no snake_case key-conversion is configured
-- in the Supabase Swift SDK, so matching it byte-for-byte from Node would be
-- fragile to changes on either side). This is the foundation for any future
-- backend-side profile-building/refresh logic.

CREATE TABLE IF NOT EXISTS onboarding_syntheses (
  user_id              UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  quiz_version         INT         NOT NULL,
  pronoun              TEXT        NOT NULL,
  quiz_language        TEXT        NOT NULL,
  tutor_cheat_sheet    TEXT        NOT NULL,
  narrative_summary    TEXT        NOT NULL,
  about_me_user_facing TEXT        NOT NULL,
  city_flavor          TEXT        NOT NULL,
  extracted_slots      JSONB       NOT NULL DEFAULT '{}',
  level_breakdown      JSONB       NOT NULL DEFAULT '{}',
  voice_tag            TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE onboarding_syntheses ENABLE ROW LEVEL SECURITY;

-- Read-only to the owning user; only the server (service role) writes.
DROP POLICY IF EXISTS onboarding_syntheses_owner_read ON onboarding_syntheses;
CREATE POLICY onboarding_syntheses_owner_read ON onboarding_syntheses
  FOR SELECT USING (auth.uid() = user_id);
