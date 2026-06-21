import { supabase } from "./supabase.js";

export async function requireUser(req, res, next) {
  const header = req.headers["authorization"] || "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) {
    return res.status(401).json({ error: "missing_bearer_token" });
  }

  const sb = supabase();
  if (!sb) {
    return res.status(503).json({ error: "auth_not_configured" });
  }

  try {
    const { data, error } = await sb.auth.getUser(token);
    if (error || !data?.user) {
      return res.status(401).json({ error: "invalid_token" });
    }
    req.user = { id: data.user.id, email: data.user.email };
    return next();
  } catch (e) {
    return res.status(401).json({ error: "auth_failed" });
  }
}
