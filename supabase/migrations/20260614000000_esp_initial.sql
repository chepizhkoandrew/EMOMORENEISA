-- Professor Madrid — Spanish Chat Tutor schema
-- Separate Supabase project (professormadrid), no prefix needed

-- Student profile (one per auth user)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  level TEXT DEFAULT 'beginner' CHECK (level IN ('beginner','intermediate','advanced')),
  native_language TEXT DEFAULT 'English',
  focus_topics TEXT[] DEFAULT '{}',
  current_study_topic TEXT,
  learning_notes TEXT DEFAULT '',
  session_count INT DEFAULT 0,
  message_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Chat sessions
CREATE TABLE IF NOT EXISTS sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mode TEXT NOT NULL CHECK (mode IN ('topic','visual')),
  title TEXT,
  topic TEXT,
  session_goal TEXT,
  message_count INT DEFAULT 0,
  last_message_preview TEXT,
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add session_goal to existing tables (safe to run if column already exists via IF NOT EXISTS)
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS session_goal TEXT;

-- Messages (root thread and sub-threads via self-reference)
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  thread_parent_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  sender TEXT NOT NULL CHECK (sender IN ('user','assistant')),
  type TEXT NOT NULL CHECK (type IN ('text','audio','image','mixed')),
  text_content TEXT,
  raw_transcript TEXT,
  audio_storage_path TEXT,
  image_storage_paths TEXT[] DEFAULT '{}',
  is_enhanced BOOLEAN DEFAULT FALSE,
  thread_reply_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS sessions_user_id_idx ON sessions(user_id);
CREATE INDEX IF NOT EXISTS sessions_updated_at_idx ON sessions(updated_at DESC);
CREATE INDEX IF NOT EXISTS messages_session_id_idx ON messages(session_id);
CREATE INDEX IF NOT EXISTS messages_thread_parent_id_idx ON messages(thread_parent_id);
CREATE INDEX IF NOT EXISTS messages_created_at_idx ON messages(created_at);

-- Auto-update sessions on new root message
CREATE OR REPLACE FUNCTION update_session_on_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE sessions
  SET
    message_count = message_count + 1,
    last_message_preview = LEFT(NEW.text_content, 100),
    last_message_at = NEW.created_at,
    updated_at = NOW()
  WHERE id = NEW.session_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER message_inserted
  AFTER INSERT ON messages
  FOR EACH ROW
  WHEN (NEW.thread_parent_id IS NULL)
  EXECUTE FUNCTION update_session_on_message();

-- Auto-increment thread_reply_count on parent message
CREATE OR REPLACE FUNCTION update_thread_reply_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.thread_parent_id IS NOT NULL THEN
    UPDATE messages
    SET thread_reply_count = thread_reply_count + 1
    WHERE id = NEW.thread_parent_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER thread_reply_inserted
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_thread_reply_count();

-- Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_owner" ON profiles
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "sessions_owner" ON sessions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "messages_owner" ON messages
  FOR ALL USING (
    session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid())
  );
