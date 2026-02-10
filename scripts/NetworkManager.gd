extends Node

var hex: TileMapLayer
var turn_mgr: Node2D

var received_map_data: Array = []
var _orders_submitted := { "player1": false, "player2": false }
var player_orders := {"player1": {}, "player2": {}}  # map player_id → orders list

const MAX_PLAYERS: int = 6

var server_peer_id: int
var client_peer_ids: Array = []
var local_username: String = ""
var local_player_id: String = ""
var lobby_slot_count: int = 2
var lobby_slots: Array = []
var peer_id_to_player_id: Dictionary = {}
var mp
var selected_map_index: int = -1
var map_selection_mode: String = "random_normal"
var match_seed: int = -1
var custom_proc_params: Dictionary = {}


var _step_ready_counts := {}
var _incoming_replay: Dictionary = {}
const REPLAY_CHUNK_SIZE: int = 200000

signal orders_ready(all_orders: Dictionary)
signal orders_cancelled(player_id: String)
signal map_index_received(map_index: int)
signal match_seed_received(match_seed: int)
signal custom_proc_params_received(params: Dictionary)
signal map_selection_changed()
signal state_snapshot_received(state: Dictionary)
signal execution_paused_received(step_idx: int, neutral_step_idx: int)
signal execution_complete_received()
signal game_over_received(player_id: String)
signal buy_result(player_id: String, unit_type: String, grid_pos: Vector2i, ok: bool, reason: String, cost: int, unit_net_id: int)
signal undo_result(player_id: String, unit_net_id: int, ok: bool, reason: String, refund: int)
signal order_result(player_id: String, unit_net_id: int, order: Dictionary, ok: bool, reason: String)
signal lobby_updated(slots: Array, slot_count: int)
signal player_id_assigned(player_id: String)

func _ready() -> void:
	print("NetworkManager _ready() fired")
	mp = get_tree().get_multiplayer()
	mp.connect("peer_connected", Callable(self, "_on_peer_connected"))
	mp.connect("peer_disconnected", Callable(self, "_on_peer_disconnected"))
	if mp.is_server():
		server_peer_id = mp.get_unique_id()

func _ignore_rpc_in_replay() -> bool:
	return turn_mgr != null and bool(turn_mgr.get("replay_mode"))

func is_host() -> bool:
	var mp = get_tree().get_multiplayer()
	return mp != null and (mp.multiplayer_peer == null or mp.is_server())

func set_local_username(name: String) -> void:
	local_username = name.strip_edges()

func _reset_lobby_state() -> void:
	lobby_slots.clear()
	peer_id_to_player_id.clear()
	client_peer_ids.clear()
	lobby_slot_count = 2
	local_player_id = ""

func _init_lobby_slots() -> void:
	lobby_slots.clear()
	peer_id_to_player_id.clear()
	for i in range(lobby_slot_count):
		lobby_slots.append({
			"peer_id": 0,
			"player_id": "player%d" % (i + 1),
			"username": ""
		})
	_assign_host_slot()
	_emit_lobby_update()

func _assign_host_slot() -> void:
	if not is_host():
		return
	if lobby_slots.is_empty():
		return
	lobby_slots[0]["peer_id"] = server_peer_id
	lobby_slots[0]["username"] = local_username if local_username != "" else "Host"
	peer_id_to_player_id[server_peer_id] = lobby_slots[0]["player_id"]
	local_player_id = lobby_slots[0]["player_id"]
	if turn_mgr != null and turn_mgr.has_method("set_local_player_id"):
		turn_mgr.set_local_player_id(local_player_id)

func _emit_lobby_update() -> void:
	var payload: Array = []
	for slot in lobby_slots:
		payload.append({
			"player_id": slot.get("player_id", ""),
			"username": slot.get("username", ""),
			"occupied": int(slot.get("peer_id", 0)) != 0
		})
	emit_signal("lobby_updated", payload, lobby_slot_count)
	_broadcast_lobby_update(payload)

func is_lobby_full() -> bool:
	if lobby_slots.is_empty():
		return false
	for slot in lobby_slots:
		var occupied = false
		if slot.has("peer_id"):
			occupied = int(slot.get("peer_id", 0)) != 0
		else:
			occupied = bool(slot.get("occupied", false))
		if not occupied:
			return false
	return true

