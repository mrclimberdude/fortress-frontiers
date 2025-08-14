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

# Find enemy pairs A<->B where A moves to B and B moves to A.
func _mg_detect_enemy_swaps(mg: MovementGraph) -> Array:
	var pairs := []	# [{"a": Vector2i, "b": Vector2i}]
	var seen := {}
	for a in mg.graph.keys():
		var b = mg.graph[a]
		if not (mg.unit_lookup.has(a) and mg.unit_lookup.has(b)):
			continue
		var ua = mg.unit_lookup[a]
		var ub = mg.unit_lookup[b]
		if ua == null or ub == null or ua.player_id == ub.player_id:
			continue
		if mg.graph.get(b, Vector2i(-999, -999)) == a:
			var k1 := str(a) + "|" + str(b)
			var k2 := str(b) + "|" + str(a)
			if not (seen.has(k1) or seen.has(k2)):
				pairs.append({"a": a, "b": b})
				seen[k1] = true
	return pairs

# Resolve a single enemy swap as a symmetric melee clash.
func _mg_resolve_enemy_swap(a_pos: Vector2i, b_pos: Vector2i) -> void:
	var ua = $GameBoardNode.get_unit_at(a_pos)
	var ub = $GameBoardNode.get_unit_at(b_pos)
	if ua == null or ub == null:
		return

	var dmg_a = calculate_damage(ua, ub, "move", 1)	# [atk_in, def_in]
	var dmg_b = calculate_damage(ub, ua, "move", 1)

	ua.curr_health -= dmg_b[1]
	ub.curr_health -= dmg_a[1]
	ua.set_health_bar()
	ub.set_health_bar()

	var ua_dead = ua.curr_health <= 0
	var ub_dead = ub.curr_health <= 0

	if ua_dead and ub_dead:
		$GameBoardNode.vacate(a_pos)
		$GameBoardNode.vacate(b_pos)
		NetworkManager.player_orders[ua.player_id].erase(ua.net_id)
		NetworkManager.player_orders[ub.player_id].erase(ub.net_id)
		ua.queue_free()
		ub.queue_free()
		return

	if ua_dead and not ub_dead:
		$GameBoardNode.vacate(a_pos)
		ub.set_grid_position(a_pos)
		NetworkManager.player_orders[ub.player_id].erase(ub.net_id)
		ub.is_moving = false
		NetworkManager.player_orders[ua.player_id].erase(ua.net_id)
		ua.queue_free()
		return

	if ub_dead and not ua_dead:
		$GameBoardNode.vacate(b_pos)
		ua.set_grid_position(b_pos)
		NetworkManager.player_orders[ua.player_id].erase(ua.net_id)
		ua.is_moving = false
		NetworkManager.player_orders[ub.player_id].erase(ub.net_id)
		ub.queue_free()
		return

	# both live → both bounce
	NetworkManager.player_orders[ua.player_id].erase(ua.net_id)
	NetworkManager.player_orders[ub.player_id].erase(ub.net_id)
	ua.is_moving = false
	ub.is_moving = false

func _pop_next_unfought(q: Array) -> Dictionary:
	var i := 0
	while i < q.size():
		if not q[i]["fought"]:
			return q.pop_at(i)
		i += 1
	return {}

