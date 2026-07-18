import crypto from "node:crypto";
import { supabase } from "./supabase.js";
import { config } from "./config.js";
import {
  newInviteToken, inviteUrl, isBlockedEitherWay,
  findUserByEmail, displayNameOf, emitEvent
} from "./social.js";

const MP3_MIME = "audio/mpeg";
// mp3s are ~1-5MB; base64 in a 12mb JSON body leaves headroom, but reject
// anything that decodes past this to keep the bucket sane.
const MAX_AUDIO_BYTES = 10 * 1024 * 1024;

let bucketReady = false;

// Idempotently ensure the private bucket exists (voice-cache pattern).
async function ensureBucket() {
  if (bucketReady) return;
  const sb = supabase();
  if (!sb) return;
  try {
    await sb.storage.createBucket(config.social.songBucket, { public: false });
  } catch (_) { /* already exists / racing instance */ }
  bucketReady = true;
}

// Shard by the first 2 hex chars, same as the voice/image caches.
function objectPath(sha) {
  return `${sha.slice(0, 2)}/${sha}.mp3`;
}

// POST /v1/songs/share
// { sourceSongId, title, genre, durationSec, lyrics, lines, scenes, audioBase64,
//   recipients: { friendUserIds: [uuid], emails: [string] } }
// Free — no wallet debit. Uploads the mp3 once (content-addressed), upserts the
// shared_songs row, then one song_shares row per recipient. Unknown emails get
// a targeted one_time invite link back so the sharer can send it along.
export async function shareSong(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });

  const b = req.body || {};
  const sourceSongId = String(b.sourceSongId || "").trim();
  const title = String(b.title || "").trim();
  const audioBase64 = String(b.audioBase64 || "");
  const friendUserIds = Array.isArray(b.recipients?.friendUserIds) ? b.recipients.friendUserIds : [];
  const emails = Array.isArray(b.recipients?.emails) ? b.recipients.emails : [];

  if (!sourceSongId || !title || !audioBase64) {
    return res.status(400).json({ error: "missing_fields" });
  }
  if (!friendUserIds.length && !emails.length) {
    return res.status(400).json({ error: "no_recipients" });
  }

  let audio;
  try {
    audio = Buffer.from(audioBase64, "base64");
  } catch (_) {
    return res.status(400).json({ error: "bad_audio" });
  }
  if (!audio.length || audio.length > MAX_AUDIO_BYTES) {
    return res.status(400).json({ error: "bad_audio" });
  }

  try {
    // 1. Content-addressed upload (dedup: N shares of one song = 1 object).
    const sha = crypto.createHash("sha256").update(audio).digest("hex");
    const path = objectPath(sha);
    await ensureBucket();
    await sb.storage.from(config.social.songBucket).upload(path, audio, {
      contentType: MP3_MIME, upsert: true
    });

    // 2. Upsert the cloud copy of the song.
    const { data: songRow, error: songErr } = await sb
      .from("shared_songs")
      .upsert({
        owner_id: req.user.id,
        source_song_id: sourceSongId,
        title,
        genre: String(b.genre || ""),
        duration_sec: Number(b.durationSec) || 0,
        lyrics: String(b.lyrics || ""),
        audio_path: path,
        audio_sha256: sha,
        lines_json: Array.isArray(b.lines) ? b.lines : [],
        scenes_json: Array.isArray(b.scenes) ? b.scenes : []
      }, { onConflict: "owner_id,source_song_id" })
      .select("id")
      .single();
    if (songErr) throw new Error(songErr.message);
    const sharedSongId = songRow.id;

    const actorName = await displayNameOf(req.user.id);
    const shared = [];
    const inviteLinks = [];

    // 3. Resolve every recipient to an email (+ user id when known).
    const targets = [];
    if (friendUserIds.length) {
      const { data: edges } = await sb
        .from("friendships")
        .select("user_a, user_b")
        .eq("status", "accepted")
        .or(`user_a.eq.${req.user.id},user_b.eq.${req.user.id}`);
      const friendSet = new Set(
        (edges || []).map(e => (e.user_a === req.user.id ? e.user_b : e.user_a))
      );
      for (const id of friendUserIds) {
        if (!friendSet.has(id)) continue; // only actual friends via the picker
        const { data: em } = await sb.rpc("find_email_by_user_id", { p_user: id });
        if (!em) continue;
        targets.push({ userId: id, email: String(em).toLowerCase() });
      }
    }
    for (const raw of emails) {
      const email = String(raw || "").trim().toLowerCase();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) continue;
      if (email === (req.user.email || "").toLowerCase()) continue;
      targets.push({ userId: await findUserByEmail(email), email });
    }

    // 4. One share row per recipient; silent-skip blocked pairs.
    for (const t of targets) {
      const userId = t.userId;
      const email = t.email;

      if (userId && await isBlockedEitherWay(req.user.id, userId)) {
        shared.push({ email }); // silent: report as shared
        continue;
      }

      const { data: shareRow, error: shareErr } = await sb
        .from("song_shares")
        .upsert({
          shared_song_id: sharedSongId,
          sharer_id: req.user.id,
          recipient_email: email,
          recipient_user_id: userId
        }, { onConflict: "shared_song_id,recipient_email" })
        .select("id")
        .single();
      if (shareErr) { console.warn("[shares] share row failed:", shareErr.message); continue; }

      shared.push({ email });

      if (userId) {
        await emitEvent(userId, req.user.id, "song_shared", {
          actorName, songTitle: title, shareId: shareRow.id
        });
      } else {
        // Unknown email → hand back a targeted one_time invite link.
        const token = newInviteToken();
        const { error: linkErr } = await sb.from("invite_links").insert({
          token, inviter_id: req.user.id, mode: "one_time", target_email: email
        });
        if (!linkErr) inviteLinks.push({ email, url: inviteUrl(token) });
      }
    }

    return res.json({ shared, inviteLinks });
  } catch (e) {
    console.error("[shares] shareSong:", e.message);
    return res.status(500).json({ error: "share_failed" });
  }
}

