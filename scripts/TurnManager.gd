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
@export var scout_scene: PackedScene

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

@export var structure_positions = [Vector2i(5, 2),
					Vector2i(12, 2),
					Vector2i(8, 7),
					Vector2i(5, 12),
					Vector2i(12, 12),
					Vector2i(-1, 7),
					Vector2i(17, 7)
					]

var base_positions := {
	"player1": Vector2i(-1, 7),
	"player2": Vector2i(17, 7)
}
var special_tiles := {
	"unclaimed": [Vector2i(5, 2),
					Vector2i(12, 2),
					Vector2i(8, 7),
					Vector2i(5, 12),
					Vector2i(12, 12)
					],
	"player1": [],
	"player2": []
}

# --- Orders Data ---
var player_orders     := { "player1": {}, "player2": {} }
var _orders_submitted := { "player1": false, "player2": false }

var local_player_id: String

# --------------------------------------------------------
# Entry point: start the game loop once the scene is ready
# --------------------------------------------------------
func _ready():
	NetworkManager.hex = $GameBoardNode/HexTileMap
	NetworkManager.turn_mgr = $"."
	unit_manager.spawn_unit("base", base_positions["player1"], "player1")
	unit_manager.spawn_unit("base", base_positions["player2"], "player2")

func start_game() -> void:
	call_deferred("_game_loop")

# --------------------------------------------------------
# Main loop: Upkeep → Orders → Execution → increment → loop
# --------------------------------------------------------
func _game_loop() -> void:
	turn_number += 1
	print("\n===== TURN %d =====" % turn_number)
	NetworkManager.broadcast_phase("UPKEEP")
	_do_upkeep()
	NetworkManager.broadcast_phase("ORDERS")
	await _do_orders()
	NetworkManager.broadcast_phase("EXECUTION")
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
	
	# reset orders and unit states
	$UI._clear_all_drawings()
	var all_units = $GameBoardNode.get_all_units()
	for p in ["player1", "player2"]:
		player_orders[p].clear()
		_orders_submitted[p] = false
		for unit in all_units[p]:
			unit.is_defending = false
			unit.just_purchased = false
			if unit.is_healing:
				unit.curr_health += unit.regen
				unit.set_health_bar()
				unit.is_healing = false
	
# --------------------------------------------------------
# Phase 2: Orders — async per-player input
# --------------------------------------------------------
func _do_orders() -> void:
	current_phase = Phase.ORDERS
	# start with player1
	var me = local_player_id
	print("--- Orders Phase for %s ---" % me.capitalize())
	emit_signal("orders_phase_begin", me)

	# wait until both players have submitted
	await NetworkManager.orders_ready
	print("→ Both players submitted orders: %s" % player_orders)

# Called by UIManager to add orders
func add_order(player: String, order: Dictionary) -> void:
	# Order is a dictionary with keys: "unit", "type", and "path"
	if order["type"] == "spawn":
		player_orders[player][order["cell"]] = order
	else:
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

func _process_spawns():
	for player_id in NetworkManager.player_orders.keys():
		for order in NetworkManager.player_orders[player_id].values():
			if order["type"] == "spawn":
				if order.owner_id != local_player_id:
					unit_manager.spawn_unit(order["unit_type"], order["cell"], order["owner_id"])
	for player_id in NetworkManager.player_orders.keys():
		for order in NetworkManager.player_orders[player_id].keys():
			if NetworkManager.player_orders[player_id][order]["type"] == "spawn":
				NetworkManager.player_orders[player_id].erase(order)

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
			target.queue_free()
		else:
			target.set_health_bar()
	$UI._draw_attacks()

