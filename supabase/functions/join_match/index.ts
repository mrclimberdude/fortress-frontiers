import { createAdminClient, handleCors, json, requireUser } from "../_shared.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const auth = await requireUser(req);
  if (auth.error || !auth.user) return auth.error!;

  const body = await req.json().catch(() => ({}));
  const matchId = String(body.match_id ?? "").trim();
  const joinCode = String(body.join_code ?? "").trim().toUpperCase();
  const displayName = String(body.display_name ?? "").trim();
  const admin = createAdminClient();

  let matchQuery = admin
    .from("matches")
    .select("match_id, join_code, status, current_turn, rules_version")
    .limit(1);
  if (matchId !== "") {
    matchQuery = matchQuery.eq("match_id", matchId);
  } else {
    matchQuery = matchQuery.eq("join_code", joinCode);
  }
  const { data: matches, error: matchError } = await matchQuery;
  const match = matches?.[0];
  if (matchError || !match) return json({ error: matchError?.message ?? "match_not_found" }, 404);

  const { data: existingPlayers, error: playersError } = await admin
    .from("match_players")
    .select("user_id, player_slot")
    .eq("match_id", match.match_id);
  if (playersError) return json({ error: playersError.message }, 400);

  const existing = existingPlayers ?? [];
  const alreadyJoined = existing.find((row) => row.user_id === auth.user.id);
  const localPlayerId = alreadyJoined?.player_slot ?? (existing.some((row) => row.player_slot === "player1") ? "player2" : "player1");
  if (!alreadyJoined) {
    if (existing.length >= 2) return json({ error: "match_full" }, 409);
    const { error: insertError } = await admin.from("match_players").insert({
      match_id: match.match_id,
      user_id: auth.user.id,
      player_slot: localPlayerId,
      display_name: displayName,
    });
    if (insertError) return json({ error: insertError.message }, 400);
  }

  const playerSlots = alreadyJoined ? existing.map((row) => row.player_slot) : [...existing.map((row) => row.player_slot), localPlayerId];
  const waiting = playerSlots.includes("player1") && playerSlots.includes("player2") ? [] : ["player2"];
  const nextStatus = waiting.length === 0 ? "waiting_for_orders" : "waiting_for_players";

  await admin
    .from("matches")
    .update({ status: nextStatus, current_turn_status: nextStatus })
    .eq("match_id", match.match_id);
  await admin
    .from("turns")
    .update({ status: nextStatus })
    .eq("match_id", match.match_id)
    .eq("turn_number", match.current_turn);

  if (waiting.length === 0 && Number(match.current_turn) === 1) {
    const { data: snapshotRows, error: snapshotError } = await admin
      .from("turn_snapshots")
      .select("snapshot_version, canonical_snapshot")
      .eq("match_id", match.match_id)
      .eq("turn_number", match.current_turn)
      .order("snapshot_version", { ascending: false })
      .limit(1);
    if (snapshotError) return json({ error: snapshotError.message }, 400);

    const snapshotRow = snapshotRows?.[0];
    const canonicalSnapshot = (snapshotRow?.canonical_snapshot ?? {}) as Record<string, unknown>;
    const snapshotState = (canonicalSnapshot.state ?? {}) as Record<string, unknown>;
    const activePlayers = Array.isArray(snapshotState.active_players)
      ? snapshotState.active_players.map((entry) => String(entry))
      : [];
    const needsReseed =
      !snapshotRow ||
      !activePlayers.includes("player1") ||
      !activePlayers.includes("player2");

    if (needsReseed) {
      const { error: reseedError } = await admin.from("resolve_jobs").upsert({
        match_id: match.match_id,
        turn_number: match.current_turn,
        job_type: "seed_match",
        status: "queued",
        snapshot_ref: {},
        orders_ref: {},
        started_at: null,
        finished_at: null,
        last_error: "",
      }, { onConflict: "match_id,turn_number,job_type" });
      if (reseedError) return json({ error: reseedError.message }, 400);
    }
  }

  return json({
    match_id: match.match_id,
    join_code: match.join_code,
    status: nextStatus,
    current_turn: match.current_turn,
    rules_version: match.rules_version,
    player_slots: playerSlots,
    waiting_on_players: waiting,
    local_player_id: localPlayerId,
  });
});
