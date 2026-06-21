// Loro voice-generation smoke test. Verifies the /v1/loro path returns all 7
// segments and that every segment is Gemini audio (no silent English-voice
// OpenAI fallback). Uses a REAL Supabase JWT (no backdoor); admin-creates a
// throwaway user, tops it up via the service role, then calls the endpoint.
//
//   SUPABASE_ANON_KEY=... PROXY_URL=https://api.professormadrid.com \
//   railway run node test/loro-smoke.mjs
//
// All inputs are env vars; this file contains no secrets.

const SUPABASE_URL = need("SUPABASE_URL");
const ANON_KEY = need("SUPABASE_ANON_KEY");
const SERVICE_KEY = need("SUPABASE_SERVICE_ROLE_KEY");
const PROXY_URL = (process.env.PROXY_URL || "https://api.professormadrid.com").replace(/\/$/, "");
const EMAIL = process.env.TEST_EMAIL || "loro-smoke@professormadrid.com";
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
    body: JSON.stringify({ p_user_id: userId, p_treats: treats, p_kind: "topup", p_reason: "loro_smoke", p_ref_id: null, p_meta: {} })
  });
  return (await res.json())?.balance_treats;
}
async function proxy(path, token, body) {
  const res = await fetch(`${PROXY_URL}${path}`, {
    method: body ? "POST" : "GET",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  let json; try { json = await res.json(); } catch { json = {}; }
  return { status: res.status, json };
}

async function main() {
  console.log(`\n=== Loro smoke test ===\nproxy: ${PROXY_URL}\nuser:  ${EMAIL}\n`);
  const health = await fetch(`${PROXY_URL}/healthz`).then(r => r.json()).catch(() => null);
  log("health", health?.features);

  const id = await adminCreateUser();
  const { token, userId } = await passwordLogin();
  await proxy("/v1/bootstrap", token, {});
  const bal = await creditWallet(userId || id, 50);
  log("topped up", { balance: bal });

  const t0 = Date.now();
  const r = await proxy("/v1/loro", token, {
    prompt: 'You are a Spanish language expert. The student (level: Beginner) has selected this phrase to memorize: "tener hambre"\n\nReturn ONLY a JSON object with keys spanish, english, sentence1, sentence2. Sentences in Spanish only, A1/A2, max 10 words.'
  });
  const ms = Date.now() - t0;

  if (r.status !== 200) { log(`loro FAILED status ${r.status}`, r.json); throw new Error("loro endpoint failed"); }

  const segs = r.json.segments || [];
  const mimes = segs.map(s => s.mime);
  const allGemini = mimes.every(m => (m || "").startsWith("audio/L16"));
  const anyWav = mimes.some(m => (m || "").startsWith("audio/wav")); // would indicate OpenAI fallback
  log("script", { spanish: r.json.spanish, english: r.json.english });
  log("result", { ms, segments: segs.length, treatsCharged: r.json.treatsCharged, mimes: [...new Set(mimes)] });

  console.log(`\n=== Result ===`);
  const ok = segs.length === 7 && allGemini && !anyWav;
  console.log(ok
    ? `PASS: 7/7 segments, all Gemini audio (no English-voice fallback), ${ms}ms.`
    : `FAIL: segments=${segs.length}, allGemini=${allGemini}, openaiFallbackDetected=${anyWav}`);
  if (!ok) process.exit(1);
}
main().catch((e) => { console.error("\nLORO SMOKE FAILED:", e.message); process.exit(1); });
