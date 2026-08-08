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
    .select("match_id, current_turn, current_turn_status")
    .eq("match_id", matchId)
    .single();
  if (matchError || !match) return json({ error: matchError?.message ?? "match_not_found" }, 404);

  const { data: snapshotRows, error: snapshotError } = await admin
    .from("turn_snapshots")
    .select("snapshot_version, canonical_snapshot, player_views")
    .eq("match_id", matchId)
    .eq("turn_number", match.current_turn)
    .order("snapshot_version", { ascending: false })
    .limit(1);
  const snapshotRow = snapshotRows?.[0];
  const localPlayerId = membership.data.player_slot;
  if (snapshotError) return json({ error: snapshotError.message }, 400);
  if (!snapshotRow) {
    return json({
      pending: true,
      match_id: matchId,
      viewer_id: localPlayerId,
      turn_number: match.current_turn,
      snapshot_version: -1,
      status: match.current_turn_status ?? "snapshot_pending",
    }, 202);
  }

  const snapshot = snapshotRow.canonical_snapshot as Record<string, unknown>;
  const snapshotRecord = (snapshot ?? {}) as Record<string, unknown>;
  const snapshotState = (snapshotRecord.state ?? {}) as Record<string, unknown>;
  const activePlayers = Array.isArray(snapshotState.active_players)
    ? snapshotState.active_players.map((entry) => String(entry))
    : [];
  if (activePlayers.length > 0 && !activePlayers.includes(localPlayerId)) {
    return json({
      pending: true,
      match_id: matchId,
      viewer_id: localPlayerId,
      turn_number: match.current_turn,
      snapshot_version: Number(snapshotRow.snapshot_version ?? -1),
      status: "snapshot_refresh_pending",
    }, 202);
  }

  return json({
    ...(snapshot as Record<string, unknown>),
    match_id: matchId,
    viewer_id: localPlayerId,
    snapshot_version: snapshotRow.snapshot_version,
  });
});
