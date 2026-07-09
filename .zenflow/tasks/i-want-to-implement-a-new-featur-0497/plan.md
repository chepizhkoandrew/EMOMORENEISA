# Coupon Feature — Implementation Plan

## Requirements
- Admin creates coupons via direct SQL in Supabase (migration provides the table + example)
- Each code can be redeemed by many users, but each user may redeem a given code only once
- Users enter their code on the Paywall sheet; their treat wallet is credited immediately

## Affected files
- `supabase/migrations/20260623000000_coupons.sql` — new migration (tables + RLS + RPC)
- `server/src/index.js` — new `POST /v1/coupon/redeem` endpoint
- `EMOMORENEISA/…/Chat/Network/ProxyClient.swift` — `redeemCoupon(code:)` method
- `EMOMORENEISA/…/Chat/Billing/PaywallView.swift` — coupon entry UI at bottom of paywall

### [x] Step 1: DB migration — coupons + coupon_redemptions + redeem_coupon RPC
- `coupons` table: code (unique), treats_amount, max_uses (nullable), uses_count, active, expires_at
- `coupon_redemptions` table: coupon_id, user_id (UNIQUE pair), treats_credited
- RPC `redeem_coupon` atomically checks validity, prevents double-redeem, increments uses_count, inserts redemption row, calls credit_wallet
- Service-role-only RLS on both tables

### [x] Step 2: Server endpoint POST /v1/coupon/redeem
- Calls `redeem_coupon` RPC, maps error codes to HTTP statuses
- Returns new wallet state + `creditedTreats` on success

### [x] Step 3: iOS — ProxyClient + PaywallView UI
- `ProxyClient.redeemCoupon(code:)` — posts to `/v1/coupon/redeem`, returns credited treats + wallet state
- `PaywallView` — expandable "Have a coupon?" section at the bottom: text field + Redeem button, success/error feedback, wallet refresh