# Decide the winner for a single tile t this tick.
# If stationary_defender is non-null, treat them as a pinned queue item.
# Returns either a winner_from (Vector2i) or null. This function mutates HP and may free nodes.
func _mg_tile_fifo_commit(t: Vector2i, entrants: Array, stationary_defender: Node) -> Variant:
	# Build entrant items with their native player_id; don't assume labels
	var entrant_items := []
	for src in entrants:
		var u = $GameBoardNode.get_unit_at(src)
		if u != null:
			entrant_items.append({"from": src, "unit": u, "fought": false})

	# No defender -> contested empty tile logic
	if stationary_defender == null:
		# Partition by first-seen side for deterministic buckets
		return _fifo_resolve_empty_tile(
			t,
			_filter_side_queue(entrant_items, entrant_items[0]["unit"].player_id if entrant_items.size() > 0  else null),
			_filter_side_queue(entrant_items, _other_side_id(entrant_items, entrant_items[0]["unit"].player_id) if entrant_items.size() > 0  else null)
		)

	# Defender case: build friend/enemy queues relative to defender's side
	var def_side = stationary_defender.player_id
	var friend_q := []
	var enemy_q := []
	for it in entrant_items:
		if it["unit"].player_id == def_side:
			friend_q.append(it)
		else:
			enemy_q.append(it)

	# Pin the defender at the very front, using a special marker (not a mover!)
	var def_item = {"from": stationary_defender.grid_pos, "unit": stationary_defender, "fought": false, "is_defender": true}
	friend_q.push_front(def_item)

	var killer_item = null  # if defender dies and the killing attacker lives, we add them post-death

	while true:
		# If defender died already, resolve remaining as contested empty
		if stationary_defender == null or stationary_defender.curr_health <= 0:
			# Remove any residual defender marker
			if friend_q.size() > 0 and friend_q.front().has("is_defender") and friend_q.front()["is_defender"]:
				friend_q.pop_front()

			# If we have a live killer from the last clash, append once as fought
			if killer_item != null and killer_item["unit"] != null and killer_item["unit"].curr_health > 0:
				killer_item["fought"] = true
				if killer_item["unit"].player_id == def_side:
					friend_q.append(killer_item)
				else:
					enemy_q.append(killer_item)
				killer_item = null

			return _fifo_resolve_empty_tile(t, friend_q, enemy_q)

		# Defender alive and no enemies left -> friendly entrants cannot pass, stop them this tick
		if enemy_q.size() == 0:
			# stop & clear orders for any friendly *entrants* (ignore the defender marker)
			for it in friend_q:
				if it.has("is_defender") and it["is_defender"]:
					continue
				var f = it["unit"]
				if f != null:
					f.is_moving = false
					if NetworkManager.player_orders.has(f.player_id):
						NetworkManager.player_orders[f.player_id].erase(f.net_id)
			return stationary_defender.grid_pos

		# Defender alive and enemies present -> clash defender vs next enemy
		# Ensure the defender marker is at the very front
		if friend_q.size() == 0 or not (friend_q.front().has("is_defender") and friend_q.front()["is_defender"]):
			# safety: re-insert defender marker at the front if needed
			friend_q.push_front(def_item)

		var enemy_item = enemy_q.pop_front()
		var atk = enemy_item["unit"]
		if atk == null:
			continue

		# Attacker hits defender; defender retaliates if still alive & is_defending
		var dmg = calculate_damage(atk, stationary_defender, "move", 1)
		stationary_defender.curr_health -= dmg[1]
		stationary_defender.set_health_bar()

		if stationary_defender.is_defending:
			atk.curr_health -= dmg[0]
			atk.set_health_bar()

		# Attacker fought this tick -> stop and clear order
		atk.is_moving = false
		if NetworkManager.player_orders.has(atk.player_id):
			NetworkManager.player_orders[atk.player_id].erase(atk.net_id)

		# Handle deaths
		if atk.curr_health <= 0:
			$GameBoardNode.vacate(atk.grid_pos)
			atk.queue_free()
			enemy_item = null
		if stationary_defender.curr_health <= 0:
			# Defender died at atk's hand; remember killer if alive
			if atk != null and atk.curr_health > 0:
				killer_item = {"from": atk.grid_pos, "unit": atk, "fought": true}
			# Remove defender from board and proceed to empty-tile FIFO
			var dpos = def_item["from"]
			$GameBoardNode.vacate(dpos)
			stationary_defender.queue_free()
			stationary_defender = null
			# loop continues; next iteration will fall into the contested-empty branch
			continue

		# Defender lives -> keep defender marker locked at the very front for next enemy
		# (do nothing: def_item is already at front)
	# unreachable
	return null


# Helper: split entrant items by specific side id
func _filter_side_queue(items: Array, side_id) -> Array:
	var q := []
	for it in items:
		var u = it["unit"]
		if u == null:
			continue
		if side_id == null:
			continue
		if u.player_id == side_id:
			q.append(it.duplicate(true))
	return q

# Helper: compute the "other" side id from a list (first non-matching)
func _other_side_id(items: Array, side_id):
	for it in items:
		var u = it["unit"]
		if u != null and u.player_id != side_id:
			return u.player_id
	return null

# Resolve contested empty tile between two side-queues (same rules as before):
# - Pop next *unfought* from each side; if one side empty -> other side's front enters.
# - When two pop, they clash; both are marked fought and stop; killers requeue once with fought=true.
# - Returns winner_from or null.
func _fifo_resolve_empty_tile(dest: Vector2i, qA: Array, qB: Array) -> Variant:

	while true:
		var a = _pop_next_unfought(qA)
		var b = _pop_next_unfought(qB)

		if a.is_empty() and b.is_empty():
			break
		if a.is_empty() or b.is_empty():
			if not a.is_empty(): qA.push_front(a)
			if not b.is_empty(): qB.push_front(b)
			break

		var ua = a["unit"]
		var ub = b["unit"]
		if ua == null or ub == null:
			continue

		var d12 = calculate_damage(ua, ub, "move", 1)
		var d21 = calculate_damage(ub, ua, "move", 1)
		ua.curr_health -= d21[1]
		ub.curr_health -= d12[1]
		ua.set_health_bar()
		ub.set_health_bar()

		# both fought this tick
		ua.is_moving = false
		ub.is_moving = false
		if NetworkManager.player_orders.has(ua.player_id):
			NetworkManager.player_orders[ua.player_id].erase(ua.net_id)
		if NetworkManager.player_orders.has(ub.player_id):
			NetworkManager.player_orders[ub.player_id].erase(ub.net_id)

		var ua_dead = ua.curr_health <= 0
		var ub_dead = ub.curr_health <= 0
		if ua_dead:
			$GameBoardNode.vacate(ua.grid_pos)
			ua.queue_free()
		if ub_dead:
			$GameBoardNode.vacate(ub.grid_pos)
			ub.queue_free()

		# killer requeues *once* with fought=true
		if not ua_dead and ub_dead:
			a["fought"] = true
			qA.append(a)
		if not ub_dead and ua_dead:
			b["fought"] = true
			qB.append(b)

	# claim step
	if qA.size() == 0 and qB.size() == 0:
		return null
	if qA.size() > 0 and qB.size() == 0:
		return qA.front()["from"]
	if qB.size() > 0 and qA.size() == 0:
		return qB.front()["from"]
	return null


