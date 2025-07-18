## TurnManager.gd

extends Node

signal orders_phase_begin(player: String)
signal orders_phase_end()

signal execution_paused(phase)   # emitted after each phase
signal execution_complete()      # emitted at the end

enum Phase { UPKEEP, ORDERS, EXECUTION }

# --- Exports & References for Unit Spawning ---
@export var unit_manager_path: NodePath
@onready var unit_manager = get_node(unit_manager_path) as Node

@export var archer_scene:  PackedScene
@export var soldier_scene: PackedScene

# --- Turn & Phase State ---
var turn_number:   int    = 0
var current_phase: Phase  = Phase.UPKEEP
var current_player:String = "player1"
var exec_steps: Array     = []
var step_index: int       = 0

# --- Economy State ---
var player_gold       := { "player1": 0, "player2": 0 }
const BASE_INCOME    : int = 5
const SPECIAL_INCOME : int = 2

var base_positions := {
	"player1": Vector2i(0, 7),
	"player2": Vector2i(17, 7)
}
var special_tiles := {
	"player1": [ Vector2i(5, 5), Vector2i(3, 11) ],
	"player2": [ Vector2i(12, 6), Vector2i(14, 2) ]
}

# --- Orders Data ---
var player_orders     := { "player1": {}, "player2": {} }
var _orders_submitted := { "player1": false, "player2": false }

# --------------------------------------------------------
# Entry point: start the game loop once the scene is ready
# --------------------------------------------------------
func _ready():
	call_deferred("_game_loop")

# --------------------------------------------------------
# Main loop: Upkeep → Orders → Execution → increment → loop
# --------------------------------------------------------
func _game_loop() -> void:
	turn_number += 1
	print("\n===== TURN %d =====" % turn_number)
	_do_upkeep()
	await _do_orders()
	_do_execution()

# --------------------------------------------------------
# Phase 1: Upkeep — award gold
# --------------------------------------------------------
func _do_upkeep() -> void:
	current_phase = Phase.UPKEEP
	print("--- Upkeep Phase ---")
	for player in ["player1", "player2"]:
		var income = 0
		if _controls_tile(player, base_positions[player]):
			income += BASE_INCOME
		for pos in special_tiles[player]:
			if _controls_tile(player, pos):
				income += SPECIAL_INCOME
		player_gold[player] += income
		print("%s income: %d  → total gold: %d" % [player.capitalize(), income, player_gold[player]])
		# reset orders state
	for p in ["player1", "player2"]:
		player_orders[p].clear()
		_orders_submitted[p] = false

# --------------------------------------------------------
# Phase 2: Orders — async per-player input
# --------------------------------------------------------
func _do_orders() -> void:
	current_phase = Phase.ORDERS
	# start with player1
	current_player = "player1"
	print("--- Orders Phase for %s ---" % current_player.capitalize())
	emit_signal("orders_phase_begin", current_player)

	# wait until both players have submitted
	await self.orders_phase_end
	print("→ Both players submitted orders: %s" % player_orders)

# Called by UIManager to add orders
func add_order(player: String, order: Dictionary) -> void:
	# Order is a dictionary with keys: "unit", "type", and "path"
	player_orders[player][order.unit] = order

func get_order(player:String, unit:Node) -> Dictionary:
	return player_orders[player].get(unit,{})

func get_all_orders(player_id: String) -> Array:
	if player_orders.has(player_id):
		return player_orders[player_id].values()
	push_error("Unknown player in get_orders: %s" % player_id)
	return []

# Called by UIManager when a player hits 'Done'
func submit_player_order(player: String) -> void:
	_orders_submitted[player] = true

	# hand off from player1 to player2
	if player == "player1" and not _orders_submitted["player2"]:
		current_player = "player2"
		print("--- Orders Phase for %s ---" % current_player.capitalize())
		emit_signal("orders_phase_begin", current_player)
		return

	# both submitted: end orders phase
	if _orders_submitted["player1"] and _orders_submitted["player2"]:
		emit_signal("orders_phase_end")