func _process_melee():
	var melee_attacks: Dictionary = {} # key: target, value: array[[attacker, priority]]
	var melee_dmg: Dictionary = {} # key: target, vale: damage recieved
	# melee orders resolution
	for player in ["player1", "player2"]:
		for unit in player_orders[player].keys():
			var order = player_orders[player][unit]
			if order["type"] == "melee":
				if is_instance_valid(order["target_unit"]):
					melee_attacks[order["target_unit"]] = melee_attacks.get(order["target_unit"], [])
					melee_attacks[order["target_unit"]].append([order["unit"], order["priority"]])
				player_orders[player].erase(unit)
	for target in melee_attacks.keys():
		var def_penalty = target.multi_def_penalty * (melee_attacks[target].size() -1)
		var def_damaged_penalty = (100 - target.curr_health) * 0.005
		var def_str = (target.melee_strength - def_penalty) * def_damaged_penalty
		melee_attacks[target].sort_custom(func(a,b): return a[1] < b[1])
		for attack in melee_attacks[target]:
			var attacker = attack[0]
			var damaged_penalty = (100 - attacker.curr_health) * 0.005
			var melee_str = attacker.melee_strength * damaged_penalty
			var def_dmg = 30 * exp((melee_str-def_str)/25 * randf_range(0.75,1.25))
			melee_dmg[target] = melee_dmg.get(target, 0) + def_dmg
			if target.is_defending:
				var atk_dmg = 30 * exp((melee_str-def_str)/25 * randf_range(0.75,1.25))
				melee_dmg[attacker] = melee_dmg.get(attacker, 0) + atk_dmg
	
	for target in melee_dmg.keys():
		target.curr_health -= melee_dmg[target]
		# dead unit, remove from all orders and remove node from game
		if target.curr_health <= 0:
			for player in ["player1", "player2"]:
				player_orders[player].erase(target)
			$GameBoardNode/HexTileMap.set_player_tile(target.grid_pos, "")
			$GameBoardNode.vacate(target.grid_pos)
			if target in melee_attacks.keys():
				melee_attacks[target][0][0].set_grid_position(target.grid_pos)
			target.queue_free()
		else:
			target.set_health_bar()
	$UI._draw_attacks()
	$UI._draw_paths()
	$UI._draw_supports()

