import crypto from "node:crypto";
import { supabase } from "./supabase.js";
import { config } from "./config.js";

// ─── Shared helpers ──────────────────────────────────────────────────────────

export function newInviteToken() {
  return crypto.randomBytes(16).toString("base64url");
}

export function inviteUrl(token) {
  return `${config.social.inviteBaseUrl}/${token}`;
}

// Blocks are silent: callers must translate a positive result into the same
// generic response as success/not-found so the blocked party can't probe.
export async function isBlockedEitherWay(userA, userB) {
  const sb = supabase();
  if (!sb) return false;
  const { data } = await sb
    .from("blocks")
    .select("blocker_id")
    .or(`and(blocker_id.eq.${userA},blocked_id.eq.${userB}),and(blocker_id.eq.${userB},blocked_id.eq.${userA})`)
    .limit(1);
  return Boolean(data?.length);
}

export async function findUserByEmail(email) {
  const sb = supabase();
  if (!sb || !email) return null;
  const { data, error } = await sb.rpc("find_user_by_email", { p_email: email.toLowerCase() });
  if (error) throw new Error(`find_user_by_email: ${error.message}`);
  return data || null;
}

export async function displayNameOf(userId) {
  const sb = supabase();
  if (!sb || !userId) return null;
  const { data } = await sb.from("profiles").select("display_name").eq("id", userId).maybeSingle();
  return data?.display_name || null;
}

// Fan-out one feed row. Best-effort: a failed event must never fail the action.
export async function emitEvent(userId, actorId, kind, payload = {}) {
  try {
    const sb = supabase();
    if (!sb) return;
    await sb.from("activity_events").insert({ user_id: userId, actor_id: actorId, kind, payload });
  } catch (e) {
    console.warn("[social] emitEvent failed:", e.message);
  }
}

// Canonical-pair friendship lookup (there is at most one edge per pair).
async function findEdge(sb, a, b) {
  const { data } = await sb
    .from("friendships")
    .select("*")
    .or(`and(user_a.eq.${a},user_b.eq.${b}),and(user_a.eq.${b},user_b.eq.${a})`)
    .limit(1);
  return data?.[0] || null;
}

// Create (or revive) a pending invite edge from `from` to `to`.
// Returns "invited" | "already_friends" | "already_pending".
async function upsertPendingEdge(sb, from, to) {
  const edge = await findEdge(sb, from, to);
  if (!edge) {
    await sb.from("friendships").insert({ user_a: from, user_b: to, status: "pending" });
    return "invited";
  }
  if (edge.status === "accepted") return "already_friends";
  if (edge.status === "pending") return "already_pending";
  // declined/removed → revive as a fresh pending request from `from`.
  await sb.from("friendships")
    .update({ user_a: from, user_b: to, status: "pending", responded_at: null })
    .eq("id", edge.id);
  return "invited";
}

// ─── Sign-in backfill (called from /v1/bootstrap on every sign-in) ───────────
//
// Binds anything that was addressed to this email before the account existed:
//   1. song_shares.recipient_user_id  (+ a song_shared feed event per share)
//   2. targeted invite_links → pending friendship invites
// Idempotent by construction — conditional updates + edge upsert no-op on rerun.
export async function claimPendingSocial(userId, email) {
  const sb = supabase();
  if (!sb || !email) return;
  const lower = email.toLowerCase();

  try {
    // 1. Bind unclaimed song shares addressed to this email.
    const { data: bound } = await sb
      .from("song_shares")
      .update({ recipient_user_id: userId })
      .eq("recipient_email", lower)
      .is("recipient_user_id", null)
      .select("id, sharer_id, shared_song_id");

    for (const share of bound || []) {
      if (await isBlockedEitherWay(userId, share.sharer_id)) continue;
      const { data: song } = await sb
        .from("shared_songs").select("title").eq("id", share.shared_song_id).maybeSingle();
      await emitEvent(userId, share.sharer_id, "song_shared", {
        actorName: await displayNameOf(share.sharer_id),
        songTitle: song?.title || "",
        shareId: share.id
      });
    }

    // 2. Convert targeted invite links into pending friend invites.
    const { data: links } = await sb
      .from("invite_links")
      .select("token, inviter_id, mode, claimed_by")
      .eq("target_email", lower)
      .is("revoked_at", null);

    for (const link of links || []) {
      if (link.inviter_id === userId) continue;
      if (link.mode === "one_time" && link.claimed_by && link.claimed_by !== userId) continue;
      if (await isBlockedEitherWay(userId, link.inviter_id)) continue;
      const outcome = await upsertPendingEdge(sb, link.inviter_id, userId);
      if (outcome === "invited") {
        await emitEvent(userId, link.inviter_id, "friend_invite", {
          actorName: await displayNameOf(link.inviter_id)
        });
      }
    }
  } catch (e) {
    // Never break sign-in over social backfill.
    console.warn("[social] claimPendingSocial failed:", e.message);
  }
}

