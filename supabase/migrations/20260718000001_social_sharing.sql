-- Professor Madrid — Song Sharing
-- Migration: 20260718000001_social_sharing.sql
--
-- What this adds:
--   1. shared_songs — the uploaded cloud copy of a locally generated song
--      (metadata + karaoke timings; the mp3 lives in the private 'shared-songs'
--      storage bucket, content-addressed by sha256 so re-sharing the same song
--      to N friends stores exactly one object).
--   2. song_shares  — one row per (song, recipient). recipient_email is always
--      set (lowercased); recipient_user_id stays NULL until an account with
--      that email exists — the /v1/bootstrap claim step binds it at sign-in,
--      which is what makes "share to someone who hasn't onboarded yet" work.
--      Rows persist forever (unfriending only hides unclaimed shares at query
--      time; nothing is deleted).
--
-- Sharing is free: no wallet debit anywhere in this flow.
-- The 'shared-songs' bucket is created lazily by the proxy (ensureBucket
-- pattern, same as voice-cache/image-cache) — no storage DDL here.

-- ─── 1. shared_songs ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS shared_songs (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- SavedSong.id on the sharer's device; makes re-shares reuse the upload.
  source_song_id  UUID        NOT NULL,
  title           TEXT        NOT NULL,
  genre           TEXT        NOT NULL DEFAULT '',
  duration_sec    INT         NOT NULL DEFAULT 0,
  lyrics          TEXT        NOT NULL DEFAULT '',
  -- Storage key inside the 'shared-songs' bucket (sharded sha256 path).
  audio_path      TEXT        NOT NULL,
  audio_sha256    TEXT        NOT NULL,
  -- Karaoke line timings + scene plan, verbatim from the device.
  lines_json      JSONB       NOT NULL DEFAULT '[]',
  scenes_json     JSONB       NOT NULL DEFAULT '[]',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, source_song_id)
);

ALTER TABLE shared_songs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shared_songs_owner_read" ON shared_songs
  FOR SELECT USING (auth.uid() = owner_id);

CREATE POLICY "shared_songs_service" ON shared_songs
  FOR ALL TO service_role USING (true);

-- ─── 2. song_shares ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS song_shares (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  shared_song_id     UUID        NOT NULL REFERENCES shared_songs(id) ON DELETE CASCADE,
  sharer_id          UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Lowercased at write time; the recipient's identity even pre-account.
  recipient_email    TEXT        NOT NULL,
  recipient_user_id  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  -- Set when the recipient downloads/materializes the song on a device.
  claimed_at         TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shared_song_id, recipient_email)
);

CREATE INDEX IF NOT EXISTS song_shares_recipient_idx
  ON song_shares (recipient_user_id, created_at DESC);
-- Fast /v1/bootstrap backfill lookup for not-yet-bound shares.
CREATE INDEX IF NOT EXISTS song_shares_unbound_email_idx
  ON song_shares (lower(recipient_email)) WHERE recipient_user_id IS NULL;

ALTER TABLE song_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY "song_shares_participant_read" ON song_shares
  FOR SELECT USING (auth.uid() = sharer_id OR auth.uid() = recipient_user_id);

CREATE POLICY "song_shares_service" ON song_shares
  FOR ALL TO service_role USING (true);
