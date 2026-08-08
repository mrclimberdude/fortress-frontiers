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
    .select("match_id, join_code, status, current_turn, rules_version")
    .eq("match_id", matchId)
    .single();
  if (matchError || !match) return json({ error: matchError?.message ?? "match_not_found" }, 404);

  const { data: players, error: playersError } = await admin
    .from("match_players")
    .select("player_slot")
    .eq("match_id", matchId);
  if (playersError) return json({ error: playersError.message }, 400);

  const { data: currentTurn } = await admin
    .from("turns")
    .select("status, snapshot_version")
    .eq("match_id", matchId)
    .eq("turn_number", match.current_turn)
    .maybeSingle();

  const playerSlots = (players ?? []).map((row) => row.player_slot);
  const waitingOnPlayers = ["player1", "player2"].filter((slot) => !playerSlots.includes(slot));

  return json({
    match_id: match.match_id,
    join_code: match.join_code,
    status: currentTurn?.status ?? match.status,
    current_turn: match.current_turn,
    rules_version: match.rules_version,
    player_slots: playerSlots,
    waiting_on_players: waitingOnPlayers,
    local_player_id: membership.data.player_slot,
    snapshot_version: currentTurn?.snapshot_version ?? 0,
  });
});
