import { supabase } from "./supabase.js";
import { config } from "./config.js";
import { displayNameOf, emitEvent, isBlockedEitherWay } from "./social.js";

// ─── Admin auth ──────────────────────────────────────────────────────────────
// Simple shared-secret header. 503 (not 401) when the key is unset so a
// misconfigured deploy fails loudly instead of silently accepting anything.
export function requireAdmin(req, res, next) {
  if (!config.social.adminApiKey) {
    return res.status(503).json({ error: "admin_not_configured" });
  }
  if (req.headers["x-admin-key"] !== config.social.adminApiKey) {
    return res.status(401).json({ error: "unauthorized" });
  }
  next();
}

// ─── Admin announcement endpoints ────────────────────────────────────────────

// POST /v1/admin/announcements { title, body } → draft (invisible to users).
export async function createAnnouncement(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const title = String(req.body?.title || "").trim();
  const body = String(req.body?.body || "").trim();
  if (!title || !body) return res.status(400).json({ error: "missing_fields" });

  const { data, error } = await sb
    .from("announcements").insert({ title, body }).select("id, status").single();
  if (error) return res.status(500).json({ error: "create_failed", detail: error.message });
  res.json({ id: data.id, status: data.status });
}

// POST /v1/admin/announcements/:id/announce → active (visible to everyone).
export async function announceAnnouncement(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const { data, error } = await sb
    .from("announcements")
    .update({ status: "active", announced_at: new Date().toISOString() })
    .eq("id", req.params.id)
    .select("id");
  if (error) return res.status(500).json({ error: "announce_failed", detail: error.message });
  if (!data?.length) return res.status(404).json({ error: "not_found" });
  res.json({ ok: true });
}

// POST /v1/admin/announcements/:id/retire → hidden again for everyone.
export async function retireAnnouncement(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const { data, error } = await sb
    .from("announcements")
    .update({ status: "retired" })
    .eq("id", req.params.id)
    .select("id");
  if (error) return res.status(500).json({ error: "retire_failed", detail: error.message });
  if (!data?.length) return res.status(404).json({ error: "not_found" });
  res.json({ ok: true });
}

// POST /v1/admin/announcements/:id/acks { userIds: [...] } or { all: true }
// Bulk-ack = retroactively cancel the announcement for those users.
export async function bulkAckAnnouncement(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const id = req.params.id;

  try {
    let userIds = Array.isArray(req.body?.userIds) ? req.body.userIds : [];
    if (req.body?.all === true) {
      const { data: profiles, error } = await sb.from("profiles").select("id");
      if (error) throw new Error(error.message);
      userIds = (profiles || []).map(p => p.id);
    }
    if (!userIds.length) return res.status(400).json({ error: "no_users" });

    const rows = userIds.map(u => ({ announcement_id: id, user_id: u }));
    const { error } = await sb
      .from("announcement_acks")
      .upsert(rows, { onConflict: "announcement_id,user_id", ignoreDuplicates: true });
    if (error) throw new Error(error.message);
    res.json({ acked: userIds.length });
  } catch (e) {
    res.status(500).json({ error: "ack_failed", detail: e.message });
  }
}

// ─── Purchase activity fan-out ───────────────────────────────────────────────
// Called from /v1/topup after a successful (non-duplicate) credit. Best-effort:
// must never fail or slow the purchase; runs detached.
export function fanOutPackPurchase(userId, productId) {
  (async () => {
    try {
      const sb = supabase();
      if (!sb) return;
      const { data: edges } = await sb
        .from("friendships")
        .select("user_a, user_b")
        .eq("status", "accepted")
        .or(`user_a.eq.${userId},user_b.eq.${userId}`);
      const friendIds = (edges || []).map(e => (e.user_a === userId ? e.user_b : e.user_a));
      if (!friendIds.length) return;

      const actorName = await displayNameOf(userId);
      for (const friendId of friendIds) {
        if (await isBlockedEitherWay(userId, friendId)) continue;
        await emitEvent(friendId, userId, "treat_pack_purchased", { actorName, packId: productId });
      }
    } catch (e) {
      console.warn("[notifications] pack fan-out failed:", e.message);
    }
  })();
}
