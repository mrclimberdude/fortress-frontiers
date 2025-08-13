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
@onready var dmg_report = $UI/DamagePanel/ScrollContainer/VBoxContainer

@export var archer_scene:  PackedScene
@export var soldier_scene: PackedScene
@export var scout_scene: PackedScene
@export var miner_scene: PackedScene
@export var phalanx_scene: PackedScene
@export var cavalry_scene: PackedScene

# --- Turn & Phase State ---
var turn_number:   int    = 0
var current_phase: Phase  = Phase.UPKEEP
var current_player:String = "player1"
var exec_steps: Array     = []
var step_index: int       = 0

# --- Economy State ---
var player_gold       := { "player1": 25, "player2": 25 }
var player_income    := { "player1": 0, "player2": 0 }
const BASE_INCOME    : int = 10
const TOWER_INCOME   : int = 5
const SPECIAL_INCOME : int = 10
const MINER_BONUS    : int = 15
const PHALANX_BONUS     : int = 20

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

var tower_positions := {
	"player1": [Vector2i(1,4),
				Vector2i(2,7),
				Vector2i(1,10)],
	"player2": [Vector2i(16,4),
				Vector2i(14,7),
				Vector2i(16,10)]
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
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --------------------------------------------------------
# Entry point: start the game loop once the scene is ready
# --------------------------------------------------------
func _ready():
	NetworkManager.hex = $GameBoardNode/HexTileMap
	NetworkManager.turn_mgr = $"."
	unit_manager.spawn_unit("base", base_positions["player1"], "player1", false)
	unit_manager.spawn_unit("base", base_positions["player2"], "player2", false)
	for player in tower_positions.keys():
		for tile in tower_positions[player]:
			structure_positions.append(tile)
			unit_manager.spawn_unit("tower", tile, player, false)
	$GameBoardNode/FogOfWar._update_fog()

func start_game() -> void:
	call_deferred("_game_loop")

func end_game():
	print("the game has ended")

# --------------------------------------------------------
# Main loop: Upkeep → Orders → Execution → increment → loop
# --------------------------------------------------------
func _game_loop() -> void:
	turn_number += 1
	print("\n===== TURN %d =====" % turn_number)
	rng.seed = turn_number
	NetworkManager._orders_submitted = { "player1": false, "player2": false }
	player_orders = NetworkManager.player_orders
	NetworkManager.broadcast_phase("UPKEEP")
	start_phase_locally("UPKEEP")
	NetworkManager.broadcast_phase("ORDERS")
	await _do_orders()
	player_orders = NetworkManager.player_orders
	NetworkManager.broadcast_phase("EXECUTION")
	_do_execution()

# --------------------------------------------------------
# Phase 1: Upkeep — award gold
# --------------------------------------------------------
func _do_upkeep() -> void:
	$UI/CancelGameButton.visible = false
	current_phase = Phase.UPKEEP
	NetworkManager._step_ready_counts = {}
	print("--- Upkeep Phase ---")
	for player in ["player1", "player2"]:
		var income = 0
		if _controls_tile(player, base_positions[player]):
			income += BASE_INCOME
		for tower in tower_positions[player]:
			income += TOWER_INCOME
		for pos in special_tiles[player]:
			if _controls_tile(player, pos):
				if $GameBoardNode.is_occupied(pos):
					if $GameBoardNode.get_unit_at(pos).is_miner:
						income += MINER_BONUS
				income += SPECIAL_INCOME
		player_gold[player] += income
		player_income[player] = income
		print("%s income: %d  → total gold: %d" % [player.capitalize(), income, player_gold[player]])
	
	# reset orders and unit states
	$UI._clear_all_drawings()
	$GameBoardNode/FogOfWar._update_fog()
	var all_units = $GameBoardNode.get_all_units()
	for p in ["player1", "player2"]:
		player_orders[p].clear()
		_orders_submitted[p] = false
		for unit in all_units[p]:
			unit.is_defending = false
			unit.just_purchased = false
			unit.ordered = false
			unit.is_moving = false
			if unit.is_healing:
				unit.curr_health += unit.regen
				unit.set_health_bar()
				unit.is_healing = false
	$GameBoardNode/FogOfWar._update_fog()
	$UI/DamagePanel.visible = true
	$GameBoardNode/OrderReminderMap.highlight_unordered_units(local_player_id)
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
	player_orders[player][order["unit_net_id"]] = order

func get_order(player:String, unit_net_id:int) -> Dictionary:
	return player_orders[player].get(unit_net_id,{})

func get_all_orders(player_id: String) -> Array:
	if player_orders.has(player_id):
		var all_orders = player_orders[player_id].values()
		var spawn_orders = []
		var non_spawn_orders = []
		for order in all_orders:
			if order["type"] == "spawn":
				spawn_orders.append(order)
			else:
				non_spawn_orders.append(order)
		non_spawn_orders.sort_custom(func(order1, order2): order1["unit_net_id"] < order2["unit_net_id"])
		for order in spawn_orders:
			non_spawn_orders.append(order)
		return non_spawn_orders
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

func calculate_damage(attacker, defender, atk_mode, num_atkrs):
	# NOTE: Whenever this function is updated, also update all manually calculated damage sections
	# search: MANUAL_DMG
	var atkr_damaged_penalty = 1- ((100 - attacker.curr_health) * 0.005)
	var atkr_str
	if atk_mode == "ranged":
		atkr_str = attacker.ranged_strength * atkr_damaged_penalty
	else:
		atkr_str = attacker.melee_strength * atkr_damaged_penalty
	var defr_damaged_penalty = 1- ((100 - defender.curr_health) * 0.005)
	var defr_str = defender.melee_strength - ((num_atkrs -1) * defender.multi_def_penalty)
	if defender.is_defending and defender.is_phalanx:
		defr_str += PHALANX_BONUS + (num_atkrs -1) * defender.multi_def_penalty
	defr_str = defr_str * defr_damaged_penalty
	var atkr_in_dmg
	if defender.is_ranged and atk_mode == "ranged":
		var defr_ranged_str = (defender.ranged_strength - ((num_atkrs -1) * defender.multi_def_penalty)) * defr_damaged_penalty
		atkr_in_dmg = 30 * (1.041**(defr_ranged_str - attacker.melee_strength * atkr_damaged_penalty))
	else:
		atkr_in_dmg = 30 * (1.041**(defr_str - attacker.melee_strength * atkr_damaged_penalty))
	var defr_in_dmg = 30 * (1.041**(atkr_str - defr_str))
	return [atkr_in_dmg, defr_in_dmg]

func dealt_dmg_report(atkr, defr, atkr_in_dmg, defr_in_dmg, retaliate, atk_mode):
	var report_label = Label.new()
	if defr.player_id == local_player_id:
		report_label.text = "Your %s #%d took %d %s damage from %s #%d" % [defr.unit_type, defr.net_id, defr_in_dmg, atk_mode, atkr.unit_type, atkr.net_id]
		dmg_report.add_child(report_label)
		if retaliate:
			report_label = Label.new()
			report_label.text = "Your %s #%d retaliated and dealt %d damage" % [defr.unit_type, defr.net_id, atkr_in_dmg]
			dmg_report.add_child(report_label)
	else:
		report_label.text = "Your %s #%d dealt %d %s damage to %s #%d" % [atkr.unit_type, atkr.net_id, defr_in_dmg, atk_mode, defr.unit_type, defr.net_id]
		dmg_report.add_child(report_label)
		if retaliate:
			report_label = Label.new()
			report_label.text = "Enemy %s #%d retaliated and dealt %d damage" % [defr.unit_type, defr.net_id, atkr_in_dmg]
			dmg_report.add_child(report_label)

func died_dmg_report(unit):
	var report_label = Label.new()
	if unit.player_id == local_player_id:
		report_label.text = "Your %s #%d died at %s" % [unit.unit_type, unit.net_id, unit.grid_pos]
		dmg_report.add_child(report_label)
	else:
		report_label.text = "Enemy %s #%d died at %s" % [unit.unit_type, unit.net_id, unit.grid_pos]
		dmg_report.add_child(report_label)

func _process_spawns():
	var spawn_orders = []
	for player_id in NetworkManager.player_orders.keys():
		for order in NetworkManager.player_orders[player_id].values():
			if order["type"] == "spawn":
				spawn_orders.append(order)
	spawn_orders.sort_custom(func(order1, order2): order1["unit_net_id"] < order2["unit_net_id"])
	for order in spawn_orders:
		if order["owner_id"] != local_player_id:
			unit_manager.spawn_unit(order["unit_type"], order["cell"], order["owner_id"], order["undo"])
	for player_id in NetworkManager.player_orders.keys():
		for order in NetworkManager.player_orders[player_id].keys():
			if NetworkManager.player_orders[player_id][order]["type"] == "spawn":
				NetworkManager.player_orders[player_id].erase(order)
	
	for player in ["player1", "player2"]:
		var unit_ids = player_orders[player].keys()
		unit_ids.sort()
		for unit_net_id in unit_ids:
			if unit_net_id is not int:
				continue
			var order = player_orders[player][unit_net_id]
			if order["type"] == "defend":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				unit.is_defending = true
			if order["type"] == "heal":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				unit.is_healing = true
	
	for player in ["player1", "player2"]:
		for unit_net_id in player_orders[player].keys():
			if player_orders[player][unit_net_id]["type"] == "move":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				unit.is_moving = true
				unit.moving_to = player_orders[player][unit_net_id]["path"][1]
	$UI._draw_all()
	$GameBoardNode/FogOfWar._update_fog()

func _process_attacks():
	var ranged_attacks: Dictionary = {} # key: target.net_id, value: [attacker.net_id]
	var ranged_dmg: Dictionary = {} # key: target.net_id, value: damage recieved
	var melee_attacks: Dictionary = {} # key: target.net_id, value: array[[attacker.net_id, priority]]
	var melee_dmg: Dictionary = {} # key: target, value: damage recieved
	
	# get all attacks
	for player in ["player1", "player2"]:
		var unit_ids = player_orders[player].keys()
		unit_ids.sort()
		for unit_net_id in unit_ids:
			if unit_net_id is not int:
				continue
			var order = player_orders[player][unit_net_id]
			if order["type"] == "ranged":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				var target = unit_manager.get_unit_by_net_id(order["target_unit_net_id"])
				# check to make sure target unit still exists
				if is_instance_valid(target):
					ranged_attacks[target.net_id] = ranged_attacks.get(target.net_id, [])
					ranged_attacks[target.net_id].append(unit.net_id)
				player_orders[player].erase(unit.net_id)
			elif order["type"] == "melee":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				var target = unit_manager.get_unit_by_net_id(order["target_unit_net_id"])
				if is_instance_valid(target):
					melee_attacks[order["target_unit_net_id"]] = melee_attacks.get(order["target_unit_net_id"], [])
					melee_attacks[order["target_unit_net_id"]].append([unit.net_id, order["priority"]])
				player_orders[player].erase(unit.net_id)
	
	# calculate all ranged attack damages done
	var target_ids = ranged_attacks.keys()
	target_ids.sort()
	for target_net_id in target_ids:
		var num_attackers = ranged_attacks.get(target_net_id, []).size() + melee_attacks.get(target_net_id, []).size()
		for unit_net_id in ranged_attacks[target_net_id]:
			var unit = unit_manager.get_unit_by_net_id(unit_net_id)
			var target = unit_manager.get_unit_by_net_id(target_net_id)
			var dmg_result = calculate_damage(unit, target, "ranged", num_attackers)
			var atkr_in_dmg = dmg_result[0]
			var defr_in_dmg = dmg_result[1]
			if target.is_defending and target.is_ranged:
				ranged_dmg[unit_net_id] = ranged_dmg.get(unit_net_id, 0) + atkr_in_dmg
			ranged_dmg[target_net_id] = ranged_dmg.get(target_net_id, 0) + defr_in_dmg
			var report_label = Label.new()
			if target.player_id == local_player_id:
				report_label.text = "Your %s #%d took %d ranged damage from %s #%d" % [target.unit_type, target.net_id, defr_in_dmg, unit.unit_type, unit.net_id]
				dmg_report.add_child(report_label)
				if target.is_defending and target.is_ranged:
					report_label = Label.new()
					report_label.text = "Your %s #%d retaliated and dealt %d damage" % [target.unit_type, target.net_id, atkr_in_dmg]
					dmg_report.add_child(report_label)
			else:
				report_label.text = "Your %s #%d dealt %d ranged damage to %s #%d" % [unit.unit_type, unit.net_id, defr_in_dmg, target.unit_type, target.net_id]
				dmg_report.add_child(report_label)
				if target.is_defending and target.is_ranged:
					report_label = Label.new()
					report_label.text = "Enemy %s #%d retaliated and dealt %d damage" % [target.unit_type, target.net_id, atkr_in_dmg]
					dmg_report.add_child(report_label)
	
	# calculate all melee attack damages done
	target_ids = melee_attacks.keys()
	target_ids.sort()
	for target_unit_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_unit_net_id)
		var num_attackers = ranged_attacks.get(target_unit_net_id, []).size() + melee_attacks.get(target_unit_net_id, []).size()
		melee_attacks[target.net_id].sort_custom(func(a,b): return a[1] < b[1])
		for attack in melee_attacks[target.net_id]:
			var attacker = unit_manager.get_unit_by_net_id(attack[0])
			var dmg_result = calculate_damage(attacker, target, "melee", num_attackers)
			var atkr_in_dmg = dmg_result[0]
			var defr_in_dmg = dmg_result[1]
			if target.is_defending:
				melee_dmg[attacker.net_id] = melee_dmg.get(attacker.net_id, 0) + atkr_in_dmg
			melee_dmg[target.net_id] = melee_dmg.get(target.net_id, 0) + defr_in_dmg
			if target.player_id == local_player_id:
				var report_label = Label.new()
				report_label.text = "Your %s #%d took %d melee damage from %s #%d" % [target.unit_type, target.net_id, defr_in_dmg, attacker.unit_type, attacker.net_id]
				dmg_report.add_child(report_label)
				if target.is_defending:
					report_label = Label.new()
					report_label.text = "Your %s #%d retaliated and dealt %d damage" % [target.unit_type, target.net_id, atkr_in_dmg]
					dmg_report.add_child(report_label)
			else:
				var report_label = Label.new()
				report_label.text = "Your %s #%d dealt %d melee damage to %s #%d" % [attacker.unit_type, attacker.net_id, defr_in_dmg, target.unit_type, target.net_id]
				dmg_report.add_child(report_label)
				if target.is_defending:
					report_label = Label.new()
					report_label.text = "Enemy %s #%d retaliated and dealt %d damage" % [target.unit_type, target.net_id, atkr_in_dmg]
					dmg_report.add_child(report_label)
	
	# deal ranged damage
	target_ids = ranged_dmg.keys()
	target_ids.sort()
	for target_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_net_id)
		target.curr_health -= ranged_dmg[target_net_id]
		# dead unit, remove from all orders and remove node from game
		if target.curr_health <= 0:
			for player in ["player1", "player2"]:
				player_orders[player].erase(target_net_id)
				var report_label = Label.new()
				if target.player_id == local_player_id:
					report_label.text = "Your %s #%d died at %s" % [target.unit_type, target.net_id, target.grid_pos]
					dmg_report.add_child(report_label)
				else:
					report_label.text = "Enemy %s #%d died at %s" % [target.unit_type, target.net_id, target.grid_pos]
					dmg_report.add_child(report_label)
			$GameBoardNode.vacate(target.grid_pos)
			$GameBoardNode/HexTileMap.set_player_tile(target.grid_pos, "")
			
			target.queue_free()
		else:
			target.set_health_bar()
	
	# deal melee damage
	target_ids = melee_dmg.keys()
	target_ids.sort()
	for target_unit_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_unit_net_id)
		target.curr_health -= melee_dmg[target.net_id]
	for target_unit_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_unit_net_id)
		# dead unit, remove from all orders and remove node from game
		if target.curr_health <= 0:
			for player in ["player1", "player2"]:
				player_orders[player].erase(target.net_id)
			if target.player_id == local_player_id:
				var report_label = Label.new()
				report_label.text = "Your %s #%d died at %s" % [target.unit_type, target.net_id, target.grid_pos]
				dmg_report.add_child(report_label)
			else:
				var report_label = Label.new()
				report_label.text = "Enemy %s #%d died at %s" % [target.unit_type, target.net_id, target.grid_pos]
				dmg_report.add_child(report_label)
			$GameBoardNode.vacate(target.grid_pos)
			$GameBoardNode/HexTileMap.set_player_tile(target.grid_pos, "")
			
			if target_unit_net_id in melee_attacks.keys():
				melee_attacks[target.net_id].sort_custom(func(a,b): return a[1] < b[1])
				for unit_priority_pair in melee_attacks[target.net_id]:
					var unit = unit_manager.get_unit_by_net_id(unit_priority_pair[0])
					if unit.curr_health > 0:
						unit.set_grid_position(target.grid_pos)
						break
				pass
			target.queue_free()
		else:
			target.set_health_bar()
	$UI._draw_attacks()
	$UI._draw_paths()
	$UI._draw_supports()
	$GameBoardNode/FogOfWar._update_fog()

