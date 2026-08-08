import { createAdminClient, handleCors, json, requireUser } from "../_shared.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const auth = await requireUser(req);
  if (auth.error || !auth.user) return auth.error!;

  const body = await req.json().catch(() => ({}));
  const displayName = String(body.display_name ?? "").trim();
  const rulesVersion = String(body.rules_version ?? "async_v1").trim();
  const matchSeed = (crypto.getRandomValues(new Uint32Array(1))[0] % 2147483646) + 1;
  const mapSelection = {
    map_selection_mode: String(body.map_selection_mode ?? "random_normal"),
    selected_map_index: Number(body.selected_map_index ?? -1),
    custom_proc_params: body.custom_proc_params ?? {},
    match_seed: matchSeed,
  };

  const admin = createAdminClient();
  const { data: match, error: matchError } = await admin
    .from("matches")
    .insert({
      created_by: auth.user.id,
      rules_version: rulesVersion,
      status: "waiting_for_players",
      current_turn: 1,
      current_turn_status: "waiting_for_players",
      map_selection: mapSelection,
    })
    .select("match_id, join_code, status, current_turn, rules_version")
    .single();

  if (matchError || !match) return json({ error: matchError?.message ?? "match_insert_failed" }, 400);

  const { error: playerError } = await admin.from("match_players").insert({
    match_id: match.match_id,
    user_id: auth.user.id,
    player_slot: "player1",
    display_name: displayName,
  });
  if (playerError) return json({ error: playerError.message }, 400);

  await admin.from("turns").insert({
    match_id: match.match_id,
    turn_number: 1,
    status: "waiting_for_players",
    snapshot_version: 0,
  });

  await admin.from("resolve_jobs").upsert({
    match_id: match.match_id,
    turn_number: 1,
    job_type: "seed_match",
    status: "queued",
    snapshot_ref: {},
    orders_ref: mapSelection,
  }, { onConflict: "match_id,turn_number,job_type" });

  return json({
    match_id: match.match_id,
    join_code: match.join_code,
    status: "waiting_for_players",
    current_turn: 1,
    rules_version: rulesVersion,
    player_slots: ["player1"],
    waiting_on_players: ["player2"],
    local_player_id: "player1",
    match_seed: matchSeed,
  });
});