func _broadcast_lobby_update(payload: Array) -> void:
	if not is_host():
		return
	for peer_id in client_peer_ids:
		rpc_id(peer_id, "rpc_lobby_update", lobby_slot_count, payload)

func set_lobby_slot_count(count: int) -> void:
	if not is_host():
		return
	var clamped = int(clamp(count, 2, MAX_PLAYERS))
	if clamped == lobby_slot_count:
		return
	if clamped < lobby_slot_count:
		var mp_local = get_tree().get_multiplayer()
		for idx in range(lobby_slot_count - 1, clamped - 1, -1):
			if idx >= 0 and idx < lobby_slots.size():
				var peer_id = int(lobby_slots[idx].get("peer_id", 0))
				if peer_id != 0 and mp_local != null and mp_local.multiplayer_peer != null:
					peer_id_to_player_id.erase(peer_id)
					if client_peer_ids.has(peer_id):
						client_peer_ids.erase(peer_id)
					mp_local.multiplayer_peer.disconnect_peer(peer_id)
		lobby_slots.resize(clamped)
	else:
		for idx in range(lobby_slot_count, clamped):
			lobby_slots.append({
				"peer_id": 0,
				"player_id": "player%d" % (idx + 1),
				"username": ""
			})
	lobby_slot_count = clamped
	_emit_lobby_update()

func _clear_peer_slot(peer_id: int) -> void:
	for slot in lobby_slots:
		if int(slot.get("peer_id", 0)) == peer_id:
			slot["peer_id"] = 0
			slot["username"] = ""
			peer_id_to_player_id.erase(peer_id)
			_emit_lobby_update()
			return

func _assign_peer_to_slot(peer_id: int, username: String) -> void:
	for slot in lobby_slots:
		if int(slot.get("peer_id", 0)) == peer_id:
			slot["username"] = username
			peer_id_to_player_id[peer_id] = slot.get("player_id", "")
			_emit_lobby_update()
			return
	for slot in lobby_slots:
		if int(slot.get("peer_id", 0)) == 0:
			slot["peer_id"] = peer_id
			slot["username"] = username
			peer_id_to_player_id[peer_id] = slot.get("player_id", "")
			rpc_id(peer_id, "rpc_set_player_id", peer_id_to_player_id[peer_id])
			_emit_lobby_update()
			return
	var mp_local = get_tree().get_multiplayer()
	if mp_local != null and mp_local.multiplayer_peer != null:
		mp_local.multiplayer_peer.disconnect_peer(peer_id)
func host_game(port: int) -> void:
	#print("NetworkManager.host_game called with port:", port)
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(port, MAX_PLAYERS - 1)
	get_tree().get_multiplayer().multiplayer_peer = peer
	server_peer_id = get_tree().get_multiplayer().get_unique_id()
	_init_lobby_slots()
	print("Hosting game on port %d" % port)

func join_game(ip: String, port: int) -> void:
	#print("NetworkManager.join_game called with ip:", ip, "port:", port)
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, port)                             # Connect to host at given IP/port
	get_tree().get_multiplayer().multiplayer_peer = peer      # Register it with Godot
	print("Joining game at %s:%d" % [ip, port])

func close_connection():
	get_tree().get_multiplayer().multiplayer_peer.close()
	_reset_lobby_state()

func _on_peer_connected(id: int) -> void:
	mp = get_tree().get_multiplayer()
	set_gold()
	if mp.is_server():
		# Host sees a new client
		if not client_peer_ids.has(id):
			client_peer_ids.append(id)
		print("Client joined as peer %d" % id)
		if custom_proc_params.size() > 0:
			rpc_id(id, "rpc_set_custom_proc_params", custom_proc_params)
		if map_selection_mode != "":
			rpc_id(id, "rpc_set_map_selection_mode", map_selection_mode)
		if selected_map_index >= 0:
			rpc_id(id, "rpc_set_map_index", selected_map_index)
		if match_seed >= 0:
			rpc_id(id, "rpc_set_match_seed", match_seed)
	else:
		# Client sees the host
		server_peer_id = id
		print("Connected to host peer %d" % id)
		if local_username == "":
			local_username = "Player"
		rpc_id(server_peer_id, "rpc_register_username", local_username)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected with ID %d" % id)
	if client_peer_ids.has(id):
		client_peer_ids.erase(id)
	if is_host():
		_clear_peer_slot(id)

