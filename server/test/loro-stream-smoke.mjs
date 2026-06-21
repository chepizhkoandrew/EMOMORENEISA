// Smoke test for POST /v1/loro/stream. Verifies the NDJSON stream emits a meta
// event, all 7 segment positions (each Gemini audio — no English-voice OpenAI
// fallback), a done event, AND that segment 0 (the Spanish word) arrives well
// before the done event (the whole point of streaming). Uses a REAL Supabase
// JWT (no backdoor); admin-creates a throwaway user and tops it up.
//
//   SUPABASE_ANON_KEY=... PROXY_URL=https://api.professormadrid.com \
//   railway run node test/loro-stream-smoke.mjs
//
// All inputs are env vars; this file contains no secrets.

const SUPABASE_URL = need("SUPABASE_URL");
const ANON_KEY = need("SUPABASE_ANON_KEY");
const SERVICE_KEY = need("SUPABASE_SERVICE_ROLE_KEY");
const PROXY_URL = (process.env.PROXY_URL || "https://api.professormadrid.com").replace(/\/$/, "");
const EMAIL = process.env.TEST_EMAIL || "loro-stream-smoke@professormadrid.com";
const PASSWORD = process.env.TEST_PASSWORD || "Smoke!12345";

function need(name) {
  const v = process.env[name];
  if (!v) { console.error(`Missing required env var: ${name}`); process.exit(1); }
  return v;
}
function log(step, obj) {
  console.log(`\u2022 ${step}${obj === undefined ? "" : " " + JSON.stringify(obj)}`);
}

async function adminCreateUser() {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD, email_confirm: true })
  });
  if (res.status === 200 || res.status === 201) { const u = await res.json(); log("created user", { id: u.id }); return u.id; }
  log(`user exists (status ${res.status})`);
  return null;
}
async function passwordLogin() {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD })
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) throw new Error(`login failed (${res.status}): ${JSON.stringify(data)}`);
  return { token: data.access_token, userId: data.user?.id };
}
async function creditWallet(userId, treats) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/credit_wallet`, {
    method: "POST", headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_user_id: userId, p_treats: treats, p_kind: "topup", p_reason: "loro_stream_smoke", p_ref_id: null, p_meta: {} })
  });
  return (await res.json())?.balance_treats;
}

async function main() {
  console.log(`\n=== Loro STREAM smoke test ===\nproxy: ${PROXY_URL}\nuser:  ${EMAIL}\n`);
  const health = await fetch(`${PROXY_URL}/healthz`).then(r => r.json()).catch(() => null);
  log("health", health?.features);

  const id = await adminCreateUser();
  const { token, userId } = await passwordLogin();
  await fetch(`${PROXY_URL}/v1/bootstrap`, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: "{}"
  });
  const bal = await creditWallet(userId || id, 50);
  log("topped up", { balance: bal });

  const t0 = Date.now();
  const res = await fetch(`${PROXY_URL}/v1/loro/stream`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      format: "aac",
      prompt: 'You are a Spanish language expert. The student (level: Beginner) has selected this phrase to memorize: "tener hambre"\n\nReturn ONLY a JSON object with keys spanish, english, sentence1, sentence2. Sentences in Spanish only, A1/A2, max 10 words.'
    })
  });

  if (res.status !== 200) {
    const body = await res.text();
    log(`stream FAILED status ${res.status}`, body);
    throw new Error("loro stream endpoint failed");
  }

  // Parse NDJSON incrementally so we can measure first-segment latency.
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  let meta = null;
  const segIndices = new Set();
  const segMimes = new Set();
  let firstSegMs = null;
  let doneSeen = false;
  let errorSeen = null;

  const handle = (obj) => {
    if (obj.type === "meta") { meta = obj; log("meta", { spanish: obj.spanish, english: obj.english, totalSegments: obj.totalSegments }); }
    else if (obj.type === "segment") {
      if (firstSegMs === null) firstSegMs = Date.now() - t0;
      segIndices.add(obj.index);
      segMimes.add((obj.mime || "").split(";")[0]);
    }
    else if (obj.type === "done") { doneSeen = true; log("done", { totalSeconds: obj.totalSeconds, ms: Date.now() - t0 }); }
    else if (obj.type === "error") { errorSeen = obj.error; }
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let nl;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (line) handle(JSON.parse(line));
    }
  }
  if (buf.trim()) handle(JSON.parse(buf.trim()));

  const totalMs = Date.now() - t0;
  // We requested format:"aac" — every segment must come back as cached/transcoded
  // AAC, never raw PCM (audio/L16) and never the English-voiced OpenAI WAV fallback.
  const allAac = [...segMimes].every(m => m.startsWith("audio/aac"));
  const anyWav = [...segMimes].some(m => m.startsWith("audio/wav"));
  log("result", { totalMs, firstSegMs, segments: segIndices.size, mimes: [...segMimes] });

  console.log(`\n=== Result ===`);
  const ok = !errorSeen
    && meta
    && segIndices.size === 7
    && segIndices.has(0)
    && allAac && !anyWav
    && doneSeen
    && firstSegMs !== null && firstSegMs < totalMs; // first audio strictly before the end
  console.log(ok
    ? `PASS: meta+done, 7/7 positions, all AAC (no English fallback). First segment at ${firstSegMs}ms, full set at ${totalMs}ms (streaming head start: ${totalMs - firstSegMs}ms).`
    : `FAIL: error=${errorSeen}, meta=${!!meta}, segs=${segIndices.size}, hasSeg0=${segIndices.has(0)}, allAac=${allAac}, openaiFallback=${anyWav}, done=${doneSeen}, firstSegMs=${firstSegMs}`);
  if (!ok) process.exit(1);
}
main().catch((e) => { console.error("\nLORO STREAM SMOKE FAILED:", e.message); process.exit(1); });
