import { createAdminClient, handleCors, json, requireUser } from "../_shared.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const auth = await requireUser(req);
  if (auth.error || !auth.user) return auth.error!;

  const admin = createAdminClient();
  const { data, error } = await admin
    .from("match_players")
    .select("player_slot, matches!inner(match_id, status, current_turn, rules_version, join_code)")
    .eq("user_id", auth.user.id);

  if (error) return json({ error: error.message }, 400);

  const matches = (data ?? []).map((row: any) => ({
    match_id: row.matches.match_id,
    status: row.matches.status,
    current_turn: row.matches.current_turn,
    rules_version: row.matches.rules_version,
    join_code: row.matches.join_code,
    local_player_id: row.player_slot,
  }));

  return json({ matches });
});
