import { createClient } from "@supabase/supabase-js";
import { config } from "./config.js";

let client = null;

export function supabase() {
  if (!config.supabaseUrl || !config.supabaseServiceKey) return null;
  if (!client) {
    client = createClient(config.supabaseUrl, config.supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    });
  }
  return client;
}
