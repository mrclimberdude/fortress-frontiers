extends Node

var hex: TileMapLayer
var turn_mgr: Node2D

var received_map_data: Array = []
var _orders_submitted := { "player1": false, "player2": false }
var player_orders := {"player1": {}, "player2": {}}  # map player_id → orders list

var server_peer_id: int
var client_peer_id: int
var mp
var selected_map_index: int = -1
var match_seed: int = -1


var _step_ready_counts := {}

signal orders_ready(all_orders: Dictionary)
signal orders_cancelled(player_id: String)
signal map_index_received(map_index: int)
signal match_seed_received(match_seed: int)
signal state_snapshot_received(state: Dictionary)
signal execution_paused_received(step_idx: int, neutral_step_idx: int)
signal execution_complete_received()
signal buy_result(player_id: String, unit_type: String, grid_pos: Vector2i, ok: bool, reason: String, cost: int)
signal undo_result(player_id: String, unit_net_id: int, ok: bool, reason: String, refund: int)
signal order_result(player_id: String, unit_net_id: int, order: Dictionary, ok: bool, reason: String)

func _ready() -> void:
	print("NetworkManager _ready() fired")
	mp = get_tree().get_multiplayer()
	mp.connect("peer_connected", Callable(self, "_on_peer_connected"))
	mp.connect("peer_disconnected", Callable(self, "_on_peer_disconnected"))
	if mp.is_server():
		server_peer_id = mp.get_unique_id()

func host_game(port: int) -> void:
	#print("NetworkManager.host_game called with port:", port)
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(port, 2)             # Port and max 2 connections (host + one client)
	get_tree().get_multiplayer().multiplayer_peer = peer
	print("Hosting game on port %d" % port)

func join_game(ip: String, port: int) -> void:
	#print("NetworkManager.join_game called with ip:", ip, "port:", port)
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, port)                             # Connect to host at given IP/port
	get_tree().get_multiplayer().multiplayer_peer = peer      # Register it with Godot
	print("Joining game at %s:%d" % [ip, port])

func close_connection():
	get_tree().get_multiplayer().multiplayer_peer.close()