// ─── Route handlers ──────────────────────────────────────────────────────────

// POST /v1/friends/invite { email, mode? } — invite a specific person by email.
// Existing account → in-app pending invite. No account → targeted invite link.
export async function inviteByEmail(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });

  const email = String(req.body?.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: "invalid_email" });
  }
  if (email === (req.user.email || "").toLowerCase()) {
    return res.status(400).json({ error: "self_invite" });
  }
  const mode = req.body?.mode === "reusable" ? "reusable" : "one_time";

  try {
    const targetId = await findUserByEmail(email);

    if (targetId) {
      // Silent block: report success without doing anything.
      if (await isBlockedEitherWay(req.user.id, targetId)) {
        return res.json({ status: "invited" });
      }
      const outcome = await upsertPendingEdge(sb, req.user.id, targetId);
      if (outcome === "invited") {
        await emitEvent(targetId, req.user.id, "friend_invite", {
          actorName: await displayNameOf(req.user.id)
        });
      }
      return res.json({ status: outcome === "already_friends" ? "already_friends" : "invited" });
    }

    const token = newInviteToken();
    const { error } = await sb.from("invite_links").insert({
      token, inviter_id: req.user.id, mode, target_email: email
    });
    if (error) throw new Error(error.message);
    return res.json({ status: "link", token, url: inviteUrl(token), mode });
  } catch (e) {
    console.error("[social] inviteByEmail:", e.message);
    return res.status(500).json({ error: "invite_failed" });
  }
}

// POST /v1/invites { mode } — bare personal link, no target email.
export async function createInviteLink(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const mode = req.body?.mode === "reusable" ? "reusable" : "one_time";
  try {
    const token = newInviteToken();
    const { error } = await sb.from("invite_links").insert({
      token, inviter_id: req.user.id, mode
    });
    if (error) throw new Error(error.message);
    return res.json({ token, url: inviteUrl(token), mode });
  } catch (e) {
    console.error("[social] createInviteLink:", e.message);
    return res.status(500).json({ error: "invite_failed" });
  }
}

// POST /v1/invites/claim { token } — signed-in user claims a link they opened.
export async function claimInvite(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const token = String(req.body?.token || "").trim();
  if (!token) return res.status(400).json({ error: "missing_token" });

  try {
    const { data, error } = await sb.rpc("claim_invite", { p_token: token, p_user: req.user.id });
    if (error) throw new Error(error.message);

    const result = data?.result || "dead_link";
    const inviterId = data?.inviter_id || null;

    // Blocks stay silent: present as a dead link.
    if (result === "blocked") return res.json({ result: "dead_link" });

    if (result === "created" && inviterId) {
      await emitEvent(inviterId, req.user.id, "friend_accepted", {
        actorName: await displayNameOf(req.user.id)
      });
    }
    const inviterName = inviterId ? await displayNameOf(inviterId) : null;
    return res.json({ result, inviterName });
  } catch (e) {
    console.error("[social] claimInvite:", e.message);
    return res.status(500).json({ error: "claim_failed" });
  }
}

// GET /v1/invites/:token/public — UNAUTHENTICATED. Feeds the professormadrid.com
// invite page. Exposes only the inviter's display name; never the email, mode,
// or claim state details (a claimed one-time link is just "invalid").
export async function publicInviteInfo(req, res) {
  res.set("Access-Control-Allow-Origin", config.social.corsOrigin);
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });

  const token = String(req.params.token || "").trim();
  try {
    const { data } = await sb
      .from("invite_links")
      .select("inviter_id, mode, claimed_by, revoked_at")
      .eq("token", token)
      .maybeSingle();

    const valid = Boolean(
      data && !data.revoked_at && (data.mode === "reusable" || !data.claimed_by)
    );
    if (!valid) return res.json({ valid: false });

    const inviterName = (await displayNameOf(data.inviter_id)) || "A friend";
    return res.json({ valid: true, inviterName });
  } catch (e) {
    return res.json({ valid: false });
  }
}

