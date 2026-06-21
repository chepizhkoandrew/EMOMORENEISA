import { config } from "./config.js";
import { supabase } from "./supabase.js";

export async function getBalance(userId) {
  const sb = supabase();
  if (!sb) return null;
  const { data, error } = await sb
    .from("wallets")
    .select("balance_treats")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) return null;
  return data ? data.balance_treats : 0;
}

// Ensures a wallet row exists and returns the full row (balance, has_paid, trial_granted).
export async function getWallet(userId) {
  const sb = supabase();
  if (!sb) return null;
  const { data, error } = await sb.rpc("ensure_wallet", { p_user_id: userId });
  if (error) return null;
  return data || null;
}

// Grants the one-time trial treats if the user has never received them. Idempotent
// (the credit_wallet RPC sets trial_granted, and we guard on the current flag).
export async function grantTrialIfNeeded(userId) {
  if (!config.enforceWallet) return { granted: false, enforced: false };
  const sb = supabase();
  if (!sb) return { granted: false, enforced: true, error: "wallet_not_configured" };

  const wallet = await getWallet(userId);
  if (!wallet) return { granted: false, enforced: true, error: "wallet_unavailable" };
  if (wallet.trial_granted) return { granted: false, enforced: true, wallet };

  const treats = config.trialGrantTreats;
  if (treats <= 0) return { granted: false, enforced: true, wallet };

  const res = await credit(userId, treats, "trial_grant", "signup_trial", { source: "auto" });
  return { granted: res.ok, enforced: true, treats, balance: res.balance };
}

// Records a verified real-money purchase: writes a topups row (deduped by Apple
// transaction id) and credits the treats. Returns { ok, duplicate, balance }.
export async function recordTopup({ userId, productId, usd, baseTreats, bonusPct, totalTreats, transactionId }) {
  const sb = supabase();
  if (!sb) return { ok: false, error: "wallet_not_configured" };

  // Dedupe: the topups.apple_transaction_id column is UNIQUE.
  const { error: insErr } = await sb.from("topups").insert({
    user_id: userId,
    product_id: productId,
    usd_amount: usd,
    base_treats: baseTreats,
    bonus_pct: bonusPct,
    total_treats: totalTreats,
    apple_transaction_id: transactionId,
    status: "completed"
  });

  if (insErr) {
    if (insErr.code === "23505") return { ok: true, duplicate: true };
    return { ok: false, error: insErr.message };
  }

  const res = await credit(userId, totalTreats, "topup", `pack_${productId}`, {
    apple_transaction_id: transactionId,
    usd
  });
  return { ok: res.ok, duplicate: false, balance: res.balance };
}

export async function debit(userId, treats, reason, meta) {
  if (!config.enforceWallet) {
    return { ok: true, enforced: false };
  }
  const sb = supabase();
  if (!sb) return { ok: false, enforced: true, error: "wallet_not_configured" };

  const { data, error } = await sb.rpc("debit_wallet", {
    p_user_id: userId,
    p_treats: treats,
    p_reason: reason,
    p_meta: meta || {}
  });

  if (error) return { ok: false, enforced: true, error: error.message };
  if (data && data.insufficient) {
    return { ok: false, enforced: true, error: "insufficient_treats", balance: data.balance_treats };
  }
  return { ok: true, enforced: true, balance: data ? data.balance_treats : undefined };
}

export async function credit(userId, treats, kind, reason, meta) {
  if (!config.enforceWallet) return { ok: true, enforced: false };
  const sb = supabase();
  if (!sb) return { ok: false, enforced: true, error: "wallet_not_configured" };

  const { data, error } = await sb.rpc("credit_wallet", {
    p_user_id: userId,
    p_treats: treats,
    p_kind: kind,
    p_reason: reason,
    p_ref_id: null,
    p_meta: meta || {}
  });

  if (error) return { ok: false, enforced: true, error: error.message };
  return { ok: true, enforced: true, balance: data ? data.balance_treats : undefined };
}
