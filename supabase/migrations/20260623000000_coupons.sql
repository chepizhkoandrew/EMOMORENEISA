-- Professor Madrid — Coupon Redemption Layer
-- Migration: 20260623000000_coupons.sql
--
-- What this adds:
--   1. coupons           — admin-managed coupon codes with treat values and optional limits.
--   2. coupon_redemptions — per-user redemption log (unique per coupon+user pair).
--   3. RPC redeem_coupon — atomic validation + wallet credit in one call.
--
-- Admin creates coupons directly in the Supabase dashboard:
--   INSERT INTO coupons (code, treats_amount, notes)
--   VALUES ('WELCOME100', 100, 'Welcome promo — unlimited uses');
--
--   INSERT INTO coupons (code, treats_amount, max_uses, expires_at, notes)
--   VALUES ('SUMMER50', 50, 500, '2026-09-01 00:00:00+00', 'Summer 2026 campaign, 500 uses max');

-- ─── 1. coupons ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS coupons (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code            TEXT        NOT NULL,
  treats_amount   BIGINT      NOT NULL CHECK (treats_amount > 0),
  max_uses        INT,
  uses_count      INT         NOT NULL DEFAULT 0,
  active          BOOLEAN     NOT NULL DEFAULT true,
  expires_at      TIMESTAMPTZ,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS coupons_code_upper_idx
  ON coupons (upper(code));

ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coupons_service" ON coupons
  FOR ALL TO service_role USING (true);

-- ─── 2. coupon_redemptions ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS coupon_redemptions (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id       UUID        NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
  user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  treats_credited BIGINT      NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (coupon_id, user_id)
);

CREATE INDEX IF NOT EXISTS coupon_redemptions_user_idx
  ON coupon_redemptions (user_id, created_at DESC);

ALTER TABLE coupon_redemptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coupon_redemptions_owner_read" ON coupon_redemptions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "coupon_redemptions_service" ON coupon_redemptions
  FOR ALL TO service_role USING (true);

-- ─── 3. RPC redeem_coupon ─────────────────────────────────────────────────────
--
-- Returns JSONB with one of:
--   { "ok": true,  "treats_credited": N, "balance_treats": B }
--   { "ok": false, "error": "<code>" }
--
-- Error codes:
--   not_found       — no coupon matches the code
--   inactive        — coupon exists but active = false
--   expired         — past expires_at
--   max_uses        — uses_count >= max_uses
--   already_redeemed — this user already redeemed this coupon

CREATE OR REPLACE FUNCTION redeem_coupon(p_user_id UUID, p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c         coupons;
  new_bal   JSONB;
BEGIN
  SELECT * INTO c FROM coupons WHERE upper(code) = upper(p_code) FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  IF NOT c.active THEN
    RETURN jsonb_build_object('ok', false, 'error', 'inactive');
  END IF;

  IF c.expires_at IS NOT NULL AND c.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;

  IF c.max_uses IS NOT NULL AND c.uses_count >= c.max_uses THEN
    RETURN jsonb_build_object('ok', false, 'error', 'max_uses');
  END IF;

  BEGIN
    INSERT INTO coupon_redemptions (coupon_id, user_id, treats_credited)
    VALUES (c.id, p_user_id, c.treats_amount);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_redeemed');
  END;

  UPDATE coupons SET uses_count = uses_count + 1 WHERE id = c.id;

  SELECT credit_wallet(
    p_user_id,
    c.treats_amount,
    'coupon',
    'coupon_' || upper(p_code),
    NULL,
    jsonb_build_object('coupon_id', c.id, 'code', upper(p_code))
  ) INTO new_bal;

  RETURN jsonb_build_object(
    'ok', true,
    'treats_credited', c.treats_amount,
    'balance_treats', (new_bal->>'balance_treats')::bigint
  );
END;
$$;