# Rotate an uncontested SCC atomically. winners_by_tile must already reflect internal predecessors.
# Returns a Set (Dictionary used as set) of tiles touched by the rotation.
func _mg_commit_rotation(scc: Array, mg: MovementGraph, winners_by_tile: Dictionary, vacated: Dictionary) -> Dictionary:
	var prev := mg.cycle_prev_map()

	# Build planned moves (from -> to) and validate uniqueness of destinations
	var moves := []  # Array[{unit: Unit, from: Vector2i, to: Vector2i}]
	var to_seen := {}
	for node in scc:
		var from_tile: Vector2i = prev.get(node, Vector2i(-999, -999))
		if from_tile == Vector2i(-999, -999):
			# safety: cycle map missing? abort rotation
			return {}
		var u = $GameBoardNode.get_unit_at(from_tile)
		if u == null or u.curr_health <= 0:
			# someone missing/ dead? abort
			return {}
		if to_seen.has(node):
			# duplicate destination in scc?! abort
			return {}
		to_seen[node] = true
		moves.append({ "unit": u, "from": from_tile, "to": node })

	# Phase A: vacate the entire component (all nodes), not just 'from' tiles.
	for i in range(moves.size()):
		moves[i]["unit"].set_grid_position(Vector2i(-998 + i, -998 +i))

	# Phase B: place each unit at its destination
	for m in moves:
		var u: Node = m["unit"]
		var to_tile: Vector2i = m["to"]
		u.set_grid_position(to_tile)
		vacated[m["from"]] = true

	# Return set of tiles that were part of rotation so later passes can skip them
	var rotated_tiles := {}
	for node in scc:
		rotated_tiles[node] = true
	return rotated_tiles

# Resolve a chain by walking from the sink backward.
#  mg          : MovementGraph already built for this tick.
#  entrants_map: mg.entries_all() (captured once before rotations).
#  start_tile  : the current sink (empty or stationary/stayed occupant).
#  rotated_tiles: Dictionary set of tiles that were part of this tick's rotations – skip them.
func _mg_resolve_chain_from_sink(mg: MovementGraph, entrants_map: Dictionary, start_tile: Vector2i, rotated_tiles: Dictionary) -> void:
	var pending := [start_tile]
	var seen := {}

	while pending.size() > 0:
		var t: Vector2i = pending.pop_front()
		if rotated_tiles.has(t) or seen.has(t):
			continue
		seen[t] = true

		# Filter entrants to live, still-moving units
		var raw = entrants_map.get(t, [])
		var entrants := []
		for src in raw:
			var u = $GameBoardNode.get_unit_at(src)
			if u != null and u.curr_health > 0 and u.is_moving:
				entrants.append(src)
				if not src in pending:
					pending.append(src)

		if entrants.size() == 0:
			continue  # chain ends here

		var occ = $GameBoardNode.get_unit_at(t)
		var winner_from = null
		var fought = false
		# stationary defender if occupant has no outgoing move (or is stayed)
		if occ != null and not occ.is_moving:
			winner_from = _mg_tile_fifo_commit(t, entrants, occ)
		else:
			winner_from = _mg_tile_fifo_commit(t, entrants, null)

		if typeof(winner_from) == TYPE_VECTOR2I:
			# The unit that entered t came from winner_from; that tile is the next sink
			var w = $GameBoardNode.get_unit_at(winner_from)
			if w != null and w.curr_health > 0:
				w.set_grid_position(t)
			#pending.append(winner_from)


# Commit chains (SCC singletons) in sink->root order using dep_edges.
func _mg_commit_chains(dep_edges: Dictionary, vacated: Dictionary) -> void:
	var incoming := {}
	for s in dep_edges.keys():
		incoming[dep_edges[s]] = true
	var roots := []
	for s in dep_edges.keys():
		if not incoming.get(s, false):
			roots.append(s)
	for s in roots:
		var cur = s
		while dep_edges.has(cur):
			var d = dep_edges[cur]
			var u = $GameBoardNode.get_unit_at(cur)
			if u == null or u.curr_health <= 0:
				break
			$GameBoardNode.vacate(cur)
			u.set_grid_position(d)
			vacated[cur] = true
			cur = d


