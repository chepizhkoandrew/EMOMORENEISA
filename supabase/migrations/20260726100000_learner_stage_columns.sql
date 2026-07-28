-- Graduated level system: adds the 6-stage `learner_stage` ladder (replacing
-- the legacy 3-way `level` for deciding how much Spanish vs. native language
-- the tutor uses) plus immersion-mode and level-up-suggestion settings.
--
-- Step 1: add `learner_stage` nullable, no default yet — existing rows land
-- NULL so they can be explicitly backfilled below, instead of silently
-- inheriting whatever default we set. Existing users must NOT regress to a
-- zero-Spanish "absolute_beginner" start just because this column is new.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS learner_stage TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS immersion_mode TEXT NOT NULL DEFAULT 'guided';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS absolute_beginner_override BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS show_inline_translations BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS auto_suggest_level_up BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS stage_progress_count INTEGER NOT NULL DEFAULT 0;

-- Step 2: backfill existing rows from the legacy 3-way `level` column.
UPDATE profiles
SET learner_stage = CASE level
    WHEN 'intermediate' THEN 'intermediate'
    WHEN 'advanced'     THEN 'advanced'
    ELSE 'beginner'
END
WHERE learner_stage IS NULL;

-- Step 3: only NOW set the column default to 'absolute_beginner' — this
-- governs rows inserted AFTER this migration (genuinely new signups via the
-- existing handle_new_user() trigger in 20260710000000_auto_create_profile_trigger.sql),
-- never the rows just backfilled above.
ALTER TABLE profiles ALTER COLUMN learner_stage SET DEFAULT 'absolute_beginner';
ALTER TABLE profiles ALTER COLUMN learner_stage SET NOT NULL;
