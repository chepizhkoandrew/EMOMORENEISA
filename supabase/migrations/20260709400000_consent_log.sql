-- Append-only audit trail of consent acceptances (Terms & Conditions,
-- Privacy Policy). Previously nothing was recorded anywhere — the sign-in
-- screen only showed a passive "by continuing you agree..." link, with no
-- record tying a specific user to a specific document version at a specific
-- time. One row per (user, document, version) acceptance; never
-- updated/deleted from the client, only inserted — this is a record of
-- history, not current status.

CREATE TABLE IF NOT EXISTS consent_log (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  document    TEXT        NOT NULL CHECK (document IN ('terms', 'privacy', 'ai_data_sharing')),
  version     TEXT        NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS consent_log_user_id_idx ON consent_log(user_id);

ALTER TABLE consent_log ENABLE ROW LEVEL SECURITY;

-- Owner can read their own history and insert new acceptances. No UPDATE/
-- DELETE policy is defined on purpose — RLS denies both by default, keeping
-- this table append-only even for the owning user.
DROP POLICY IF EXISTS consent_log_owner_select ON consent_log;
CREATE POLICY consent_log_owner_select ON consent_log
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS consent_log_owner_insert ON consent_log;
CREATE POLICY consent_log_owner_insert ON consent_log
  FOR INSERT WITH CHECK (auth.uid() = user_id);