func _process_ranged():
	var ranged_dmg: Dictionary = {}
	# ranged orders resolution
	for player in ["player1", "player2"]:
		for unit in player_orders[player].keys():
			var order = player_orders[player][unit]
			if order["type"] == "ranged":
				# check to make sure target unit still exists
				if is_instance_valid(order["target_unit"]):
					var damaged_penalty = (100 - order["unit"].curr_health) * 0.005
					var ranged_str = order["unit"].ranged_strength * damaged_penalty
					var def_str
					if order["target_unit"].is_ranged:
						def_str = order["target_unit"].ranged_strength
					else:
						def_str = order["target_unit"].melee_strength
					var dmg = 30 * exp((ranged_str-def_str)/25 * randf_range(0.75,1.25))
					ranged_dmg[order["target_unit"]] = ranged_dmg.get(order["target_unit"], 0) + dmg
				player_orders[player].erase(unit)
	for target in ranged_dmg.keys():
		target.curr_health -= ranged_dmg[target]
		# dead unit, remove from all orders and remove node from game
		if target.curr_health <= 0:
			for player in ["player1", "player2"]:
				player_orders[player].erase(target)
			$GameBoardNode/HexTileMap.set_player_tile(target.grid_pos, "")
			$GameBoardNode.vacate(target.grid_pos)
			target.free()
		else:
			target.set_health_bar()
	$UI._draw_attacks()

func _process_melee():
	var melee_dmg: Dictionary = {}
	# melee orders resolution
	for player in ["player1", "player2"]:
		for unit in player_orders[player].keys():
			var order = player_orders[player][unit]
			if order["type"] == "melee":
				if is_instance_valid(order["target_unit"]):
					var damaged_penalty = (100 - order["unit"].curr_health) * 0.005
					var melee_str = order["unit"].melee_strength * damaged_penalty
					var def_str = order["target_unit"].melee_strength
					var dmg = 30 * exp((melee_str-def_str)/25 * randf_range(0.75,1.25))
					melee_dmg[order["target_unit"]] = melee_dmg.get(order["target_unit"], 0) + dmg
				player_orders[player].erase(unit)
	
	for target in melee_dmg.keys():
		target.curr_health -= melee_dmg[target]
		# dead unit, remove from all orders and remove node from game
		if target.curr_health <= 0:
			for player in ["player1", "player2"]:
				player_orders[player].erase(target)
			$GameBoardNode/HexTileMap.set_player_tile(target.grid_pos, "")
			$GameBoardNode.vacate(target.grid_pos)
			target.free()
		else:
			target.set_health_bar()
	$UI._draw_attacks()
	$UI._draw_paths()
	$UI._draw_supports()

func _process_move():
	pass
	#var melee_dmg: Dictionary = {}
	#var tiles_entering: Dictionary = {}
	#for player in ["player1", "player2"]:
		#for unit in player_orders[player].keys():
			#var order = player_orders[player][unit]
			#if order["type"] == "move":
				#var next_tile = order["path"][1]
				#tiles_entering[next_tile] = tiles_entering.get(next_tile, []).append(unit)
				

func _initialize_execution():
	$UI._draw_attacks()
	$UI._draw_heals()

# --------------------------------------------------------
# Phase 3: Execution — process orders
# --------------------------------------------------------
func _do_execution() -> void:
	current_phase = Phase.EXECUTION
	print("Executing orders...")
	exec_steps = [
		func(): _initialize_execution(),
		func(): _process_ranged(),
		func(): _process_melee(),
		func(): _process_move()
	]

	step_index = 0
	_run_next_step()

func _run_next_step():
	if step_index >= exec_steps.size():
		emit_signal("execution_complete")
		call_deferred("_game_loop")
		return
	exec_steps[step_index].call()
	emit_signal("execution_paused", step_index)

func resume_execution():
	step_index += 1
	_run_next_step()

# --------------------------------------------------------
# API: attempt to buy and spawn a unit
# --------------------------------------------------------
func buy_unit(player: String, unit_type: String, grid_pos: Vector2i) -> bool:
	var scene: PackedScene = null
	if unit_type.to_lower() == "archer":
		scene = archer_scene
	elif unit_type.to_lower() == "soldier":
		scene = soldier_scene
	else:
		push_error("Unknown unit type '%s'" % unit_type)
		return false
	if scene == null:
		push_error("Unit scene for '%s' not assigned in Inspector" % unit_type)
		return false

	# check cost
	var tmp_unit = scene.instantiate()
	var cost = tmp_unit.get("cost")
	tmp_unit.queue_free()
	if player_gold[player] < cost:
		print("%s cannot afford a %s (needs %d gold)" % [player, unit_type, cost])
		return false

	# deduct gold & spawn
	player_gold[player] -= cost
	unit_manager.spawn_unit(unit_type, grid_pos, player)
	print("%s bought a %s at %s for %d gold" % [player, unit_type, grid_pos, cost])
	return true

# --------------------------------------------------------
# Stub: determine if a player controls a given tile
# --------------------------------------------------------
func _controls_tile(player: String, pos: Vector2i) -> bool:
	return true  # replace with actual ownership logic
