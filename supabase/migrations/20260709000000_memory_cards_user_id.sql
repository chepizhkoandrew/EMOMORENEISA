-- Turns out memory_cards never existed in the live database at all (confirmed
-- via `relation "memory_cards" does not exist" when this migration first ran
-- as an ALTER-only file) — every upsert from MemoryCardService.emitEvent has
-- been silently failing since day one (caught and logged, never surfaced).
-- This creates the table matching RemoteMemoryCard.swift's exact shape, with
-- user_id included from the start — no legacy NULL-owner rows to worry
-- about, since there were never any rows at all.

CREATE TABLE IF NOT EXISTS memory_cards (
  id             UUID        PRIMARY KEY,
  user_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content        TEXT        NOT NULL,
  translation    TEXT        NOT NULL,
  exposure_count INT         NOT NULL DEFAULT 0,
  next_due_at    TIMESTAMPTZ,
  last_played_at TIMESTAMPTZ,
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  device_id      TEXT        NOT NULL,
  event          TEXT,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS memory_cards_user_id_idx ON memory_cards(user_id);

ALTER TABLE memory_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS memory_cards_owner ON memory_cards;
CREATE POLICY memory_cards_owner ON memory_cards
  FOR ALL USING (auth.uid() = user_id);
