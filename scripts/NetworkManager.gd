extends Node


var hex: TileMapLayer
var turn_mgr: Node2D

var received_map_data: Array = []
var _orders_submitted := { "player1": false, "player2": false }
var player_orders := {"player1": {}, "player2": {}}  # map player_id → orders list
var server_peer_id: int
var client_peer_id: int

signal orders_ready(all_orders: Dictionary)

func _ready() -> void:
	print("NetworkManager _ready() fired")
	var mp = get_tree().get_multiplayer()
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

func _on_peer_connected(id: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		# Host sees a new client
		client_peer_id = id
		print("Client joined as peer %d — starting game!" % id)
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

@rpc("any_peer", "reliable")
func rpc_submit_orders(player_id: String, orders: Array) -> void:
	var mp = get_tree().get_multiplayer()
	if not mp.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	print("[NM] Host received rpc_submit_orders from peer %d for %s" % [sender, player_id])
	_buffer_orders(player_id, orders)

func submit_orders(player_id: String, orders: Array) -> void:
	var mp = get_tree().get_multiplayer()
	if mp.is_server():
		_buffer_orders(player_id, orders)
		print("[NM] Host buffering orders for %s locally" % player_id)
	else:
		print("[NM] Client sending orders for %s to host peer %d" % [player_id, server_peer_id])
		rpc_id(server_peer_id, "rpc_submit_orders", player_id, orders)

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
	for order in orders:
		if order["type"] == "spawn":
			player_orders[player_id][order["cell"]] = order
		else:
			player_orders[player_id][order.unit] = order

	# once both are in, multicast and signal
	if _orders_submitted["player1"] and _orders_submitted["player2"]:
		print("[NM] Both orders in, broadcasting & emitting orders_ready")
		rpc("rpc_orders_ready", player_orders)
		emit_signal("orders_ready", player_orders)

@rpc("any_peer", "reliable")
func rpc_orders_ready(all_orders: Dictionary) -> void:
	player_orders = all_orders
	print("[NM] rpc_orders_ready received with keys:", all_orders.keys())
	emit_signal("orders_ready", all_orders)

# Helper to translate a peer ID into your player‐ID string
func _peer_id_to_player_id(peer_id: int) -> String:
	if peer_id == server_peer_id:
		return "player1"
	elif peer_id == client_peer_id:
		return "player2"
	else:
		return ""