func _process_move():
	var tiles_entering: Dictionary = {} # key: tile, value: [unit]
	# find all tiles that are being entered into on the next move by both players
	for player in ["player1", "player2"]:
		for unit in player_orders[player].keys():
			var order = player_orders[player][unit]
			if order["type"] == "move":
				var next_tile = order["path"][1]
				tiles_entering[next_tile] = tiles_entering.get(next_tile, [])
				tiles_entering[next_tile].append(unit)
	
	for tile in tiles_entering.keys():
		# if only one unit entering a tile, perform the move
		if tiles_entering[tile].size() == 1:
			var curr_unit = tiles_entering[tile][0]
			# check if there is something there and fight if an enemy
			if $GameBoardNode.is_occupied(tile):
				var obstacle = $GameBoardNode.get_unit_at(tile)
				if obstacle.is_moving:
					if obstacle.player_id == curr_unit.player_id or obstacle.moving_to != curr_unit.grid_pos:
						var dependency_path = $GameBoardNode/Units.find_end(curr_unit, [curr_unit.grid_pos], false, false)
						if dependency_path[0][-1] == curr_unit.grid_pos:
							# circular path
							var units = []
							for spot in dependency_path[0]:
								units.append($GameBoardNode.get_unit_at(spot))
							for i in range(units.size()-1):
								units[i].set_grid_position(dependency_path[0][i+1])
								if player_orders[units[i].player_id][units[i]]["path"].size() <= 2:
									player_orders[units[i].player_id].erase(units[i])
									units[i].is_moving = false
								else:
									player_orders[units[i].player_id][units[i]]["path"].pop_front()
									units[i].moving_to = player_orders[units[i].player_id][units[i]]["path"][1]
							for i in range(units.size()-1):
								units[i].set_grid_position(dependency_path[0][i+1])
							break
				if obstacle.player_id != curr_unit.player_id:
					var atkr_damaged_penalty = (100 - curr_unit.curr_health) * 0.005
					var atkr_melee_str = curr_unit.melee_strength * (1- atkr_damaged_penalty)
					var defr_damaged_penalty = (100 - obstacle.curr_health) * 0.005
					var defr_melee_str = obstacle.melee_strength * (1- defr_damaged_penalty)
					var atkr_dmg = 30 * exp((defr_melee_str - atkr_melee_str)/25 * randf_range(0.75,1.25))
					var defr_dmg = 30 * exp((atkr_melee_str - defr_melee_str)/25 * randf_range(0.75,1.25))
					obstacle.curr_health -= defr_dmg
					obstacle.set_health_bar()
					if obstacle.is_defending:
						curr_unit.curr_health -= atkr_dmg
						curr_unit.set_health_bar()
					if obstacle.moving_to == curr_unit.grid_pos:
						curr_unit.curr_health -= atkr_dmg
						curr_unit.set_health_bar()
						player_orders[obstacle.player_id].erase(obstacle)
					if obstacle.curr_health <= 0:
						player_orders[obstacle.player_id].erase(obstacle)
						$GameBoardNode/HexTileMap.set_player_tile(obstacle.grid_pos, "")
						$GameBoardNode.vacate(obstacle.grid_pos)
						obstacle.queue_free()
						if curr_unit.curr_health > 0:
							curr_unit.set_grid_position(tile)
					player_orders[curr_unit.player_id].erase(curr_unit)
					if curr_unit.curr_health <= 0:
						player_orders[curr_unit.player_id].erase(curr_unit)
						$GameBoardNode/HexTileMap.set_player_tile(curr_unit.grid_pos, "")
						$GameBoardNode.vacate(curr_unit.grid_pos)
						if obstacle.moving_to == curr_unit.grid_pos:
							obstacle.set_grid_position(curr_unit.grid_pos)
							player_orders[obstacle.player_id].erase(obstacle)
						curr_unit.queue_free()
					break
				else:
					player_orders[curr_unit.player_id].erase(curr_unit)
			else:
				curr_unit.set_grid_position(tile)
				if player_orders[curr_unit.player_id][curr_unit]["path"].size() <= 2:
					player_orders[curr_unit.player_id].erase(curr_unit)
				else:
					player_orders[curr_unit.player_id][curr_unit]["path"].pop_front()
			
		
		# conflict handling
		else:
			var p1_units = []
			var p2_units = []
			for unit in tiles_entering[tile]:
				if unit.player_id == "player1":
					p1_units.append([unit,player_orders["player1"][unit]["priority"]])
				else:
					p2_units.append([unit,player_orders["player2"][unit]["priority"]])
			p1_units.sort_custom(func(a,b): return a[1] < b[1])
			p2_units.sort_custom(func(a,b): return a[1] < b[1])
			
			while p1_units.size() > 0 or p2_units.size() > 0:
				
				# all of one players entering units have acted or died
				if p1_units.size() == 0:
					p2_units[0][0].set_grid_position(tile)
					for unit in p2_units:
						player_orders["player2"].erase(unit[0])
					break
				if p2_units.size() == 0:
					p1_units[0][0].set_grid_position(tile)
					for unit in p1_units:
						player_orders["player1"].erase(unit[0])
					break
				var first_p1 = p1_units[0][0]
				var first_p2 = p2_units[0][0]
				# first priority units of each player fight each other
				var p1_damaged_penalty = (100 - first_p1.curr_health) * 0.005
				var p1_melee_str = first_p1.melee_strength * (1 - p1_damaged_penalty)
				var p2_damaged_penalty = (100 - first_p2.curr_health) * 0.005
				var p2_melee_str = first_p2.melee_strength * (1- p2_damaged_penalty)
				var p1_dmg = 30 * exp((p2_melee_str - first_p1.melee_strength)/25 * randf_range(0.75,1.25))
				var p2_dmg = 30 * exp((p1_melee_str - first_p2.melee_strength)/25 * randf_range(0.75,1.25))
				first_p1.curr_health -= p1_dmg
				first_p1.set_health_bar()
				first_p2.curr_health -= p2_dmg
				first_p2.set_health_bar()
				
				# dead unit handling
				# both dead
				if first_p1.curr_health <= 0 and first_p2.curr_health <=0:
					player_orders["player1"].erase(first_p1)
					player_orders["player2"].erase(first_p2)
					$GameBoardNode/HexTileMap.set_player_tile(first_p1.grid_pos, "")
					$GameBoardNode/HexTileMap.set_player_tile(first_p2.grid_pos, "")
					$GameBoardNode.vacate(first_p1.grid_pos)
					$GameBoardNode.vacate(first_p2.grid_pos)
					first_p1.queue_free()
					first_p2.queue_free()
					p1_units.pop_front()
					p2_units.pop_front()
				# just one dead
				elif first_p1.curr_health <= 0 or first_p2.curr_health <= 0:
					# p1 unit dead
					if first_p1.curr_health <= 0:
						player_orders["player1"].erase(first_p1)
						$GameBoardNode/HexTileMap.set_player_tile(first_p1.grid_pos, "")
						$GameBoardNode.vacate(first_p1.grid_pos)
						first_p1.queue_free()
						p1_units.pop_front()
						if p1_units.size() == 0:
							first_p2.set_grid_position(tile)
							for unit in p2_units:
								player_orders["player2"].erase(unit[0])
							break
						else:
							player_orders["player2"].erase(first_p2)
							p2_units.pop_front()
							
					#p2 unit dead
					else:
						player_orders["player2"].erase(first_p2)
						$GameBoardNode/HexTileMap.set_player_tile(first_p2.grid_pos, "")
						$GameBoardNode.vacate(first_p2.grid_pos)
						first_p2.queue_free()
						p2_units.pop_front()
						if p2_units.size() == 0:
							first_p1.set_grid_position(tile)
							for unit in p1_units:
								player_orders["player1"].erase(unit[0])
							break
						else:
							player_orders["player1"].erase(first_p1)
							p1_units.pop_front()
				
				# both still alive
				else:
					player_orders["player1"].erase(first_p1)
					p1_units.pop_front()
					player_orders["player2"].erase(first_p2)
					p2_units.pop_front()
	
	# check if there are more moves and requeue _process_moves
	for player in ["player1", "player2"]:
		for unit in player_orders[player].keys():
			var order = player_orders[player][unit]
			if order["type"] == "move":
				exec_steps.append(func(): _process_move())
				$UI._draw_paths()
				return
	$UI._draw_paths()

