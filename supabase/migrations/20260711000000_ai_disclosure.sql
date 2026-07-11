-- Apple rejection (Guideline 5.1.1(i) / 5.1.2(i), July 11 2026): the app must
-- explain what data is sent to third-party AI services, name them, and get
-- the user's permission BEFORE sharing — and this cannot live only in the
-- Terms/Privacy Policy. Adds a dedicated timestamp so we can gate every
-- signed-in user (new and existing) behind a standalone in-app disclosure
-- screen until they explicitly accept it, mirroring the existing
-- has_completed_onboarding gating pattern.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS ai_disclosure_accepted_at TIMESTAMPTZ;