func _process_move():
	var tiles_entering: Dictionary = {} # key: tile, value: [unit]
	# find all tiles that are being entered into on the next move by both players
	for player in ["player1", "player2"]:
		var unit_ids = player_orders[player].keys()
		unit_ids.sort()
		for unit_net_id in unit_ids:
			if unit_net_id is not int:
				continue
			var unit = unit_manager.get_unit_by_net_id(unit_net_id)
			var order = player_orders[player][unit_net_id]
			if order["type"] == "move":
				var next_tile = order["path"][1]
				tiles_entering[next_tile] = tiles_entering.get(next_tile, [])
				tiles_entering[next_tile].append(unit_net_id)
	var sorted_tiles = tiles_entering.keys()
	sorted_tiles.sort()
	for tile in sorted_tiles:
		# if only one unit entering a tile, perform the move
		if tiles_entering[tile].size() == 1:
			var curr_unit = unit_manager.get_unit_by_net_id(tiles_entering[tile][0])
			# check if there is something there and fight if an enemy
			if $GameBoardNode.is_occupied(tile):
				var obstacle = $GameBoardNode.get_unit_at(tile)
				if obstacle.is_moving:
					if obstacle.player_id == curr_unit.player_id or obstacle.moving_to != curr_unit.grid_pos:
						var dependency_path = $GameBoardNode/Units.find_end(curr_unit, [curr_unit.grid_pos], false, false)
						var dupe_tile = null
						for spot in dependency_path[0]:
							if dependency_path[0].count(spot) > 1:
								dupe_tile = spot
								break
						if dupe_tile:
							var dupe_index = dependency_path[0].find(dupe_tile)
							var circle = dependency_path[0].slice(dupe_index)
							var units = []
							for spot in circle:
								var unit = $GameBoardNode.get_unit_at(spot)
								units.append(unit)
							var first_unit = units[-1]
							first_unit.set_grid_position(Vector2i(-100, -100))
							for i in range(units.size() -2, -1, -1):
								units[i].set_grid_position(circle[i+1])
								if player_orders[units[i].player_id][units[i].net_id]["path"].size() <= 2:
									player_orders[units[i].player_id].erase(units[i].net_id)
									units[i].is_moving = false
								else:
									player_orders[units[i].player_id][units[i].net_id]["path"].pop_front()
									units[i].moving_to = player_orders[units[i].player_id][units[i].net_id]["path"][1]
							break
						var units = []
						for spot in dependency_path[0]:
							var unit = $GameBoardNode.get_unit_at(spot)
							if unit:
								if unit in units:
									break
								if unit.is_moving:
									units.append(unit)
						for i in range(units.size()-1, -1, -1):
							var entering_unit = units[i]
							var new_tile = dependency_path[0][i+1]
							var unit_at_tile = $GameBoardNode.get_unit_at(new_tile)
							if unit_at_tile:
								if unit_at_tile.player_id == entering_unit.player_id:
									if unit_at_tile.is_moving:
										if unit_at_tile.moving_to !=entering_unit.grid_pos:
											continue
										unit_at_tile.set_grid_position(Vector2i(-100, -100))
										var old_tile = entering_unit.grid_pos
										entering_unit.set_grid_position(new_tile)
										unit_at_tile.set_grid_position(old_tile)
										if player_orders[entering_unit.player_id][entering_unit.net_id]["path"].size() <= 2:
											player_orders[entering_unit.player_id].erase(entering_unit.net_id)
											entering_unit.is_moving = false
										else:
											player_orders[entering_unit.player_id][entering_unit.net_id]["path"].pop_front()
											entering_unit.moving_to = player_orders[entering_unit.player_id][entering_unit.net_id]["path"][1]
										if player_orders[unit_at_tile.player_id][unit_at_tile.net_id]["path"].size() <= 2:
											player_orders[unit_at_tile.player_id].erase(unit_at_tile.net_id)
											unit_at_tile.is_moving = false
										else:
											player_orders[unit_at_tile.player_id][unit_at_tile.net_id]["path"].pop_front()
											unit_at_tile.moving_to = player_orders[unit_at_tile.player_id][unit_at_tile.net_id]["path"][1]
										continue
									player_orders[entering_unit.player_id].erase(entering_unit.net_id)
									entering_unit.is_moving = false
								else:
									if unit_at_tile.is_moving and unit_at_tile.moving_to != entering_unit.grid_pos:
										continue
									var dmg_result = calculate_damage(entering_unit, unit_at_tile, "move", 1)
									var atkr_in_dmg = dmg_result[0]
									var defr_in_dmg = dmg_result[1]
									unit_at_tile.curr_health -= defr_in_dmg
									unit_at_tile.set_health_bar()
									if unit_at_tile.is_defending:
										entering_unit.curr_health -= atkr_in_dmg
										entering_unit.set_health_bar()
										dealt_dmg_report(entering_unit, unit_at_tile, atkr_in_dmg, defr_in_dmg, true, "melee")
										if entering_unit.curr_health <= 0:
											died_dmg_report(entering_unit)
											player_orders[entering_unit.player_id].erase(entering_unit.net_id)
											$GameBoardNode.vacate(entering_unit.grid_pos)
											$GameBoardNode/HexTileMap.set_player_tile(entering_unit.grid_pos, "")
											entering_unit.queue_free()
									
									elif unit_at_tile.is_moving and unit_at_tile.moving_to == entering_unit.grid_pos:
										entering_unit.curr_health -= atkr_in_dmg
										entering_unit.set_health_bar()
										dealt_dmg_report(entering_unit, unit_at_tile, atkr_in_dmg, defr_in_dmg, true, "melee")
										if entering_unit.curr_health <= 0:
											died_dmg_report(entering_unit)
											player_orders[entering_unit.player_id].erase(entering_unit.net_id)
											$GameBoardNode.vacate(entering_unit.grid_pos)
											$GameBoardNode/HexTileMap.set_player_tile(entering_unit.grid_pos, "")
											if unit_at_tile.curr_health > 0:
												unit_at_tile.set_grid_position(entering_unit.grid_pos)
											unit_at_tile.is_moving = false
											player_orders[unit_at_tile.player_id].erase(unit_at_tile.net_id)
											entering_unit.queue_free()
									else:
										dealt_dmg_report(entering_unit, unit_at_tile, atkr_in_dmg, defr_in_dmg, false, "melee")
									
									if unit_at_tile.curr_health <= 0:
										died_dmg_report(unit_at_tile)
										player_orders[unit_at_tile.player_id].erase(unit_at_tile.net_id)
										$GameBoardNode.vacate(unit_at_tile.grid_pos)
										$GameBoardNode/HexTileMap.set_player_tile(unit_at_tile.grid_pos, "")
										if entering_unit.curr_health > 0:
											entering_unit.set_grid_position(new_tile)
										entering_unit.is_moving = false
										player_orders[entering_unit.player_id].erase(entering_unit.net_id)
										unit_at_tile.queue_free()
									
									player_orders[entering_unit.player_id].erase(entering_unit.net_id)
									entering_unit.is_moving = false
								continue
							
							# no unit in next_tile
							units[i].set_grid_position(dependency_path[0][i+1])
							if player_orders[units[i].player_id][units[i].net_id]["path"].size() <= 2:
								player_orders[units[i].player_id].erase(units[i].net_id)
								units[i].is_moving = false
							else:
								player_orders[units[i].player_id][units[i].net_id]["path"].pop_front()
								units[i].moving_to = player_orders[units[i].player_id][units[i].net_id]["path"][1]
						break
				if obstacle.player_id != curr_unit.player_id:
					var dmg_result = calculate_damage(curr_unit, obstacle, "move", 1)
					var atkr_in_dmg = dmg_result[0]
					var defr_in_dmg = dmg_result[1]
					obstacle.curr_health -= defr_in_dmg
					obstacle.set_health_bar()
					if obstacle.is_defending:
						curr_unit.curr_health -= atkr_in_dmg
						curr_unit.set_health_bar()
						dealt_dmg_report(curr_unit, obstacle, atkr_in_dmg, defr_in_dmg, true, "melee")
					if obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving and obstacle.curr_health > 0:
						curr_unit.curr_health -= atkr_in_dmg
						curr_unit.set_health_bar()
						player_orders[obstacle.player_id].erase(obstacle.net_id)
						obstacle.is_moving = false
						dealt_dmg_report(curr_unit, obstacle, atkr_in_dmg, defr_in_dmg, true, "melee")
					
					
					
					if obstacle.player_id == local_player_id:
						var report_label = Label.new()
						report_label.text = "Your %s #%d took %d melee damage from %s #%d" % [obstacle.unit_type, obstacle.net_id, defr_in_dmg, curr_unit.unit_type, curr_unit.net_id]
						dmg_report.add_child(report_label)
						if obstacle.is_defending or (obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving):
							report_label = Label.new()
							report_label.text = "Your %s #%d retaliated and dealt %d damage" % [obstacle.unit_type, obstacle.net_id, atkr_in_dmg]
							dmg_report.add_child(report_label)
					else:
						var report_label = Label.new()
						report_label.text = "Your %s #%d dealt %d melee damage to %s #%d" % [curr_unit.unit_type, curr_unit.net_id, defr_in_dmg, obstacle.unit_type, obstacle.net_id]
						dmg_report.add_child(report_label)
						if obstacle.is_defending or (obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving):
							report_label = Label.new()
							report_label.text = "Enemy %s #%d retaliated and dealt %d damage" % [obstacle.unit_type, obstacle.net_id, atkr_in_dmg]
							dmg_report.add_child(report_label)
					if obstacle.curr_health <= 0:
						player_orders[obstacle.player_id].erase(obstacle.net_id)
						$GameBoardNode.vacate(obstacle.grid_pos)
						$GameBoardNode/HexTileMap.set_player_tile(obstacle.grid_pos, "")
						if obstacle.player_id == local_player_id:
							var report_label = Label.new()
							report_label.text = "Your %s #%d died at %s" % [obstacle.unit_type, obstacle.net_id, obstacle.grid_pos]
							dmg_report.add_child(report_label)
						else:
							var report_label = Label.new()
							report_label.text = "Your %s #%d died at %s" % [obstacle.unit_type, obstacle.net_id, obstacle.grid_pos]
							dmg_report.add_child(report_label)
						obstacle.queue_free()
						if curr_unit.curr_health > 0 and curr_unit.is_moving:
							curr_unit.set_grid_position(tile)
							#$GameBoardNode/HexTileMap.set_player_tile(tile, curr_unit.player_id)
					player_orders[curr_unit.player_id].erase(curr_unit.net_id)
					curr_unit.is_moving = false
					if curr_unit.curr_health <= 0:
						$GameBoardNode.vacate(curr_unit.grid_pos)
						$GameBoardNode/HexTileMap.set_player_tile(curr_unit.grid_pos, "")
						
						if obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving and obstacle.curr_health > 0:
							obstacle.set_grid_position(curr_unit.grid_pos)
							player_orders[obstacle.player_id].erase(obstacle.net_id)
							obstacle.is_moving = false
						curr_unit.queue_free()
					break
				else:
					player_orders[curr_unit.player_id].erase(curr_unit.net_id)
					curr_unit.is_moving = false
			else:
				curr_unit.set_grid_position(tile)
				if player_orders[curr_unit.player_id][curr_unit.net_id]["path"].size() <= 2:
					player_orders[curr_unit.player_id].erase(curr_unit.net_id)
					curr_unit.is_moving = false
				else:
					player_orders[curr_unit.player_id][curr_unit.net_id]["path"].pop_front()
					curr_unit.moving_to = player_orders[curr_unit.player_id][curr_unit.net_id]["path"][1]
			
		
		# conflict handling
		else:
			var p1_units = []
			var p2_units = []
			var _is_p1_occupied = false
			var _is_p2_occupied = false
			if $GameBoardNode.is_occupied(tile):
				var obstacle = $GameBoardNode.get_unit_at(tile)
				if obstacle.player_id == "player1":
					_is_p1_occupied = true
					p1_units.append([obstacle, -1])
				else:
					_is_p2_occupied = true
					p2_units.append([obstacle, -1])
			for unit_net_id in tiles_entering[tile]:
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				if unit.player_id == "player1":
					p1_units.append([unit,player_orders["player1"][unit.net_id]["priority"]])
				else:
					p2_units.append([unit,player_orders["player2"][unit.net_id]["priority"]])
			p1_units.sort_custom(func(a,b): return a[1] < b[1])
			p2_units.sort_custom(func(a,b): return a[1] < b[1])
			
			while p1_units.size() > 0 or p2_units.size() > 0:
				
				# all of one players entering units have acted or died
				if p1_units.size() == 0:
					if not _is_p2_occupied:
						p2_units[0][0].set_grid_position(tile)
					for unit in p2_units:
						player_orders["player2"].erase(unit[0].net_id)
						unit[0].is_moving = false
					break
				if p2_units.size() == 0:
					if not _is_p1_occupied:
						p1_units[0][0].set_grid_position(tile)
					for unit in p1_units:
						player_orders["player1"].erase(unit[0].net_id)
						unit[0].is_moving = false
					break
				var first_p1 = p1_units[0][0]
				var first_p2 = p2_units[0][0]
				# first priority units of each player fight each other
				# NOTE: UPDATE THIS SECTION WHENEVER DAMAGE CALCULATION IS UPDATED
				# search for MANUAL_DMG
				var p1_damaged_penalty
				var p1_melee_str = first_p1.melee_strength
				if (_is_p1_occupied and first_p1.is_defending) or not _is_p1_occupied:
					if first_p1.is_defending and first_p1.is_phalanx:
						p1_melee_str += PHALANX_BONUS
					p1_damaged_penalty = 1 - ((100 - first_p1.curr_health) * 0.005)
					p1_melee_str = p1_melee_str * p1_damaged_penalty
				var p2_damaged_penalty
				var p2_melee_str = first_p2.melee_strength
				if (_is_p2_occupied and first_p2.is_defending) or not _is_p2_occupied:
					if first_p2.is_defending and first_p2.is_phalanx:
						p2_melee_str += PHALANX_BONUS
					p2_damaged_penalty = 1 - ((100 - first_p2.curr_health) * 0.005)
					p2_melee_str = p2_melee_str * p2_damaged_penalty
				var p1_dmg = 30 * (1.041**(p2_melee_str - first_p1.melee_strength))
				var p2_dmg = 30 * (1.041**(p1_melee_str - first_p2.melee_strength))
				if (_is_p2_occupied and first_p2.is_defending) or not _is_p2_occupied:
					first_p1.curr_health -= p1_dmg
					first_p1.set_health_bar()
					var report_label = Label.new()
					if local_player_id == "player1":
						report_label.text = "Your %s #%d took %d melee damage from %s #%d" % [first_p1.unit_type, first_p1.net_id, p1_dmg, first_p2.unit_type, first_p2.net_id]
						dmg_report.add_child(report_label)
					else:
						report_label.text = "Your %s #%d dealt %d melee damage to %s #%d" % [first_p2.unit_type, first_p2.net_id, p1_dmg, first_p1.unit_type, first_p1.net_id]
						dmg_report.add_child(report_label)
				if (_is_p1_occupied and first_p1.is_defending) or not _is_p1_occupied:
					first_p2.curr_health -= p2_dmg
					first_p2.set_health_bar()
					var report_label = Label.new()
					if local_player_id == "player1":
						report_label.text = "Your %s #%d dealt %d melee damage to %s #%d" % [first_p1.unit_type, first_p1.net_id, p1_dmg, first_p2.unit_type, first_p2.net_id]
						dmg_report.add_child(report_label)
					else:
						report_label.text = "Your %s #%d took %d melee damage from %s #%d" % [first_p2.unit_type, first_p2.net_id, p1_dmg, first_p1.unit_type, first_p1.net_id]
						dmg_report.add_child(report_label)
				# dead unit handling
				# both dead
				if first_p1.curr_health <= 0 and first_p2.curr_health <=0:
					if _is_p1_occupied:
						_is_p1_occupied = false
					if _is_p2_occupied:
						_is_p2_occupied = false
					var report_label
					if local_player_id == "player1":
						report_label = Label.new()
						report_label.text = "Your %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
						dmg_report.add_child(report_label)
						report_label = Label.new()
						report_label.text = "Enemy %s #%d died at %s" % [first_p2.unit_type, first_p2.net_id, first_p2.grid_pos]
						dmg_report.add_child(report_label)
					else:
						report_label = Label.new()
						report_label.text = "Enemy %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
						dmg_report.add_child(report_label)
						report_label = Label.new()
						report_label.text = "Your %s #%d died at %s" % [first_p2.unit_type, first_p2.net_id, first_p2.grid_pos]
						dmg_report.add_child(report_label)
					player_orders["player1"].erase(first_p1.net_id)
					player_orders["player2"].erase(first_p2.net_id)
					$GameBoardNode.vacate(first_p1.grid_pos)
					$GameBoardNode.vacate(first_p2.grid_pos)
					$GameBoardNode/HexTileMap.set_player_tile(first_p1.grid_pos, "")
					$GameBoardNode/HexTileMap.set_player_tile(first_p2.grid_pos, "")
					first_p1.queue_free()
					first_p2.queue_free()
					p1_units.pop_front()
					p2_units.pop_front()
				# just one dead
				elif first_p1.curr_health <= 0 or first_p2.curr_health <= 0:
					# p1 unit dead
					if first_p1.curr_health <= 0:
						if _is_p1_occupied:
							_is_p1_occupied = false
						var report_label
						if local_player_id == "player1":
							report_label = Label.new()
							report_label.text = "Your %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							dmg_report.add_child(report_label)
						else:
							report_label = Label.new()
							report_label.text = "Enemy %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							dmg_report.add_child(report_label)
						player_orders["player1"].erase(first_p1.net_id)
						first_p1.is_moving = false
						$GameBoardNode.vacate(first_p1.grid_pos)
						$GameBoardNode/HexTileMap.set_player_tile(first_p1.grid_pos, "")
						first_p1.queue_free()
						p1_units.pop_front()
						if p1_units.size() == 0:
							first_p2.set_grid_position(tile)
							for unit in p2_units:
								player_orders["player2"].erase(unit[0].net_id)
								unit[0].is_moving = false
							break
						elif _is_p2_occupied:
							continue
						else:
							player_orders["player2"].erase(first_p2.net_id)
							first_p2.is_moving = false
							p2_units.pop_front()
							
					#p2 unit dead
					else:
						if _is_p2_occupied:
							_is_p2_occupied = false
						var report_label
						if local_player_id == "player1":
							report_label = Label.new()
							report_label.text = "Enemy %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							dmg_report.add_child(report_label)
						else:
							report_label = Label.new()
							report_label.text = "Your %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							dmg_report.add_child(report_label)
						player_orders["player2"].erase(first_p2.net_id)
						first_p2.is_moving = false
						$GameBoardNode.vacate(first_p2.grid_pos)
						$GameBoardNode/HexTileMap.set_player_tile(first_p2.grid_pos, "")
						first_p2.queue_free()
						p2_units.pop_front()
						if p2_units.size() == 0:
							first_p1.set_grid_position(tile)
							for unit in p1_units:
								player_orders["player1"].erase(unit[0].net_id)
								unit[0].is_moving = false
							break
						elif _is_p1_occupied:
							continue
						else:
							player_orders["player1"].erase(first_p1.net_id)
							first_p1.is_moving = false
							p1_units.pop_front()
				
				# both still alive
				else:
					if _is_p2_occupied:
						player_orders["player1"].erase(first_p1.net_id)
						first_p1.is_moving = false
						p1_units.pop_front()
					elif _is_p1_occupied:
						player_orders["player2"].erase(first_p2.net_id)
						first_p2.is_moving = false
						p2_units.pop_front()
					else:
						player_orders["player1"].erase(first_p1.net_id)
						first_p1.is_moving = false
						p1_units.pop_front()
						player_orders["player2"].erase(first_p2.net_id)
						first_p2.is_moving = false
						p2_units.pop_front()
	
	# check if there are more moves and requeue _process_moves
	for player in ["player1", "player2"]:
		for unit_net_id in player_orders[player].keys():
			if unit_net_id is not int:
				continue
			var unit = unit_manager.get_unit_by_net_id(unit_net_id)
			var order = player_orders[player][unit.net_id]
			if order["type"] == "move":
				exec_steps.append(func(): _process_move())
				$UI._draw_paths()
				$GameBoardNode/FogOfWar._update_fog()
				return
	$UI._draw_paths()
	$GameBoardNode/FogOfWar._update_fog()