func _process_move():
	var all_units = $GameBoardNode.get_all_units()
	var units: Array = all_units["player1"] + all_units["player2"]
	var mg = MovementGraph.new()
	mg.build(units)
	
	# 1. Resolve enemy swaps first
	for pair in mg.detect_enemy_swaps():
		_mg_resolve_enemy_swap(pair["a"], pair["b"])

	# Rebuild after swaps
	all_units = $GameBoardNode.get_all_units()
	units = all_units["player1"] + all_units["player2"]
	mg.build(units)

	# 2. Determine entrants and provisional winners on single‑entry tiles
	var entrants_all = mg.entries_all()
	var winners_by_tile: Dictionary = {}
	for t in entrants_all.keys():
		if entrants_all[t].size() == 1:
			var occ = $GameBoardNode.get_unit_at(t)
			if occ == null or occ.is_moving:
				winners_by_tile[t] = entrants_all[t][0]
	
	# 3. Build dependency edges and detect SCCs
	var dep_edges = mg.dependency_edges_from_winners(winners_by_tile)
	var sccs = mg.strongly_connected_components(dep_edges)

	# 4. Commit uncontested rotations and chains
	var vacated := {}
	var stayed := {}
	var rotated_tiles := {}
	for comp in sccs:
		if mg.scc_is_uncontested_rotation(comp, winners_by_tile):
			var touched = _mg_commit_rotation(comp, mg, winners_by_tile, vacated)
			for t in touched.keys():
				rotated_tiles[t] = true
	
	all_units = $GameBoardNode.get_all_units()
	units = all_units["player1"] + all_units["player2"]
	mg.build(units)
	entrants_all = mg.entries_all()
	
	# Build SCCs on the raw intent graph (one outgoing per mover)
	var graph_edges := {}
	for from_tile in mg.graph.keys():
		graph_edges[from_tile] = [mg.graph[from_tile]]
	var sccs_all: Array = mg.strongly_connected_components(graph_edges)

	# Targeted "entrant-vs-entrant" pre-fight ONLY at contested cycle entry tiles
	# We do not move anyone here; we only stop fighters. We IGNORE any return value.
	for comp in sccs_all:
		if rotated_tiles.has(comp.front()):
			continue
		if mg.scc_is_contested_cycle(comp, entrants_all):
			# Build quick lookup sets
			var in_comp := {}
			for n in comp:
				in_comp[n] = true
			var prev := mg.cycle_prev_map()

			for node in comp:
				# entrants to this node in this tick
				var raw_arr: Array = entrants_all.get(node, [])
				# Keep internal predecessor IF present (the mover from inside the cycle)
				var internal_src = prev.get(node, null)
				# Collect external entrants (outside SCC) + the internal predecessor
				var fight_list := []
				for src in raw_arr:
					if src == internal_src:
						fight_list.append(src)          # internal predecessor is also an entrant
					elif not in_comp.has(src):
						fight_list.append(src)          # true external entrant

				# Only pre-fight if at least two entrants meet at this node
				if fight_list.size() >= 2:
					_mg_tile_fifo_commit(node, fight_list, null)  # fight-only; ignore winner

	# Rebuild graph & entrants after these fights (is_moving/HP may have changed)
	all_units = $GameBoardNode.get_all_units()
	units = all_units["player1"] + all_units["player2"]
	mg.build(units)
	entrants_all = mg.entries_all()

	# 5. Identify sinks: empty tiles with entrants, plus tiles whose occupant does not have an outgoing move
	var sink_tiles := []
	for t in entrants_all.keys():
		if rotated_tiles.has(t):
			continue
		var occ = $GameBoardNode.get_unit_at(t)
		if occ == null or not occ.is_moving:
			sink_tiles.append(t)

	# Walk each sink to resolve the chain
	for t in sink_tiles:
		_mg_resolve_chain_from_sink(mg, entrants_all, t, rotated_tiles)

	all_units = $GameBoardNode.get_all_units()
	units = all_units["player1"] + all_units["player2"]
	mg.build(units)
	entrants_all = mg.entries_all()
	
	# Mark units that did not move as stationary for this tick
	for u in units:
		if u.is_moving and not vacated.get(u.grid_pos, false) and not rotated_tiles.has(u.grid_pos):
			stayed[u.grid_pos] = true
	
	## 5. Run bounce‑as‑stationary defender fights
	for t in entrants_all.keys():
		if rotated_tiles.has(t):
			continue
		if stayed.get(t, false):
			var defender = $GameBoardNode.get_unit_at(t)
			if defender != null:
				var winner_from2 = _mg_tile_fifo_commit(t, entrants_all[t], defender)
				if typeof(winner_from2) == TYPE_VECTOR2I:
					var w2 = $GameBoardNode.get_unit_at(winner_from2)
					if w2 != null and w2.curr_health > 0:
						# set_grid_position handles vacate+occupy
						w2.set_grid_position(t)
						w2.is_moving = false
	
	## 6. Resolve contested empty tiles with FIFO queues
	#for t in entrants_all.keys():
		#if rotated_tiles.has(t):
			#continue
		#if stayed.get(t, false):
			#continue
		#if entrants_all[t].size() > 0:
			#var winner_from = _mg_tile_fifo_commit(t, entrants_all[t], $GameBoardNode.get_unit_at(t))
			#if winner_from is Vector2i:
				#var wunit = $GameBoardNode.get_unit_at(winner_from)
				#if wunit != null and wunit.curr_health > 0:
					#$GameBoardNode.vacate(wunit.grid_pos)
					#wunit.set_grid_position(t)
					#wunit.is_moving = false
					#NetworkManager.player_orders[wunit.player_id].erase(wunit.net_id)
	
	# 7. Pop one path step for every unit that moved; clear finished orders
	for u in units:
		var orders = NetworkManager.player_orders.get(u.player_id, {})
		if orders.has(u.net_id):
			var ord = orders[u.net_id]
			if ord.has("path") and ord["path"].size() > 1 and u.grid_pos == ord["path"][1]:
				ord["path"].pop_front()
				if ord["path"].size() <= 1:
					u.is_moving = false
					orders.erase(u.net_id)
				else:
					u.moving_to = ord["path"][1]
	
	# 8. Refresh the UI and fog each tick
	$UI._draw_attacks()
	$UI._draw_paths()
	$UI._draw_supports()
	$GameBoardNode/FogOfWar._update_fog()
	
	# 10) schedule the next tick if any moves remain
	for player in ["player1", "player2"]:
		for unit_id in NetworkManager.player_orders[player].keys():
			var ord = NetworkManager.player_orders[player][unit_id]
			if ord.has("type") and ord["type"] == "move":
				exec_steps.append(func(): _process_move())
				$UI._draw_paths()
				$GameBoardNode/FogOfWar._update_fog()
				return  # pause execution here

	
	#var tiles_entering: Dictionary = {} # key: tile, value: [unit]
	## find all tiles that are being entered into on the next move by both players
	#for player in ["player1", "player2"]:
		#var unit_ids = player_orders[player].keys()
		#unit_ids.sort()
		#for unit_net_id in unit_ids:
			#if unit_net_id is not int:
				#continue
			#var unit = unit_manager.get_unit_by_net_id(unit_net_id)
			#var order = player_orders[player][unit_net_id]
			#if order["type"] == "move":
				#var next_tile = order["path"][1]
				#tiles_entering[next_tile] = tiles_entering.get(next_tile, [])
				#tiles_entering[next_tile].append(unit_net_id)
	#var sorted_tiles = tiles_entering.keys()
	#sorted_tiles.sort()
	#for tile in sorted_tiles:
		## if only one unit entering a tile, perform the move
		#if tiles_entering[tile].size() == 1:
			#var curr_unit = unit_manager.get_unit_by_net_id(tiles_entering[tile][0])
			## check if there is something there and fight if an enemy
			#if $GameBoardNode.is_occupied(tile):
				#var obstacle = $GameBoardNode.get_unit_at(tile)
				#if obstacle.is_moving:
					#if obstacle.player_id == curr_unit.player_id or obstacle.moving_to != curr_unit.grid_pos:
						#var dependency_path = $GameBoardNode/Units.find_end(curr_unit, [curr_unit.grid_pos], false, false)
						#var dupe_tile = null
						#for spot in dependency_path[0]:
							#if dependency_path[0].count(spot) > 1:
								#dupe_tile = spot
								#break
						#if dupe_tile:
							#var dupe_index = dependency_path[0].find(dupe_tile)
							#var circle = dependency_path[0].slice(dupe_index)
							#var units = []
							#for spot in circle:
								#var unit = $GameBoardNode.get_unit_at(spot)
								#units.append(unit)
							#var first_unit = units[-1]
							#first_unit.set_grid_position(Vector2i(-100, -100))
							#for i in range(units.size() -2, -1, -1):
								#units[i].set_grid_position(circle[i+1])
								#if player_orders[units[i].player_id][units[i].net_id]["path"].size() <= 2:
									#player_orders[units[i].player_id].erase(units[i].net_id)
									#units[i].is_moving = false
								#else:
									#player_orders[units[i].player_id][units[i].net_id]["path"].pop_front()
									#units[i].moving_to = player_orders[units[i].player_id][units[i].net_id]["path"][1]
							#break
						#var units = []
						#for spot in dependency_path[0]:
							#var unit = $GameBoardNode.get_unit_at(spot)
							#if unit:
								#if unit in units:
									#break
								#if unit.is_moving:
									#units.append(unit)
						#for i in range(units.size()-1, -1, -1):
							#var entering_unit = units[i]
							#var new_tile = dependency_path[0][i+1]
							#var unit_at_tile = $GameBoardNode.get_unit_at(new_tile)
							#if unit_at_tile:
								#if unit_at_tile.player_id == entering_unit.player_id:
									#if unit_at_tile.is_moving:
										#if unit_at_tile.moving_to !=entering_unit.grid_pos:
											#continue
										#unit_at_tile.set_grid_position(Vector2i(-100, -100))
										#var old_tile = entering_unit.grid_pos
										#entering_unit.set_grid_position(new_tile)
										#unit_at_tile.set_grid_position(old_tile)
										#if player_orders[entering_unit.player_id][entering_unit.net_id]["path"].size() <= 2:
											#player_orders[entering_unit.player_id].erase(entering_unit.net_id)
											#entering_unit.is_moving = false
										#else:
											#player_orders[entering_unit.player_id][entering_unit.net_id]["path"].pop_front()
											#entering_unit.moving_to = player_orders[entering_unit.player_id][entering_unit.net_id]["path"][1]
										#if player_orders[unit_at_tile.player_id][unit_at_tile.net_id]["path"].size() <= 2:
											#player_orders[unit_at_tile.player_id].erase(unit_at_tile.net_id)
											#unit_at_tile.is_moving = false
										#else:
											#player_orders[unit_at_tile.player_id][unit_at_tile.net_id]["path"].pop_front()
											#unit_at_tile.moving_to = player_orders[unit_at_tile.player_id][unit_at_tile.net_id]["path"][1]
										#continue
									#player_orders[entering_unit.player_id].erase(entering_unit.net_id)
									#entering_unit.is_moving = false
								#else:
									#if unit_at_tile.is_moving and unit_at_tile.moving_to != entering_unit.grid_pos:
										#continue
									#var dmg_result = calculate_damage(entering_unit, unit_at_tile, "move", 1)
									#var atkr_in_dmg = dmg_result[0]
									#var defr_in_dmg = dmg_result[1]
									#unit_at_tile.curr_health -= defr_in_dmg
									#unit_at_tile.set_health_bar()
									#if unit_at_tile.is_defending:
										#entering_unit.curr_health -= atkr_in_dmg
										#entering_unit.set_health_bar()
										#dealt_dmg_report(entering_unit, unit_at_tile, atkr_in_dmg, defr_in_dmg, true, "melee")
										#if entering_unit.curr_health <= 0:
											#died_dmg_report(entering_unit)
											#player_orders[entering_unit.player_id].erase(entering_unit.net_id)
											#$GameBoardNode.vacate(entering_unit.grid_pos)
											#$GameBoardNode/HexTileMap.set_player_tile(entering_unit.grid_pos, "")
											#entering_unit.queue_free()
									#
									#elif unit_at_tile.is_moving and unit_at_tile.moving_to == entering_unit.grid_pos:
										#entering_unit.curr_health -= atkr_in_dmg
										#entering_unit.set_health_bar()
										#dealt_dmg_report(entering_unit, unit_at_tile, atkr_in_dmg, defr_in_dmg, true, "melee")
										#if entering_unit.curr_health <= 0:
											#died_dmg_report(entering_unit)
											#player_orders[entering_unit.player_id].erase(entering_unit.net_id)
											#$GameBoardNode.vacate(entering_unit.grid_pos)
											#$GameBoardNode/HexTileMap.set_player_tile(entering_unit.grid_pos, "")
											#if unit_at_tile.curr_health > 0:
												#unit_at_tile.set_grid_position(entering_unit.grid_pos)
											#unit_at_tile.is_moving = false
											#player_orders[unit_at_tile.player_id].erase(unit_at_tile.net_id)
											#entering_unit.queue_free()
									#else:
										#dealt_dmg_report(entering_unit, unit_at_tile, atkr_in_dmg, defr_in_dmg, false, "melee")
									#
									#if unit_at_tile.curr_health <= 0:
										#died_dmg_report(unit_at_tile)
										#player_orders[unit_at_tile.player_id].erase(unit_at_tile.net_id)
										#$GameBoardNode.vacate(unit_at_tile.grid_pos)
										#$GameBoardNode/HexTileMap.set_player_tile(unit_at_tile.grid_pos, "")
										#if entering_unit.curr_health > 0:
											#entering_unit.set_grid_position(new_tile)
										#entering_unit.is_moving = false
										#player_orders[entering_unit.player_id].erase(entering_unit.net_id)
										#unit_at_tile.queue_free()
									#
									#player_orders[entering_unit.player_id].erase(entering_unit.net_id)
									#entering_unit.is_moving = false
								#continue
							#
							## no unit in next_tile
							#units[i].set_grid_position(dependency_path[0][i+1])
							#if player_orders[units[i].player_id][units[i].net_id]["path"].size() <= 2:
								#player_orders[units[i].player_id].erase(units[i].net_id)
								#units[i].is_moving = false
							#else:
								#player_orders[units[i].player_id][units[i].net_id]["path"].pop_front()
								#units[i].moving_to = player_orders[units[i].player_id][units[i].net_id]["path"][1]
						#break
				#if obstacle.player_id != curr_unit.player_id:
					#var dmg_result = calculate_damage(curr_unit, obstacle, "move", 1)
					#var atkr_in_dmg = dmg_result[0]
					#var defr_in_dmg = dmg_result[1]
					#obstacle.curr_health -= defr_in_dmg
					#obstacle.set_health_bar()
					#if obstacle.is_defending:
						#curr_unit.curr_health -= atkr_in_dmg
						#curr_unit.set_health_bar()
						#dealt_dmg_report(curr_unit, obstacle, atkr_in_dmg, defr_in_dmg, true, "melee")
					#if obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving and obstacle.curr_health > 0:
						#curr_unit.curr_health -= atkr_in_dmg
						#curr_unit.set_health_bar()
						#player_orders[obstacle.player_id].erase(obstacle.net_id)
						#obstacle.is_moving = false
						#dealt_dmg_report(curr_unit, obstacle, atkr_in_dmg, defr_in_dmg, true, "melee")
					#
					#
					#
					#if obstacle.player_id == local_player_id:
						#var report_label = Label.new()
						#report_label.text = "Your %s #%d took %d melee damage from %s #%d" % [obstacle.unit_type, obstacle.net_id, defr_in_dmg, curr_unit.unit_type, curr_unit.net_id]
						#dmg_report.add_child(report_label)
						#if obstacle.is_defending or (obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving):
							#report_label = Label.new()
							#report_label.text = "Your %s #%d retaliated and dealt %d damage" % [obstacle.unit_type, obstacle.net_id, atkr_in_dmg]
							#dmg_report.add_child(report_label)
					#else:
						#var report_label = Label.new()
						#report_label.text = "Your %s #%d dealt %d melee damage to %s #%d" % [curr_unit.unit_type, curr_unit.net_id, defr_in_dmg, obstacle.unit_type, obstacle.net_id]
						#dmg_report.add_child(report_label)
						#if obstacle.is_defending or (obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving):
							#report_label = Label.new()
							#report_label.text = "Enemy %s #%d retaliated and dealt %d damage" % [obstacle.unit_type, obstacle.net_id, atkr_in_dmg]
							#dmg_report.add_child(report_label)
					#if obstacle.curr_health <= 0:
						#player_orders[obstacle.player_id].erase(obstacle.net_id)
						#$GameBoardNode.vacate(obstacle.grid_pos)
						#$GameBoardNode/HexTileMap.set_player_tile(obstacle.grid_pos, "")
						#if obstacle.player_id == local_player_id:
							#var report_label = Label.new()
							#report_label.text = "Your %s #%d died at %s" % [obstacle.unit_type, obstacle.net_id, obstacle.grid_pos]
							#dmg_report.add_child(report_label)
						#else:
							#var report_label = Label.new()
							#report_label.text = "Your %s #%d died at %s" % [obstacle.unit_type, obstacle.net_id, obstacle.grid_pos]
							#dmg_report.add_child(report_label)
						#obstacle.queue_free()
						#if curr_unit.curr_health > 0 and curr_unit.is_moving:
							#curr_unit.set_grid_position(tile)
							##$GameBoardNode/HexTileMap.set_player_tile(tile, curr_unit.player_id)
					#player_orders[curr_unit.player_id].erase(curr_unit.net_id)
					#curr_unit.is_moving = false
					#if curr_unit.curr_health <= 0:
						#$GameBoardNode.vacate(curr_unit.grid_pos)
						#$GameBoardNode/HexTileMap.set_player_tile(curr_unit.grid_pos, "")
						#
						#if obstacle.moving_to == curr_unit.grid_pos and obstacle.is_moving and obstacle.curr_health > 0:
							#obstacle.set_grid_position(curr_unit.grid_pos)
							#player_orders[obstacle.player_id].erase(obstacle.net_id)
							#obstacle.is_moving = false
						#curr_unit.queue_free()
					#break
				#else:
					#player_orders[curr_unit.player_id].erase(curr_unit.net_id)
					#curr_unit.is_moving = false
			#else:
				#curr_unit.set_grid_position(tile)
				#if player_orders[curr_unit.player_id][curr_unit.net_id]["path"].size() <= 2:
					#player_orders[curr_unit.player_id].erase(curr_unit.net_id)
					#curr_unit.is_moving = false
				#else:
					#player_orders[curr_unit.player_id][curr_unit.net_id]["path"].pop_front()
					#curr_unit.moving_to = player_orders[curr_unit.player_id][curr_unit.net_id]["path"][1]
			#
		#
		## conflict handling
		#else:
			#var p1_units = []
			#var p2_units = []
			#var _is_p1_occupied = false
			#var _is_p2_occupied = false
			#if $GameBoardNode.is_occupied(tile):
				#var obstacle = $GameBoardNode.get_unit_at(tile)
				#if obstacle.player_id == "player1":
					#_is_p1_occupied = true
					#p1_units.append([obstacle, -1])
				#else:
					#_is_p2_occupied = true
					#p2_units.append([obstacle, -1])
			#for unit_net_id in tiles_entering[tile]:
				#var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				#if unit.player_id == "player1":
					#p1_units.append([unit,player_orders["player1"][unit.net_id]["priority"]])
				#else:
					#p2_units.append([unit,player_orders["player2"][unit.net_id]["priority"]])
			#p1_units.sort_custom(func(a,b): return a[1] < b[1])
			#p2_units.sort_custom(func(a,b): return a[1] < b[1])
			#
			#while p1_units.size() > 0 or p2_units.size() > 0:
				#
				## all of one players entering units have acted or died
				#if p1_units.size() == 0:
					#if not _is_p2_occupied:
						#p2_units[0][0].set_grid_position(tile)
					#for unit in p2_units:
						#player_orders["player2"].erase(unit[0].net_id)
						#unit[0].is_moving = false
					#break
				#if p2_units.size() == 0:
					#if not _is_p1_occupied:
						#p1_units[0][0].set_grid_position(tile)
					#for unit in p1_units:
						#player_orders["player1"].erase(unit[0].net_id)
						#unit[0].is_moving = false
					#break
				#var first_p1 = p1_units[0][0]
				#var first_p2 = p2_units[0][0]
				## first priority units of each player fight each other
				## NOTE: UPDATE THIS SECTION WHENEVER DAMAGE CALCULATION IS UPDATED
				## search for MANUAL_DMG
				#var p1_damaged_penalty
				#var p1_melee_str = first_p1.melee_strength
				#if (_is_p1_occupied and first_p1.is_defending) or not _is_p1_occupied:
					#if first_p1.is_defending and first_p1.is_phalanx:
						#p1_melee_str += PHALANX_BONUS
					#p1_damaged_penalty = 1 - ((100 - first_p1.curr_health) * 0.005)
					#p1_melee_str = p1_melee_str * p1_damaged_penalty
				#var p2_damaged_penalty
				#var p2_melee_str = first_p2.melee_strength
				#if (_is_p2_occupied and first_p2.is_defending) or not _is_p2_occupied:
					#if first_p2.is_defending and first_p2.is_phalanx:
						#p2_melee_str += PHALANX_BONUS
					#p2_damaged_penalty = 1 - ((100 - first_p2.curr_health) * 0.005)
					#p2_melee_str = p2_melee_str * p2_damaged_penalty
				#var p1_dmg = 30 * (1.041**(p2_melee_str - first_p1.melee_strength))
				#var p2_dmg = 30 * (1.041**(p1_melee_str - first_p2.melee_strength))
				#if (_is_p2_occupied and first_p2.is_defending) or not _is_p2_occupied:
					#first_p1.curr_health -= p1_dmg
					#first_p1.set_health_bar()
					#var report_label = Label.new()
					#if local_player_id == "player1":
						#report_label.text = "Your %s #%d took %d melee damage from %s #%d" % [first_p1.unit_type, first_p1.net_id, p1_dmg, first_p2.unit_type, first_p2.net_id]
						#dmg_report.add_child(report_label)
					#else:
						#report_label.text = "Your %s #%d dealt %d melee damage to %s #%d" % [first_p2.unit_type, first_p2.net_id, p1_dmg, first_p1.unit_type, first_p1.net_id]
						#dmg_report.add_child(report_label)
				#if (_is_p1_occupied and first_p1.is_defending) or not _is_p1_occupied:
					#first_p2.curr_health -= p2_dmg
					#first_p2.set_health_bar()
					#var report_label = Label.new()
					#if local_player_id == "player1":
						#report_label.text = "Your %s #%d dealt %d melee damage to %s #%d" % [first_p1.unit_type, first_p1.net_id, p1_dmg, first_p2.unit_type, first_p2.net_id]
						#dmg_report.add_child(report_label)
					#else:
						#report_label.text = "Your %s #%d took %d melee damage from %s #%d" % [first_p2.unit_type, first_p2.net_id, p1_dmg, first_p1.unit_type, first_p1.net_id]
						#dmg_report.add_child(report_label)
				## dead unit handling
				## both dead
				#if first_p1.curr_health <= 0 and first_p2.curr_health <=0:
					#if _is_p1_occupied:
						#_is_p1_occupied = false
					#if _is_p2_occupied:
						#_is_p2_occupied = false
					#var report_label
					#if local_player_id == "player1":
						#report_label = Label.new()
						#report_label.text = "Your %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
						#dmg_report.add_child(report_label)
						#report_label = Label.new()
						#report_label.text = "Enemy %s #%d died at %s" % [first_p2.unit_type, first_p2.net_id, first_p2.grid_pos]
						#dmg_report.add_child(report_label)
					#else:
						#report_label = Label.new()
						#report_label.text = "Enemy %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
						#dmg_report.add_child(report_label)
						#report_label = Label.new()
						#report_label.text = "Your %s #%d died at %s" % [first_p2.unit_type, first_p2.net_id, first_p2.grid_pos]
						#dmg_report.add_child(report_label)
					#player_orders["player1"].erase(first_p1.net_id)
					#player_orders["player2"].erase(first_p2.net_id)
					#$GameBoardNode.vacate(first_p1.grid_pos)
					#$GameBoardNode.vacate(first_p2.grid_pos)
					#$GameBoardNode/HexTileMap.set_player_tile(first_p1.grid_pos, "")
					#$GameBoardNode/HexTileMap.set_player_tile(first_p2.grid_pos, "")
					#first_p1.queue_free()
					#first_p2.queue_free()
					#p1_units.pop_front()
					#p2_units.pop_front()
				## just one dead
				#elif first_p1.curr_health <= 0 or first_p2.curr_health <= 0:
					## p1 unit dead
					#if first_p1.curr_health <= 0:
						#if _is_p1_occupied:
							#_is_p1_occupied = false
						#var report_label
						#if local_player_id == "player1":
							#report_label = Label.new()
							#report_label.text = "Your %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							#dmg_report.add_child(report_label)
						#else:
							#report_label = Label.new()
							#report_label.text = "Enemy %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							#dmg_report.add_child(report_label)
						#player_orders["player1"].erase(first_p1.net_id)
						#first_p1.is_moving = false
						#$GameBoardNode.vacate(first_p1.grid_pos)
						#$GameBoardNode/HexTileMap.set_player_tile(first_p1.grid_pos, "")
						#first_p1.queue_free()
						#p1_units.pop_front()
						#if p1_units.size() == 0:
							#first_p2.set_grid_position(tile)
							#for unit in p2_units:
								#player_orders["player2"].erase(unit[0].net_id)
								#unit[0].is_moving = false
							#break
						#elif _is_p2_occupied:
							#continue
						#else:
							#player_orders["player2"].erase(first_p2.net_id)
							#first_p2.is_moving = false
							#p2_units.pop_front()
							#
					##p2 unit dead
					#else:
						#if _is_p2_occupied:
							#_is_p2_occupied = false
						#var report_label
						#if local_player_id == "player1":
							#report_label = Label.new()
							#report_label.text = "Enemy %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							#dmg_report.add_child(report_label)
						#else:
							#report_label = Label.new()
							#report_label.text = "Your %s #%d died at %s" % [first_p1.unit_type, first_p1.net_id, first_p1.grid_pos]
							#dmg_report.add_child(report_label)
						#player_orders["player2"].erase(first_p2.net_id)
						#first_p2.is_moving = false
						#$GameBoardNode.vacate(first_p2.grid_pos)
						#$GameBoardNode/HexTileMap.set_player_tile(first_p2.grid_pos, "")
						#first_p2.queue_free()
						#p2_units.pop_front()
						#if p2_units.size() == 0:
							#first_p1.set_grid_position(tile)
							#for unit in p1_units:
								#player_orders["player1"].erase(unit[0].net_id)
								#unit[0].is_moving = false
							#break
						#elif _is_p1_occupied:
							#continue
						#else:
							#player_orders["player1"].erase(first_p1.net_id)
							#first_p1.is_moving = false
							#p1_units.pop_front()
				#
				## both still alive
				#else:
					#if _is_p2_occupied:
						#player_orders["player1"].erase(first_p1.net_id)
						#first_p1.is_moving = false
						#p1_units.pop_front()
					#elif _is_p1_occupied:
						#player_orders["player2"].erase(first_p2.net_id)
						#first_p2.is_moving = false
						#p2_units.pop_front()
					#else:
						#player_orders["player1"].erase(first_p1.net_id)
						#first_p1.is_moving = false
						#p1_units.pop_front()
						#player_orders["player2"].erase(first_p2.net_id)
						#first_p2.is_moving = false
						#p2_units.pop_front()
	#
	## check if there are more moves and requeue _process_moves
	#for player in ["player1", "player2"]:
		#for unit_net_id in player_orders[player].keys():
			#if unit_net_id is not int:
				#continue
			#var unit = unit_manager.get_unit_by_net_id(unit_net_id)
			#var order = player_orders[player][unit.net_id]
			#if order["type"] == "move":
				#exec_steps.append(func(): _process_move())
				#$UI._draw_paths()
				#$GameBoardNode/FogOfWar._update_fog()
				#return
	#$UI._draw_paths()
	#$GameBoardNode/FogOfWar._update_fog()


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
