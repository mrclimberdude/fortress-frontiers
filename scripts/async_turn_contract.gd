class_name AsyncTurnContract
extends RefCounted

const RULES_VERSION: String = "async_v1"

var tm


func _init(turn_manager) -> void:
	tm = turn_manager


func build_match_state(match_id: String, waiting_on_players: Array = []) -> Dictionary:
	return {
		"match_id": match_id,
		"status": "waiting_for_orders",
		"current_turn": int(tm.turn_number),
		"rules_version": RULES_VERSION,
		"player_slots": tm.active_players.duplicate(),
		"waiting_on_players": waiting_on_players.duplicate()
	}


func build_turn_snapshot(match_id: String, viewer_id: String = "", bump_seq: bool = false) -> Dictionary:
	var state := {}
	if viewer_id == "":
		state = tm.get_state_snapshot(bump_seq)
	else:
		state = tm.get_state_snapshot_for(viewer_id, bump_seq)
	return {
		"match_id": match_id,
		"turn_number": int(tm.turn_number),
		"rules_version": RULES_VERSION,
		"map_seed": int(NetworkManager.match_seed),
		"snapshot_version": int(tm.state_seq),
		"created_at": int(Time.get_unix_time_from_system()),
		"viewer_id": viewer_id,
		"state": tm._encode_value(state)
	}


func build_order_submission(match_id: String, turn_number: int, snapshot_version: int, player_id: String, orders: Array, buy_events: Array, undo_events: Array) -> Dictionary:
	var submission_orders = _duplicate_array(orders)
	var submission_buys = _duplicate_array(buy_events)
	var submission_undos = _duplicate_array(undo_events)
	_remap_submission_unit_ids(player_id, submission_orders, submission_buys, submission_undos)
	return {
		"match_id": match_id,
		"turn_number": int(turn_number),
		"snapshot_version": int(snapshot_version),
		"player_id": player_id,
		"submitted_at": int(Time.get_unix_time_from_system()),
		"orders": tm._encode_value(submission_orders),
		"buy_events": tm._encode_value(submission_buys),
		"undo_events": tm._encode_value(submission_undos)
	}


func normalize_order_submissions(raw_submissions: Array) -> Array:
	var normalized: Array = []
	for raw in raw_submissions:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw.duplicate(true)
		entry["match_id"] = str(entry.get("match_id", "")).strip_edges()
		entry["player_id"] = str(entry.get("player_id", "")).strip_edges()
		entry["turn_number"] = int(entry.get("turn_number", 0))
		entry["snapshot_version"] = int(entry.get("snapshot_version", 0))
		entry["submitted_at"] = int(entry.get("submitted_at", 0))
		entry["orders"] = _normalize_order_array(tm._decode_value(entry.get("orders", [])))
		entry["buy_events"] = _normalize_buy_events(tm._decode_value(entry.get("buy_events", [])))
		entry["undo_events"] = _normalize_undo_events(tm._decode_value(entry.get("undo_events", [])))
		normalized.append(entry)
	return normalized


func extract_state(snapshot_envelope: Dictionary) -> Dictionary:
	var payload = snapshot_envelope.get("state", {})
	var decoded = tm._decode_value(payload)
	return decoded.duplicate(true) if decoded is Dictionary else {}


func _duplicate_array(values) -> Array:
	if values is Array:
		return values.duplicate(true)
	return []


func _remap_submission_unit_ids(player_id: String, orders: Array, buy_events: Array, undo_events: Array) -> void:
	var remapped_ids := {}
	var next_temp_id = _temp_unit_id_base(player_id)
	for idx in range(buy_events.size()):
		if not (buy_events[idx] is Dictionary):
			continue
		var event = buy_events[idx].duplicate(true)
		var client_unit_id = int(event.get("unit_net_id", -1))
		if client_unit_id <= 0:
			buy_events[idx] = event
			continue
		if not remapped_ids.has(client_unit_id):
			remapped_ids[client_unit_id] = next_temp_id
			next_temp_id -= 1
		event["unit_net_id"] = int(remapped_ids[client_unit_id])
		buy_events[idx] = event
	if remapped_ids.is_empty():
		return
	_remap_order_unit_ids(orders, remapped_ids)
	_remap_event_unit_ids(undo_events, remapped_ids)


func _remap_order_unit_ids(orders: Array, remapped_ids: Dictionary) -> void:
	for idx in range(orders.size()):
		if not (orders[idx] is Dictionary):
			continue
		var order = orders[idx].duplicate(true)
		var unit_id = int(order.get("unit_net_id", -1))
		if remapped_ids.has(unit_id):
			order["unit_net_id"] = int(remapped_ids[unit_id])
		orders[idx] = order


func _remap_event_unit_ids(events: Array, remapped_ids: Dictionary) -> void:
	for idx in range(events.size()):
		if not (events[idx] is Dictionary):
			continue
		var event = events[idx].duplicate(true)
		var unit_id = int(event.get("unit_net_id", -1))
		if remapped_ids.has(unit_id):
			event["unit_net_id"] = int(remapped_ids[unit_id])
		events[idx] = event


func _temp_unit_id_base(player_id: String) -> int:
	match player_id:
		"player1":
			return -1000000
		"player2":
			return -2000000
		_:
			return -3000000


func _normalize_order_array(values) -> Array:
	var orders: Array = []
	if not (values is Array):
		return orders
	for raw in values:
		if raw is Dictionary:
			orders.append(raw.duplicate(true))
	return orders


func _normalize_buy_events(values) -> Array:
	var events: Array = []
	if not (values is Array):
		return events
	for raw in values:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw.duplicate(true)
		event["unit_type"] = str(event.get("unit_type", "")).strip_edges()
		event["unit_net_id"] = int(event.get("unit_net_id", -1))
		event["grid_pos"] = tm._decode_log_vec2i(event.get("grid_pos", Vector2i.ZERO))
		events.append(event)
	return events


func _normalize_undo_events(values) -> Array:
	var events: Array = []
	if not (values is Array):
		return events
	for raw in values:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw.duplicate(true)
		event["unit_net_id"] = int(event.get("unit_net_id", -1))
		events.append(event)
	return events
