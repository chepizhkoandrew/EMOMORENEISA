-- Bump the documented signup bonus from 50/250 to 150 treats, matching the
-- TRIAL_GRANT_TREATS default in server/src/config.js. This table isn't read
-- at runtime (the server grants trials from the env-backed config value),
-- it's the "source of truth" doc row referenced by pricing_config's header
-- comment — keep it in sync so it doesn't mislead future readers.
UPDATE pricing_config
SET bonus_rules = jsonb_set(bonus_rules, '{trial_grant_treats}', '150', true)
WHERE active = true;
