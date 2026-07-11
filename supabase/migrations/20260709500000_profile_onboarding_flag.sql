-- Single, explicit "has this user finished onboarding" flag — replaces the
-- implicit onboarding_profile IS NOT NULL check as the gate for BOTH the
-- feature-tour carousel and the voice quiz, so QA can force either one to
-- replay by flipping a single column and relaunching the app.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS has_completed_onboarding BOOLEAN NOT NULL DEFAULT false;