// GET /v1/songs/shared — the recipient's feed. Per spec, unfriending/blocking
// hides *unclaimed* shares (already-materialized songs live on-device and are
// unaffected); rows are never deleted.
export async function listSharedSongs(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });
  const me = req.user.id;

  try {
    const { data: rows, error } = await sb
      .from("song_shares")
      .select("id, sharer_id, claimed_at, created_at, shared_songs ( id, title, genre, duration_sec, owner_id )")
      .eq("recipient_user_id", me)
      .order("created_at", { ascending: false });
    if (error) throw new Error(error.message);

    const sharerIds = [...new Set((rows || []).map(r => r.sharer_id))];

    // Live accepted friendships + blocks, to filter unclaimed shares.
    const { data: edges } = await sb
      .from("friendships")
      .select("user_a, user_b")
      .eq("status", "accepted")
      .or(`user_a.eq.${me},user_b.eq.${me}`);
    const friendSet = new Set((edges || []).map(e => (e.user_a === me ? e.user_b : e.user_a)));

    const { data: myBlocks } = await sb
      .from("blocks").select("blocked_id").eq("blocker_id", me);
    const blockedSet = new Set((myBlocks || []).map(b => b.blocked_id));

    let names = {};
    if (sharerIds.length) {
      const { data: profiles } = await sb
        .from("profiles").select("id, display_name").in("id", sharerIds);
      for (const p of profiles || []) names[p.id] = p.display_name;
    }

    const items = [];
    for (const r of rows || []) {
      const hidden = !r.claimed_at && (!friendSet.has(r.sharer_id) || blockedSet.has(r.sharer_id));
      if (hidden) continue;
      items.push({
        shareId: r.id,
        sharerId: r.sharer_id,
        sharedByName: names[r.sharer_id] || "A friend",
        claimed: Boolean(r.claimed_at),
        createdAt: r.created_at,
        song: {
          title: r.shared_songs?.title || "",
          genre: r.shared_songs?.genre || "",
          durationSec: r.shared_songs?.duration_sec || 0
        }
      });
    }
    return res.json({ shares: items });
  } catch (e) {
    console.error("[shares] listSharedSongs:", e.message);
    return res.status(500).json({ error: "shared_list_failed" });
  }
}

// POST /v1/songs/shared/:shareId/download — recipient materializes the song.
// Marks claimed_at and returns a 1-hour signed URL + full karaoke metadata.
export async function downloadSharedSong(req, res) {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "social_not_configured" });

  try {
    const { data: share, error } = await sb
      .from("song_shares")
      .select("id, sharer_id, recipient_user_id, claimed_at, shared_songs ( title, genre, duration_sec, lyrics, audio_path, lines_json, scenes_json )")
      .eq("id", req.params.shareId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!share || share.recipient_user_id !== req.user.id || !share.shared_songs) {
      return res.status(404).json({ error: "not_found" });
    }

    const { data: signed, error: signErr } = await sb.storage
      .from(config.social.songBucket)
      .createSignedUrl(share.shared_songs.audio_path, 3600);
    if (signErr || !signed?.signedUrl) throw new Error(signErr?.message || "sign_failed");

    if (!share.claimed_at) {
      await sb.from("song_shares")
        .update({ claimed_at: new Date().toISOString() })
        .eq("id", share.id);
    }

    return res.json({
      signedUrl: signed.signedUrl,
      sharedByName: (await displayNameOf(share.sharer_id)) || "A friend",
      sharerId: share.sharer_id,
      song: {
        title: share.shared_songs.title,
        genre: share.shared_songs.genre,
        durationSec: share.shared_songs.duration_sec,
        lyrics: share.shared_songs.lyrics,
        lines: share.shared_songs.lines_json,
        scenes: share.shared_songs.scenes_json
      }
    });
  } catch (e) {
    console.error("[shares] downloadSharedSong:", e.message);
    return res.status(500).json({ error: "download_failed" });
  }
}
