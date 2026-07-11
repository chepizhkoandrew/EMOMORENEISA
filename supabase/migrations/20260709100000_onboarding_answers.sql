-- Captures each onboarding-quiz answer the moment the user confirms it,
-- instead of only the final synthesized profile written at the very end of
-- the 11-question flow. Users who drop off partway through an onboarding
-- voice quiz are common; without this, their answers left zero trace.

CREATE TABLE IF NOT EXISTS onboarding_answers (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  slot         TEXT        NOT NULL,
  transcript   TEXT        NOT NULL,
  recorded_at  TIMESTAMPTZ NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, slot)
);

CREATE INDEX IF NOT EXISTS onboarding_answers_user_id_idx ON onboarding_answers(user_id);

ALTER TABLE onboarding_answers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS onboarding_answers_owner ON onboarding_answers;
CREATE POLICY onboarding_answers_owner ON onboarding_answers
  FOR ALL USING (auth.uid() = user_id);