# RPC to receive the map data on clients
@rpc("any_peer", "reliable")
func map_sync(id) -> void:
	if get_tree().get_multiplayer().is_server():
		var data = get_map_data()
		rpc_id(id, "map_sync", data)

@rpc("any_peer", "reliable")
func rpc_set_map_index(map_index: int) -> void:
	if _ignore_rpc_in_replay():
		return
	selected_map_index = map_index
	emit_signal("map_index_received", map_index)
	emit_signal("map_selection_changed")
	if turn_mgr != null and turn_mgr.has_method("_maybe_log_match_init"):
		turn_mgr._maybe_log_match_init()

@rpc("any_peer", "reliable")
func rpc_set_map_selection_mode(mode: String) -> void:
	if _ignore_rpc_in_replay():
		return
	map_selection_mode = mode
	emit_signal("map_selection_changed")

@rpc("any_peer", "reliable")
func rpc_set_match_seed(seed_value: int) -> void:
	if _ignore_rpc_in_replay():
		return
	match_seed = seed_value
	emit_signal("match_seed_received", seed_value)
	if turn_mgr != null and turn_mgr.has_method("_maybe_log_match_init"):
		turn_mgr._maybe_log_match_init()

@rpc("any_peer", "reliable")
func rpc_set_custom_proc_params(params: Dictionary) -> void:
	if _ignore_rpc_in_replay():
		return
	custom_proc_params = params.duplicate(true)
	emit_signal("custom_proc_params_received", custom_proc_params)

@rpc("any_peer", "reliable")
func rpc_register_username(username: String) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp_local = get_tree().get_multiplayer()
	if mp_local == null or not mp_local.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var clean_name = username.strip_edges()
	if clean_name == "":
		clean_name = "Player"
	_assign_peer_to_slot(sender, clean_name)

@rpc("any_peer", "reliable")
func rpc_set_player_id(player_id: String) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp_local = get_tree().get_multiplayer()
	if mp_local != null and mp_local.is_server():
		return
	local_player_id = player_id
	if turn_mgr != null and turn_mgr.has_method("set_local_player_id"):
		turn_mgr.set_local_player_id(player_id)
	emit_signal("player_id_assigned", player_id)

@rpc("any_peer", "reliable")
func rpc_lobby_update(slot_count: int, slots_payload: Array) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp_local = get_tree().get_multiplayer()
	if mp_local != null and mp_local.is_server():
		return
	lobby_slot_count = slot_count
	lobby_slots = []
	for slot in slots_payload:
		if slot is Dictionary:
			lobby_slots.append({
				"player_id": slot.get("player_id", ""),
				"username": slot.get("username", ""),
				"occupied": bool(slot.get("occupied", false))
			})
	emit_signal("lobby_updated", lobby_slots, lobby_slot_count)

@rpc("any_peer", "reliable")
func rpc_start_game() -> void:
	if _ignore_rpc_in_replay():
		return
	var mp_local = get_tree().get_multiplayer()
	if mp_local != null and mp_local.is_server():
		return
	if turn_mgr != null and turn_mgr.has_method("start_game"):
		turn_mgr.start_game()

func set_custom_proc_params(params: Dictionary) -> void:
	custom_proc_params = params.duplicate(true)
	var mp = get_tree().get_multiplayer()
	if mp != null and mp.is_server():
		for peer_id in client_peer_ids:
			rpc_id(peer_id, "rpc_set_custom_proc_params", custom_proc_params)

func broadcast_map_selection() -> void:
	if not is_host():
		return
	for peer_id in client_peer_ids:
		rpc_id(peer_id, "rpc_set_map_selection_mode", map_selection_mode)
		rpc_id(peer_id, "rpc_set_map_index", selected_map_index)

@rpc("any_peer", "reliable")
func rpc_state_snapshot(state: Dictionary) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("state_snapshot_received", state)

