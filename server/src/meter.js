import { supabase } from "./supabase.js";

export async function record(event) {
  const sb = supabase();
  if (!sb) return;
  try {
    await sb.from("usage_meter").insert({
      user_id: event.userId,
      kind: event.kind,
      provider: event.provider || null,
      input_tokens: event.inputTokens || 0,
      output_tokens: event.outputTokens || 0,
      seconds: event.seconds || 0,
      raw_cost_usd: event.rawCostUsd || 0,
      treats_charged: event.treatsCharged || 0
    });
  } catch (_) {}
}