# --------------------------------------------------------
# Phase 3: Execution — process orders
# --------------------------------------------------------
func _do_execution() -> void:
	current_phase = Phase.EXECUTION
	print("Executing orders...")
	$UI/CancelDoneButton.visible = false
	$GameBoardNode/OrderReminderMap.clear()
	for child in dmg_report.get_children():
		child.queue_free()
	#exec_steps = [
		#func(): _process_spawns(),
		#func(): _process_ranged(),
		#func(): _process_melee(),
		#func(): _process_move()
	#]
	exec_steps = [
		func(): _process_spawns(),
		func(): _process_attacks(),
		func(): _process_move()
	]

	step_index = 0
	_run_next_step()

func _run_next_step():
	$GameBoardNode/FogOfWar._update_fog()
	if step_index >= exec_steps.size():
		emit_signal("execution_complete")
		if get_tree().get_multiplayer().is_server():
			call_deferred("_game_loop")
		return
	exec_steps[step_index].call()
	emit_signal("execution_paused", step_index)

func resume_execution():
	step_index += 1
	_run_next_step()

func start_phase_locally(phase_name: String) -> void:
	print("[TurnManager] start_phase_locally:", phase_name)
	player_orders = NetworkManager.player_orders
	match phase_name:
		"UPKEEP":
			NetworkManager._orders_submitted = { "player1": false, "player2": false }
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
	elif unit_type.to_lower() == "miner":
		scene = miner_scene
	elif unit_type.to_lower() == "phalanx":
		scene = phalanx_scene
	elif unit_type.to_lower() == "cavalry":
		scene = cavalry_scene
	else:
		push_error("Unknown unit type '%s'" % unit_type)
		print("Unknown unit type '%s'" % unit_type)
		return false
	if scene == null:
		push_error("Unit scene for '%s' not assigned in Inspector" % unit_type)
		print("Unit scene for '%s' not assigned in Inspector" % unit_type)
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
	var unit = unit_manager.spawn_unit(unit_type, grid_pos, local_player_id, false)
	$GameBoardNode/FogOfWar._update_fog()
	add_order(local_player_id, {
		"type": "spawn",
		"unit_type": unit_type,
		"unit_net_id": unit.net_id,
		"cell": grid_pos,
		"owner_id": local_player_id,
		"undo": false
	})
	print("%s bought a %s at %s for %d gold" % [player, unit_type, grid_pos, cost])
	return true

# --------------------------------------------------------
# Stub: determine if a player controls a given tile
# --------------------------------------------------------
func _controls_tile(player: String, pos: Vector2i) -> bool:
	return true  # replace with actual ownership logic