@rpc("any_peer", "reliable")
func rpc_request_state() -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var state = turn_mgr.get_state_snapshot(true)
	var viewer = _peer_id_to_player_id(sender)
	if viewer != "" and turn_mgr.has_method("get_state_snapshot_for"):
		state = turn_mgr.get_state_snapshot_for(viewer, true)
	rpc_id(sender, "rpc_state_snapshot", state)
	if turn_mgr.current_phase == turn_mgr.Phase.EXECUTION:
		rpc_id(sender, "rpc_execution_paused", turn_mgr.step_index, turn_mgr.neutral_step_index)

@rpc("any_peer", "reliable")
func rpc_request_buy_unit(player_id: String, unit_type: String, grid_pos: Vector2i) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0:
		var expected_player := _peer_id_to_player_id(sender)
		if player_id != expected_player:
			push_error("Buy request owner mismatch: got '%s' from peer %d (expected '%s')" 
			% [player_id, sender, expected_player])
			return
	var result = _handle_buy_request(player_id, unit_type, grid_pos)
	rpc_id(sender, "rpc_buy_result", player_id, unit_type, grid_pos, result["ok"], result["reason"], result["cost"], result["unit_net_id"])

@rpc("any_peer", "reliable")
func rpc_request_undo_buy(player_id: String, unit_net_id: int) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0:
		var expected_player := _peer_id_to_player_id(sender)
		if player_id != expected_player:
			push_error("Undo request owner mismatch: got '%s' from peer %d (expected '%s')" 
			% [player_id, sender, expected_player])
			return
	var result = _handle_undo_buy_request(player_id, unit_net_id)
	rpc_id(sender, "rpc_undo_buy_result", player_id, unit_net_id, result["ok"], result["reason"], result["refund"])

@rpc("any_peer", "reliable")
func rpc_request_order(player_id: String, order: Dictionary) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0:
		var expected_player := _peer_id_to_player_id(sender)
		if player_id != expected_player:
			push_error("Order owner mismatch: got '%s' from peer %d (expected '%s')" 
			% [player_id, sender, expected_player])
			return
	var result = _handle_order_request(player_id, order)
	rpc_id(sender, "rpc_order_result", player_id, result["unit_net_id"], result["order"], result["ok"], result["reason"])

