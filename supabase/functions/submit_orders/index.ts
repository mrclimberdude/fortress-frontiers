import { createAdminClient, getMembership, handleCors, json, requireUser } from "../_shared.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const auth = await requireUser(req);
  if (auth.error || !auth.user) return auth.error!;

  const body = await req.json().catch(() => ({}));
  const matchId = String(body.match_id ?? "").trim();
  const turnNumber = Number(body.turn_number ?? 0);
  const snapshotVersion = Number(body.snapshot_version ?? -1);
  const declaredPlayerId = String(body.player_id ?? "").trim();
  if (matchId === "" || turnNumber <= 0) return json({ error: "invalid_submission" }, 400);

  const admin = createAdminClient();
  const membership = await getMembership(admin, matchId, auth.user.id);
  if (membership.error || !membership.data) return json({ error: "not_a_match_member" }, 403);
  if (declaredPlayerId !== "" && declaredPlayerId !== membership.data.player_slot) {
    return json({ error: "player_slot_mismatch" }, 409);
  }

  const { data: turn, error: turnError } = await admin
    .from("turns")
    .select("turn_number, status, snapshot_version")
    .eq("match_id", matchId)
    .eq("turn_number", turnNumber)
    .single();
  if (turnError || !turn) return json({ error: turnError?.message ?? "turn_not_found" }, 404);
  if (turn.status !== "waiting_for_orders") return json({ error: "turn_not_accepting_orders" }, 409);
  if (snapshotVersion !== turn.snapshot_version) return json({ error: "stale_snapshot_version" }, 409);

  const payload = {
    ...body,
    player_id: membership.data.player_slot,
  };

  const insertResult = await admin.from("turn_orders").insert({
    match_id: matchId,
    turn_number: turnNumber,
    player_slot: membership.data.player_slot,
    submitted_by: auth.user.id,
    snapshot_version: snapshotVersion,
    payload,
  });
  if (insertResult.error) {
    return json({ error: insertResult.error.message }, 409);
  }

  const { data: orderRows, error: ordersError } = await admin
    .from("turn_orders")
    .select("player_slot")
    .eq("match_id", matchId)
    .eq("turn_number", turnNumber);
  if (ordersError) return json({ error: ordersError.message }, 400);

  const submittedSlots = (orderRows ?? []).map((row) => row.player_slot);
  const waitingOnPlayers = ["player1", "player2"].filter((slot) => !submittedSlots.includes(slot));
  const allSubmitted = waitingOnPlayers.length === 0;

  if (allSubmitted) {
    await admin
      .from("turns")
      .update({ status: "resolving" })
      .eq("match_id", matchId)
      .eq("turn_number", turnNumber);
    await admin
      .from("matches")
      .update({ status: "resolving", current_turn_status: "resolving" })
      .eq("match_id", matchId);
    await admin.from("resolve_jobs").upsert({
      match_id: matchId,
      turn_number: turnNumber,
      job_type: "resolve_turn",
      status: "queued",
      snapshot_ref: { snapshot_version: turn.snapshot_version },
      orders_ref: { submitted_slots: submittedSlots },
    }, { onConflict: "match_id,turn_number,job_type" });
  }

  return json({
    ok: true,
    match_id: matchId,
    turn_number: turnNumber,
    status: allSubmitted ? "resolving" : "waiting_for_orders",
    waiting_on_players: waitingOnPlayers,
    player_id: membership.data.player_slot,
  });
});
