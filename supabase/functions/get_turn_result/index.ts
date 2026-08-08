import { createAdminClient, getMembership, handleCors, json, requireUser } from "../_shared.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const auth = await requireUser(req);
  if (auth.error || !auth.user) return auth.error!;

  const body = await req.json().catch(() => ({}));
  const matchId = String(body.match_id ?? "").trim();
  if (matchId === "") return json({ error: "match_id_required" }, 400);

  const admin = createAdminClient();
  const membership = await getMembership(admin, matchId, auth.user.id);
  if (membership.error || !membership.data) return json({ error: "not_a_match_member" }, 403);

  const { data: match, error: matchError } = await admin
    .from("matches")
    .select("match_id, status, current_turn, rules_version, current_turn_status")
    .eq("match_id", matchId)
    .single();
  if (matchError || !match) return json({ error: matchError?.message ?? "match_not_found" }, 404);

  const { data: turn, error: turnError } = await admin
    .from("turns")
    .select("turn_number, status, snapshot_version, resolved_at")
    .eq("match_id", matchId)
    .eq("turn_number", match.current_turn)
    .single();
  if (turnError || !turn) return json({ error: turnError?.message ?? "turn_not_found" }, 404);

  return json({
    match_id: match.match_id,
    status: turn.status,
    current_turn: match.current_turn,
    rules_version: match.rules_version,
    snapshot_version: turn.snapshot_version,
    resolved_at: turn.resolved_at,
    local_player_id: membership.data.player_slot,
  });
});
