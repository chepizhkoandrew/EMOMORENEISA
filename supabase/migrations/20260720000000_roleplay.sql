-- Roleplay podcast feature: Madrid (host) + a rotating object/character (guest)
-- in a 3-way chat with a generated background scene. Sessions get a new mode
-- and scene metadata; messages get a speaker tag so Madrid's and the object's
-- lines (both still sender='assistant') can be told apart and styled distinctly.

-- Widen sessions.mode to allow 'roleplay'. The CHECK constraint was declared
-- inline with no explicit name, so Postgres auto-named it
-- "sessions_mode_check" (default <table>_<column>_check convention).
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_mode_check;
ALTER TABLE sessions ADD CONSTRAINT sessions_mode_check
  CHECK (mode IN ('topic', 'visual', 'roleplay'));

ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS roleplay_object_label TEXT,
  ADD COLUMN IF NOT EXISTS roleplay_environment_label TEXT,
  ADD COLUMN IF NOT EXISTS roleplay_object_voice TEXT,
  ADD COLUMN IF NOT EXISTS roleplay_scene_image_path TEXT;

-- Distinguishes Madrid's line from the object's line within a roleplay turn.
-- Left untyped/unconstrained (nullable free text: 'madrid' | 'object') rather
-- than a CHECK, since `sender` itself stays 'user'/'assistant' unchanged and
-- this is purely a display-routing hint, not a data-integrity boundary.
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS speaker_id TEXT;
