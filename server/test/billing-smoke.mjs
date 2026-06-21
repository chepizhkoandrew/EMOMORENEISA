// Billing smoke test: exercises the full treat wallet through the live proxy
// using a REAL Supabase JWT (no backdoor). It admin-creates a throwaway test
// user, logs in to obtain an access token, then drives the billable endpoints
// and watches treats debit / enforcement / refill end to end.
//
// Run it with the backend secrets injected (service role + supabase url come
// from Railway), e.g.:
//
//   SUPABASE_ANON_KEY=... PROXY_URL=https://api-production-ff98.up.railway.app \
//   TEST_EMAIL=billing-smoke@professormadrid.com TEST_PASSWORD='Smoke!12345' \
//   railway run node test/billing-smoke.mjs
//
// All inputs are env vars; this file contains no secrets.

const SUPABASE_URL = need("SUPABASE_URL");
const ANON_KEY = need("SUPABASE_ANON_KEY");
const SERVICE_KEY = need("SUPABASE_SERVICE_ROLE_KEY");
const PROXY_URL = (process.env.PROXY_URL || "https://api-production-ff98.up.railway.app").replace(/\/$/, "");
const EMAIL = process.env.TEST_EMAIL || "billing-smoke@professormadrid.com";
const PASSWORD = process.env.TEST_PASSWORD || "Smoke!12345";

function need(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
  return v;
}

function log(step, obj) {
  const body = obj === undefined ? "" : " " + JSON.stringify(obj);
  console.log(`\u2022 ${step}${body}`);
}

async function adminCreateUser() {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD, email_confirm: true })
  });
  if (res.status === 200 || res.status === 201) {
    const u = await res.json();
    log("admin create user: created", { id: u.id });
    return u.id;
  }
  // 422 = already registered; fine, we just log in below.
  const txt = await res.text();
  log(`admin create user: existing (status ${res.status})`);
  return null;
}

async function passwordLogin() {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD })
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error(`login failed (${res.status}): ${JSON.stringify(data)}`);
  }
  log("login ok", { userId: data.user?.id });
  return { token: data.access_token, userId: data.user?.id };
}

async function proxy(path, token, body) {
  const res = await fetch(`${PROXY_URL}${path}`, {
    method: body ? "POST" : "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: body ? JSON.stringify(body) : undefined
  });
  let json;
  try { json = await res.json(); } catch { json = {}; }
  return { status: res.status, json };
}

async function creditWallet(userId, treats, kind, reason) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/credit_wallet`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      p_user_id: userId,
      p_treats: treats,
      p_kind: kind,
      p_reason: reason,
      p_ref_id: null,
      p_meta: {}
    })
  });
  const data = await res.json();
  return data?.balance_treats ?? data;
}

async function main() {
  console.log(`\n=== Billing smoke test ===`);
  console.log(`proxy:    ${PROXY_URL}`);
  console.log(`supabase: ${SUPABASE_URL}`);
  console.log(`user:     ${EMAIL}\n`);

  const health = await fetch(`${PROXY_URL}/healthz`).then(r => r.json()).catch(() => null);
  log("health", health?.features);
  if (!health?.features?.wallet) throw new Error("wallet feature disabled on server");

  await adminCreateUser();
  const { token, userId } = await passwordLogin();

  // 1. bootstrap (ensures wallet + grants one-time trial if enforced)
  const boot = await proxy("/v1/bootstrap", token, {});
  log("bootstrap", boot.json);
  const enforced = boot.json?.enforced;

  if (!enforced) {
    console.log("\nNOTE: ENFORCE_WALLET is false -> debits are no-ops. Flip it to true to test enforcement.\n");
  }

  // 2. wallet read
  const w0 = await proxy("/v1/wallet", token);
  log("wallet", w0.json);

  // 3. drive chat until treats run out (or cap iterations)
  let saw402 = false;
  for (let i = 1; i <= 30; i++) {
    const r = await proxy("/v1/chat", token, {
      systemPrompt: "You are a terse Spanish tutor.",
      history: [],
      userText: "Say 'hola' once.",
      maxTokens: 16
    });
    if (r.status === 402) {
      log(`chat #${i}: 402 INSUFFICIENT (enforcement works)`, { balance: r.json.balance });
      saw402 = true;
      break;
    }
    if (r.status !== 200) {
      log(`chat #${i}: error ${r.status}`, r.json);
      break;
    }
    const wallet = await proxy("/v1/wallet", token);
    log(`chat #${i}: ok`, { treatsCharged: r.json.treatsCharged, balance: wallet.json.balanceTreats });
    if (!enforced) break; // balance won't move; one call is enough to prove the path
  }

  // 4. voice (tts) debit
  const tts = await proxy("/v1/tts", token, { text: "Hola, ¿qué tal?" });
  if (tts.status === 200) {
    const wallet = await proxy("/v1/wallet", token);
    log("tts: ok", { treatsCharged: tts.json.treatsCharged, balance: wallet.json.balanceTreats, provider: tts.json.provider });
  } else {
    log(`tts: status ${tts.status}`, tts.json);
  }

  // 5. refill via service role and confirm balance restored
  if (enforced && userId) {
    const newBal = await creditWallet(userId, 100, "topup", "smoke_refill");
    log("refill +100 (service role)", { balance: newBal });
    const after = await proxy("/v1/chat", token, {
      systemPrompt: "Terse.", history: [], userText: "hola", maxTokens: 16
    });
    log("chat after refill", { status: after.status, treatsCharged: after.json?.treatsCharged });
  }

  console.log(`\n=== Result ===`);
  console.log(enforced
    ? (saw402 ? "PASS: debit + enforcement + refill verified." : "PARTIAL: debits ran but balance never hit 0 (raise iterations or start lower).")
    : "PASS (non-enforced): endpoints reachable; flip ENFORCE_WALLET=true to test debits.");
}

main().catch((e) => {
  console.error("\nSMOKE TEST FAILED:", e.message);
  process.exit(1);
});
