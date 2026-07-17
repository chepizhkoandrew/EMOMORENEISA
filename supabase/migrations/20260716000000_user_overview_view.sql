-- Human-readable "everything about a user" view — joins profiles + wallets
-- into one row per user for browsing in Supabase Studio. Columns are
-- ordered most -> least important and renamed to plain English; JSONB
-- arrays are collapsed to counts and text[] columns to comma-separated
-- strings so the table editor is actually readable at a glance.
--
-- security_invoker = true: without it, a view runs with its *creator's*
-- privileges and silently bypasses the RLS policies on profiles/wallets
-- (auth.uid() = id / auth.uid() = user_id). Setting it means the view
-- enforces the same per-user RLS as the underlying tables if it's ever
-- queried through the app's API, while still working normally for admins
-- in Supabase Studio (which connects as postgres and bypasses RLS anyway).

CREATE OR REPLACE VIEW user_overview
WITH (security_invoker = true) AS
SELECT
  -- identity
  p.id                                                    AS user_id,
  p.display_name                                          AS name,
  p.user_pronoun                                           AS pronoun,

  -- status flags (what state is this user in right now)
  p.has_completed_onboarding                               AS onboarding_complete,
  (p.ai_disclosure_accepted_at IS NOT NULL)                 AS ai_disclosure_accepted,
  COALESCE(w.has_paid, false)                               AS has_paid,
  COALESCE(w.trial_granted, false)                          AS trial_granted,

  -- wallet balance
  COALESCE(w.balance_treats, 0)                             AS treats_balance,

  -- learning level
  p.level                                                  AS level,
  p.target_level                                            AS target_level,
  p.native_language                                         AS native_language,
  p.current_study_topic                                     AS current_topic,
  array_to_string(p.focus_topics, ', ')                     AS focus_topics,

  -- activity stats
  p.session_count                                           AS sessions_count,
  p.message_count                                           AS messages_count,

  -- why / how they're learning
  p.why_learning                                            AS why_learning,
  p.practice_style                                          AS practice_style,

  -- learning content (counts instead of raw JSON blobs)
  jsonb_array_length(COALESCE(p.word_bank, '[]'))           AS words_learned,
  jsonb_array_length(COALESCE(p.phrase_bank, '[]'))         AS phrases_learned,
  jsonb_array_length(COALESCE(p.error_log, '[]'))           AS errors_logged,
  jsonb_array_length(COALESCE(p.session_summaries, '[]'))   AS session_summaries_logged,
  array_to_string(p.mastered_areas, ', ')                   AS mastered_areas,
  array_to_string(p.weak_areas, ', ')                       AS weak_areas,
  array_to_string(p.hobbies, ', ')                          AS hobbies,
  array_to_string(p.exercise_history, ', ')                 AS exercise_history,

  -- free-text notes
  p.learning_notes                                          AS learning_notes,
  p.life_notes                                              AS life_notes,

  -- raw onboarding synthesis (kept as JSONB for debugging, lowest priority)
  p.onboarding_profile                                      AS onboarding_profile_raw,

  -- lifetime wallet stats (secondary to current balance/flags above)
  COALESCE(w.lifetime_purchased, 0)                         AS treats_purchased_lifetime,
  COALESCE(w.lifetime_spent, 0)                             AS treats_spent_lifetime,
  COALESCE(w.lifetime_bonus, 0)                             AS treats_bonus_lifetime,

  -- audit timestamps (least important for a quick glance)
  p.ai_disclosure_accepted_at                               AS ai_disclosure_accepted_at,
  p.created_at                                              AS profile_created_at,
  p.updated_at                                              AS profile_updated_at,
  w.created_at                                              AS wallet_created_at,
  w.updated_at                                              AS wallet_updated_at
FROM profiles p
LEFT JOIN wallets w ON w.user_id = p.id;

GRANT SELECT ON user_overview TO authenticated;
GRANT SELECT ON user_overview TO service_role;