func _on_peer_connected(id: int) -> void:
	mp = get_tree().get_multiplayer()
	set_gold()
	if mp.is_server():
		# Host sees a new client
		client_peer_id = id
		print("Client joined as peer %d - starting game!" % id)
		if selected_map_index >= 0:
			rpc_id(id, "rpc_set_map_index", selected_map_index)
		if match_seed >= 0:
			rpc_id(id, "rpc_set_match_seed", match_seed)
		turn_mgr.start_game()
	else:
		# Client sees the host
		server_peer_id = id
		print("Connected to host peer %d" % id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected with ID %d" % id)

# RPC to receive the map data on clients
@rpc("any_peer", "reliable")
func map_sync(id) -> void:
	if get_tree().get_multiplayer().is_server():
		var data = get_map_data()
		rpc_id(id, "map_sync", data)

@rpc("any_peer", "reliable")
func rpc_set_map_index(map_index: int) -> void:
	selected_map_index = map_index
	emit_signal("map_index_received", map_index)

@rpc("any_peer", "reliable")
func rpc_set_match_seed(seed_value: int) -> void:
	match_seed = seed_value
	emit_signal("match_seed_received", seed_value)

@rpc("any_peer", "reliable")
func rpc_state_snapshot(state: Dictionary) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("state_snapshot_received", state)

@rpc("any_peer", "reliable")
func rpc_request_state() -> void:
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var state = turn_mgr.get_state_snapshot()
	rpc_id(sender, "rpc_state_snapshot", state)
	if turn_mgr.current_phase == turn_mgr.Phase.EXECUTION:
		rpc_id(sender, "rpc_execution_paused", turn_mgr.step_index, turn_mgr.neutral_step_index)

@rpc("any_peer", "reliable")
func rpc_request_buy_unit(player_id: String, unit_type: String, grid_pos: Vector2i) -> void:
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
	rpc_id(sender, "rpc_buy_result", player_id, unit_type, grid_pos, result["ok"], result["reason"], result["cost"])

@rpc("any_peer", "reliable")
func rpc_request_undo_buy(player_id: String, unit_net_id: int) -> void:
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
func rpc_buy_result(player_id: String, unit_type: String, grid_pos: Vector2i, ok: bool, reason: String, cost: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("buy_result", player_id, unit_type, grid_pos, ok, reason, cost)

@rpc("any_peer", "reliable")
func rpc_undo_buy_result(player_id: String, unit_net_id: int, ok: bool, reason: String, refund: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("undo_result", player_id, unit_net_id, ok, reason, refund)

@rpc("any_peer", "reliable")
func rpc_order_result(player_id: String, unit_net_id: int, order: Dictionary, ok: bool, reason: String) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("order_result", player_id, unit_net_id, order, ok, reason)

@rpc("any_peer", "reliable")
func rpc_execution_paused(step_idx: int, neutral_step_idx: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		return
	emit_signal("execution_paused_received", step_idx, neutral_step_idx)

@rpc("any_peer", "reliable")
func rpc_execution_complete() -> void:
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
	rpc("rpc_state_snapshot", state)

func request_state() -> void:
	var mp = get_tree().get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return
	if mp.is_server():
		emit_signal("state_snapshot_received", turn_mgr.get_state_snapshot())
	else:
		rpc_id(server_peer_id, "rpc_request_state")

func request_buy_unit(player_id: String, unit_type: String, grid_pos: Vector2i) -> bool:
	var mp = get_tree().get_multiplayer()
	var is_host = mp == null or mp.multiplayer_peer == null or mp.is_server()
	if is_host:
		var result = _handle_buy_request(player_id, unit_type, grid_pos)
		emit_signal("buy_result", player_id, unit_type, grid_pos, result["ok"], result["reason"], result["cost"])
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
		broadcast_state(turn_mgr.get_state_snapshot())
	return result

func _handle_undo_buy_request(player_id: String, unit_net_id: int) -> Dictionary:
	var result = turn_mgr.undo_buy_unit(player_id, unit_net_id)
	if result.get("ok", false):
		broadcast_state(turn_mgr.get_state_snapshot())
	return result

func _handle_order_request(player_id: String, order: Dictionary) -> Dictionary:
	return turn_mgr.validate_and_add_order(player_id, order)

func _handle_cancel_request(player_id: String) -> void:
	print("[NetworkManager] Player ", player_id, " cancelled their orders.")
	_orders_submitted[player_id] = false
	turn_mgr.reset_orders_for_player(player_id)
	broadcast_state(turn_mgr.get_state_snapshot())

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

@rpc("any_peer", "reliable")
func rpc_submit_orders(player_id: String, orders: Array) -> void:
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
		broadcast_state(turn_mgr.get_state_snapshot())
		rpc("rpc_orders_ready", turn_mgr.player_orders)
		emit_signal("orders_ready", turn_mgr.player_orders)

@rpc("any_peer", "reliable")
func rpc_orders_ready(all_orders: Dictionary) -> void:
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

@rpc("any_peer", "call_local")
func rpc_orders_cancelled(player_id: String):
	print("[NetworkManager] Received cancellation from ", player_id)
	_orders_submitted[player_id] = false
	orders_cancelled.emit(player_id)

# Helper to translate a peer ID into your player‐ID string
func _peer_id_to_player_id(peer_id: int) -> String:
	if peer_id == server_peer_id:
		return "player1"
	elif peer_id == client_peer_id:
		return "player2"
	else:
		return ""

@rpc("any_peer", "reliable")
func rpc_step_ready(step_idx: int) -> void:
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
	print("[NM] rpc_resume_execution received for step %d" % step_idx)
	turn_mgr.resume_execution()


func set_gold():
	turn_mgr.turn_number = 0
