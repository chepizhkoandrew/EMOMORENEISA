-- Professor Madrid — Billing / Treats Wallet Layer
-- Migration: 20260621000000_billing_treats.sql
--
-- What this adds:
--   1. pricing_config  — versioned, server-owned pricing knobs (treat<->COGS ratio,
--      margin, Apple fee, per-model rates, pack tiers, bonus curve). Source of truth;
--      the Railway proxy can read the active row instead of env vars.
--   2. wallets         — one row per user. Treat balance + lifetime counters + paywall flag.
--   3. treat_transactions — append-only ledger. Every credit/debit, with balance_after.
--   4. topups          — real-money purchases (StoreKit) mapped to treats granted.
--   5. usage_meter     — one row per metered AI action (cost + treats charged).
--   6. RPCs            — ensure_wallet, debit_wallet (atomic), credit_wallet.
--
-- Money model: balance is stored in TREATS (integer). 1 treat = pricing_config.usd_per_treat
-- of *retail* value. Debits are computed by the proxy from real COGS * margin.
-- Real-money top-ups are recorded in `topups`; bonuses/trials are ledger credits.

-- ─── 1. pricing_config ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS pricing_config (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  version               INT         NOT NULL UNIQUE,
  active                BOOLEAN     NOT NULL DEFAULT false,

  usd_per_treat         NUMERIC     NOT NULL DEFAULT 0.01,
  target_margin         NUMERIC     NOT NULL DEFAULT 5.0,
  infra_overhead        NUMERIC     NOT NULL DEFAULT 0.15,
  apple_fee             NUMERIC     NOT NULL DEFAULT 0.15,

  usd_per_mtok_in_chat  NUMERIC     NOT NULL DEFAULT 2.0,
  usd_per_mtok_out_chat NUMERIC     NOT NULL DEFAULT 8.0,
  usd_per_min_tts_gemini NUMERIC    NOT NULL DEFAULT 0.0048,
  usd_per_min_tts_openai NUMERIC    NOT NULL DEFAULT 0.015,

  streetview_free_per_day INT       NOT NULL DEFAULT 20,
  trial_budget_usd      NUMERIC     NOT NULL DEFAULT 0.05,

  -- Treat-cost catalog for each billable action (what the proxy debits).
  action_costs          JSONB       NOT NULL DEFAULT '{}',
  -- StoreKit pack tiers with bonus curve (see seed below).
  packs                 JSONB       NOT NULL DEFAULT '[]',
  -- Earn/bonus rules and caps.
  bonus_rules           JSONB       NOT NULL DEFAULT '{}',

  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Only one row may be active at a time.
CREATE UNIQUE INDEX IF NOT EXISTS pricing_config_one_active
  ON pricing_config (active) WHERE active;

ALTER TABLE pricing_config ENABLE ROW LEVEL SECURITY;

-- Authenticated clients may read the active config (to render packs / limits).
CREATE POLICY "pricing_config_read_active" ON pricing_config
  FOR SELECT TO authenticated USING (active);

CREATE POLICY "pricing_config_service" ON pricing_config
  FOR ALL TO service_role USING (true);

-- ─── 2. wallets ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS wallets (
  user_id             UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance_treats      BIGINT      NOT NULL DEFAULT 0 CHECK (balance_treats >= 0),
  lifetime_purchased  BIGINT      NOT NULL DEFAULT 0,
  lifetime_spent      BIGINT      NOT NULL DEFAULT 0,
  lifetime_bonus      BIGINT      NOT NULL DEFAULT 0,
  -- Paywall: becomes true after the first real-money top-up. Trial grant does NOT set it.
  has_paid            BOOLEAN     NOT NULL DEFAULT false,
  trial_granted       BOOLEAN     NOT NULL DEFAULT false,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wallets_owner_read" ON wallets
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "wallets_service" ON wallets
  FOR ALL TO service_role USING (true);

-- ─── 3. treat_transactions (append-only ledger) ─────────────────────────────

CREATE TABLE IF NOT EXISTS treat_transactions (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Positive = credit (topup/bonus/trial/refund), negative = debit (usage/decay).
  delta_treats    BIGINT      NOT NULL,
  balance_after   BIGINT      NOT NULL,
  kind            TEXT        NOT NULL,  -- topup | debit | bonus | trial_grant | monthly_decay | refund | adjustment
  reason          TEXT,
  ref_id          TEXT,                  -- e.g. topup id / apple transaction id
  meta            JSONB       NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS treat_tx_user_time_idx
  ON treat_transactions (user_id, created_at DESC);

ALTER TABLE treat_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "treat_tx_owner_read" ON treat_transactions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "treat_tx_service" ON treat_transactions
  FOR ALL TO service_role USING (true);

-- ─── 4. topups (real-money purchases) ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS topups (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id            TEXT        NOT NULL,
  usd_amount            NUMERIC     NOT NULL,
  base_treats           BIGINT      NOT NULL,
  bonus_pct             NUMERIC     NOT NULL DEFAULT 0,
  total_treats          BIGINT      NOT NULL,
  apple_transaction_id  TEXT        UNIQUE,
  status                TEXT        NOT NULL DEFAULT 'pending', -- pending | completed | failed | refunded
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS topups_user_time_idx
  ON topups (user_id, created_at DESC);

ALTER TABLE topups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "topups_owner_read" ON topups
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "topups_service" ON topups
  FOR ALL TO service_role USING (true);

-- ─── 5. usage_meter ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS usage_meter (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind            TEXT        NOT NULL,  -- chat | vision | tts | analyst
  provider        TEXT,
  input_tokens    INT         NOT NULL DEFAULT 0,
  output_tokens   INT         NOT NULL DEFAULT 0,
  seconds         INT         NOT NULL DEFAULT 0,
  raw_cost_usd    NUMERIC     NOT NULL DEFAULT 0,
  treats_charged  BIGINT      NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS usage_meter_user_time_idx
  ON usage_meter (user_id, created_at DESC);

ALTER TABLE usage_meter ENABLE ROW LEVEL SECURITY;

CREATE POLICY "usage_meter_owner_read" ON usage_meter
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "usage_meter_service" ON usage_meter
  FOR ALL TO service_role USING (true);

-- ─── 6. RPCs ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION ensure_wallet(p_user_id UUID)
RETURNS wallets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  w wallets;
BEGIN
  INSERT INTO wallets (user_id) VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO w FROM wallets WHERE user_id = p_user_id;
  RETURN w;
END;
$$;

-- Atomic debit. Returns { insufficient: bool, balance_treats: bigint }.
CREATE OR REPLACE FUNCTION debit_wallet(
  p_user_id UUID,
  p_treats  BIGINT,
  p_reason  TEXT,
  p_meta    JSONB DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cur BIGINT;
  new_balance BIGINT;
BEGIN
  PERFORM ensure_wallet(p_user_id);

  SELECT balance_treats INTO cur FROM wallets
   WHERE user_id = p_user_id FOR UPDATE;

  IF p_treats <= 0 THEN
    RETURN jsonb_build_object('insufficient', false, 'balance_treats', cur);
  END IF;

  IF cur < p_treats THEN
    RETURN jsonb_build_object('insufficient', true, 'balance_treats', cur);
  END IF;

  new_balance := cur - p_treats;

  UPDATE wallets
     SET balance_treats = new_balance,
         lifetime_spent = lifetime_spent + p_treats,
         updated_at = now()
   WHERE user_id = p_user_id;

  INSERT INTO treat_transactions (user_id, delta_treats, balance_after, kind, reason, meta)
  VALUES (p_user_id, -p_treats, new_balance, 'debit', p_reason, COALESCE(p_meta, '{}'));

  RETURN jsonb_build_object('insufficient', false, 'balance_treats', new_balance);
END;
$$;

-- Credit treats (topup / bonus / trial_grant / refund / adjustment).
-- Returns { balance_treats: bigint }.
CREATE OR REPLACE FUNCTION credit_wallet(
  p_user_id UUID,
  p_treats  BIGINT,
  p_kind    TEXT,
  p_reason  TEXT,
  p_ref_id  TEXT DEFAULT NULL,
  p_meta    JSONB DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cur BIGINT;
  new_balance BIGINT;
BEGIN
  PERFORM ensure_wallet(p_user_id);

  SELECT balance_treats INTO cur FROM wallets
   WHERE user_id = p_user_id FOR UPDATE;

  new_balance := cur + GREATEST(p_treats, 0);

  UPDATE wallets
     SET balance_treats = new_balance,
         lifetime_purchased = lifetime_purchased + CASE WHEN p_kind = 'topup' THEN p_treats ELSE 0 END,
         lifetime_bonus = lifetime_bonus + CASE WHEN p_kind IN ('bonus','trial_grant') THEN p_treats ELSE 0 END,
         has_paid = has_paid OR (p_kind = 'topup'),
         trial_granted = trial_granted OR (p_kind = 'trial_grant'),
         updated_at = now()
   WHERE user_id = p_user_id;

  INSERT INTO treat_transactions (user_id, delta_treats, balance_after, kind, reason, ref_id, meta)
  VALUES (p_user_id, GREATEST(p_treats, 0), new_balance, p_kind, p_reason, p_ref_id, COALESCE(p_meta, '{}'));

  RETURN jsonb_build_object('balance_treats', new_balance);
END;
$$;

-- ─── 7. Seed initial pricing config (version 1, active) ──────────────────────

INSERT INTO pricing_config (
  version, active,
  usd_per_treat, target_margin, infra_overhead, apple_fee,
  usd_per_mtok_in_chat, usd_per_mtok_out_chat,
  usd_per_min_tts_gemini, usd_per_min_tts_openai,
  streetview_free_per_day, trial_budget_usd,
  action_costs, packs, bonus_rules, notes
) VALUES (
  1, true,
  0.01, 5.0, 0.15, 0.15,
  2.0, 8.0,
  0.0048, 0.015,
  20, 0.05,
  jsonb_build_object(
    'chat_message', 5,
    'voice_message', 2,
    'street_view_message', 9,
    'loro_drill', 3
  ),
  jsonb_build_array(
    jsonb_build_object('product_id','treats_599','usd',5.99,'base_treats',599,'bonus_pct',0,'total_treats',599,'headline_conversations',6,'is_min',true),
    jsonb_build_object('product_id','treats_1199','usd',11.99,'base_treats',1199,'bonus_pct',15,'total_treats',1379,'headline_conversations',14),
    jsonb_build_object('product_id','treats_2499','usd',24.99,'base_treats',2499,'bonus_pct',25,'total_treats',3124,'headline_conversations',31),
    jsonb_build_object('product_id','treats_4999','usd',49.99,'base_treats',4999,'bonus_pct',48,'total_treats',7399,'headline_conversations',74)
  ),
  jsonb_build_object(
    'trial_grant_treats', 250,
    'earn_complete_loro', 3,
    'earn_per_n_messages', jsonb_build_object('n', 20, 'treats', 5),
    'earn_audio_engagement', 2,
    'earn_daily_cap', 15,
    'earn_monthly_cap', 150,
    'monthly_decay_treats', 0
  ),
  'Initial billing config. Treat = 1 cent retail. 5x margin over loaded COGS, Apple 15% SBP. Pack bonus curve 0/15/25/48%. headline_conversations are estimates pending measured per-conversation cost.'
);