func _initialize_execution():
	$UI._draw_attacks()
	$UI._draw_heals()
	$UI._draw_defends()

# --------------------------------------------------------
# Phase 3: Execution — process orders
# --------------------------------------------------------
func _do_execution() -> void:
	current_phase = Phase.EXECUTION
	print("Executing orders...")
	exec_steps = [
		func(): _initialize_execution(),
		func(): _process_spawns(),
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

func start_phase_locally(phase_name: String) -> void:
	print("[TurnManager] start_phase_locally:", phase_name)
	match phase_name:
		"UPKEEP":
			_do_upkeep()
		"ORDERS":
			# kick off the orders coroutine on the client
			_do_orders()
		"EXECUTION":
			_do_execution()

# --------------------------------------------------------
# API: attempt to buy and spawn a unit
# --------------------------------------------------------
func buy_unit(player: String, unit_type: String, grid_pos: Vector2i) -> bool:
	var scene: PackedScene = null
	if unit_type.to_lower() == "archer":
		scene = archer_scene
	elif unit_type.to_lower() == "soldier":
		scene = soldier_scene
	elif unit_type.to_lower() == "scout":
		scene = scout_scene
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
	add_order(player, {
		"type": "spawn",
		"unit_type": unit_type,
		"cell": grid_pos,
		"owner_id": local_player_id
	})
	print("%s bought a %s at %s for %d gold" % [player, unit_type, grid_pos, cost])
	return true

# --------------------------------------------------------
# Stub: determine if a player controls a given tile
# --------------------------------------------------------
func _controls_tile(player: String, pos: Vector2i) -> bool:
	return true  # replace with actual ownership logic
