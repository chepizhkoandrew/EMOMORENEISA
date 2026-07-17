// One-off: list the memorize-queue words for a user (by email) from the
// Supabase mirror table. Run: railway run --service api node scripts/dump_memory_words.mjs <email>
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error("missing supabase env"); process.exit(1); }
const sb = createClient(url, key);

const email = process.argv[2];
const { data: users, error: uerr } = await sb.auth.admin.listUsers({ perPage: 200 });
if (uerr) { console.error(uerr.message); process.exit(1); }
const user = users.users.find(u => u.email === email);
if (!user) { console.error("no user for", email); process.exit(1); }

const { data, error } = await sb
  .from("memory_cards")
  .select("content, translation, is_archived, updated_at")
  .eq("user_id", user.id)
  .order("updated_at", { ascending: false })
  .limit(40);
if (error) { console.error(error.message); process.exit(1); }
console.log(JSON.stringify({ userId: user.id, cards: data }, null, 2));
