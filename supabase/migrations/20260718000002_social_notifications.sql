-- Professor Madrid — In-App Notifications
-- Migration: 20260718000002_social_notifications.sql
--
-- What this adds:
--   1. activity_events    — per-recipient social feed, fan-out on write by the
--      proxy. v1 kinds: friend_invite, friend_accepted, song_shared,
--      treat_pack_purchased. Client may SELECT and mark-read its own rows.
--   2. announcements      — admin-authored app notifications. Created as
--      'draft' (invisible), flipped to 'active' by the announce endpoint,
--      'retired' hides them again for everyone.
--   3. announcement_acks  — per-user seen/dismissed state. Client inserts its
--      own ack; the admin can bulk-insert acks to retroactively cancel an
--      announcement for some or all users.

-- ─── 1. activity_events ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS activity_events (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The recipient whose feed this row lives in.
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Who did the thing (NULL if the actor deleted their account).
  actor_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  kind        TEXT        NOT NULL CHECK (kind IN
                ('friend_invite','friend_accepted','song_shared','treat_pack_purchased')),
  -- Denormalized display payload: { actorName, songTitle, shareId, packId, ... }
  payload     JSONB       NOT NULL DEFAULT '{}',
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS activity_events_user_time_idx
  ON activity_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS activity_events_unread_idx
  ON activity_events (user_id) WHERE read_at IS NULL;

ALTER TABLE activity_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "activity_events_owner_read" ON activity_events
  FOR SELECT USING (auth.uid() = user_id);

-- Mark-read only; inserts stay proxy-side.
CREATE POLICY "activity_events_owner_mark_read" ON activity_events
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "activity_events_service" ON activity_events
  FOR ALL TO service_role USING (true);

-- ─── 2. announcements ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS announcements (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title         TEXT        NOT NULL,
  body          TEXT        NOT NULL,
  status        TEXT        NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft','active','retired')),
  announced_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;

-- Every signed-in user sees active announcements; drafts/retired are invisible.
CREATE POLICY "announcements_read_active" ON announcements
  FOR SELECT TO authenticated USING (status = 'active');

CREATE POLICY "announcements_service" ON announcements
  FOR ALL TO service_role USING (true);

-- ─── 3. announcement_acks ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS announcement_acks (
  announcement_id  UUID        NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  user_id          UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  acked_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (announcement_id, user_id)
);

ALTER TABLE announcement_acks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "announcement_acks_owner_read" ON announcement_acks
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "announcement_acks_owner_insert" ON announcement_acks
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "announcement_acks_service" ON announcement_acks
  FOR ALL TO service_role USING (true);
