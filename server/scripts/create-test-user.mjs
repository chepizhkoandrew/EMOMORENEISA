import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://rbbgayxvrobzlndprcwt.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJiYmdheXh2cm9iemxuZHByY3d0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MTQ2NzU4NSwiZXhwIjoyMDk3MDQzNTg1fQ.5pQrNWBftj0bFO4EK6kPHL051Yg192mS3Zjx21LlmAA";

if (!SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Error: SUPABASE_SERVICE_ROLE_KEY env var is required.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

const TEST_EMAIL = "spanishlearnerua@professormadrid.com";
const TEST_PASSWORD = "UD78SNN.4x,-$S9";

async function run() {
  console.log(`Creating test user: ${TEST_EMAIL}`);

  const { data, error } = await supabase.auth.admin.createUser({
    email: TEST_EMAIL,
    password: TEST_PASSWORD,
    email_confirm: true
  });

  if (error) {
    if (error.message?.toLowerCase().includes("already") || error.status === 422) {
      console.log("User already exists — updating password instead.");
      const list = await supabase.auth.admin.listUsers();
      const existing = list.data?.users?.find(u => u.email === TEST_EMAIL);
      if (existing) {
        const { error: updErr } = await supabase.auth.admin.updateUserById(existing.id, {
          password: TEST_PASSWORD,
          email_confirm: true
        });
        if (updErr) {
          console.error("Failed to update existing user:", updErr.message);
          process.exit(1);
        }
        console.log(`Password updated for existing user (id: ${existing.id})`);
      } else {
        console.error("Could not find existing user in list.");
        process.exit(1);
      }
    } else {
      console.error("Failed to create user:", error.message);
      process.exit(1);
    }
  } else {
    console.log(`Test user created successfully (id: ${data.user.id})`);
  }

  console.log("\nDone. The user will receive 250 trial treats on first app sign-in.");
}

run();