@rpc("any_peer", "reliable")
func rpc_buy_result(player_id: String, unit_type: String, grid_pos: Vector2i, ok: bool, reason: String, cost: int, unit_net_id: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	if turn_mgr != null and turn_mgr.has_method("log_remote_buy_result"):
		turn_mgr.log_remote_buy_result(player_id, unit_type, grid_pos, ok, reason, cost, unit_net_id)
	emit_signal("buy_result", player_id, unit_type, grid_pos, ok, reason, cost, unit_net_id)

@rpc("any_peer", "reliable")
func rpc_undo_buy_result(player_id: String, unit_net_id: int, ok: bool, reason: String, refund: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	if turn_mgr != null and turn_mgr.has_method("log_remote_undo_buy_result"):
		turn_mgr.log_remote_undo_buy_result(player_id, unit_net_id, ok, reason, refund)
	emit_signal("undo_result", player_id, unit_net_id, ok, reason, refund)

@rpc("any_peer", "reliable")
func rpc_order_result(player_id: String, unit_net_id: int, order: Dictionary, ok: bool, reason: String) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	if turn_mgr != null and turn_mgr.has_method("log_remote_order_result"):
		turn_mgr.log_remote_order_result(player_id, unit_net_id, order, ok, reason)
	emit_signal("order_result", player_id, unit_net_id, order, ok, reason)

@rpc("any_peer", "reliable")
func rpc_execution_paused(step_idx: int, neutral_step_idx: int) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("execution_paused_received", step_idx, neutral_step_idx)

@rpc("any_peer", "reliable")
func rpc_execution_complete() -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("execution_complete_received")

# Helper to gather the host's map layout
func get_map_data() -> Array:
	return hex.get_used_cells()

# Apply the received map data to the local TileMap
func _apply_map_data() -> void:
	if not hex:
		push_error("NetworkManager: hex_map is null when applying map data.")
		return
	# Clear existing cells
	hex.clear()
	# Set each cell based on received data
	var src = hex.tile_set.get_source_id(0)
	var tint = hex.ground_tile
	for cell in received_map_data:
		hex.set_cell(cell, src, tint)

# RPC to receive phase start notifications
@rpc("any_peer", "reliable")
func phase_started(phase_name: String) -> void:
	if _ignore_rpc_in_replay():
		return
	print("[NetworkManager] phase_started received: %s" % phase_name)
	# Call into your TurnManager to start the phase locally
	turn_mgr.start_phase_locally(phase_name)

# Called by host to broadcast a new phase to all peers
func broadcast_phase(phase_name: String) -> void:
	if get_tree().get_multiplayer().is_server():
		print("[NetworkManager] Broadcasting phase: %s" % phase_name)
		rpc("phase_started", phase_name)

func broadcast_state(state: Dictionary) -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if not mp.is_server():
		return
	var force_apply = bool(state.get("force_apply", false))
	for peer_id in client_peer_ids:
		var viewer = _peer_id_to_player_id(peer_id)
		var snapshot = state
		if viewer != "" and turn_mgr.has_method("get_state_snapshot_for"):
			snapshot = turn_mgr.get_state_snapshot_for(viewer)
			if force_apply:
				snapshot["force_apply"] = true
		rpc_id(peer_id, "rpc_state_snapshot", snapshot)

func request_state() -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if mp.is_server():
		var state = turn_mgr.get_state_snapshot()
		if turn_mgr.has_method("get_state_snapshot_for"):
			state = turn_mgr.get_state_snapshot_for(turn_mgr.local_player_id)
		emit_signal("state_snapshot_received", state)
	else:
		rpc_id(server_peer_id, "rpc_request_state")

func request_buy_unit(player_id: String, unit_type: String, grid_pos: Vector2i) -> bool:
	var mp = get_tree().get_multiplayer()
	var is_host = mp == null or mp.multiplayer_peer == null or mp.is_server()
	if is_host:
		var result = _handle_buy_request(player_id, unit_type, grid_pos)
		emit_signal("buy_result", player_id, unit_type, grid_pos, result["ok"], result["reason"], result["cost"], result["unit_net_id"])
		return bool(result["ok"])
	rpc_id(server_peer_id, "rpc_request_buy_unit", player_id, unit_type, grid_pos)
	return false

func request_undo_buy(player_id: String, unit_net_id: int) -> bool:
	var mp = get_tree().get_multiplayer()
	var is_host = mp == null or mp.multiplayer_peer == null or mp.is_server()
	if is_host:
		var result = _handle_undo_buy_request(player_id, unit_net_id)
		emit_signal("undo_result", player_id, unit_net_id, result["ok"], result["reason"], result["refund"])
		return bool(result["ok"])
	rpc_id(server_peer_id, "rpc_request_undo_buy", player_id, unit_net_id)
	return false

func request_order(player_id: String, order: Dictionary) -> bool:
	var mp = get_tree().get_multiplayer()
	var is_host = mp == null or mp.multiplayer_peer == null or mp.is_server()
	if is_host:
		var result = _handle_order_request(player_id, order)
		emit_signal("order_result", player_id, result["unit_net_id"], result["order"], result["ok"], result["reason"])
		return bool(result["ok"])
	rpc_id(server_peer_id, "rpc_request_order", player_id, order)
	return false

func _handle_buy_request(player_id: String, unit_type: String, grid_pos: Vector2i) -> Dictionary:
	var result = turn_mgr.buy_unit(player_id, unit_type, grid_pos)
	if result.get("ok", false):
		broadcast_state(turn_mgr.get_state_snapshot(true))
	return result

func _handle_undo_buy_request(player_id: String, unit_net_id: int) -> Dictionary:
	var result = turn_mgr.undo_buy_unit(player_id, unit_net_id)
	if result.get("ok", false):
		broadcast_state(turn_mgr.get_state_snapshot(true))
	return result

func _handle_order_request(player_id: String, order: Dictionary) -> Dictionary:
	return turn_mgr.validate_and_add_order(player_id, order)

func _handle_concede_request(player_id: String) -> void:
	if turn_mgr != null and turn_mgr.has_method("concede"):
		turn_mgr.concede(player_id)

func _handle_cancel_request(player_id: String) -> void:
	print("[NetworkManager] Player ", player_id, " cancelled their orders.")
	_orders_submitted[player_id] = false
	broadcast_state(turn_mgr.get_state_snapshot(true))

func broadcast_execution_paused(step_idx: int, neutral_step_idx: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if not mp.is_server():
		return
	rpc("rpc_execution_paused", step_idx, neutral_step_idx)

func broadcast_execution_complete() -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if not mp.is_server():
		return
	rpc("rpc_execution_complete")

func broadcast_game_over(player_id: String) -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if not mp.is_server():
		return
	for peer_id in client_peer_ids:
		rpc_id(peer_id, "rpc_game_over", player_id)

func start_game_for_all() -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if not mp.is_server():
		return
	if not is_lobby_full():
		return
	if turn_mgr != null and turn_mgr.has_method("_ensure_map_loaded"):
		turn_mgr._ensure_map_loaded()
	broadcast_map_selection()
	if turn_mgr != null and turn_mgr.has_method("start_game"):
		turn_mgr.start_game()
	for peer_id in client_peer_ids:
		rpc_id(peer_id, "rpc_start_game")

@rpc("any_peer", "reliable")
func rpc_game_over(player_id: String) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	if turn_mgr != null and turn_mgr.has_method("_show_game_over"):
		turn_mgr._show_game_over(player_id)
	emit_signal("game_over_received", player_id)

func send_replay_log_to_client(path: String) -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if not mp.is_server():
		return
	if client_peer_ids.is_empty():
		return
	if path == "":
		return
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if raw.size() == 0:
		return
	var compressed: PackedByteArray = _compress_bytes_gzip(raw, _tmp_replay_path("send", path))
	if compressed.size() == 0:
		return
	var base_name = _replay_filename_from_path(path)
	var total_chunks = int((compressed.size() + REPLAY_CHUNK_SIZE - 1) / REPLAY_CHUNK_SIZE)
	for peer_id in client_peer_ids:
		rpc_id(peer_id, "rpc_replay_log_begin", base_name, total_chunks, raw.size())
		for idx in range(total_chunks):
			var start = idx * REPLAY_CHUNK_SIZE
			var end = min(start + REPLAY_CHUNK_SIZE, compressed.size())
			var chunk = compressed.slice(start, end)
			rpc_id(peer_id, "rpc_replay_log_chunk", base_name, idx, chunk)
		rpc_id(peer_id, "rpc_replay_log_end", base_name)

@rpc("any_peer", "reliable")
func rpc_replay_log_begin(name: String, total_chunks: int, original_size: int) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	if total_chunks <= 0:
		return
	var safe_name = _sanitize_replay_name(name)
	var chunks: Array = []
	chunks.resize(total_chunks)
	_incoming_replay = {
		"name": safe_name,
		"total": total_chunks,
		"original_size": original_size,
		"chunks": chunks,
		"received": 0
	}

@rpc("any_peer", "reliable")
func rpc_replay_log_chunk(name: String, idx: int, data: PackedByteArray) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	if _incoming_replay.is_empty():
		return
	if _incoming_replay.get("name", "") != _sanitize_replay_name(name):
		return
	var chunks: Array = _incoming_replay.get("chunks", [])
	if idx < 0 or idx >= chunks.size():
		return
	if chunks[idx] == null:
		_incoming_replay["received"] = int(_incoming_replay.get("received", 0)) + 1
	chunks[idx] = data
	_incoming_replay["chunks"] = chunks

@rpc("any_peer", "reliable")
func rpc_replay_log_end(name: String) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	if _incoming_replay.is_empty():
		return
	var safe_name = _sanitize_replay_name(name)
	if _incoming_replay.get("name", "") != safe_name:
		return
	var total = int(_incoming_replay.get("total", 0))
	if int(_incoming_replay.get("received", 0)) < total:
		_send_replay_ack(safe_name, false, "missing_chunks")
		_incoming_replay = {}
		return
	var compressed := PackedByteArray()
	for chunk in _incoming_replay.get("chunks", []):
		if chunk == null:
			_send_replay_ack(safe_name, false, "missing_chunks")
			_incoming_replay = {}
			return
		compressed.append_array(chunk)
	var original_size = int(_incoming_replay.get("original_size", 0))
	var decompressed: PackedByteArray = _decompress_bytes_gzip(compressed, original_size, _tmp_replay_path("recv", safe_name))
	if decompressed.size() == 0 or decompressed.size() != original_size:
		_send_replay_ack(safe_name, false, "decompress_failed")
		_incoming_replay = {}
		return
	var path = _unique_replay_path(safe_name)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_send_replay_ack(safe_name, false, "write_failed")
		_incoming_replay = {}
		return
	file.store_buffer(decompressed)
	file.close()
	if turn_mgr != null and turn_mgr.has_method("set_host_replay_log_path"):
		turn_mgr.set_host_replay_log_path(path)
	_send_replay_ack(safe_name, true, path)
	_incoming_replay = {}

@rpc("any_peer", "reliable")
func rpc_replay_log_ack(name: String, ok: bool, saved_path: String) -> void:
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	print("[NetworkManager] Replay log transfer:", name, ok, saved_path)

func _send_replay_ack(name: String, ok: bool, info: String) -> void:
	if server_peer_id <= 0:
		return
	rpc_id(server_peer_id, "rpc_replay_log_ack", name, ok, info)

func _sanitize_replay_name(name: String) -> String:
	var base = name.get_file()
	if base == "":
		base = "dev_log_replay.jsonl"
	if not base.ends_with(".jsonl"):
		base += ".jsonl"
	return base

func _replay_filename_from_path(path: String) -> String:
	var base = path.get_file()
	if base == "":
		return "dev_log_replay.jsonl"
	var suffix = "_replay"
	if base.ends_with(".jsonl"):
		base = base.substr(0, base.length() - 6)
	return "%s%s.jsonl" % [base, suffix]

func _unique_replay_path(base_name: String) -> String:
	var name = _sanitize_replay_name(base_name)
	var path = "user://%s" % name
	if not FileAccess.file_exists(path):
		return path
	var stem = name.substr(0, name.length() - 6)
	var idx = 1
	while true:
		var candidate = "user://%s_%d.jsonl" % [stem, idx]
		if not FileAccess.file_exists(candidate):
			return candidate
		idx += 1
	return path

func _tmp_replay_path(prefix: String, name: String) -> String:
	var safe = name.get_file()
	if safe == "":
		safe = "dev_log.jsonl"
	safe = safe.replace(".jsonl", "").replace(".gz", "")
	return "user://_tmp_%s_%s.gz" % [prefix, safe]

func _compress_bytes_gzip(raw: PackedByteArray, tmp_path: String) -> PackedByteArray:
	if tmp_path == "":
		return PackedByteArray()
	var writer = FileAccess.open_compressed(tmp_path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if writer == null:
		return PackedByteArray()
	writer.store_buffer(raw)
	writer.close()
	var compressed = FileAccess.get_file_as_bytes(tmp_path)
	_dir_remove_if_exists(tmp_path)
	return compressed

func _decompress_bytes_gzip(compressed: PackedByteArray, expected_size: int, tmp_path: String) -> PackedByteArray:
	if tmp_path == "":
		return PackedByteArray()
	var raw_writer = FileAccess.open(tmp_path, FileAccess.WRITE)
	if raw_writer == null:
		return PackedByteArray()
	raw_writer.store_buffer(compressed)
	raw_writer.close()
	var reader = FileAccess.open_compressed(tmp_path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if reader == null:
		_dir_remove_if_exists(tmp_path)
		return PackedByteArray()
	var data = reader.get_buffer(expected_size)
	reader.close()
	_dir_remove_if_exists(tmp_path)
	return data

func _dir_remove_if_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dir = DirAccess.open("user://")
	if dir != null:
		dir.remove(path.get_file())

@rpc("any_peer", "reliable")
func rpc_submit_orders(player_id: String, orders: Array) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	print("[NM] Host received rpc_submit_orders from peer %d for %s" % [sender, player_id])
	if orders.size() > 0:
		print("[NM] Ignoring client orders payload (%d orders) - host is authoritative" % orders.size())
	_buffer_orders(player_id, [])

func submit_orders(player_id: String, orders: Array) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		_buffer_orders(player_id, [])
		print("[NM] Host buffering orders for %s locally" % player_id)
	else:
		print("[NM] Client sending orders for %s to host peer %d" % [player_id, server_peer_id])
		rpc_id(server_peer_id, "rpc_submit_orders", player_id, [])

func request_concede(player_id: String) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		_handle_concede_request(player_id)
	else:
		rpc_id(server_peer_id, "rpc_request_concede", player_id)

func _buffer_orders(player_id:String, orders:Array) -> void:
	print("[NM] _record_orders() called with player_id=%s, sender=%d" % [player_id, multiplayer.get_remote_sender_id()])
	# validate ownership: ensure player_id matches the peer who sent it
	var mp = get_tree().get_multiplayer()
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0:
		var expected_player := _peer_id_to_player_id(sender)
		if player_id != expected_player:
			push_error("Order owner mismatch: got orders for '%s' from peer %d (which is '%s')" 
			% [player_id, sender, expected_player])
			return
	_orders_submitted[player_id] = true

	# once both are in, multicast and signal
	if _orders_submitted["player1"] and _orders_submitted["player2"]:
		print("[NM] Both orders in, broadcasting & emitting orders_ready")
		turn_mgr.committed_orders = turn_mgr.player_orders.duplicate(true)
		broadcast_state(turn_mgr.get_state_snapshot(true))
		rpc("rpc_orders_ready", turn_mgr.player_orders)
		emit_signal("orders_ready", turn_mgr.player_orders)

@rpc("any_peer", "reliable")
func rpc_orders_ready(all_orders: Dictionary) -> void:
	if _ignore_rpc_in_replay():
		return
	player_orders = all_orders
	print("[NM] rpc_orders_ready received with keys:", all_orders.keys())
	emit_signal("orders_ready", all_orders)

func cancel_orders(player_id: String):
	if not mp.is_server():
		rpc_id(server_peer_id, "rpc_request_cancel_orders", player_id)
	else:
		rpc_request_cancel_orders(player_id)

@rpc("any_peer", "reliable")
func rpc_request_cancel_orders(player_id: String) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp := get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0:
		var expected_player := _peer_id_to_player_id(sender)
		if player_id != expected_player:
			push_error("Cancel request owner mismatch: got '%s' from peer %d (expected '%s')" 
			% [player_id, sender, expected_player])
			return
	_handle_cancel_request(player_id)
	rpc("rpc_orders_cancelled", player_id)

@rpc("any_peer", "reliable")
func rpc_request_concede(player_id: String) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp := get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0:
		var expected_player := _peer_id_to_player_id(sender)
		if player_id != expected_player:
			push_error("Concede request owner mismatch: got '%s' from peer %d (expected '%s')" 
			% [player_id, sender, expected_player])
			return
	_handle_concede_request(player_id)

@rpc("any_peer", "call_local")
func rpc_orders_cancelled(player_id: String):
	if _ignore_rpc_in_replay():
		return
	print("[NetworkManager] Received cancellation from ", player_id)
	_orders_submitted[player_id] = false
	orders_cancelled.emit(player_id)

# Helper to translate a peer ID into your player‐ID string
func _peer_id_to_player_id(peer_id: int) -> String:
	if peer_id_to_player_id.has(peer_id):
		return str(peer_id_to_player_id[peer_id])
	if peer_id == server_peer_id:
		return "player1"
	return ""

@rpc("any_peer", "reliable")
func rpc_step_ready(step_idx: int) -> void:
	if _ignore_rpc_in_replay():
		return
	var mp = get_tree().get_multiplayer()
	# only the host/server should count these
	if not mp.is_server():
		return

	# bump the counter
	_step_ready_counts[step_idx] = _step_ready_counts.get(step_idx, 0) + 1
	print("[NM] step_ready for step %d: count = %d" % [step_idx, _step_ready_counts[step_idx]])

	# once both players are in, broadcast resume
	if _step_ready_counts[step_idx] >= 2:
		print("[NM] both ready for step %d, resuming…" % step_idx)
		rpc("rpc_resume_execution", step_idx)
		rpc_resume_execution(step_idx)
@rpc("any_peer", "reliable")
func rpc_resume_execution(step_idx: int) -> void:
	if _ignore_rpc_in_replay():
		return
	print("[NM] rpc_resume_execution received for step %d" % step_idx)
	turn_mgr.resume_execution()


func set_gold():
	turn_mgr.turn_number = 0
