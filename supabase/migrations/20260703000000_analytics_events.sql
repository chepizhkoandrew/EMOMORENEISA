-- Professor Madrid — User-behaviour analytics events
-- Migration: 20260703000000_analytics_events.sql
--
-- A lightweight, privacy-respecting event stream for understanding how learners
-- use the app. No third-party SDK. Events are inserted directly from the iOS
-- client over the existing Supabase connection.
--
-- Design principles:
--   • properties column is JSONB so queries can filter/aggregate on any field
--     without schema changes (new events just add new keys).
--   • user_id is nullable so pre-sign-in events (e.g. app open) could be added
--     later without a schema change; for now all events are authenticated.
--   • No PII stored here — properties contains only opaque IDs and numeric
--     values (product_id, treat counts, mode names). No email, no name.
--   • RLS: users can INSERT their own events; nobody reads them from the client.
--     Analytics queries run via service_role (Edge Functions / SQL dashboard).

CREATE TABLE IF NOT EXISTS analytics_events (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  name         TEXT        NOT NULL,
  properties   JSONB       NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS analytics_events_user_id_idx    ON analytics_events(user_id);
CREATE INDEX IF NOT EXISTS analytics_events_name_idx       ON analytics_events(name);
CREATE INDEX IF NOT EXISTS analytics_events_created_at_idx ON analytics_events(created_at DESC);

ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "analytics_events_insert_own" ON analytics_events
  FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

CREATE POLICY "analytics_events_service" ON analytics_events
  FOR ALL TO service_role USING (true);