// GET /v1/friends — friends + incoming pending + outgoing pending, with names.
export async function listFriends(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const me = req.user.id;

  try {
    const { data: edges, error } = await sb
      .from("friendships")
      .select("id, user_a, user_b, status, created_at, responded_at")
      .or(`user_a.eq.${me},user_b.eq.${me}`)
      .in("status", ["pending", "accepted"]);
    if (error) throw new Error(error.message);

    const otherIds = [...new Set((edges || []).map(e => (e.user_a === me ? e.user_b : e.user_a)))];
    let names = {};
    if (otherIds.length) {
      const { data: profiles } = await sb
        .from("profiles").select("id, display_name").in("id", otherIds);
      for (const p of profiles || []) names[p.id] = p.display_name;
    }

    const friends = [], pending = [], outgoing = [];
    for (const e of edges || []) {
      const otherId = e.user_a === me ? e.user_b : e.user_a;
      const item = {
        friendshipId: e.id,
        userId: otherId,
        displayName: names[otherId] || "Learner",
        since: e.responded_at || e.created_at
      };
      if (e.status === "accepted") friends.push(item);
      else if (e.user_b === me) pending.push(item);   // they invited me
      else outgoing.push(item);                        // I invited them
    }
    return res.json({ friends, pending, outgoing });
  } catch (e) {
    console.error("[social] listFriends:", e.message);
    return res.status(500).json({ error: "friends_failed" });
  }
}

// POST /v1/friends/:id/accept | /v1/friends/:id/decline — respond to a pending
// invite. Only the addressee (user_b) may respond.
export function respondToInvite(accept) {
  return async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: "social_not_configured" });
    try {
      const { data, error } = await sb
        .from("friendships")
        .update({ status: accept ? "accepted" : "declined", responded_at: new Date().toISOString() })
        .eq("id", req.params.id)
        .eq("user_b", req.user.id)
        .eq("status", "pending")
        .select("user_a");
      if (error) throw new Error(error.message);
      if (!data?.length) return res.status(404).json({ error: "not_found" });

      if (accept) {
        await emitEvent(data[0].user_a, req.user.id, "friend_accepted", {
          actorName: await displayNameOf(req.user.id)
        });
      }
      return res.json({ ok: true });
    } catch (e) {
      console.error("[social] respondToInvite:", e.message);
      return res.status(500).json({ error: "respond_failed" });
    }
  };
}

// DELETE /v1/friends/:id — unfriend. Silent: no event to the other side.
export async function unfriend(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  try {
    const { data, error } = await sb
      .from("friendships")
      .update({ status: "removed", responded_at: new Date().toISOString() })
      .eq("id", req.params.id)
      .or(`user_a.eq.${req.user.id},user_b.eq.${req.user.id}`)
      .in("status", ["accepted", "pending"])
      .select("id");
    if (error) throw new Error(error.message);
    if (!data?.length) return res.status(404).json({ error: "not_found" });
    return res.json({ ok: true });
  } catch (e) {
    console.error("[social] unfriend:", e.message);
    return res.status(500).json({ error: "unfriend_failed" });
  }
}

// POST /v1/blocks { userId } — silent block; also severs any live friendship.
export async function blockUser(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const target = String(req.body?.userId || "").trim();
  if (!target || target === req.user.id) return res.status(400).json({ error: "invalid_user" });

  try {
    await sb.from("blocks").upsert(
      { blocker_id: req.user.id, blocked_id: target },
      { onConflict: "blocker_id,blocked_id", ignoreDuplicates: true }
    );
    await sb
      .from("friendships")
      .update({ status: "removed", responded_at: new Date().toISOString() })
      .or(`and(user_a.eq.${req.user.id},user_b.eq.${target}),and(user_a.eq.${target},user_b.eq.${req.user.id})`)
      .in("status", ["accepted", "pending"]);
    return res.json({ ok: true });
  } catch (e) {
    console.error("[social] blockUser:", e.message);
    return res.status(500).json({ error: "block_failed" });
  }
}

// DELETE /v1/blocks/:userId — unblock (does NOT restore the friendship).
export async function unblockUser(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  try {
    await sb
      .from("blocks")
      .delete()
      .eq("blocker_id", req.user.id)
      .eq("blocked_id", req.params.userId);
    return res.json({ ok: true });
  } catch (e) {
    console.error("[social] unblockUser:", e.message);
    return res.status(500).json({ error: "unblock_failed" });
  }
}
