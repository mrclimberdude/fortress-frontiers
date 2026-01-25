## TurnManager.gd

extends Node

signal orders_phase_begin(player: String)
signal orders_phase_end()
signal state_applied()

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
@export var crystal_miner_scene: PackedScene
@export var phalanx_scene: PackedScene
@export var cavalry_scene: PackedScene
@export var wizard_scene: PackedScene

const MineScene = preload("res://scenes/GemMine.tscn")
const MapGenerator = preload("res://scripts/MapGenerator.gd")

@export var map_data: Array[Resource] = []
var terrain_overlay: TileMapLayer
var rng := RandomNumberGenerator.new()
var current_map_index: int = -1

func _map_category_for(md: MapData) -> String:
	if md == null:
		return "normal"
	var cat = str(md.map_category).strip_edges().to_lower()
	if cat != "":
		return cat
	var name = str(md.map_name).strip_edges().to_lower()
	if name.begins_with("map_"):
		var suffix = name.substr(4, name.length() - 4)
		if suffix.is_valid_int():
			return "normal"
	return "themed"

func _map_size_for(md: MapData) -> String:
	if md == null:
		return "normal"
	var size = str(md.map_size).strip_edges().to_lower()
	if size != "":
		return size
	return "normal"

func _apply_custom_proc_params(md: MapData, params: Dictionary) -> void:
	if md == null or params.is_empty():
		return
	if params.has("map_size"):
		md.map_size = str(params["map_size"])
	if params.has("proc_columns"):
		md.proc_columns = int(params["proc_columns"])
	if params.has("proc_rows"):
		md.proc_rows = int(params["proc_rows"])
	if params.has("proc_forest_ratio"):
		md.proc_forest_ratio = float(params["proc_forest_ratio"])
	if params.has("proc_mountain_ratio"):
		md.proc_mountain_ratio = float(params["proc_mountain_ratio"])
	if params.has("proc_river_ratio"):
		md.proc_river_ratio = float(params["proc_river_ratio"])
	if params.has("proc_lake_ratio"):
		md.proc_lake_ratio = float(params["proc_lake_ratio"])
	if params.has("proc_mine_count"):
		md.proc_mine_count = int(params["proc_mine_count"])
	if params.has("proc_camp_count"):
		md.proc_camp_count = int(params["proc_camp_count"])
	if params.has("proc_dragon_count"):
		md.proc_dragon_count = int(params["proc_dragon_count"])

func _pick_random_map_index(mode: String) -> int:
	if map_data.size() == 0:
		return -1
	var normalized = str(mode).strip_edges().to_lower()
	if normalized == "":
		normalized = "random_normal"
	if normalized == "procedural_custom":
		normalized = "procedural"
	var candidates := []
	for i in range(map_data.size()):
		var md = map_data[i] as MapData
		if md == null:
			continue
		if md.procedural and normalized != "procedural":
			continue
		if normalized == "procedural" and not md.procedural:
			continue
		var cat = _map_category_for(md)
		var size = _map_size_for(md)
		if normalized == "random_themed" and (cat != "themed" or size != "normal"):
			continue
		if normalized == "random_normal" and (cat != "normal" or size != "normal"):
			continue
		if normalized == "random_small" and size != "small":
			continue
		candidates.append(i)
	if candidates.size() == 0:
		return rng.randi_range(0, map_data.size() - 1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]

const SAVE_VERSION: int = 1
const SAVE_DEFAULT_PATH: String = "user://save_game.json"
const SAVE_AUTOSAVE_PATH: String = "user://autosave.json"
const SAVE_SLOT_COUNT: int = 3
const SAVE_MARKER_VEC2I: String = "__gd_vec2i"
const SAVE_MARKER_VEC2: String = "__gd_vec2"
const SAVE_KEY_PREFIX_STR: String = "s:"
const SAVE_KEY_PREFIX_INT: String = "i:"
const SAVE_KEY_PREFIX_VEC2I: String = "v2i:"

func _is_host() -> bool:
	var mp = get_tree().get_multiplayer()
	return mp == null or mp.multiplayer_peer == null or mp.is_server()

func is_host() -> bool:
	return _is_host()

# --- Turn & Phase State ---
var turn_number:   int    = 0
var current_phase: Phase  = Phase.UPKEEP
var current_player:String = "player1"
var exec_steps: Array     = []
var step_index: int       = 0
var neutral_step_index: int = -1
var movement_phase_count: int = 0
const MAX_MOVEMENT_PHASES: int = 20

# --- Economy State ---
var player_gold       := { "player1": 25, "player2": 25 }
var player_income    := { "player1": 0, "player2": 0 }
var player_mana       := { "player1": 0, "player2": 0 }
var player_mana_income := { "player1": 0, "player2": 0 }
var player_mana_cap   := { "player1": 50, "player2": 50 }
const BASE_INCOME    : int = 10
const TOWER_INCOME   : int = 5
const SPECIAL_INCOME : int = 10
const MINER_BONUS    : int = 15
const CRYSTAL_MINER_MANA : int = 5
const BASE_MANA_CAP : int = 50
const MANA_POOL_CAP_BONUS : int = 100
const PHALANX_BONUS     : int = 20
const PHALANX_ADJ_BONUS : int = 2
var state_seq: int = 0
var last_state_seq_applied: int = -1

@export var structure_positions = []

var base_positions := {
	"player1": Vector2i(-1, 15),
	"player2": Vector2i(35, 15)
}

var tower_positions := {
	"player1": [Vector2i(1,4),
				Vector2i(2,7),
				Vector2i(1,10)],
	"player2": [Vector2i(16,4),
				Vector2i(14,7),
				Vector2i(16,10)]
}
var mines := {
	"unclaimed": [],
	"player1": [],
	"player2": []
}

var camps := {
	"basic" : [],
	"dragon": []
}

const NEUTRAL_PLAYER_ID: String = "neutral"
const CAMP_ARCHER_TYPE: String = "camp_archer"
const DRAGON_TYPE: String = "dragon"
const DRAGON_REWARD_GOLD: String = "gold"
const DRAGON_REWARD_MELEE: String = "melee_bonus"
const DRAGON_REWARD_RANGED: String = "ranged_bonus"
const CAMP_RESPAWN_DISPLAY_TURNS: int = 3
const DRAGON_RESPAWN_DISPLAY_TURNS: int = 5

@export var camp_respawn_min: int = 8
@export var camp_respawn_max: int = 12
@export var dragon_respawn_min: int = 14
@export var dragon_respawn_max: int = 20
@export var camp_gold_min: int = 150
@export var camp_gold_max: int = 250
@export var dragon_gold_bonus: int = 1000
@export var dragon_melee_bonus: int = 3
@export var dragon_ranged_bonus: int = 3
@export var camp_archer_range: int = 2
@export var dragon_fire_range: int = 3
@export var dragon_cleave_targets: int = 3

const STRUCT_FORTIFICATION: String = "fortification"
const STRUCT_ROAD: String = "road"
const STRUCT_RAIL: String = "rail"
const STRUCT_TRAP: String = "trap"
const STRUCT_MANA_POOL: String = "mana_pool"
const STRUCT_SPAWN_TOWER: String = "spawn_tower"
const SPAWN_TOWER_ROAD_UNITS := ["scout", "builder", "miner", "crystal_miner", "soldier", "wizard"]

const STRUCT_STATUS_BUILDING: String = "building"
const STRUCT_STATUS_INTACT: String = "intact"
const STRUCT_STATUS_DISABLED: String = "disabled"

const ENGINEERING_PHASE_NAME: String = "Engineering"
const TRAP_DAMAGE: int = 30
const REPAIR_AMOUNT: int = 30
const BUILD_TURNS_SHORT: int = 2
const BUILD_TURNS_TOWER: int = 4
const BUILD_TURNS_MANA_POOL: int = 3
const ROAD_COST_PER_TURN: int = 5
const RAIL_COST_PER_TURN: int = 10
const FORT_COST_PER_TURN: int = 15
const TRAP_COST_PER_TURN: int = 15
const TOWER_COST_PER_TURN: int = 10
const MANA_POOL_COST_PER_TURN: int = 10
@export var mine_road_bonus: int = 10
@export var mine_rail_bonus: int = 20

@export var fort_sprite: Texture2D
@export var road_sprite: Texture2D
@export var rail_sprite: Texture2D
@export var trap_sprite: Texture2D
@export var mana_pool_sprite: Texture2D
@export var spawn_tower_sprite: Texture2D
@export var structure_sprite_scale: float = 1.35

@export var fort_melee_bonus: int = 3
@export var fort_ranged_bonus: int = 3

const TOWER_MELEE_BONUS: int = 3
const TOWER_RANGED_BONUS: int = 3
const TOWER_RANGE_BONUS: int = 1
const SPELL_RANGE: int = 3
const SPELL_COST: int = 30
const SPELL_HEAL_AMOUNT: int = 25
const SPELL_FIREBALL_DAMAGE: int = 30
const SPELL_FIREBALL_STRUCT_DAMAGE: int = 10
const SPELL_BUFF_AMOUNT: int = 5
const SPELL_BUFF_TURNS: int = 1
const SPELL_HEAL: String = "heal"
const SPELL_FIREBALL: String = "fireball"
const SPELL_BUFF: String = "buff"

var camp_units := {}
var dragon_units := {}
var camp_respawns := {}
var dragon_respawns := {}
var camp_respawn_counts := {}
var dragon_rewards := {}
var dragon_spawn_counts := {}
var show_respawn_timers_override: bool = false
var player_melee_bonus := { "player1": 0, "player2": 0 }
var player_ranged_bonus := { "player1": 0, "player2": 0 }
var damage_log := { "player1": [], "player2": [] }

var buildable_structures := {}
var mana_pool_mines := {}
var spawn_tower_positions := { "player1": [], "player2": [] }
var income_tower_positions := { "player1": [], "player2": [] }
var structure_markers := {}
var structure_memory := { "player1": {}, "player2": {} }
var neutral_tile_memory := { "player1": {}, "player2": {} }
var _structure_marker_points: PackedVector2Array = PackedVector2Array()

func _get_terrain_tile_data(cell: Vector2i) -> TileData:
	if terrain_overlay == null:
		return null
	return terrain_overlay.get_cell_tile_data(cell)

func _terrain_bonus(cell: Vector2i, key: String) -> int:
	var td = _get_terrain_tile_data(cell)
	if td == null:
		return 0
	var val = td.get_custom_data(key)
	if val == null:
		return 0
	return int(val)

func _terrain_type(cell: Vector2i) -> String:
	var td = _get_terrain_tile_data(cell)
	if td == null:
		return ""
	var val = td.get_custom_data("terrain")
	return "" if val == null else str(val)

func _is_open_terrain(cell: Vector2i) -> bool:
	var t = _terrain_type(cell)
	if t == "":
		return true
	return not (t in ["forest", "river", "mountain", "lake"])

func _structure_state(cell: Vector2i) -> Dictionary:
	return buildable_structures.get(cell, {})

func _adjacent_mines(cell: Vector2i) -> Array:
	var all_mines: Array = []
	for owner in ["unclaimed", "player1", "player2"]:
		all_mines.append_array(mines.get(owner, []))
	var adj := []
	for neighbor in $GameBoardNode.get_offset_neighbors(cell):
		if neighbor in all_mines:
			adj.append(neighbor)
	return adj

func _reserved_mana_pool_mines(exclude_unit_id: int) -> Dictionary:
	var reserved := {}
	for player in ["player1", "player2"]:
		var orders = player_orders.get(player, {})
		for unit_id in orders.keys():
			if int(unit_id) == exclude_unit_id:
				continue
			var order = orders[unit_id]
			if str(order.get("type", "")) != "build":
				continue
			if str(order.get("structure_type", "")) != STRUCT_MANA_POOL:
				continue
			var mine = order.get("mana_mine", null)
			if typeof(mine) == TYPE_VECTOR2I:
				reserved[mine] = true
	return reserved

func _pick_mana_pool_mine(cell: Vector2i, exclude_unit_id: int = -1) -> Vector2i:
	var candidates = _adjacent_mines(cell)
	if candidates.is_empty():
		return Vector2i(-9999, -9999)
	var used := {}
	for mine in mana_pool_mines.values():
		if typeof(mine) == TYPE_VECTOR2I:
			used[mine] = true
	var reserved = _reserved_mana_pool_mines(exclude_unit_id)
	for mine in reserved.keys():
		used[mine] = true
	candidates.sort_custom(func(a, b): return a.x < b.x if a.y == b.y else a.y < b.y)
	for mine in candidates:
		if not used.has(mine):
			return mine
	return Vector2i(-9999, -9999)

func _clear_mana_pool_assignment(tile: Vector2i) -> void:
	if mana_pool_mines.has(tile):
		mana_pool_mines.erase(tile)

func _rebuild_mana_pool_assignments() -> void:
	mana_pool_mines.clear()
	var pool_tiles := []
	for cell in buildable_structures.keys():
		var state = buildable_structures[cell]
		if str(state.get("type", "")) == STRUCT_MANA_POOL:
			pool_tiles.append(cell)
	pool_tiles.sort_custom(func(a, b): return a.x < b.x if a.y == b.y else a.y < b.y)
	for cell in pool_tiles:
		var state = buildable_structures[cell]
		var mine = state.get("mana_mine", null)
		if typeof(mine) != TYPE_VECTOR2I:
			mine = _pick_mana_pool_mine(cell)
		if typeof(mine) == TYPE_VECTOR2I and mine != Vector2i(-9999, -9999):
			mana_pool_mines[cell] = mine
			state["mana_mine"] = mine
			buildable_structures[cell] = state

func _recalculate_mana_caps() -> void:
	for player in ["player1", "player2"]:
		var pools = 0
		for state in buildable_structures.values():
			if str(state.get("type", "")) != STRUCT_MANA_POOL:
				continue
			if str(state.get("owner", "")) != player:
				continue
			if str(state.get("status", "")) != STRUCT_STATUS_INTACT:
				continue
			pools += 1
		player_mana_cap[player] = BASE_MANA_CAP + pools * MANA_POOL_CAP_BONUS
		if player_mana[player] > player_mana_cap[player]:
			player_mana[player] = player_mana_cap[player]

func _structure_counts_as_road(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	var status = str(state.get("status", ""))
	if status == STRUCT_STATUS_DISABLED:
		return false
	var stype = str(state.get("type", ""))
	if stype == STRUCT_ROAD:
		return status == STRUCT_STATUS_INTACT
	if stype == STRUCT_RAIL:
		return status == STRUCT_STATUS_INTACT or status == STRUCT_STATUS_BUILDING
	return false

func _structure_counts_as_rail(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	var status = str(state.get("status", ""))
	if status == STRUCT_STATUS_DISABLED:
		return false
	var stype = str(state.get("type", ""))
	if stype == STRUCT_RAIL:
		return status == STRUCT_STATUS_INTACT
	return false

func _tile_is_road_or_rail(tile: Vector2i) -> bool:
	var state = _structure_state(tile)
	return _structure_counts_as_road(state) or _structure_counts_as_rail(state)

func _tile_counts_as_road(tile: Vector2i, player_id: String) -> bool:
	if _structure_counts_as_road(_structure_state(tile)):
		return true
	if player_id == "":
		return false
	if base_positions.get(player_id, Vector2i(-9999, -9999)) == tile:
		return true
	if tile in tower_positions.get(player_id, []):
		return true
	return false

func _tile_counts_as_rail(tile: Vector2i, player_id: String) -> bool:
	if _structure_counts_as_rail(_structure_state(tile)):
		return true
	if player_id == "":
		return false
	if base_positions.get(player_id, Vector2i(-9999, -9999)) == tile:
		return true
	if tile in tower_positions.get(player_id, []):
		return true
	return false

func _structure_move_cost(base_cost: float, state: Dictionary) -> float:
	if state.is_empty():
		return base_cost
	var status = str(state.get("status", ""))
	if status == STRUCT_STATUS_DISABLED:
		return base_cost
	var stype = str(state.get("type", ""))
	if stype == STRUCT_ROAD and status == STRUCT_STATUS_INTACT:
		return base_cost * 0.5
	if stype == STRUCT_RAIL and status == STRUCT_STATUS_BUILDING:
		return base_cost * 0.5
	if stype == STRUCT_RAIL and status == STRUCT_STATUS_INTACT:
		return base_cost * 0.25
	return base_cost

func get_structure_move_cost(cell: Vector2i, base_cost: float) -> float:
	return _structure_move_cost(base_cost, _structure_state(cell))

func get_build_turn_cost(struct_type: String) -> int:
	return _structure_turn_cost(struct_type)

func _structure_build_turns(struct_type: String, cell: Vector2i) -> int:
	var turns: int = BUILD_TURNS_SHORT
	if struct_type == STRUCT_SPAWN_TOWER:
		turns = BUILD_TURNS_TOWER
	if struct_type == STRUCT_MANA_POOL:
		turns = BUILD_TURNS_MANA_POOL
	if struct_type in [STRUCT_ROAD, STRUCT_RAIL] and _terrain_type(cell) == "river":
		turns += 1
	return turns

func _structure_turn_cost(struct_type: String) -> int:
	if struct_type == STRUCT_ROAD:
		return ROAD_COST_PER_TURN
	if struct_type == STRUCT_RAIL:
		return RAIL_COST_PER_TURN
	if struct_type == STRUCT_FORTIFICATION:
		return FORT_COST_PER_TURN
	if struct_type == STRUCT_TRAP:
		return TRAP_COST_PER_TURN
	if struct_type == STRUCT_SPAWN_TOWER:
		return TOWER_COST_PER_TURN
	if struct_type == STRUCT_MANA_POOL:
		return MANA_POOL_COST_PER_TURN
	return 0

func _unit_on_friendly_tower(unit) -> bool:
	if unit == null or unit.is_base or unit.is_tower:
		return false
	var tower = $GameBoardNode.get_structure_unit_at(unit.grid_pos)
	if tower == null:
		return false
	return tower.is_tower and tower.player_id == unit.player_id

func _spawn_tower_has_connected_road(tile: Vector2i, player_id: String) -> bool:
	var connected = _connected_road_tiles(player_id)
	if connected.has(tile):
		return true
	for neighbor in $GameBoardNode.get_offset_neighbors(tile):
		if connected.has(neighbor):
			return true
	return false

func _tile_in_spawn_range(tile: Vector2i, origin: Vector2i) -> bool:
	if tile == origin:
		return true
	return tile in $GameBoardNode.get_offset_neighbors(origin)

func _spawn_limit_for_tile(player_id: String, tile: Vector2i) -> String:
	if player_id == "":
		return ""
	var base_pos = base_positions.get(player_id, Vector2i(-9999, -9999))
	if _tile_in_spawn_range(tile, base_pos):
		return "full"
	for tower_pos in tower_positions.get(player_id, []):
		if spawn_tower_positions.has(player_id) and tower_pos in spawn_tower_positions[player_id]:
			continue
		if _tile_in_spawn_range(tile, tower_pos):
			return "full"
	var connected_roads = _connected_road_tiles(player_id)
	var connected_rails = _connected_rail_tiles(player_id)
	var limit = ""
	for spawn_pos in spawn_tower_positions.get(player_id, []):
		if not _tile_in_spawn_range(tile, spawn_pos):
			continue
		var has_rail = false
		for neighbor in $GameBoardNode.get_offset_neighbors(spawn_pos):
			if connected_rails.has(neighbor):
				has_rail = true
				break
		if has_rail:
			return "full"
		var has_road = false
		for neighbor in $GameBoardNode.get_offset_neighbors(spawn_pos):
			if connected_roads.has(neighbor):
				has_road = true
				break
		if has_road:
			limit = "road"
	return limit

func can_spawn_unit_at(player_id: String, unit_type: String, tile: Vector2i) -> bool:
	var limit = _spawn_limit_for_tile(player_id, tile)
	if limit == "":
		return false
	if limit == "road":
		return unit_type.to_lower() in SPAWN_TOWER_ROAD_UNITS
	return true

func _friendly_structure_for_unit(unit) -> Node:
	if unit == null or not is_instance_valid(unit):
		return null
	var structure = $GameBoardNode.get_structure_unit_at(unit.grid_pos)
	if structure == null or not is_instance_valid(structure):
		return null
	if structure.player_id != unit.player_id:
		return null
	if not (structure.is_base or structure.is_tower):
		return null
	return structure

func _get_retaliator_for_target(target):
	if target == null:
		return null
	if not (target.is_base or target.is_tower):
		return target
	var garrison = $GameBoardNode.get_unit_at(target.grid_pos)
	if garrison == null:
		return null
	if garrison.player_id != target.player_id:
		return null
	return garrison

func _retaliation_target_for_attacker(attacker, atk_mode: String) -> Node:
	var structure = _friendly_structure_for_unit(attacker)
	if structure == null:
		return attacker
	if attacker.is_moving:
		return attacker
	if atk_mode == "melee":
		return structure
	return structure

func get_effective_ranged_range(unit) -> int:
	var range = int(unit.ranged_range)
	if _unit_on_friendly_tower(unit):
		range += TOWER_RANGE_BONUS
	return range

func _structure_is_visible_to_viewer(state: Dictionary, viewer_id: String) -> bool:
	if state.is_empty():
		return false
	var stype = str(state.get("type", ""))
	var status = str(state.get("status", ""))
	if stype == STRUCT_TRAP and status == STRUCT_STATUS_INTACT:
		return str(state.get("owner", "")) == viewer_id
	return true

func _structure_is_visible_to_local(state: Dictionary) -> bool:
	return _structure_is_visible_to_viewer(state, local_player_id)

func _structure_marker_color(state: Dictionary) -> Color:
	var stype = str(state.get("type", ""))
	var status = str(state.get("status", ""))
	var color = Color(1, 1, 1, 0.8)
	match stype:
		STRUCT_FORTIFICATION:
			color = Color(0.62, 0.45, 0.25, 0.8)
		STRUCT_ROAD:
			color = Color(0.6, 0.6, 0.6, 0.8)
		STRUCT_RAIL:
			color = Color(0.35, 0.35, 0.35, 0.8)
		STRUCT_TRAP:
			color = Color(0.7, 0.2, 0.7, 0.8)
		STRUCT_MANA_POOL:
			color = Color(0.2, 0.75, 0.85, 0.8)
		STRUCT_SPAWN_TOWER:
			color = Color(0.2, 0.6, 0.9, 0.8)
	if status == STRUCT_STATUS_BUILDING:
		color.a = 0.45
	elif status == STRUCT_STATUS_DISABLED:
		color = color.darkened(0.4)
		color.a = 0.35
	return color

func _structure_sprite_for_state(state: Dictionary) -> Texture2D:
	var stype = str(state.get("type", ""))
	match stype:
		STRUCT_FORTIFICATION:
			return fort_sprite
		STRUCT_ROAD:
			return road_sprite
		STRUCT_RAIL:
			return rail_sprite
		STRUCT_TRAP:
			return trap_sprite
		STRUCT_MANA_POOL:
			return mana_pool_sprite
		STRUCT_SPAWN_TOWER:
			return spawn_tower_sprite
	return null

func _structure_sprite_modulate(state: Dictionary) -> Color:
	var status = str(state.get("status", ""))
	var color = Color(1, 1, 1, 1)
	if status == STRUCT_STATUS_DISABLED:
		color = color.darkened(0.4)
		color.a = 0.35
	return color

func _structure_build_marker_color() -> Color:
	return Color(0.6, 0.6, 0.6, 0.7)

func _structure_display_name(stype: String) -> String:
	match stype:
		STRUCT_FORTIFICATION:
			return "Fort"
		STRUCT_ROAD:
			return "Road"
		STRUCT_RAIL:
			return "Rail"
		STRUCT_TRAP:
			return "Trap"
		STRUCT_MANA_POOL:
			return "Mana Pool"
		STRUCT_SPAWN_TOWER:
			return "Tower"
	return stype.capitalize()

func _structure_build_label(state: Dictionary) -> String:
	var stype = str(state.get("type", ""))
	var name = _structure_display_name(stype)
	var total = int(state.get("build_total", 0))
	var left = int(state.get("build_left", 0))
	if total <= 0:
		return name
	var done = max(total - left, 0)
	return "%s %d/%d" % [name, done, total]

func get_build_hover_text(cell: Vector2i) -> String:
	if local_player_id == "":
		return ""
	var state = _structure_state(cell)
	if state.is_empty():
		return ""
	if str(state.get("status", "")) != STRUCT_STATUS_BUILDING:
		return ""
	if not _structure_is_visible_to_local(state):
		return ""
	var fog = $GameBoardNode/FogOfWar
	if fog != null and fog.visiblity.has(local_player_id):
		var vis = fog.visiblity[local_player_id]
		if int(vis.get(cell, 0)) == 0:
			return ""
	return _structure_build_label(state)

func is_unit_hidden_for_viewer(unit, viewer_id: String) -> bool:
	if unit == null:
		return false
	if viewer_id == "":
		return false
	if current_phase != Phase.ORDERS:
		return false
	if not bool(unit.just_purchased):
		return false
	return unit.player_id != viewer_id

func is_unit_hidden_to_local(unit) -> bool:
	return is_unit_hidden_for_viewer(unit, local_player_id)

func _player_can_see_tile(player_id: String, tile: Vector2i) -> bool:
	if player_id == "":
		return false
	var fog = $GameBoardNode.get_node_or_null("FogOfWar")
	if fog == null or not fog.visiblity.has(player_id):
		return true
	return int(fog.visiblity[player_id].get(tile, 0)) == 2

func _get_structure_marker_points() -> PackedVector2Array:
	if _structure_marker_points.size() > 0:
		return _structure_marker_points
	var tile_size = $GameBoardNode/HexTileMap.tile_size
	var w = tile_size.x * 0.25
	var h = tile_size.y * 0.25
	var dx = w * 0.866
	_structure_marker_points = PackedVector2Array([
		Vector2(0, -h),
		Vector2(dx, -h * 0.5),
		Vector2(dx, h * 0.5),
		Vector2(0, h),
		Vector2(-dx, h * 0.5),
		Vector2(-dx, -h * 0.5)
	])
	return _structure_marker_points

func _get_structure_marker_root() -> Node2D:
	var root = $GameBoardNode/HexTileMap.get_node_or_null("BuildableStructures")
	if root == null:
		root = Node2D.new()
		root.name = "BuildableStructures"
		$GameBoardNode/HexTileMap.add_child(root)
	return root

func _get_structure_memory(player_id: String) -> Dictionary:
	if player_id == "":
		return {}
	if not structure_memory.has(player_id):
		structure_memory[player_id] = {}
	return structure_memory[player_id]

func _get_neutral_tile_memory(player_id: String) -> Dictionary:
	if player_id == "":
		return {}
	if not neutral_tile_memory.has(player_id):
		neutral_tile_memory[player_id] = {}
	return neutral_tile_memory[player_id]

func _spawn_tower_owner_at(cell: Vector2i) -> String:
	for player_id in ["player1", "player2"]:
		if spawn_tower_positions.has(player_id) and cell in spawn_tower_positions[player_id]:
			return player_id
	return ""

func update_structure_memory_for(player_id: String, vis: Dictionary) -> void:
	if player_id == "":
		return
	var memory = _get_structure_memory(player_id)
	for cell in vis.keys():
		if int(vis.get(cell, 0)) != 2:
			continue
		var state = buildable_structures.get(cell, {})
		if state.is_empty():
			var spawn_owner = _spawn_tower_owner_at(cell)
			if spawn_owner != "":
				memory[cell] = {
					"type": STRUCT_SPAWN_TOWER,
					"owner": spawn_owner,
					"status": STRUCT_STATUS_INTACT
				}
			else:
				memory.erase(cell)
			continue
		if _structure_is_visible_to_viewer(state, player_id):
			memory[cell] = state.duplicate(true)
		else:
			memory.erase(cell)

func update_neutral_tile_memory_for(player_id: String, vis: Dictionary) -> void:
	if player_id == "":
		return
	var memory = _get_neutral_tile_memory(player_id)
	for cell in vis.keys():
		if int(vis.get(cell, 0)) != 2:
			continue
		var tile_type := ""
		if cell in camps["basic"]:
			tile_type = "camp"
		elif cell in camps["dragon"]:
			tile_type = "dragon"
		if tile_type == "":
			memory.erase(cell)
			continue
		var entry := { "tile": tile_type }
		if tile_type == "dragon":
			var unit = $GameBoardNode.get_unit_at(cell)
			if unit != null and unit.player_id == "neutral" and str(unit.unit_type) == "dragon":
				entry["unit"] = "dragon"
				var reward = str(dragon_rewards.get(cell, ""))
				if reward == "":
					var spawn_count = int(dragon_spawn_counts.get(cell, 0))
					reward = _dragon_reward_for_pos(cell, spawn_count)
				entry["reward"] = reward
		memory[cell] = entry

func refresh_structure_markers() -> void:
	var root = _get_structure_marker_root()
	for child in root.get_children():
		child.queue_free()
	structure_markers.clear()
	var tile_map = $GameBoardNode/HexTileMap
	var tile_size = tile_map.tile_size
	var fog = $GameBoardNode/FogOfWar
	var vis = {}
	if fog != null and fog.visiblity.has(local_player_id):
		vis = fog.visiblity[local_player_id]
	var memory = _get_structure_memory(local_player_id)
	if vis.size() > 0:
		update_structure_memory_for(local_player_id, vis)
	var draw_states := {}
	for cell in buildable_structures.keys():
		var state = buildable_structures[cell]
		var vis_state = 2
		if vis.size() > 0:
			vis_state = int(vis.get(cell, 0))
			if vis_state == 0:
				continue
		if vis_state == 2:
			if _structure_is_visible_to_local(state):
				draw_states[cell] = state
		else:
			if memory.has(cell):
				draw_states[cell] = memory[cell]
	for cell in memory.keys():
		if draw_states.has(cell):
			continue
		if vis.size() > 0 and int(vis.get(cell, 0)) != 1:
			continue
		draw_states[cell] = memory[cell]
	for cell in draw_states.keys():
		var state = draw_states[cell]
		var marker_root = Node2D.new()
		marker_root.position = tile_map.map_to_world(cell) + tile_size * 0.5
		marker_root.z_index = 6
		root.add_child(marker_root)
		var status = str(state.get("status", ""))
		if status == STRUCT_STATUS_BUILDING:
			var marker = Polygon2D.new()
			marker.polygon = _get_structure_marker_points()
			marker.color = _structure_build_marker_color()
			marker_root.add_child(marker)
		else:
			var sprite = _structure_sprite_for_state(state)
			if sprite != null:
				var marker_sprite = Sprite2D.new()
				marker_sprite.texture = sprite
				var tex_size = sprite.get_size()
				if tex_size.x > 0:
					var scale = (tile_size.x * structure_sprite_scale) / tex_size.x
					marker_sprite.scale = Vector2(scale, scale)
				marker_sprite.modulate = _structure_sprite_modulate(state)
				marker_root.add_child(marker_sprite)
			else:
				var marker = Polygon2D.new()
				marker.polygon = _get_structure_marker_points()
				marker.color = _structure_marker_color(state)
				marker_root.add_child(marker)
		structure_markers[cell] = marker_root

func refresh_mine_tiles() -> void:
	var hex = $GameBoardNode/HexTileMap
	if hex == null:
		return
	for owner in ["unclaimed", "player1", "player2"]:
		var tiles = mines.get(owner, [])
		for pos in tiles:
			hex.set_player_tile(pos, owner)

func _connected_road_tiles(player_id: String) -> Dictionary:
	var connected := {}
	var queue: Array = []
	var starts := []
	if base_positions.has(player_id):
		starts.append(base_positions[player_id])
	for tower_pos in tower_positions.get(player_id, []):
		starts.append(tower_pos)
	for start in starts:
		if _tile_counts_as_road(start, player_id) and not connected.has(start):
			connected[start] = true
			queue.append(start)
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for neighbor in $GameBoardNode.get_offset_neighbors(current):
			if _tile_counts_as_road(neighbor, player_id) and not connected.has(neighbor):
				connected[neighbor] = true
				queue.append(neighbor)
	return connected

func _connected_rail_tiles(player_id: String) -> Dictionary:
	var connected := {}
	var queue: Array = []
	var starts := []
	if base_positions.has(player_id):
		starts.append(base_positions[player_id])
	for tower_pos in tower_positions.get(player_id, []):
		starts.append(tower_pos)
	for start in starts:
		if _tile_counts_as_rail(start, player_id) and not connected.has(start):
			connected[start] = true
			queue.append(start)
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for neighbor in $GameBoardNode.get_offset_neighbors(current):
			if _tile_counts_as_rail(neighbor, player_id) and not connected.has(neighbor):
				connected[neighbor] = true
				queue.append(neighbor)
	return connected

func _mine_connected_to_roads(pos: Vector2i, connected: Dictionary) -> bool:
	if connected.has(pos):
		return true
	for neighbor in $GameBoardNode.get_offset_neighbors(pos):
		if connected.has(neighbor):
			return true
	return false

func get_spawn_points(player_id: String) -> Array:
	var points := []
	for pos in income_tower_positions.get(player_id, []):
		points.append(pos)
	var connected = _connected_road_tiles(player_id)
	for pos in spawn_tower_positions.get(player_id, []):
		for neighbor in $GameBoardNode.get_offset_neighbors(pos):
			if connected.has(neighbor):
				points.append(pos)
				break
	return points

func _special_tile_pid(pos: Vector2i) -> String:
	if pos in camps["basic"]:
		return "camp"
	if pos in camps["dragon"]:
		return "dragon"
	return ""

func _refresh_tile_after_unit_change(tile: Vector2i) -> void:
	var hex = $GameBoardNode/HexTileMap
	if hex == null:
		return
	var special_pid = _special_tile_pid(tile)
	if special_pid != "":
		hex.set_player_tile(tile, special_pid)
		return
	for owner in ["player1", "player2", "unclaimed"]:
		var tiles = mines.get(owner, [])
		if tile in tiles:
			hex.set_player_tile(tile, owner)
			return
	var structure_unit = $GameBoardNode.get_structure_unit_at(tile)
	if structure_unit != null and (structure_unit.is_base or structure_unit.is_tower):
		hex.set_player_tile(tile, structure_unit.player_id)
		return
	hex.set_player_tile(tile, "")

func _get_neutral_marker_root() -> Node2D:
	var root = $GameBoardNode/HexTileMap.get_node_or_null("NeutralMarkers")
	if root == null:
		root = Node2D.new()
		root.name = "NeutralMarkers"
		$GameBoardNode/HexTileMap.add_child(root)
	return root

func _offset_to_cube(cell: Vector2i) -> Vector3i:
	var x = cell.x - (cell.y - (cell.y & 1)) / 2
	var z = cell.y
	var y = -x - z
	return Vector3i(x, y, z)

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac = _offset_to_cube(a)
	var bc = _offset_to_cube(b)
	return int(max(abs(ac.x - bc.x), abs(ac.y - bc.y), abs(ac.z - bc.z)))

func _target_weight(unit, origin: Vector2i) -> float:
	var dist = _hex_distance(origin, unit.grid_pos)
	var hp_ratio = clamp(float(unit.curr_health) / float(unit.max_health), 0.01, 1.0)
	var low_hp_bias = 3.0
	var dist_factor = 1.0 / float(dist + 1)
	var hp_factor = 1.0 + low_hp_bias * (1.0 - hp_ratio)
	return max(0.001, hp_factor * dist_factor)

func _pick_weighted_index(weights: Array) -> int:
	var total = 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return -1
	var roll = rng.randf() * total
	for i in range(weights.size()):
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return weights.size() - 1

func _get_player_units() -> Array:
	var all_units = $GameBoardNode.get_all_units()
	return all_units.get("player1", []) + all_units.get("player2", [])

func _units_in_range(origin: Vector2i, range: int) -> Array:
	var out := []
	for unit in _get_player_units():
		if unit == null:
			continue
		if _hex_distance(origin, unit.grid_pos) <= range:
			out.append(unit)
	return out

func _units_adjacent(origin: Vector2i) -> Array:
	var out := []
	var neighbors: Array = $GameBoardNode.get_offset_neighbors(origin)
	for unit in _get_player_units():
		if unit == null:
			continue
		if unit.grid_pos in neighbors:
			out.append(unit)
	return out

func _positions_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var neighbors: Array = $GameBoardNode.get_offset_neighbors(a)
	return b in neighbors

func _retaliator_can_hit(attacker, retaliator) -> bool:
	if attacker == null or retaliator == null:
		return false
	if not is_instance_valid(attacker) or not is_instance_valid(retaliator):
		return false
	if not retaliator.is_defending:
		return false
	var melee_tiles = $GameBoardNode.get_reachable_tiles(retaliator.grid_pos, 1, "move")["tiles"]
	if attacker.grid_pos in melee_tiles:
		return true
	if retaliator.is_ranged:
		var range = get_effective_ranged_range(retaliator)
		var ranged_tiles = $GameBoardNode.get_reachable_tiles(retaliator.grid_pos, range, "ranged")["tiles"]
		return attacker.grid_pos in ranged_tiles
	return false

func _units_in_range_los(origin: Vector2i, range: int) -> Array:
	var result = $GameBoardNode.get_reachable_tiles(origin, range, "ranged")
	var tiles = result.get("tiles", [])
	var out := []
	for unit in _get_player_units():
		if unit == null:
			continue
		if unit.grid_pos in tiles:
			out.append(unit)
	return out

func _pick_weighted_targets(candidates: Array, origin: Vector2i, count: int) -> Array:
	var pool := candidates.duplicate()
	var picks: int = int(min(count, pool.size()))
	var out := []
	for i in range(picks):
		var weights := []
		for unit in pool:
			weights.append(_target_weight(unit, origin))
		var idx = _pick_weighted_index(weights)
		if idx < 0:
			break
		out.append(pool[idx])
		pool.remove_at(idx)
	return out

func _pick_adjacent_pair(candidates: Array, origin: Vector2i) -> Array:
	var pairs := []
	var weights := []
	for i in range(candidates.size()):
		for j in range(i + 1, candidates.size()):
			var a = candidates[i]
			var b = candidates[j]
			if _hex_distance(a.grid_pos, b.grid_pos) != 1:
				continue
			pairs.append([a, b])
			weights.append(_target_weight(a, origin) * _target_weight(b, origin))
	if pairs.size() == 0:
		return []
	var idx = _pick_weighted_index(weights)
	if idx < 0:
		return []
	return pairs[idx]

func _queue_neutral_attack(attacker, target, atk_mode: String, dmg_map: Dictionary, src_map: Dictionary, ret_map: Dictionary, ret_src_map: Dictionary) -> void:
	if attacker == null or target == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	var dmg_result = calculate_damage(attacker, target, atk_mode, 1)
	var defr_in_dmg = dmg_result[1]
	var ret_dmg = dmg_result[0]
	var retaliator = _get_retaliator_for_target(target)
	var retaliate = _retaliator_can_hit(attacker, retaliator)
	if retaliate and retaliator != target:
		ret_dmg = calculate_damage(attacker, retaliator, atk_mode, 1)[0]
	dmg_map[target.net_id] = dmg_map.get(target.net_id, 0) + defr_in_dmg
	_accumulate_damage_by_player(src_map, target.net_id, attacker.player_id, defr_in_dmg)
	if retaliate:
		ret_map[attacker.net_id] = ret_map.get(attacker.net_id, 0) + ret_dmg
		_accumulate_damage_by_player(ret_src_map, attacker.net_id, retaliator.player_id, ret_dmg)
	dealt_dmg_report(attacker, target, ret_dmg, defr_in_dmg, retaliate, atk_mode)

func _camp_gold_reward(pos: Vector2i) -> int:
	var count = camp_respawn_counts.get(pos, 0)
	var seed = int(pos.x * 73856093) ^ int(pos.y * 19349663) ^ int(count * 83492791)
	var min_val = int(ceil(float(camp_gold_min) / 5.0)) * 5
	var max_val = int(floor(float(camp_gold_max) / 5.0)) * 5
	if max_val < min_val:
		return camp_gold_min
	var steps = int(((max_val - min_val) / 5) + 1)
	return min_val + (abs(seed) % steps) * 5

func _roll_camp_respawn() -> int:
	return rng.randi_range(camp_respawn_min, camp_respawn_max)

func _roll_dragon_respawn() -> int:
	return rng.randi_range(dragon_respawn_min, dragon_respawn_max)

func _reward_report(player_id: String, text: String) -> void:
	if not damage_log.has(player_id):
		damage_log[player_id] = []
	damage_log[player_id].append(text)
	if player_id != local_player_id:
		return
	var report_label = Label.new()
	report_label.text = text
	dmg_report.add_child(report_label)

func _dragon_reward_for_pos(pos: Vector2i, spawn_count: int) -> String:
	var rewards = [DRAGON_REWARD_GOLD, DRAGON_REWARD_MELEE, DRAGON_REWARD_RANGED]
	var seed = int(pos.x * 1259) + int(pos.y * 1931) + int(spawn_count * 83492791) + int(current_map_index + 1) * 104729 + int(NetworkManager.match_seed) * 32452843
	var idx = abs(seed) % rewards.size()
	return rewards[idx]

func _apply_dragon_reward_color(unit, reward: String) -> void:
	match reward:
		DRAGON_REWARD_GOLD:
			unit.modulate = Color(1, 0.84, 0)
		DRAGON_REWARD_MELEE:
			unit.modulate = Color(0.9, 0.35, 0.25)
		DRAGON_REWARD_RANGED:
			unit.modulate = Color(0.35, 0.6, 1)
		_:
			unit.modulate = Color(1, 1, 1)

# --- Orders Data ---
var player_orders     := { "player1": {}, "player2": {} }
var committed_orders := { "player1": {}, "player2": {} }

var local_player_id: String

# --------------------------------------------------------
# Entry point: start the game loop once the scene is ready
# --------------------------------------------------------
func _ready():
	NetworkManager.hex = $GameBoardNode/HexTileMap
	NetworkManager.turn_mgr = $"."
	NetworkManager.connect("map_index_received", Callable(self, "_on_map_index_received"))
	NetworkManager.connect("match_seed_received", Callable(self, "_on_match_seed_received"))
	NetworkManager.connect("state_snapshot_received", Callable(self, "_on_state_snapshot_received"))
	NetworkManager.connect("execution_paused_received", Callable(self, "_on_execution_paused_received"))
	NetworkManager.connect("execution_complete_received", Callable(self, "_on_execution_complete_received"))
	var quit_button = $GameOver.get_node_or_null("QuitToLobbyButton")
	if quit_button != null:
		quit_button.connect("pressed", Callable(self, "_on_game_over_quit_pressed"))
	
	rng.randomize()
	var mp = get_tree().get_multiplayer()
	var has_peer = mp != null and mp.multiplayer_peer != null
	var is_server = (not has_peer) or mp.is_server()
	var map_index = -1
	if is_server:
		if NetworkManager.selected_map_index < 0:
			NetworkManager.selected_map_index = _pick_random_map_index(NetworkManager.map_selection_mode)
		if NetworkManager.match_seed < 0:
			NetworkManager.match_seed = rng.randi_range(1, 2147483646)
		map_index = NetworkManager.selected_map_index
	else:
		if NetworkManager.selected_map_index < 0:
			await NetworkManager.map_index_received
		if NetworkManager.match_seed < 0:
			await NetworkManager.match_seed_received
		map_index = NetworkManager.selected_map_index
	_load_map_by_index(map_index)
	_spawn_neutral_units()
	$GameBoardNode/FogOfWar._update_fog()

func _load_map_by_index(map_index: int) -> void:
	if map_data.size() == 0:
		push_error("TurnManager: map_data is empty.")
		return
	var existing = $GameBoardNode.get_node_or_null("TerrainMap")
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	var idx = int(clamp(map_index, 0, map_data.size() - 1))
	current_map_index = idx
	var md = map_data[idx] as MapData
	md = md.duplicate(true)
	if md.procedural and NetworkManager.custom_proc_params.size() > 0:
		_apply_custom_proc_params(md, NetworkManager.custom_proc_params)
	print("loaded map: ", md.map_name)
	var inst: Node = md.terrain_scene.instantiate()
	var bounds_cells: Array = []
	var bounds_ref = inst.get_node_or_null("UnderlyingReference")
	if bounds_ref != null and bounds_ref is TileMapLayer:
		bounds_cells = (bounds_ref as TileMapLayer).get_used_cells()
	var tmap = inst.get_node_or_null("TerrainMap")
	if tmap == null and inst is TileMapLayer:
		tmap = inst as TileMapLayer
	tmap.name = "TerrainMap"
	tmap.z_index = 5
	tmap.get_parent().remove_child(tmap)
	$GameBoardNode.add_child(tmap)
	terrain_overlay = tmap
	if $GameBoardNode != null:
		$GameBoardNode.terrain_overlay = tmap
	if bounds_cells.is_empty() and tmap != null:
		bounds_cells = tmap.get_used_cells()
	var generated := {}
	if md.procedural:
		var gen_rng = RandomNumberGenerator.new()
		var seed_val = NetworkManager.match_seed
		if seed_val <= 0:
			seed_val = rng.randi_range(1, 2147483646)
		gen_rng.seed = seed_val + idx * 7919
		generated = MapGenerator.generate(md, gen_rng)
		if generated.has("bounds"):
			bounds_cells = generated["bounds"]
	if bounds_cells.size() > 0:
		var hex = $GameBoardNode/HexTileMap
		if hex != null and hex.has_method("apply_bounds"):
			hex.apply_bounds(bounds_cells)
			var fog = $GameBoardNode.get_node_or_null("FogOfWar")
			if fog != null and fog.has_method("reset_fog"):
				fog.reset_fog()
	if md.procedural:
		if tmap != null:
			tmap.clear()
			var forest_src = 1
			var mountain_src = 2
			var river_src = 3
			var lake_src = 4
			var terrain_cells = generated.get("terrain_cells", {})
			for cell in terrain_cells.get("forest", []):
				tmap.set_cell(cell, forest_src, Vector2i(0, 0))
			for cell in terrain_cells.get("mountain", []):
				tmap.set_cell(cell, mountain_src, Vector2i(0, 0))
			for cell in terrain_cells.get("river", []):
				tmap.set_cell(cell, river_src, Vector2i(0, 0))
			for cell in terrain_cells.get("lake", []):
				tmap.set_cell(cell, lake_src, Vector2i(0, 0))
			tmap.update_internals()
		base_positions = generated.get("base_positions", md.base_positions)
		tower_positions = generated.get("tower_positions", md.tower_positions)
		mines = generated.get("mines", md.mines)
		camps = generated.get("camps", md.camps)
	else:
		md.populate_from_terrain(terrain_overlay)
		base_positions = md.base_positions
		tower_positions = md.tower_positions
		mines = md.mines
		camps = md.camps
	var hex_map = $GameBoardNode/HexTileMap
	if hex_map != null:
		for tile in camps.get("basic", []):
			hex_map.set_player_tile(tile, "camp")
		for tile in camps.get("dragon", []):
			hex_map.set_player_tile(tile, "dragon")
	buildable_structures.clear()
	mana_pool_mines.clear()
	spawn_tower_positions = { "player1": [], "player2": [] }
	income_tower_positions = {
		"player1": tower_positions.get("player1", []).duplicate(),
		"player2": tower_positions.get("player2", []).duplicate()
	}
	
	for player in tower_positions.keys():
		for tile in tower_positions[player]:
			structure_positions.append(tile)
			unit_manager.spawn_unit("tower", tile, player, false)
	for player in base_positions.keys():
		var tile = base_positions[player]
		structure_positions.append(tile)
		unit_manager.spawn_unit("base", tile, player, false)
	for tile in mines["unclaimed"]:
		structure_positions.append(tile)
		$GameBoardNode/HexTileMap.set_player_tile(tile, "unclaimed")
		tmap.set_cell(tile)
		var mine = MineScene.instantiate() as Sprite2D
		mine.position = $GameBoardNode/HexTileMap.map_to_world(tile) + $GameBoardNode/HexTileMap.tile_size * 0.5
		mine.z_index = 6
		mine.grid_pos = tile
		$GameBoardNode/HexTileMap/Structures.add_child(mine)
		$GameBoardNode.set_structure_at(tile, mine)

func _serialize_unit(unit) -> Dictionary:
	return {
		"net_id": unit.net_id,
		"player_id": unit.player_id,
		"unit_type": unit.unit_type,
		"grid_pos": unit.grid_pos,
		"curr_health": unit.curr_health,
		"max_health": unit.max_health,
		"is_defending": unit.is_defending,
		"is_healing": unit.is_healing,
		"auto_heal": unit.auto_heal,
		"auto_defend": unit.auto_defend,
		"auto_build": unit.auto_build,
		"auto_build_type": unit.auto_build_type,
		"build_queue": unit.build_queue,
		"build_queue_type": unit.build_queue_type,
		"build_queue_last_type": unit.build_queue_last_type,
		"build_queue_last_target": unit.build_queue_last_target,
		"build_queue_last_build_left": unit.build_queue_last_build_left,
		"move_queue": unit.move_queue,
		"move_queue_last_target": unit.move_queue_last_target,
		"is_moving": unit.is_moving,
		"is_looking_out": unit.is_looking_out,
		"moving_to": unit.moving_to,
		"just_purchased": unit.just_purchased,
		"first_turn_move": unit.first_turn_move,
		"ordered": unit.ordered,
		"last_damaged_by": unit.last_damaged_by,
		"spell_buff_melee": unit.spell_buff_melee,
		"spell_buff_ranged": unit.spell_buff_ranged,
		"spell_buff_turns": unit.spell_buff_turns
	}

func _encode_key(key) -> String:
	var t = typeof(key)
	if t == TYPE_STRING:
		return SAVE_KEY_PREFIX_STR + key
	if t == TYPE_INT:
		return SAVE_KEY_PREFIX_INT + str(key)
	if t == TYPE_VECTOR2I:
		return SAVE_KEY_PREFIX_VEC2I + str(key.x) + "," + str(key.y)
	return SAVE_KEY_PREFIX_STR + str(key)

func _decode_key(key: String):
	if key.begins_with(SAVE_KEY_PREFIX_STR):
		return key.substr(SAVE_KEY_PREFIX_STR.length())
	if key.begins_with(SAVE_KEY_PREFIX_INT):
		return int(key.substr(SAVE_KEY_PREFIX_INT.length()))
	if key.begins_with(SAVE_KEY_PREFIX_VEC2I):
		var coords = key.substr(SAVE_KEY_PREFIX_VEC2I.length()).split(",")
		if coords.size() >= 2:
			return Vector2i(int(coords[0]), int(coords[1]))
		return Vector2i.ZERO
	return key

func _encode_value(value):
	var t = typeof(value)
	if t == TYPE_VECTOR2I:
		return { SAVE_MARKER_VEC2I: [value.x, value.y] }
	if t == TYPE_VECTOR2:
		return { SAVE_MARKER_VEC2: [value.x, value.y] }
	if t == TYPE_DICTIONARY:
		var out := {}
		for k in value.keys():
			out[_encode_key(k)] = _encode_value(value[k])
		return out
	if t == TYPE_ARRAY:
		var arr := []
		for v in value:
			arr.append(_encode_value(v))
		return arr
	return value

func _decode_value(value):
	var t = typeof(value)
	if t == TYPE_DICTIONARY:
		if value.size() == 1 and value.has(SAVE_MARKER_VEC2I):
			var vec = value[SAVE_MARKER_VEC2I]
			if vec is Array and vec.size() >= 2:
				return Vector2i(int(vec[0]), int(vec[1]))
		if value.size() == 1 and value.has(SAVE_MARKER_VEC2):
			var v = value[SAVE_MARKER_VEC2]
			if v is Array and v.size() >= 2:
				return Vector2(float(v[0]), float(v[1]))
		var out := {}
		for k in value.keys():
			var decoded_key = k
			if k is String:
				decoded_key = _decode_key(k)
			out[decoded_key] = _decode_value(value[k])
		return out
	if t == TYPE_ARRAY:
		var arr := []
		for v in value:
			arr.append(_decode_value(v))
		return arr
	return value

func _collect_state() -> Dictionary:
	var units := []
	for unit in $GameBoardNode.get_all_units_flat():
		if unit == null:
			continue
		units.append(_serialize_unit(unit))
	return {
		"state_seq": state_seq,
		"map_index": current_map_index,
		"match_seed": NetworkManager.match_seed,
		"turn_number": turn_number,
		"current_phase": int(current_phase),
		"current_player": current_player,
		"player_gold": player_gold,
		"player_income": player_income,
		"player_mana": player_mana,
		"player_mana_income": player_mana_income,
		"player_mana_cap": player_mana_cap,
		"player_melee_bonus": player_melee_bonus,
		"player_ranged_bonus": player_ranged_bonus,
		"camp_respawns": camp_respawns,
		"dragon_respawns": dragon_respawns,
		"camp_respawn_counts": camp_respawn_counts,
		"dragon_rewards": dragon_rewards,
		"dragon_spawn_counts": dragon_spawn_counts,
		"camps": camps,
		"mines": mines,
		"structure_positions": structure_positions,
		"buildable_structures": buildable_structures,
		"mana_pool_mines": mana_pool_mines,
		"structure_memory": structure_memory,
		"neutral_tile_memory": neutral_tile_memory,
		"spawn_tower_positions": spawn_tower_positions,
		"income_tower_positions": income_tower_positions,
		"base_positions": base_positions,
		"tower_positions": tower_positions,
		"neutral_step_index": neutral_step_index,
		"committed_orders": committed_orders,
		"units": units,
		"damage_log": damage_log
	}

func get_state_snapshot(bump_seq: bool = false) -> Dictionary:
	if bump_seq:
		state_seq += 1
	return _collect_state()

func _collect_state_for(viewer_id: String) -> Dictionary:
	var state = _collect_state()
	if viewer_id == "":
		return state
	if current_phase != Phase.ORDERS:
		return state
	var filtered := []
	for data in state.get("units", []):
		var owner = str(data.get("player_id", ""))
		var just_purchased = bool(data.get("just_purchased", false))
		if just_purchased and owner != viewer_id:
			continue
		filtered.append(data)
	state["units"] = filtered
	var viewer_orders := {}
	viewer_orders[viewer_id] = player_orders.get(viewer_id, {}).duplicate(true)
	state["player_orders"] = viewer_orders
	var fog = $GameBoardNode.get_node_or_null("FogOfWar")
	if fog != null and fog.visiblity.has(viewer_id):
		state["fog_visibility"] = { viewer_id: fog.visiblity[viewer_id].duplicate(true) }
	return state

func get_state_snapshot_for(viewer_id: String, bump_seq: bool = false) -> Dictionary:
	if bump_seq:
		state_seq += 1
	return _collect_state_for(viewer_id)

func _save_path_for_slot(slot: int) -> String:
	if slot < 0:
		return SAVE_AUTOSAVE_PATH
	if slot >= SAVE_SLOT_COUNT:
		slot = SAVE_SLOT_COUNT - 1
	return "user://save_slot_%d.json" % (slot + 1)

func save_game(path: String = SAVE_DEFAULT_PATH, allow_non_orders: bool = false) -> bool:
	if not _is_host():
		push_error("Save failed: host only.")
		return false
	if current_phase != Phase.ORDERS and not allow_non_orders:
		push_error("Save failed: only supported during the orders phase.")
		return false
	var state = _collect_state()
	var fog = $GameBoardNode.get_node_or_null("FogOfWar")
	if fog != null:
		state["fog_visibility"] = fog.visiblity.duplicate(true)
	var payload = {
		"save_version": SAVE_VERSION,
		"state": _encode_value(state)
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: could not open file %s" % path)
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	return true

func save_game_slot(slot: int, allow_non_orders: bool = false) -> bool:
	return save_game(_save_path_for_slot(slot), allow_non_orders)

func load_game(path: String = SAVE_DEFAULT_PATH) -> bool:
	if not _is_host():
		push_error("Load failed: host only.")
		return false
	if not FileAccess.file_exists(path):
		push_error("Load failed: file not found %s" % path)
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Load failed: could not open file %s" % path)
		return false
	var content = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Load failed: invalid save format.")
		return false
	var payload = parsed as Dictionary
	var version = int(payload.get("save_version", 0))
	if version != SAVE_VERSION:
		push_error("Load failed: unsupported save version.")
		return false
	var state = _decode_value(payload.get("state", {}))
	if typeof(state) != TYPE_DICTIONARY or state.is_empty():
		push_error("Load failed: missing state data.")
		return false
	state["force_apply"] = true
	var phase = int(state.get("current_phase", int(Phase.ORDERS)))
	if phase != int(Phase.ORDERS):
		push_error("Load failed: only orders-phase saves are supported.")
		return false
	var map_index = int(state.get("map_index", 0))
	var match_seed = int(state.get("match_seed", -1))
	NetworkManager.selected_map_index = map_index
	if match_seed > 0:
		NetworkManager.match_seed = match_seed
	_reset_map_state()
	_load_map_by_index(map_index)
	apply_state(state, true)
	call_deferred("_refresh_fog_after_load")
	NetworkManager._orders_submitted = { "player1": false, "player2": false }
	NetworkManager._step_ready_counts = {}
	_broadcast_state(true)
	call_deferred("_broadcast_state", true)
	return true

func load_game_slot(slot: int) -> bool:
	return load_game(_save_path_for_slot(slot))

func _refresh_fog_after_load() -> void:
	var fog = $GameBoardNode.get_node_or_null("FogOfWar")
	if fog != null:
		fog._update_fog()

func _broadcast_state(force_apply: bool = false) -> void:
	if not _is_host():
		return
	var state = get_state_snapshot(true)
	if force_apply:
		state["force_apply"] = true
	NetworkManager.broadcast_state(state)

func _clear_units_only() -> void:
	var hex = $GameBoardNode/HexTileMap
	for tile in $GameBoardNode.occupied_tiles.keys():
		var special_pid = _special_tile_pid(tile)
		if special_pid != "":
			hex.set_player_tile(tile, special_pid)
		elif not $GameBoardNode.structure_tiles.has(tile):
			hex.set_player_tile(tile, "")
	for child in unit_manager.get_children():
		if child != null and (child.is_base or child.is_tower):
			$GameBoardNode.structure_tiles.erase(child.grid_pos)
		child.queue_free()
	unit_manager.unit_by_net_id.clear()
	$GameBoardNode.occupied_tiles.clear()
	$GameBoardNode.structure_units.clear()

func _apply_units(units_data: Array) -> void:
	_clear_units_only()
	var max_odd = 1
	var max_even = 2
	var max_neutral = 1000001
	for data in units_data:
		var unit = unit_manager.spawn_unit(
			data.get("unit_type", ""),
			data.get("grid_pos", Vector2i.ZERO),
			data.get("player_id", ""),
			false,
			int(data.get("net_id", -1))
		)
		if unit == null:
			continue
		unit.curr_health = int(data.get("curr_health", unit.curr_health))
		unit.max_health = int(data.get("max_health", unit.max_health))
		unit.is_defending = bool(data.get("is_defending", false))
		unit.is_healing = bool(data.get("is_healing", false))
		unit.auto_heal = bool(data.get("auto_heal", false))
		unit.auto_defend = bool(data.get("auto_defend", false))
		unit.auto_build = bool(data.get("auto_build", false))
		unit.auto_build_type = str(data.get("auto_build_type", ""))
		var queue_data = data.get("build_queue", [])
		unit.build_queue = queue_data if queue_data is Array else []
		unit.build_queue_type = str(data.get("build_queue_type", ""))
		unit.build_queue_last_type = str(data.get("build_queue_last_type", ""))
		var last_target = data.get("build_queue_last_target", Vector2i(-9999, -9999))
		unit.build_queue_last_target = last_target if typeof(last_target) == TYPE_VECTOR2I else Vector2i(-9999, -9999)
		unit.build_queue_last_build_left = int(data.get("build_queue_last_build_left", -1))
		var move_queue_data = data.get("move_queue", [])
		unit.move_queue = move_queue_data if move_queue_data is Array else []
		var move_last_target = data.get("move_queue_last_target", Vector2i(-9999, -9999))
		unit.move_queue_last_target = move_last_target if typeof(move_last_target) == TYPE_VECTOR2I else Vector2i(-9999, -9999)
		unit.is_moving = bool(data.get("is_moving", false))
		unit.is_looking_out = bool(data.get("is_looking_out", false))
		unit.moving_to = data.get("moving_to", unit.grid_pos)
		unit.just_purchased = bool(data.get("just_purchased", false))
		unit.first_turn_move = bool(data.get("first_turn_move", false))
		unit.ordered = bool(data.get("ordered", false))
		unit.last_damaged_by = data.get("last_damaged_by", "")
		unit.spell_buff_melee = int(data.get("spell_buff_melee", 0))
		unit.spell_buff_ranged = int(data.get("spell_buff_ranged", 0))
		unit.spell_buff_turns = int(data.get("spell_buff_turns", 0))
		unit.set_health_bar()
		if unit.is_tower and spawn_tower_positions.has(unit.player_id):
			if unit.grid_pos in spawn_tower_positions[unit.player_id]:
				unit.is_spawn_tower = true
				if unit.has_method("_update_owner_overlay"):
					unit._update_owner_overlay()
		if str(unit.unit_type) == DRAGON_TYPE:
			var reward = dragon_rewards.get(unit.grid_pos, "")
			if reward == "" and dragon_spawn_counts.has(unit.grid_pos):
				var count = int(dragon_spawn_counts.get(unit.grid_pos, 1)) - 1
				reward = _dragon_reward_for_pos(unit.grid_pos, max(count, 0))
			_apply_dragon_reward_color(unit, reward)
		var net_id = int(unit.net_id)
		if unit.player_id == "player1":
			max_odd = max(max_odd, net_id)
		elif unit.player_id == "player2":
			max_even = max(max_even, net_id)
		else:
			max_neutral = max(max_neutral, net_id)
	unit_manager._next_net_id_odd = max_odd + 2
	unit_manager._next_net_id_even = max_even + 2
	unit_manager._next_net_id_neutral = max_neutral + 1

func _on_state_snapshot_received(state: Dictionary) -> void:
	apply_state(state)

func _on_execution_paused_received(step_idx: int, neutral_step_idx: int) -> void:
	if _is_host():
		return
	neutral_step_index = neutral_step_idx
	emit_signal("execution_paused", step_idx)

func _on_execution_complete_received() -> void:
	if _is_host():
		return
	emit_signal("execution_complete")

func apply_state(state: Dictionary, force_host: bool = false) -> void:
	if _is_host() and not force_host:
		return
	if state.is_empty():
		return
	var incoming_seq = int(state.get("state_seq", -1))
	var force_apply = bool(state.get("force_apply", false))
	if incoming_seq >= 0:
		if not force_apply and incoming_seq <= last_state_seq_applied:
			return
		last_state_seq_applied = incoming_seq
		state_seq = max(state_seq, incoming_seq)
	var map_index = int(state.get("map_index", current_map_index))
	var match_seed = int(state.get("match_seed", NetworkManager.match_seed))
	if match_seed > 0:
		NetworkManager.match_seed = match_seed
	if map_index != current_map_index:
		_reset_map_state()
		_load_map_by_index(map_index)
	if state.has("base_positions"):
		base_positions = state["base_positions"]
	if state.has("tower_positions"):
		tower_positions = state["tower_positions"]
	if state.has("structure_positions"):
		structure_positions = state["structure_positions"]
	if state.has("buildable_structures"):
		buildable_structures = state["buildable_structures"]
	if state.has("mana_pool_mines"):
		mana_pool_mines = state["mana_pool_mines"]
	else:
		_rebuild_mana_pool_assignments()
	if state.has("structure_memory"):
		structure_memory = state["structure_memory"]
	if state.has("neutral_tile_memory"):
		neutral_tile_memory = state["neutral_tile_memory"]
	if state.has("spawn_tower_positions"):
		spawn_tower_positions = state["spawn_tower_positions"]
	if state.has("income_tower_positions"):
		income_tower_positions = state["income_tower_positions"]
	if state.has("camps"):
		camps = state["camps"]
	if state.has("mines"):
		mines = state["mines"]
	turn_number = int(state.get("turn_number", turn_number))
	current_phase = int(state.get("current_phase", int(current_phase)))
	current_player = state.get("current_player", current_player)
	player_gold = state.get("player_gold", player_gold)
	player_income = state.get("player_income", player_income)
	player_mana = state.get("player_mana", player_mana)
	player_mana_income = state.get("player_mana_income", player_mana_income)
	player_mana_cap = state.get("player_mana_cap", player_mana_cap)
	player_melee_bonus = state.get("player_melee_bonus", player_melee_bonus)
	player_ranged_bonus = state.get("player_ranged_bonus", player_ranged_bonus)
	camp_respawns = state.get("camp_respawns", camp_respawns)
	dragon_respawns = state.get("dragon_respawns", dragon_respawns)
	camp_respawn_counts = state.get("camp_respawn_counts", camp_respawn_counts)
	dragon_rewards = state.get("dragon_rewards", dragon_rewards)
	dragon_spawn_counts = state.get("dragon_spawn_counts", dragon_spawn_counts)
	damage_log = state.get("damage_log", damage_log)
	neutral_step_index = int(state.get("neutral_step_index", neutral_step_index))
	_apply_units(state.get("units", []))
	player_orders = { "player1": {}, "player2": {} }
	if state.has("player_orders"):
		var incoming_orders = state["player_orders"]
		if incoming_orders is Dictionary:
			for pid in incoming_orders.keys():
				player_orders[pid] = incoming_orders[pid]
	NetworkManager.player_orders = player_orders
	committed_orders = state.get("committed_orders", { "player1": {}, "player2": {} })
	_recalculate_mana_caps()
	_prune_dead_units_after_apply()
	if state.has("fog_visibility"):
		var fog = $GameBoardNode.get_node_or_null("FogOfWar")
		var fog_data = state["fog_visibility"]
		if fog != null and fog_data is Dictionary:
			if fog.visiblity == null or fog.visiblity.is_empty():
				fog.reset_fog()
			for pid in fog_data.keys():
				if fog_data[pid] is Dictionary:
					fog.visiblity[pid] = fog_data[pid].duplicate(true)
	$GameBoardNode/FogOfWar._update_fog()
	update_neutral_markers()
	refresh_structure_markers()
	refresh_mine_tiles()
	_render_damage_log_for_local()
	emit_signal("state_applied")

func _reset_map_state() -> void:
	if terrain_overlay != null:
		if is_instance_valid(terrain_overlay):
			var parent = terrain_overlay.get_parent()
			if parent != null:
				parent.remove_child(terrain_overlay)
			terrain_overlay.free()
		terrain_overlay = null
		if $GameBoardNode != null:
			$GameBoardNode.terrain_overlay = null
	var fog = $GameBoardNode.get_node_or_null("FogOfWar")
	if fog != null and fog.has_method("reset_fog"):
		fog.reset_fog()
	var hex = $GameBoardNode/HexTileMap
	var src = hex.tile_set.get_source_id(0)
	for cell in hex.get_used_cells():
		hex.set_cell(cell, src, hex.ground_tile)
	hex.update_internals()
	var structures = $GameBoardNode/HexTileMap.get_node_or_null("Structures")
	if structures != null:
		for child in structures.get_children():
			child.queue_free()
	var build_root = $GameBoardNode/HexTileMap.get_node_or_null("BuildableStructures")
	if build_root != null:
		for child in build_root.get_children():
			child.queue_free()
	structure_positions.clear()
	$GameBoardNode.structure_units.clear()
	buildable_structures.clear()
	spawn_tower_positions = { "player1": [], "player2": [] }
	income_tower_positions = { "player1": [], "player2": [] }
	structure_markers.clear()
	structure_memory = { "player1": {}, "player2": {} }
	neutral_tile_memory = { "player1": {}, "player2": {} }
	camps = {"basic": [], "dragon": []}
	mines = {"unclaimed": [], "player1": [], "player2": []}
	camp_units.clear()
	dragon_units.clear()
	camp_respawns.clear()
	dragon_respawns.clear()
	camp_respawn_counts.clear()
	dragon_rewards.clear()
	dragon_spawn_counts.clear()
	$GameBoardNode.occupied_tiles.clear()
	$GameBoardNode.structure_tiles.clear()
	for child in unit_manager.get_children():
		child.queue_free()
	unit_manager.unit_by_net_id.clear()
	unit_manager._next_net_id_odd = 1
	unit_manager._next_net_id_even = 2
	unit_manager._next_net_id_neutral = 1000001

func _on_map_index_received(map_index: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp != null and mp.multiplayer_peer != null and mp.is_server():
		return
	if current_map_index == -1:
		return
	if map_index == current_map_index:
		return
	_reset_map_state()
	_load_map_by_index(map_index)
	_spawn_neutral_units()
	$GameBoardNode/FogOfWar._update_fog()

func _on_match_seed_received(seed_value: int) -> void:
	var mp = get_tree().get_multiplayer()
	if mp != null and mp.multiplayer_peer != null and mp.is_server():
		return
	if seed_value == NetworkManager.match_seed:
		return
	NetworkManager.match_seed = seed_value

func _spawn_camp_at(pos: Vector2i) -> Node:
	var unit = unit_manager.spawn_unit(CAMP_ARCHER_TYPE, pos, NEUTRAL_PLAYER_ID, false)
	if unit == null:
		return null
	unit.is_defending = false
	unit.just_purchased = false
	camp_units[pos] = unit
	if not camp_respawn_counts.has(pos):
		camp_respawn_counts[pos] = 0
	return unit

func _spawn_dragon_at(pos: Vector2i) -> Node:
	var unit = unit_manager.spawn_unit(DRAGON_TYPE, pos, NEUTRAL_PLAYER_ID, false)
	if unit == null:
		return null
	unit.is_defending = false
	unit.just_purchased = false
	var spawn_count = dragon_spawn_counts.get(pos, 0)
	var reward = _dragon_reward_for_pos(pos, spawn_count)
	dragon_spawn_counts[pos] = spawn_count + 1
	dragon_rewards[pos] = reward
	_apply_dragon_reward_color(unit, reward)
	dragon_units[pos] = unit
	return unit

func _spawn_neutral_units() -> void:
	for pos in camps["basic"]:
		if camp_units.has(pos):
			continue
		if camp_respawns.has(pos):
			continue
		_spawn_camp_at(pos)
	for pos in camps["dragon"]:
		if dragon_units.has(pos):
			continue
		if dragon_respawns.has(pos):
			continue
		_spawn_dragon_at(pos)
	update_neutral_markers()

func _tick_neutral_respawns() -> void:
	var camp_positions = camp_respawns.keys()
	camp_positions.sort()
	for pos in camp_positions:
		if $GameBoardNode.is_occupied(pos):
			camp_respawns[pos] = _roll_camp_respawn()
			continue
		camp_respawns[pos] -= 1
		if camp_respawns[pos] <= 0:
			camp_respawns.erase(pos)
			_spawn_camp_at(pos)
	var dragon_positions = dragon_respawns.keys()
	dragon_positions.sort()
	for pos in dragon_positions:
		if $GameBoardNode.is_occupied(pos):
			dragon_respawns[pos] = _roll_dragon_respawn()
			continue
		dragon_respawns[pos] -= 1
		if dragon_respawns[pos] <= 0:
			dragon_respawns.erase(pos)
			_spawn_dragon_at(pos)
	update_neutral_markers()

func start_game() -> void:
	call_deferred("_game_loop")

func update_neutral_markers() -> void:
	var root = _get_neutral_marker_root()
	for child in root.get_children():
		child.queue_free()
	var fog = $GameBoardNode/FogOfWar
	var vis = {}
	if fog != null and fog.visiblity.has(local_player_id):
		vis = fog.visiblity[local_player_id]
	for pos in camp_respawns.keys():
		if vis.get(pos, 0) == 2 and not $GameBoardNode.is_occupied(pos):
			if show_respawn_timers_override or camp_respawns[pos] <= CAMP_RESPAWN_DISPLAY_TURNS:
				_add_neutral_marker(root, pos, str(camp_respawns[pos]))
	for pos in dragon_respawns.keys():
		if vis.get(pos, 0) == 2 and not $GameBoardNode.is_occupied(pos):
			if show_respawn_timers_override or dragon_respawns[pos] <= DRAGON_RESPAWN_DISPLAY_TURNS:
				_add_neutral_marker(root, pos, str(dragon_respawns[pos]))

func set_respawn_timer_override(enabled: bool) -> void:
	show_respawn_timers_override = enabled
	update_neutral_markers()

func _add_neutral_marker(root: Node2D, pos: Vector2i, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 36)
	label.position = $GameBoardNode/HexTileMap.map_to_world(pos) + $GameBoardNode/HexTileMap.tile_size * 0.35
	label.z_index = 101
	root.add_child(label)

func _show_game_over(player_id: String) -> void:
	$GameOver/GameOverLabel.add_theme_font_size_override("font_size", 100)
	$GameOver/GameOverLabel.text = "%s lost!" % player_id
	$GameOver.visible = true
	$UI.visible = false

func _on_game_over_quit_pressed() -> void:
	if has_node("UI") and $UI.has_method("_on_cancel_game_pressed"):
		$UI.visible = true
		$UI._on_cancel_game_pressed()
	else:
		reset_to_lobby()

func end_game(player_id: String) -> void:
	_show_game_over(player_id)
	if _is_host():
		NetworkManager.broadcast_game_over(player_id)
	print("the game has ended")

func reset_to_lobby() -> void:
	_reset_map_state()
	current_map_index = -1
	turn_number = 0
	current_phase = Phase.UPKEEP
	current_player = "player1"
	exec_steps = []
	step_index = 0
	neutral_step_index = -1
	player_gold = { "player1": 25, "player2": 25 }
	player_income = { "player1": 0, "player2": 0 }
	player_mana = { "player1": 0, "player2": 0 }
	player_mana_income = { "player1": 0, "player2": 0 }
	player_mana_cap = { "player1": BASE_MANA_CAP, "player2": BASE_MANA_CAP }
	player_melee_bonus = { "player1": 0, "player2": 0 }
	player_ranged_bonus = { "player1": 0, "player2": 0 }
	damage_log = { "player1": [], "player2": [] }
	player_orders = { "player1": {}, "player2": {} }
	committed_orders = { "player1": {}, "player2": {} }
	local_player_id = ""
	if NetworkManager != null:
		NetworkManager.selected_map_index = -1
		NetworkManager.match_seed = -1
		NetworkManager.custom_proc_params = {}
		NetworkManager.player_orders = player_orders
		NetworkManager._orders_submitted = { "player1": false, "player2": false }
		NetworkManager._step_ready_counts = {}
	$UI/DamagePanel.visible = false
	$GameOver.visible = false

# --------------------------------------------------------
# Main loop: Upkeep → Orders → Execution → increment → loop
# --------------------------------------------------------
func _game_loop() -> void:
	_ensure_map_loaded()
	turn_number += 1
	print("\n===== TURN %d =====" % turn_number)
	rng.seed = turn_number
	save_game_slot(-1, true)
	NetworkManager._orders_submitted = { "player1": false, "player2": false }
	player_orders = NetworkManager.player_orders
	NetworkManager.broadcast_phase("UPKEEP")
	start_phase_locally("UPKEEP")
	NetworkManager.broadcast_phase("ORDERS")
	await _do_orders()
	player_orders = NetworkManager.player_orders
	NetworkManager.broadcast_phase("EXECUTION")
	_do_execution()

func _ensure_map_loaded() -> void:
	if current_map_index >= 0 and terrain_overlay != null:
		return
	if map_data.size() == 0:
		push_error("TurnManager: map_data is empty.")
		return
	var map_rng := RandomNumberGenerator.new()
	map_rng.randomize()
	if NetworkManager.selected_map_index < 0:
		NetworkManager.selected_map_index = _pick_random_map_index(NetworkManager.map_selection_mode)
	if NetworkManager.match_seed < 0:
		NetworkManager.match_seed = map_rng.randi_range(1, 2147483646)
	var map_index = NetworkManager.selected_map_index
	_load_map_by_index(map_index)
	_spawn_neutral_units()
	$GameBoardNode/FogOfWar._update_fog()

# --------------------------------------------------------
# Phase 1: Upkeep — award gold
# --------------------------------------------------------
func _do_upkeep() -> void:
	$UI/CancelGameButton.visible = false
	current_phase = Phase.UPKEEP
	NetworkManager._step_ready_counts = {}
	print("--- Upkeep Phase ---")
	_recalculate_mana_caps()
	for player in ["player1", "player2"]:
		var income = 0
		var mana_income = 0
		var connected_roads = _connected_road_tiles(player)
		var connected_rails = _connected_rail_tiles(player)
		if _controls_tile(player, base_positions[player]):
			income += BASE_INCOME
		for tower in income_tower_positions.get(player, []):
			income += TOWER_INCOME
		for pos in mines[player]:
			if _controls_tile(player, pos):
				if $GameBoardNode.is_occupied(pos):
					var occupant = $GameBoardNode.get_unit_at(pos)
					if occupant != null and occupant.is_miner:
						income += MINER_BONUS
					if occupant != null and occupant.is_crystal_miner:
						mana_income += CRYSTAL_MINER_MANA
				income += SPECIAL_INCOME
				if mine_rail_bonus > 0 and _mine_connected_to_roads(pos, connected_rails):
					income += mine_rail_bonus
				elif mine_road_bonus > 0 and _mine_connected_to_roads(pos, connected_roads):
					income += mine_road_bonus
		player_gold[player] += income
		player_income[player] = income
		player_mana[player] = min(player_mana_cap[player], player_mana[player] + mana_income)
		player_mana_income[player] = mana_income
		print("%s income: %d  → total gold: %d" % [player.capitalize(), income, player_gold[player]])
	
	# reset orders and unit states
	$UI._clear_all_drawings()
	$GameBoardNode/FogOfWar._update_fog()
	var all_units = $GameBoardNode.get_all_units()
	for p in ["player1", "player2"]:
		player_orders[p].clear()
		if NetworkManager.player_orders.has(p):
			NetworkManager.player_orders[p].clear()
		for unit in all_units[p]:
			unit.is_defending = false
			unit.just_purchased = false
			unit.ordered = false
			unit.is_moving = false
			if unit.spell_buff_turns > 0:
				unit.spell_buff_turns -= 1
				if unit.spell_buff_turns <= 0:
					unit.spell_buff_melee = 0
					unit.spell_buff_ranged = 0
			if unit.is_healing:
				unit.curr_health += unit.regen
				unit.set_health_bar()
				unit.is_healing = false
			if unit.auto_heal and unit.curr_health >= unit.max_health:
				unit.auto_heal = false
	for unit in all_units.get("neutral", []):
		unit.is_defending = false
		unit.is_moving = false
	_apply_auto_heal_orders(all_units)
	_apply_auto_defend_orders(all_units)
	_apply_auto_build_orders(all_units)
	_apply_build_queue_orders(all_units)
	_apply_move_queue_orders(all_units)
	_tick_neutral_respawns()
	$GameBoardNode/FogOfWar._update_fog()
	$UI/DamagePanel.visible = true
	$GameBoardNode/OrderReminderMap.highlight_unordered_units(local_player_id)
	_broadcast_state()

func _apply_auto_heal_orders(all_units: Dictionary) -> void:
	for player in ["player1", "player2"]:
		if not all_units.has(player):
			continue
		var orders = player_orders.get(player, {})
		if not NetworkManager.player_orders.has(player):
			NetworkManager.player_orders[player] = orders
		for unit in all_units[player]:
			if unit == null or unit.is_base or unit.is_tower:
				continue
			if unit.move_queue.size() > 0:
				continue
			if unit.build_queue.size() > 0:
				continue
			if unit.curr_health <= 0:
				unit.auto_heal = false
				continue
			if not unit.auto_heal:
				continue
			if unit.curr_health >= unit.max_health:
				unit.auto_heal = false
				continue
			var order = {"unit_net_id": unit.net_id, "type": "heal", "auto_heal": true}
			orders[unit.net_id] = order
			NetworkManager.player_orders[player][unit.net_id] = order
			_apply_order_flags(unit, order)
		player_orders[player] = orders

func _apply_auto_defend_orders(all_units: Dictionary) -> void:
	for player in ["player1", "player2"]:
		if not all_units.has(player):
			continue
		var orders = player_orders.get(player, {})
		if not NetworkManager.player_orders.has(player):
			NetworkManager.player_orders[player] = orders
		for unit in all_units[player]:
			if unit == null or unit.is_base or unit.is_tower:
				continue
			if unit.move_queue.size() > 0:
				continue
			if unit.build_queue.size() > 0:
				continue
			if unit.curr_health <= 0:
				unit.auto_defend = false
				continue
			if not unit.auto_defend:
				continue
			if orders.has(unit.net_id):
				continue
			var order = {"unit_net_id": unit.net_id, "type": "defend", "auto_defend": true}
			orders[unit.net_id] = order
			NetworkManager.player_orders[player][unit.net_id] = order
			_apply_order_flags(unit, order)
		player_orders[player] = orders

func _apply_auto_build_orders(all_units: Dictionary) -> void:
	for player in ["player1", "player2"]:
		if not all_units.has(player):
			continue
		var orders = player_orders.get(player, {})
		if not NetworkManager.player_orders.has(player):
			NetworkManager.player_orders[player] = orders
		for unit in all_units[player]:
			if unit == null or not unit.is_builder:
				if unit != null:
					unit.auto_build = false
					unit.auto_build_type = ""
				continue
			if unit.move_queue.size() > 0:
				continue
			if unit.curr_health <= 0:
				unit.auto_build = false
				unit.auto_build_type = ""
				continue
			if unit.build_queue.size() > 0:
				continue
			if not unit.auto_build:
				continue
			if orders.has(unit.net_id):
				continue
			var state = _structure_state(unit.grid_pos)
			if state.is_empty():
				unit.auto_build = false
				unit.auto_build_type = ""
				continue
			if str(state.get("owner", "")) != player:
				unit.auto_build = false
				unit.auto_build_type = ""
				continue
			if str(state.get("status", "")) != STRUCT_STATUS_BUILDING:
				unit.auto_build = false
				unit.auto_build_type = ""
				continue
			if unit.auto_build_type != "" and str(state.get("type", "")) != unit.auto_build_type:
				unit.auto_build = false
				unit.auto_build_type = ""
				continue
			var order = {
				"unit_net_id": unit.net_id,
				"type": "build",
				"structure_type": str(state.get("type", "")),
				"target_tile": unit.grid_pos
			}
			orders[unit.net_id] = order
			NetworkManager.player_orders[player][unit.net_id] = order
			_apply_order_flags(unit, order)
		player_orders[player] = orders

func _clear_build_queue(unit) -> void:
	if unit == null:
		return
	unit.build_queue = []
	unit.build_queue_type = ""
	unit.build_queue_last_type = ""
	unit.build_queue_last_target = Vector2i(-9999, -9999)
	unit.build_queue_last_build_left = -1

func _clear_move_queue(unit) -> void:
	if unit == null:
		return
	unit.move_queue = []
	unit.move_queue_last_target = Vector2i(-9999, -9999)

func _road_queue_tile_status(tile: Vector2i, player_id: String, allow_start: bool = false) -> String:
	if not $GameBoardNode/HexTileMap.is_cell_valid(tile):
		return "invalid"
	if $GameBoardNode._terrain_is_impassable(tile):
		return "invalid"
	var terrain = _terrain_type(tile)
	if terrain in ["mountain", "lake"]:
		return "invalid"
	if tile in camps.get("basic", []) or tile in camps.get("dragon", []):
		return "skip" if allow_start else "invalid"
	if tile in structure_positions:
		if tile == base_positions.get(player_id, Vector2i(-9999, -9999)) or tile in tower_positions.get(player_id, []):
			return "skip"
		return "skip" if allow_start else "invalid"
	var state = _structure_state(tile)
	if not state.is_empty():
		var stype = str(state.get("type", ""))
		var status = str(state.get("status", ""))
		var owner = str(state.get("owner", ""))
		if status == STRUCT_STATUS_DISABLED:
			return "skip" if allow_start else "invalid"
		if stype == STRUCT_ROAD:
			if status == STRUCT_STATUS_BUILDING:
				return "build" if owner == player_id else ("skip" if allow_start else "invalid")
			if status == STRUCT_STATUS_INTACT:
				return "skip"
		if stype == STRUCT_RAIL:
			if status in [STRUCT_STATUS_BUILDING, STRUCT_STATUS_INTACT]:
				return "skip"
		return "skip" if allow_start else "invalid"
	return "build"

func _rail_queue_tile_status(tile: Vector2i, player_id: String, allow_start: bool = false) -> String:
	if not $GameBoardNode/HexTileMap.is_cell_valid(tile):
		return "invalid"
	if $GameBoardNode._terrain_is_impassable(tile):
		return "invalid"
	var terrain = _terrain_type(tile)
	if terrain in ["mountain", "lake"]:
		return "invalid"
	if tile in camps.get("basic", []) or tile in camps.get("dragon", []):
		return "invalid"
	if tile in structure_positions:
		if tile == base_positions.get(player_id, Vector2i(-9999, -9999)) or tile in tower_positions.get(player_id, []):
			return "skip"
		return "invalid"
	var state = _structure_state(tile)
	if state.is_empty():
		return "invalid"
	var stype = str(state.get("type", ""))
	var status = str(state.get("status", ""))
	var owner = str(state.get("owner", ""))
	if status == STRUCT_STATUS_DISABLED:
		return "invalid"
	if stype == STRUCT_ROAD:
		if status == STRUCT_STATUS_INTACT and owner == player_id:
			return "build"
		return "invalid"
	if stype == STRUCT_RAIL:
		if owner != player_id:
			return "invalid"
		if status == STRUCT_STATUS_BUILDING:
			return "build"
		if status == STRUCT_STATUS_INTACT:
			return "skip"
	return "invalid"

func is_road_queue_tile_valid(tile: Vector2i, player_id: String, allow_start: bool = false) -> bool:
	return _road_queue_tile_status(tile, player_id, allow_start) != "invalid"

func _queue_path_index(path: Array, tile: Vector2i) -> int:
	for i in range(path.size()):
		if path[i] == tile:
			return i
	return -1

func _build_queue_last_step_ok(unit, player_id: String) -> bool:
	var last_type = str(unit.build_queue_last_type)
	if last_type == "":
		return true
	if last_type == "move":
		return unit.grid_pos == unit.build_queue_last_target
	if last_type == "build":
		var tile: Vector2i = unit.build_queue_last_target
		var state = _structure_state(tile)
		if state.is_empty():
			return false
		var status = str(state.get("status", ""))
		if status == STRUCT_STATUS_DISABLED:
			return false
		return true
	return true

func _build_queue_next_order(unit, player_id: String) -> Dictionary:
	if unit == null:
		return {}
	var path = unit.build_queue
	if not (path is Array) or path.size() < 2:
		return {}
	var idx = _queue_path_index(path, unit.grid_pos)
	if idx < 0:
		return {}
	var queue_type = str(unit.build_queue_type)
	if queue_type == "":
		queue_type = STRUCT_ROAD
	var status = _road_queue_tile_status(unit.grid_pos, player_id, idx == 0)
	if queue_type == STRUCT_RAIL:
		status = _rail_queue_tile_status(unit.grid_pos, player_id, idx == 0)
	if status == "invalid":
		return {}
	if status == "build":
		var struct_type = STRUCT_ROAD if queue_type != STRUCT_RAIL else STRUCT_RAIL
		var turn_cost = _structure_turn_cost(struct_type)
		if turn_cost > 0 and player_gold[player_id] < turn_cost:
			return {"_queue_fail": "not_enough_gold"}
		return {
			"unit_net_id": unit.net_id,
			"type": "build",
			"structure_type": struct_type,
			"target_tile": unit.grid_pos,
			"priority": 0
		}
	if idx >= path.size() - 1:
		return {}
	var next_tile = path[idx + 1]
	if not $GameBoardNode/HexTileMap.is_cell_valid(next_tile):
		return {}
	if not next_tile in $GameBoardNode.get_offset_neighbors(unit.grid_pos):
		return {}
	if $GameBoardNode._terrain_is_impassable(next_tile):
		return {}
	if $GameBoardNode.is_enemy_structure_tile(next_tile, player_id):
		return {}
	return {
		"unit_net_id": unit.net_id,
		"type": "move",
		"path": [unit.grid_pos, next_tile],
		"priority": 0
	}

func _record_build_queue_last_order(unit, order: Dictionary) -> void:
	if unit == null:
		return
	var otype = str(order.get("type", ""))
	unit.build_queue_last_type = otype
	unit.build_queue_last_target = Vector2i(-9999, -9999)
	unit.build_queue_last_build_left = -1
	if otype == "move":
		var path = order.get("path", [])
		if path is Array and path.size() > 0:
			var tail = path[path.size() - 1]
			if typeof(tail) == TYPE_VECTOR2I:
				unit.build_queue_last_target = tail
	elif otype == "build":
		var tile = order.get("target_tile", unit.grid_pos)
		if typeof(tile) == TYPE_VECTOR2I:
			unit.build_queue_last_target = tile
			var struct_type = str(order.get("structure_type", STRUCT_ROAD))
			var state = _structure_state(tile)
			if state.is_empty():
				unit.build_queue_last_build_left = _structure_build_turns(struct_type, tile)
			else:
				var build_left_val = state.get("build_left", null)
				if build_left_val == null:
					unit.build_queue_last_build_left = _structure_build_turns(struct_type, tile)
				else:
					unit.build_queue_last_build_left = int(build_left_val)

func _move_queue_last_step_ok(unit) -> bool:
	if unit == null:
		return false
	var target = unit.move_queue_last_target
	if target == Vector2i(-9999, -9999):
		return true
	return unit.grid_pos == target

func _move_queue_next_order(unit, player_id: String) -> Dictionary:
	if unit == null:
		return {}
	var path = unit.move_queue
	if not (path is Array) or path.size() < 2:
		return {}
	var idx = _queue_path_index(path, unit.grid_pos)
	if idx < 0:
		return {}
	if idx >= path.size() - 1:
		return {}
	var budget = float(unit.move_range)
	var segment: Array = [unit.grid_pos]
	var prev = unit.grid_pos
	for i in range(idx + 1, path.size()):
		var step = path[i]
		if typeof(step) != TYPE_VECTOR2I:
			return {}
		if not step in $GameBoardNode.get_offset_neighbors(prev):
			return {}
		if $GameBoardNode._terrain_is_impassable(step):
			return {}
		if $GameBoardNode.is_enemy_structure_tile(step, player_id) and i != path.size() - 1:
			return {}
		var cost = float($GameBoardNode.get_move_cost(step, unit))
		if cost > budget + 0.001:
			break
		budget -= cost
		segment.append(step)
		prev = step
		if $GameBoardNode.is_enemy_structure_tile(step, player_id):
			break
	if segment.size() < 2:
		return {}
	return {
		"unit_net_id": unit.net_id,
		"type": "move",
		"path": segment,
		"priority": 0
	}

func _record_move_queue_last_order(unit, order: Dictionary) -> void:
	if unit == null:
		return
	unit.move_queue_last_target = Vector2i(-9999, -9999)
	var path = order.get("path", [])
	if path is Array and path.size() > 0:
		var tail = path[path.size() - 1]
		if typeof(tail) == TYPE_VECTOR2I:
			unit.move_queue_last_target = tail

func _apply_move_queue_orders(all_units: Dictionary) -> void:
	for player in ["player1", "player2"]:
		if not all_units.has(player):
			continue
		var orders = player_orders.get(player, {})
		if not NetworkManager.player_orders.has(player):
			NetworkManager.player_orders[player] = orders
		for unit in all_units[player]:
			if unit == null or unit.is_base or unit.is_tower:
				continue
			if unit.curr_health <= 0:
				_clear_move_queue(unit)
				continue
			if unit.move_queue.size() == 0:
				continue
			if orders.has(unit.net_id):
				_clear_move_queue(unit)
				continue
			if not _move_queue_last_step_ok(unit):
				_clear_move_queue(unit)
				continue
			unit.move_queue_last_target = Vector2i(-9999, -9999)
			var order = _move_queue_next_order(unit, player)
			if order.is_empty():
				_clear_move_queue(unit)
				continue
			orders[unit.net_id] = order
			NetworkManager.player_orders[player][unit.net_id] = order
			_apply_order_flags(unit, order)
			_record_move_queue_last_order(unit, order)
		player_orders[player] = orders

func get_move_queue_front_order(unit, player_id: String) -> Dictionary:
	if unit == null:
		return {}
	if unit.player_id != player_id:
		return {}
	if unit.move_queue.size() < 2:
		return {}
	var order = _move_queue_next_order(unit, player_id)
	if order.is_empty():
		return {}
	return order

func get_queue_front_order(unit, player_id: String) -> Dictionary:
	if unit == null:
		return {}
	if unit.player_id != player_id:
		return {}
	if unit.build_queue.size() < 2:
		return {}
	var order = _build_queue_next_order(unit, player_id)
	if order.is_empty() or order.has("_queue_fail"):
		return {}
	return order

func _apply_build_queue_orders(all_units: Dictionary) -> void:
	for player in ["player1", "player2"]:
		if not all_units.has(player):
			continue
		var orders = player_orders.get(player, {})
		if not NetworkManager.player_orders.has(player):
			NetworkManager.player_orders[player] = orders
		for unit in all_units[player]:
			if unit == null or not unit.is_builder:
				if unit != null:
					_clear_build_queue(unit)
				continue
			if unit.curr_health <= 0:
				_clear_build_queue(unit)
				continue
			if unit.build_queue.size() == 0:
				continue
			if orders.has(unit.net_id):
				_clear_build_queue(unit)
				continue
			if not _build_queue_last_step_ok(unit, player):
				_clear_build_queue(unit)
				continue
			unit.build_queue_last_type = ""
			unit.build_queue_last_target = Vector2i(-9999, -9999)
			unit.build_queue_last_build_left = -1
			var order = _build_queue_next_order(unit, player)
			if order.is_empty():
				_clear_build_queue(unit)
				continue
			if order.has("_queue_fail"):
				_clear_build_queue(unit)
				continue
			orders[unit.net_id] = order
			NetworkManager.player_orders[player][unit.net_id] = order
			_apply_order_flags(unit, order)
			_record_build_queue_last_order(unit, order)
		player_orders[player] = orders
# --------------------------------------------------------
# Phase 2: Orders — async per-player input
# --------------------------------------------------------
func _do_orders() -> void:
	current_phase = Phase.ORDERS
	# start with player1
	var me = local_player_id
	print("--- Orders Phase for %s ---" % me.capitalize())
	emit_signal("orders_phase_begin", me)
	_broadcast_state()
	if has_node("UI"):
		$UI._draw_all()
		if $UI.has_method("_update_done_button_state"):
			$UI._update_done_button_state()

	# wait until both players have submitted
	await NetworkManager.orders_ready
	print("→ Both players submitted orders: %s" % player_orders)

# Called by UIManager to add orders
func add_order(player: String, order: Dictionary) -> void:
	# Order is a dictionary with keys: "unit", "type", and "path"
	player_orders[player][order["unit_net_id"]] = order

func reset_orders_for_player(player_id: String) -> void:
	if not _is_host():
		return
	player_orders[player_id].clear()
	NetworkManager.player_orders[player_id].clear()
	var all_units = $GameBoardNode.get_all_units().get(player_id, [])
	for unit in all_units:
		if unit == null:
			continue
		if unit.is_base or unit.is_tower:
			continue
		unit.ordered = false
		unit.is_defending = false
		unit.is_healing = false
		unit.is_moving = false

func force_skip_movement_phase() -> void:
	if not _is_host():
		return
	var players = ["player1", "player2"]
	for player in players:
		var orders = NetworkManager.player_orders.get(player, {})
		var to_remove := []
		for unit_id in orders.keys():
			var ord = orders[unit_id]
			if ord.get("type", "") == "move":
				to_remove.append(unit_id)
		for unit_id in to_remove:
			orders.erase(unit_id)
		NetworkManager.player_orders[player] = orders
		player_orders[player] = orders
		var committed = committed_orders.get(player, {})
		var committed_remove := []
		for unit_id in committed.keys():
			var ord = committed[unit_id]
			if ord.get("type", "") == "move":
				committed_remove.append(unit_id)
		for unit_id in committed_remove:
			committed.erase(unit_id)
		committed_orders[player] = committed
	for unit in $GameBoardNode.get_all_units_flat(false):
		if unit != null and unit.is_moving:
			unit.is_moving = false
			unit.moving_to = unit.grid_pos
	_broadcast_state()
	if has_node("UI"):
		$UI._draw_paths()

func _remove_player_order(player_id: String, unit_net_id: int) -> void:
	player_orders[player_id].erase(unit_net_id)
	NetworkManager.player_orders[player_id].erase(unit_net_id)

func _clear_unit_order_flags(unit) -> void:
	unit.is_defending = false
	unit.is_healing = false
	unit.is_moving = false

func _apply_order_flags(unit, order: Dictionary) -> void:
	_clear_unit_order_flags(unit)
	if bool(order.get("auto_heal", false)):
		unit.auto_heal = true
	if bool(order.get("auto_defend", false)):
		unit.auto_defend = true
	match order.get("type", ""):
		"move":
			unit.is_moving = true
			var path = order.get("path", [])
			if path.size() > 1:
				unit.moving_to = path[1]
		"heal":
			unit.is_healing = true
		"defend":
			unit.is_defending = true
	unit.ordered = true

func validate_and_add_order(player_id: String, order: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"order": {},
		"unit_net_id": -1
	}
	if not _is_host():
		result["reason"] = "not_host"
		return result
	if current_phase != Phase.ORDERS:
		result["reason"] = "wrong_phase"
		return result
	if not order.has("type") or not order.has("unit_net_id"):
		result["reason"] = "invalid_order"
		return result
	var unit_net_id = int(order.get("unit_net_id", -1))
	result["unit_net_id"] = unit_net_id
	if unit_net_id < 0:
		result["reason"] = "invalid_order"
		return result
	var unit = unit_manager.get_unit_by_net_id(unit_net_id)
	if unit == null:
		result["reason"] = "unit_missing"
		return result
	if unit.player_id != player_id:
		result["reason"] = "not_owner"
		return result
	var order_type = str(order.get("type", ""))
	if unit.is_base or unit.is_tower:
		if order_type != "spell":
			result["reason"] = "invalid_unit"
			return result
	if unit.just_purchased and order_type not in ["move", "move_to"]:
		result["reason"] = "not_ready"
		return result
	if unit.just_purchased and order_type in ["move", "move_to"] and not unit.first_turn_move:
		result["reason"] = "not_ready"
		return result
	if order_type != "heal_until_full" and order_type != "heal":
		unit.auto_heal = false
	if order_type != "defend_always" and order_type != "defend":
		unit.auto_defend = false
	if order_type != "build":
		unit.auto_build = false
		unit.auto_build_type = ""
	if order_type != "build_road_to" and order_type != "build_rail_to":
		_clear_build_queue(unit)
	if order_type != "move_to":
		_clear_move_queue(unit)

	var sanitized := {"unit_net_id": unit_net_id, "type": order_type}
	match order_type:
		"move":
			var path = order.get("path", [])
			if not (path is Array) or path.size() < 2:
				result["reason"] = "invalid_path"
				return result
			if path[0] != unit.grid_pos:
				result["reason"] = "invalid_path"
				return result
			var total_cost: float = 0.0
			for i in range(1, path.size()):
				var prev = path[i - 1]
				var step = path[i]
				if not $GameBoardNode/HexTileMap.is_cell_valid(step):
					result["reason"] = "invalid_path"
					return result
				if not step in $GameBoardNode.get_offset_neighbors(prev):
					result["reason"] = "invalid_path"
					return result
				if $GameBoardNode._terrain_is_impassable(step):
					result["reason"] = "invalid_path"
					return result
				if $GameBoardNode.is_enemy_structure_tile(step, unit.player_id):
					if i != path.size() - 1:
						result["reason"] = "invalid_path"
						return result
				total_cost += float($GameBoardNode.get_move_cost(step, unit))
				if total_cost > float(unit.move_range):
					result["reason"] = "invalid_path"
					return result
			sanitized["path"] = path
			sanitized["priority"] = int(order.get("priority", 0))
		"move_to":
			var path = order.get("path", [])
			if not (path is Array) or path.size() < 2:
				result["reason"] = "invalid_path"
				return result
			if path[0] != unit.grid_pos:
				result["reason"] = "invalid_path"
				return result
			for i in range(1, path.size()):
				var prev = path[i - 1]
				var step = path[i]
				if typeof(step) != TYPE_VECTOR2I:
					result["reason"] = "invalid_path"
					return result
				if not $GameBoardNode/HexTileMap.is_cell_valid(step):
					result["reason"] = "invalid_path"
					return result
				if not step in $GameBoardNode.get_offset_neighbors(prev):
					result["reason"] = "invalid_path"
					return result
				if $GameBoardNode._terrain_is_impassable(step):
					result["reason"] = "invalid_path"
					return result
				if $GameBoardNode.is_enemy_structure_tile(step, player_id) and i != path.size() - 1:
					result["reason"] = "invalid_path"
					return result
			_clear_move_queue(unit)
			unit.move_queue = path
			unit.move_queue_last_target = Vector2i(-9999, -9999)
			var queued = _move_queue_next_order(unit, player_id)
			if queued.is_empty():
				_clear_move_queue(unit)
				result["reason"] = "invalid_path"
				return result
			sanitized = queued
			sanitized["move_queue_path"] = path
			_record_move_queue_last_order(unit, queued)
		"ranged":
			if not unit.is_ranged:
				result["reason"] = "invalid_action"
				return result
			if not order.has("target_tile") or not order.has("target_unit_net_id"):
				result["reason"] = "invalid_target"
				return result
			var target_tile = order.get("target_tile")
			var target_id = int(order.get("target_unit_net_id", -1))
			var target = unit_manager.get_unit_by_net_id(target_id)
			if target == null or target.player_id == player_id:
				result["reason"] = "invalid_target"
				return result
			if target.grid_pos != target_tile:
				result["reason"] = "invalid_target"
				return result
			var ranged_range = get_effective_ranged_range(unit)
			var ranged_tiles = $GameBoardNode.get_reachable_tiles(unit.grid_pos, ranged_range, "ranged")["tiles"]
			if target_tile not in ranged_tiles:
				result["reason"] = "out_of_range"
				return result
			sanitized["target_tile"] = target_tile
			sanitized["target_unit_net_id"] = target_id
			sanitized["priority"] = int(order.get("priority", 0))
		"melee":
			if not unit.can_melee:
				result["reason"] = "invalid_action"
				return result
			if not order.has("target_tile") or not order.has("target_unit_net_id"):
				result["reason"] = "invalid_target"
				return result
			var melee_tile = order.get("target_tile")
			var melee_target_id = int(order.get("target_unit_net_id", -1))
			var melee_target = unit_manager.get_unit_by_net_id(melee_target_id)
			if melee_target == null or melee_target.player_id == player_id:
				result["reason"] = "invalid_target"
				return result
			if melee_target.grid_pos != melee_tile:
				result["reason"] = "invalid_target"
				return result
			var melee_tiles = $GameBoardNode.get_reachable_tiles(unit.grid_pos, 1, "melee")["tiles"]
			if melee_tile not in melee_tiles:
				result["reason"] = "out_of_range"
				return result
			sanitized["target_tile"] = melee_tile
			sanitized["target_unit_net_id"] = melee_target_id
			sanitized["priority"] = int(order.get("priority", 0))
		"spell":
			if not (unit.is_wizard or unit.is_base or unit.is_tower):
				result["reason"] = "invalid_action"
				return result
			if not order.has("spell_type") or not order.has("target_tile") or not order.has("target_unit_net_id"):
				result["reason"] = "invalid_target"
				return result
			var spell_type = str(order.get("spell_type", "")).to_lower()
			if spell_type not in [SPELL_HEAL, SPELL_FIREBALL, SPELL_BUFF]:
				result["reason"] = "invalid_action"
				return result
			var target_tile = order.get("target_tile")
			if typeof(target_tile) == TYPE_VECTOR2:
				target_tile = Vector2i(int(round(target_tile.x)), int(round(target_tile.y)))
			if typeof(target_tile) != TYPE_VECTOR2I:
				result["reason"] = "invalid_target"
				return result
			if not _player_can_see_tile(player_id, target_tile):
				result["reason"] = "no_vision"
				return result
			var target_id = int(order.get("target_unit_net_id", -1))
			var target = unit_manager.get_unit_by_net_id(target_id)
			if target == null or target.grid_pos != target_tile:
				result["reason"] = "invalid_target"
				return result
			if is_unit_hidden_for_viewer(target, player_id):
				result["reason"] = "no_vision"
				return result
			var struct = $GameBoardNode.get_structure_unit_at(target_tile)
			if spell_type == SPELL_FIREBALL:
				if struct != null and struct.player_id != player_id:
					target = struct
					target_id = struct.net_id
				if target.player_id == player_id:
					result["reason"] = "invalid_target"
					return result
			else:
				if target.player_id != player_id:
					result["reason"] = "invalid_target"
					return result
			if _hex_distance(unit.grid_pos, target_tile) > SPELL_RANGE:
				result["reason"] = "out_of_range"
				return result
			if player_mana.get(player_id, 0) < SPELL_COST:
				result["reason"] = "not_enough_mana"
				return result
			sanitized["spell_type"] = spell_type
			sanitized["target_tile"] = target_tile
			sanitized["target_unit_net_id"] = target_id
		"heal":
			pass
		"heal_until_full":
			unit.auto_heal = true
			sanitized["type"] = "heal"
			sanitized["auto_heal"] = true
		"defend":
			pass
		"defend_always":
			unit.auto_defend = true
			sanitized["type"] = "defend"
			sanitized["auto_defend"] = true
		"lookout":
			var unit_type = str(unit.unit_type).to_lower()
			if unit_type != "scout":
				result["reason"] = "invalid_action"
				return result
		"build_road_to":
			if not unit.is_builder:
				result["reason"] = "not_builder"
				return result
			var path = order.get("path", [])
			if not (path is Array) or path.size() < 2:
				result["reason"] = "invalid_path"
				return result
			if path[0] != unit.grid_pos:
				result["reason"] = "invalid_path"
				return result
			var has_build := false
			for i in range(path.size()):
				var step = path[i]
				if typeof(step) != TYPE_VECTOR2I:
					result["reason"] = "invalid_path"
					return result
				if i > 0:
					var prev = path[i - 1]
					if not step in $GameBoardNode.get_offset_neighbors(prev):
						result["reason"] = "invalid_path"
						return result
				if $GameBoardNode.is_enemy_structure_tile(step, player_id):
					result["reason"] = "invalid_path"
					return result
				var status = _road_queue_tile_status(step, player_id, i == 0)
				if status == "invalid":
					result["reason"] = "invalid_path"
					return result
				if status == "build":
					has_build = true
			if not has_build:
				result["reason"] = "invalid_path"
				return result
			_clear_build_queue(unit)
			unit.build_queue = path
			unit.build_queue_type = STRUCT_ROAD
			unit.build_queue_last_type = ""
			unit.build_queue_last_target = Vector2i(-9999, -9999)
			unit.build_queue_last_build_left = -1
			var queued = _build_queue_next_order(unit, player_id)
			if queued.is_empty():
				_clear_build_queue(unit)
				result["reason"] = "invalid_path"
				return result
			if queued.has("_queue_fail"):
				_clear_build_queue(unit)
				result["reason"] = str(queued.get("_queue_fail"))
				return result
			sanitized = queued
			sanitized["queue_path"] = path
			sanitized["queue_type"] = STRUCT_ROAD
			_record_build_queue_last_order(unit, queued)
		"build_rail_to":
			if not unit.is_builder:
				result["reason"] = "not_builder"
				return result
			var rail_path = order.get("path", [])
			if not (rail_path is Array) or rail_path.size() < 2:
				result["reason"] = "invalid_path"
				return result
			if rail_path[0] != unit.grid_pos:
				result["reason"] = "invalid_path"
				return result
			for i in range(rail_path.size()):
				var step = rail_path[i]
				if typeof(step) != TYPE_VECTOR2I:
					result["reason"] = "invalid_path"
					return result
				if i > 0:
					var prev = rail_path[i - 1]
					if not step in $GameBoardNode.get_offset_neighbors(prev):
						result["reason"] = "invalid_path"
						return result
				if $GameBoardNode._terrain_is_impassable(step):
					result["reason"] = "invalid_path"
					return result
				if $GameBoardNode.is_enemy_structure_tile(step, player_id):
					result["reason"] = "invalid_path"
					return result
				var status = _road_queue_tile_status(step, player_id, i == 0)
				if status == "invalid":
					result["reason"] = "invalid_path"
					return result
			_clear_build_queue(unit)
			unit.build_queue = rail_path
			unit.build_queue_type = STRUCT_RAIL
			unit.build_queue_last_type = ""
			unit.build_queue_last_target = Vector2i(-9999, -9999)
			unit.build_queue_last_build_left = -1
			var rail_queued = _build_queue_next_order(unit, player_id)
			if rail_queued.is_empty():
				_clear_build_queue(unit)
				result["reason"] = "invalid_path"
				return result
			if rail_queued.has("_queue_fail"):
				_clear_build_queue(unit)
				result["reason"] = str(rail_queued.get("_queue_fail"))
				return result
			sanitized = rail_queued
			sanitized["queue_path"] = rail_path
			sanitized["queue_type"] = STRUCT_RAIL
			_record_build_queue_last_order(unit, rail_queued)
		"build":
			if not unit.is_builder:
				result["reason"] = "not_builder"
				return result
			if not order.has("structure_type"):
				result["reason"] = "invalid_structure"
				return result
			var target_raw = order.get("target_tile", unit.grid_pos)
			if typeof(target_raw) != TYPE_VECTOR2I:
				result["reason"] = "invalid_tile"
				return result
			var target_tile: Vector2i = target_raw
			if target_tile != unit.grid_pos:
				result["reason"] = "invalid_tile"
				return result
			var struct_type = str(order.get("structure_type", ""))
			if struct_type == "":
				result["reason"] = "invalid_structure"
				return result
			if struct_type not in [STRUCT_FORTIFICATION, STRUCT_ROAD, STRUCT_RAIL, STRUCT_TRAP, STRUCT_MANA_POOL, STRUCT_SPAWN_TOWER]:
				result["reason"] = "invalid_structure"
				return result
			var state = _structure_state(target_tile)
			if state.is_empty():
				if $GameBoardNode.is_occupied(target_tile) and $GameBoardNode.get_unit_at(target_tile) != unit:
					result["reason"] = "invalid_tile"
					return result
				if target_tile in camps["basic"] or target_tile in camps["dragon"]:
					result["reason"] = "invalid_tile"
					return result
				if target_tile in structure_positions:
					result["reason"] = "invalid_tile"
					return result
				if struct_type == STRUCT_RAIL:
					result["reason"] = "invalid_structure"
					return result
				if struct_type in [STRUCT_ROAD, STRUCT_RAIL]:
					if $GameBoardNode._terrain_is_impassable(target_tile):
						result["reason"] = "invalid_tile"
						return result
					var terrain = _terrain_type(target_tile)
					if terrain in ["mountain", "lake"]:
						result["reason"] = "invalid_tile"
						return result
				else:
					var terrain = _terrain_type(target_tile)
					if struct_type == STRUCT_TRAP:
						if terrain in ["mountain", "lake"] or $GameBoardNode._terrain_is_impassable(target_tile):
							result["reason"] = "invalid_tile"
							return result
					elif not _is_open_terrain(target_tile) or $GameBoardNode._terrain_is_impassable(target_tile):
						result["reason"] = "invalid_tile"
						return result
				if struct_type == STRUCT_MANA_POOL:
					var mine_choice = _pick_mana_pool_mine(target_tile, unit_net_id)
					if mine_choice == Vector2i(-9999, -9999):
						result["reason"] = "invalid_structure"
						return result
					sanitized["mana_mine"] = mine_choice
				if struct_type == STRUCT_SPAWN_TOWER and not _spawn_tower_has_connected_road(target_tile, player_id):
					result["reason"] = "invalid_structure"
					return result
			else:
				var existing_type = str(state.get("type", ""))
				var existing_status = str(state.get("status", ""))
				var existing_owner = str(state.get("owner", ""))
				if existing_owner != player_id:
					result["reason"] = "not_owner"
					return result
				if existing_status == STRUCT_STATUS_DISABLED:
					result["reason"] = "invalid_structure"
					return result
				if existing_status == STRUCT_STATUS_BUILDING:
					if existing_type != struct_type:
						result["reason"] = "invalid_structure"
						return result
					if struct_type == STRUCT_MANA_POOL:
						var existing_mine = state.get("mana_mine", Vector2i(-9999, -9999))
						if typeof(existing_mine) == TYPE_VECTOR2I:
							sanitized["mana_mine"] = existing_mine
				elif existing_status == STRUCT_STATUS_INTACT:
					if not (struct_type == STRUCT_RAIL and existing_type == STRUCT_ROAD):
						result["reason"] = "invalid_structure"
						return result
			var turn_cost = _structure_turn_cost(struct_type)
			if turn_cost > 0 and player_gold[player_id] < turn_cost:
				result["reason"] = "not_enough_gold"
				return result
			unit.auto_build = true
			unit.auto_build_type = struct_type
			sanitized["target_tile"] = target_tile
			sanitized["structure_type"] = struct_type
		"repair":
			if not unit.is_builder:
				result["reason"] = "not_builder"
				return result
			if not order.has("target_tile"):
				result["reason"] = "invalid_target"
				return result
			var repair_raw = order.get("target_tile")
			if typeof(repair_raw) != TYPE_VECTOR2I:
				result["reason"] = "invalid_target"
				return result
			var repair_tile: Vector2i = repair_raw
			if repair_tile == unit.grid_pos:
				var repair_state = _structure_state(repair_tile)
				if not repair_state.is_empty():
					if str(repair_state.get("owner", "")) != player_id:
						result["reason"] = "not_owner"
						return result
					if str(repair_state.get("status", "")) != STRUCT_STATUS_DISABLED:
						result["reason"] = "invalid_target"
						return result
				else:
					var same_tile = $GameBoardNode.get_structure_unit_at(repair_tile)
					if same_tile == null or not (same_tile.is_base or same_tile.is_tower):
						result["reason"] = "invalid_target"
						return result
					if same_tile.player_id != player_id:
						result["reason"] = "not_owner"
						return result
					if same_tile.curr_health >= same_tile.max_health:
						result["reason"] = "invalid_target"
						return result
			else:
				if _hex_distance(unit.grid_pos, repair_tile) != 1:
					result["reason"] = "invalid_target"
					return result
				var target_unit = $GameBoardNode.get_structure_unit_at(repair_tile)
				if target_unit == null or not (target_unit.is_base or target_unit.is_tower):
					result["reason"] = "invalid_target"
					return result
				if target_unit.player_id != player_id:
					result["reason"] = "not_owner"
					return result
				if target_unit.curr_health >= target_unit.max_health:
					result["reason"] = "invalid_target"
					return result
			sanitized["target_tile"] = repair_tile
		"sabotage":
			var sabotage_raw = order.get("target_tile", unit.grid_pos)
			var sabotage_tile: Vector2i
			if typeof(sabotage_raw) == TYPE_VECTOR2I:
				sabotage_tile = sabotage_raw
			elif typeof(sabotage_raw) == TYPE_VECTOR2:
				sabotage_tile = Vector2i(int(round(sabotage_raw.x)), int(round(sabotage_raw.y)))
			else:
				result["reason"] = "invalid_target"
				return result
			if sabotage_tile != unit.grid_pos:
				result["reason"] = "invalid_target"
				return result
			var sab_state = _structure_state(sabotage_tile)
			var sab_owner = str(sab_state.get("owner", ""))
			var sab_status = str(sab_state.get("status", ""))
			var sab_type = str(sab_state.get("type", ""))
			if sab_owner == player_id and sab_type == STRUCT_SPAWN_TOWER and sab_status != STRUCT_STATUS_BUILDING:
				result["reason"] = "invalid_target"
				return result
			if sab_owner == player_id and sab_status != STRUCT_STATUS_BUILDING:
				result["reason"] = "invalid_target"
				return result
			sanitized["target_tile"] = sabotage_tile
		_:
			result["reason"] = "invalid_action"
			return result

	player_orders[player_id][unit_net_id] = sanitized
	NetworkManager.player_orders[player_id][unit_net_id] = sanitized
	_apply_order_flags(unit, sanitized)
	result["ok"] = true
	result["order"] = sanitized
	return result

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

func get_all_orders_for_phase(player_id: String) -> Array:
	var src = player_orders
	if current_phase == Phase.EXECUTION:
		src = committed_orders
	if src.has(player_id):
		var all_orders = src[player_id].values()
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
	push_error("Unknown player in get_orders_for_phase: %s" % player_id)
	return []

func _has_adjacent_defending_phalanx(unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	for neighbor in $GameBoardNode.get_offset_neighbors(unit.grid_pos):
		var other = $GameBoardNode.get_unit_at(neighbor)
		if other == null:
			continue
		if other.player_id != unit.player_id:
			continue
		if other.is_phalanx and other.is_defending:
			return true
	return false

# Called by UIManager when a player hits 'Done'
func submit_player_order(player: String) -> void:
	NetworkManager.submit_orders(player, [])

func calculate_damage(attacker, defender, atk_mode, num_atkrs):
	# NOTE: Whenever this function is updated, also update all manually calculated damage sections
	# search: MANUAL_DMG
	if attacker == null or defender == null:
		return [0.0, 0.0]
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return [0.0, 0.0]
	var atkr_damaged_penalty = 1.0
	if attacker.player_id != "neutral" and not attacker.is_base and not attacker.is_tower:
		atkr_damaged_penalty = 1 - ((100 - attacker.curr_health) * 0.005)
	var atkr_buff_melee = attacker.spell_buff_melee if attacker.spell_buff_turns > 0 else 0
	var atkr_buff_ranged = attacker.spell_buff_ranged if attacker.spell_buff_turns > 0 else 0
	var defr_buff_melee = defender.spell_buff_melee if defender.spell_buff_turns > 0 else 0
	var defr_buff_ranged = defender.spell_buff_ranged if defender.spell_buff_turns > 0 else 0
	var atkr_str
	if atk_mode == "ranged":
		atkr_str = (attacker.ranged_strength + atkr_buff_ranged) * atkr_damaged_penalty
	else:
		atkr_str = (attacker.melee_strength + atkr_buff_melee) * atkr_damaged_penalty
	var atkr_fort = _structure_state(attacker.grid_pos)
	if str(atkr_fort.get("type", "")) == STRUCT_FORTIFICATION and str(atkr_fort.get("status", "")) == STRUCT_STATUS_INTACT:
		if atk_mode == "ranged":
			atkr_str += fort_ranged_bonus
		else:
			atkr_str += fort_melee_bonus
	if _unit_on_friendly_tower(attacker):
		if atk_mode == "ranged":
			atkr_str += TOWER_RANGED_BONUS
		else:
			atkr_str += TOWER_MELEE_BONUS
	if _has_adjacent_defending_phalanx(attacker):
		atkr_str += PHALANX_ADJ_BONUS
	if atk_mode == "ranged":
		atkr_str += player_ranged_bonus.get(attacker.player_id, 0)
	else:
		atkr_str += player_melee_bonus.get(attacker.player_id, 0)
	if atk_mode != "ranged":
		atkr_str += _terrain_bonus(attacker.grid_pos, "melee_attack_bonus")
	var defr_damaged_penalty = 1.0
	if defender.player_id != "neutral" and not defender.is_base and not defender.is_tower:
		defr_damaged_penalty = 1 - ((100 - defender.curr_health) * 0.005)
	var defr_str = defender.melee_strength + defr_buff_melee
	if defender.player_id != "neutral":
		defr_str -= ((num_atkrs - 1) * defender.multi_def_penalty)
	if defender.is_defending and defender.is_phalanx:
		defr_str += PHALANX_BONUS + (num_atkrs - 1) * defender.multi_def_penalty
	defr_str = defr_str * defr_damaged_penalty
	var defr_fort = _structure_state(defender.grid_pos)
	if str(defr_fort.get("type", "")) == STRUCT_FORTIFICATION and str(defr_fort.get("status", "")) == STRUCT_STATUS_INTACT:
		if atk_mode == "ranged":
			defr_str += fort_ranged_bonus
		else:
			defr_str += fort_melee_bonus
	if _unit_on_friendly_tower(defender):
		defr_str += TOWER_MELEE_BONUS
	if _has_adjacent_defending_phalanx(defender):
		defr_str += PHALANX_ADJ_BONUS
	if atk_mode == "ranged":
		defr_str += _terrain_bonus(defender.grid_pos, "ranged_defense_bonus")
	else:
		defr_str += _terrain_bonus(defender.grid_pos, "melee_defense_bonus")
	var atkr_in_dmg
	if defender.is_ranged and atk_mode == "ranged":
		var defr_ranged_str = defender.ranged_strength + defr_buff_ranged
		if defender.player_id != "neutral":
			defr_ranged_str -= ((num_atkrs - 1) * defender.multi_def_penalty)
		defr_ranged_str *= defr_damaged_penalty
		if str(defr_fort.get("type", "")) == STRUCT_FORTIFICATION and str(defr_fort.get("status", "")) == STRUCT_STATUS_INTACT:
			defr_ranged_str += fort_ranged_bonus
		if _unit_on_friendly_tower(defender):
			defr_ranged_str += TOWER_RANGED_BONUS
		if _has_adjacent_defending_phalanx(defender):
			defr_ranged_str += PHALANX_ADJ_BONUS
		defr_ranged_str += _terrain_bonus(defender.grid_pos, "ranged_defense_bonus")
		atkr_in_dmg = 30 * (1.041**(defr_ranged_str - attacker.melee_strength * atkr_damaged_penalty))
	else:
		atkr_in_dmg = 30 * (1.041**(defr_str - attacker.melee_strength * atkr_damaged_penalty))
	var defr_in_dmg = 30 * (1.041**(atkr_str - defr_str))
	return [atkr_in_dmg, defr_in_dmg]

func _accumulate_damage_by_player(dmg_map: Dictionary, target_net_id: int, player_id: String, amount: float) -> void:
	if amount <= 0:
		return
	if player_id == "":
		return
	var by_player = dmg_map.get(target_net_id, {})
	by_player[player_id] = float(by_player.get(player_id, 0.0)) + float(amount)
	dmg_map[target_net_id] = by_player

func _assign_last_damaged_by(target, dmg_map: Dictionary, target_net_id: int) -> void:
	if target == null:
		return
	var by_player = dmg_map.get(target_net_id, {})
	if by_player.size() == 0:
		return
	var max_dmg := -1.0
	var tied: Array = []
	for player_id in by_player.keys():
		var dmg = float(by_player[player_id])
		if dmg > max_dmg:
			max_dmg = dmg
			tied = [player_id]
		elif dmg == max_dmg:
			tied.append(player_id)
	if tied.size() == 1:
		target.last_damaged_by = tied[0]
		return
	# TODO: Replace random tie-break with deterministic logic.
	var idx = rng.randi_range(0, tied.size() - 1)
	target.last_damaged_by = tied[idx]

func _grant_dragon_reward(player_id: String, pos: Vector2i) -> void:
	var reward = dragon_rewards.get(pos, DRAGON_REWARD_GOLD)
	match reward:
		DRAGON_REWARD_GOLD:
			player_gold[player_id] += dragon_gold_bonus
		DRAGON_REWARD_MELEE:
			player_melee_bonus[player_id] += dragon_melee_bonus
		DRAGON_REWARD_RANGED:
			player_ranged_bonus[player_id] += dragon_ranged_bonus

func _handle_neutral_death(unit) -> void:
	if unit == null:
		return
	if unit.player_id != NEUTRAL_PLAYER_ID:
		return
	var pos = unit.grid_pos
	if unit.unit_type == CAMP_ARCHER_TYPE:
		camp_units.erase(pos)
		var camp_duration = _roll_camp_respawn()
		camp_respawns[pos] = camp_duration
		var killer = unit.last_damaged_by
		if killer in ["player1", "player2"]:
			var reward = _camp_gold_reward(pos)
			player_gold[killer] += reward
			_reward_report(killer, "Camp defeated: +%d gold" % reward)
		camp_respawn_counts[pos] = camp_respawn_counts.get(pos, 0) + 1
	elif unit.unit_type == DRAGON_TYPE:
		dragon_units.erase(pos)
		var dragon_duration = _roll_dragon_respawn()
		dragon_respawns[pos] = dragon_duration
		var killer = unit.last_damaged_by
		if killer in ["player1", "player2"]:
			var reward = dragon_rewards.get(pos, DRAGON_REWARD_GOLD)
			_grant_dragon_reward(killer, pos)
			match reward:
				DRAGON_REWARD_GOLD:
					_reward_report(killer, "Dragon defeated: +%d gold" % dragon_gold_bonus)
				DRAGON_REWARD_MELEE:
					_reward_report(killer, "Dragon defeated: +%d melee strength" % dragon_melee_bonus)
				DRAGON_REWARD_RANGED:
					_reward_report(killer, "Dragon defeated: +%d ranged strength" % dragon_ranged_bonus)
	update_neutral_markers()

func _cleanup_dead_unit(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	for player in ["player1", "player2"]:
		player_orders[player].erase(unit.net_id)
		NetworkManager.player_orders[player].erase(unit.net_id)
	died_dmg_report(unit)
	_handle_neutral_death(unit)
	$GameBoardNode.vacate(unit.grid_pos, unit)
	_refresh_tile_after_unit_change(unit.grid_pos)
	unit_manager.unit_by_net_id.erase(unit.net_id)
	unit.queue_free()

func _remove_dead_unit_silent(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	for player in ["player1", "player2"]:
		player_orders[player].erase(unit.net_id)
		NetworkManager.player_orders[player].erase(unit.net_id)
		committed_orders[player].erase(unit.net_id)
	$GameBoardNode.vacate(unit.grid_pos, unit)
	_refresh_tile_after_unit_change(unit.grid_pos)
	unit_manager.unit_by_net_id.erase(unit.net_id)
	unit.queue_free()

func _prune_dead_units_after_apply() -> void:
	var to_remove: Array = []
	for unit in unit_manager.get_children():
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.player_id not in ["player1", "player2"]:
			continue
		if unit.is_base or unit.is_tower:
			continue
		if unit.curr_health <= 0:
			to_remove.append(unit)
	for unit in to_remove:
		_remove_dead_unit_silent(unit)

func dealt_dmg_report(atkr, defr, atkr_in_dmg, defr_in_dmg, retaliate, atk_mode):
	_append_damage_log(atkr, defr, atkr_in_dmg, defr_in_dmg, retaliate, atk_mode)
	var lines = _damage_lines_for_viewer(local_player_id, atkr, defr, atkr_in_dmg, defr_in_dmg, retaliate, atk_mode)
	for line in lines:
		var report_label = Label.new()
		report_label.text = line
		dmg_report.add_child(report_label)

func died_dmg_report(unit):
	_append_death_log(unit)
	var lines = _death_lines_for_viewer(local_player_id, unit)
	for line in lines:
		var report_label = Label.new()
		report_label.text = line
		dmg_report.add_child(report_label)

func _damage_lines_for_viewer(viewer_id: String, atkr, defr, atkr_in_dmg, defr_in_dmg, retaliate, atk_mode) -> Array:
	if viewer_id == "":
		return []
	if atkr.player_id != viewer_id and defr.player_id != viewer_id:
		return []
	var lines := []
	if defr.player_id == viewer_id:
		lines.append("Your %s #%d took %d %s damage from %s #%d" % [defr.unit_type, defr.net_id, defr_in_dmg, atk_mode, atkr.unit_type, atkr.net_id])
		if retaliate:
			lines.append("Your %s #%d retaliated and dealt %d damage" % [defr.unit_type, defr.net_id, atkr_in_dmg])
	else:
		lines.append("Your %s #%d dealt %d %s damage to %s #%d" % [atkr.unit_type, atkr.net_id, defr_in_dmg, atk_mode, defr.unit_type, defr.net_id])
		if retaliate:
			lines.append("Enemy %s #%d retaliated and dealt %d damage" % [defr.unit_type, defr.net_id, atkr_in_dmg])
	return lines

func _death_lines_for_viewer(viewer_id: String, unit) -> Array:
	if viewer_id == "":
		return []
	if unit.player_id != viewer_id and unit.last_damaged_by != viewer_id:
		return []
	if unit.player_id == viewer_id:
		return ["Your %s #%d died at %s" % [unit.unit_type, unit.net_id, unit.grid_pos]]
	return ["Enemy %s #%d died at %s" % [unit.unit_type, unit.net_id, unit.grid_pos]]

func _append_damage_log(atkr, defr, atkr_in_dmg, defr_in_dmg, retaliate, atk_mode) -> void:
	for viewer_id in ["player1", "player2"]:
		var lines = _damage_lines_for_viewer(viewer_id, atkr, defr, atkr_in_dmg, defr_in_dmg, retaliate, atk_mode)
		for line in lines:
			damage_log[viewer_id].append(line)

func _append_death_log(unit) -> void:
	for viewer_id in ["player1", "player2"]:
		var lines = _death_lines_for_viewer(viewer_id, unit)
		for line in lines:
			damage_log[viewer_id].append(line)

func _render_damage_log_for_local() -> void:
	for child in dmg_report.get_children():
		child.queue_free()
	var lines = damage_log.get(local_player_id, [])
	for line in lines:
		var report_label = Label.new()
		report_label.text = line
		dmg_report.add_child(report_label)

func _process_spawns():
	var spawn_orders = []
	var orders_source = committed_orders
	for player_id in orders_source.keys():
		for order in orders_source[player_id].values():
			if order["type"] == "spawn":
				spawn_orders.append(order)
	spawn_orders.sort_custom(func(order1, order2): order1["unit_net_id"] < order2["unit_net_id"])
	for order in spawn_orders:
		if unit_manager.get_unit_by_net_id(order["unit_net_id"]) != null:
			continue
		if order["owner_id"] != local_player_id:
			unit_manager.spawn_unit(order["unit_type"], order["cell"], order["owner_id"], order["undo"])
	for player_id in orders_source.keys():
		for order in orders_source[player_id].keys():
			if orders_source[player_id][order]["type"] == "spawn":
				orders_source[player_id].erase(order)
	
	for player in ["player1", "player2"]:
		var unit_ids = orders_source[player].keys()
		unit_ids.sort()
		for unit_net_id in unit_ids:
			if unit_net_id is not int:
				continue
			var order = orders_source[player][unit_net_id]
			if order["type"] == "defend":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				if unit == null:
					continue
				unit.is_defending = true
			if order["type"] == "heal":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				if unit == null:
					continue
				unit.is_healing = true
	
	for player in ["player1", "player2"]:
		for unit_net_id in orders_source[player].keys():
			if orders_source[player][unit_net_id]["type"] == "move":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				if unit == null:
					continue
				unit.is_moving = true
				unit.moving_to = orders_source[player][unit_net_id]["path"][1]
	$UI._draw_all()
	$GameBoardNode/FogOfWar._update_fog()

func _process_spells() -> void:
	var spell_orders := []
	for player in ["player1", "player2"]:
		var unit_ids = player_orders[player].keys()
		unit_ids.sort()
		for unit_net_id in unit_ids:
			if unit_net_id is not int:
				continue
			var order = player_orders[player][unit_net_id]
			if str(order.get("type", "")) != "spell":
				continue
			if str(order.get("spell_type", "")) == SPELL_FIREBALL:
				continue
			spell_orders.append({"player": player, "unit_net_id": unit_net_id, "order": order})
	for entry in spell_orders:
		var player_id = entry["player"]
		var caster = unit_manager.get_unit_by_net_id(entry["unit_net_id"])
		if caster == null or caster.curr_health <= 0:
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		var order = entry["order"]
		var target_id = int(order.get("target_unit_net_id", -1))
		var target = unit_manager.get_unit_by_net_id(target_id)
		if target == null or target.curr_health <= 0:
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		if player_mana.get(player_id, 0) < SPELL_COST:
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		player_mana[player_id] -= SPELL_COST
		var spell_type = str(order.get("spell_type", ""))
		if spell_type == SPELL_HEAL:
			target.curr_health = min(target.max_health, target.curr_health + SPELL_HEAL_AMOUNT)
			target.set_health_bar()
		elif spell_type == SPELL_BUFF:
			target.spell_buff_melee = SPELL_BUFF_AMOUNT
			target.spell_buff_ranged = SPELL_BUFF_AMOUNT
			target.spell_buff_turns = SPELL_BUFF_TURNS
		_remove_player_order(player_id, entry["unit_net_id"])

func _process_attacks():
	var ranged_attacks: Dictionary = {} # key: target.net_id, value: [attacker.net_id]
	var ranged_dmg: Dictionary = {} # key: target.net_id, value: damage recieved
	var melee_attacks: Dictionary = {} # key: target.net_id, value: array[[attacker.net_id, priority]]
	var melee_dmg: Dictionary = {} # key: target, value: damage recieved
	var ranged_sources: Dictionary = {} # key: target.net_id, value: {player_id: damage}
	var melee_sources: Dictionary = {} # key: target.net_id, value: {player_id: damage}
	var spell_dmg: Dictionary = {} # key: target.net_id, value: damage received
	
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
				if unit != null and is_instance_valid(target):
					ranged_attacks[target.net_id] = ranged_attacks.get(target.net_id, [])
					ranged_attacks[target.net_id].append(unit.net_id)
				player_orders[player].erase(unit.net_id)
			elif order["type"] == "melee":
				var unit = unit_manager.get_unit_by_net_id(unit_net_id)
				var target = unit_manager.get_unit_by_net_id(order["target_unit_net_id"])
				if unit != null and is_instance_valid(target):
					melee_attacks[order["target_unit_net_id"]] = melee_attacks.get(order["target_unit_net_id"], [])
					melee_attacks[order["target_unit_net_id"]].append([unit.net_id, order["priority"]])
				player_orders[player].erase(unit.net_id)
			elif order["type"] == "spell":
				if str(order.get("spell_type", "")) != SPELL_FIREBALL:
					continue
				var caster = unit_manager.get_unit_by_net_id(unit_net_id)
				if caster == null or caster.curr_health <= 0:
					player_orders[player].erase(unit_net_id)
					continue
				var target = unit_manager.get_unit_by_net_id(order.get("target_unit_net_id", -1))
				if target == null:
					player_orders[player].erase(unit_net_id)
					continue
				var target_tile = target.grid_pos
				var struct = $GameBoardNode.get_structure_unit_at(target_tile)
				if struct != null and struct.player_id != caster.player_id:
					target = struct
				if target.player_id == caster.player_id:
					player_orders[player].erase(unit_net_id)
					continue
				if player_mana.get(player, 0) < SPELL_COST:
					player_orders[player].erase(unit_net_id)
					continue
				player_mana[player] -= SPELL_COST
				var dmg = SPELL_FIREBALL_STRUCT_DAMAGE if target.is_base or target.is_tower else SPELL_FIREBALL_DAMAGE
				spell_dmg[target.net_id] = spell_dmg.get(target.net_id, 0) + dmg
				_accumulate_damage_by_player(ranged_sources, target.net_id, caster.player_id, dmg)
				player_orders[player].erase(unit_net_id)
	
	# calculate all ranged attack damages done
	var target_ids = ranged_attacks.keys()
	target_ids.sort()
	for target_net_id in target_ids:
		var num_attackers = ranged_attacks.get(target_net_id, []).size() + melee_attacks.get(target_net_id, []).size()
		for unit_net_id in ranged_attacks[target_net_id]:
			var unit = unit_manager.get_unit_by_net_id(unit_net_id)
			if unit == null or not is_instance_valid(unit):
				continue
			var target = unit_manager.get_unit_by_net_id(target_net_id)
			if target == null:
				continue
			var dmg_result = calculate_damage(unit, target, "ranged", num_attackers)
			var defr_in_dmg = dmg_result[1]
			var ret_dmg = dmg_result[0]
			var retaliator = _get_retaliator_for_target(target)
			var retaliate = _retaliator_can_hit(unit, retaliator)
			var ret_target = _retaliation_target_for_attacker(unit, "ranged")
			if retaliate:
				var ret_calc_target = ret_target if ret_target != null else unit
				ret_dmg = calculate_damage(ret_calc_target, retaliator, "ranged", num_attackers)[0]
			if retaliate:
				var ret_target_id = (ret_target if ret_target != null else unit).net_id
				ranged_dmg[ret_target_id] = ranged_dmg.get(ret_target_id, 0) + ret_dmg
				_accumulate_damage_by_player(ranged_sources, ret_target_id, retaliator.player_id, ret_dmg)
			ranged_dmg[target_net_id] = ranged_dmg.get(target_net_id, 0) + defr_in_dmg
			_accumulate_damage_by_player(ranged_sources, target_net_id, unit.player_id, defr_in_dmg)
			dealt_dmg_report(unit, target, ret_dmg, defr_in_dmg, retaliate, "ranged")
	
	# calculate all melee attack damages done
	target_ids = melee_attacks.keys()
	target_ids.sort()
	for target_unit_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_unit_net_id)
		if target == null:
			continue
		var num_attackers = ranged_attacks.get(target_unit_net_id, []).size() + melee_attacks.get(target_unit_net_id, []).size()
		var attacks = melee_attacks.get(target_unit_net_id, [])
		attacks.sort_custom(func(a,b): return a[1] < b[1])
		for attack in attacks:
			var attacker = unit_manager.get_unit_by_net_id(attack[0])
			if attacker == null or not is_instance_valid(attacker):
				continue
			var dmg_result = calculate_damage(attacker, target, "melee", num_attackers)
			var defr_in_dmg = dmg_result[1]
			var ret_dmg = dmg_result[0]
			var retaliator = _get_retaliator_for_target(target)
			var retaliate = _retaliator_can_hit(attacker, retaliator)
			var ret_target = _retaliation_target_for_attacker(attacker, "melee")
			if retaliate:
				var ret_calc_target = ret_target if ret_target != null else attacker
				ret_dmg = calculate_damage(ret_calc_target, retaliator, "melee", num_attackers)[0]
			if retaliate:
				var ret_target_id = (ret_target if ret_target != null else attacker).net_id
				melee_dmg[ret_target_id] = melee_dmg.get(ret_target_id, 0) + ret_dmg
				_accumulate_damage_by_player(melee_sources, ret_target_id, retaliator.player_id, ret_dmg)
			melee_dmg[target.net_id] = melee_dmg.get(target.net_id, 0) + defr_in_dmg
			_accumulate_damage_by_player(melee_sources, target.net_id, attacker.player_id, defr_in_dmg)
			dealt_dmg_report(attacker, target, ret_dmg, defr_in_dmg, retaliate, "melee")

	for target_net_id in spell_dmg.keys():
		ranged_dmg[target_net_id] = ranged_dmg.get(target_net_id, 0) + spell_dmg[target_net_id]
	
	# deal ranged damage
	target_ids = ranged_dmg.keys()
	target_ids.sort()
	for target_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_net_id)
		if target == null:
			continue
		target.curr_health -= ranged_dmg[target_net_id]
		_assign_last_damaged_by(target, ranged_sources, target_net_id)
		# dead unit, remove from all orders and remove node from game
		if target.curr_health <= 0:
			_cleanup_dead_unit(target)
		else:
			target.set_health_bar()
	
	# deal melee damage
	target_ids = melee_dmg.keys()
	target_ids.sort()
	for target_unit_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_unit_net_id)
		if target == null:
			continue
		target.curr_health -= melee_dmg.get(target_unit_net_id, 0)
	for target_unit_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_unit_net_id)
		if target == null:
			continue
		_assign_last_damaged_by(target, melee_sources, target.net_id)
		# dead unit, remove from all orders and remove node from game
		if target.curr_health <= 0:
			if target_unit_net_id in melee_attacks.keys():
				var attacks = melee_attacks.get(target_unit_net_id, [])
				attacks.sort_custom(func(a,b): return a[1] < b[1])
				var occupant = $GameBoardNode.get_unit_at(target.grid_pos)
				var allow_move = occupant == null or occupant == target
				if allow_move:
					for unit_priority_pair in attacks:
						var unit = unit_manager.get_unit_by_net_id(unit_priority_pair[0])
						if unit != null and unit.curr_health > 0:
							unit.set_grid_position(target.grid_pos)
							break
				pass
			_cleanup_dead_unit(target)
		else:
			target.set_health_bar()
	$UI._draw_attacks()
	$UI._draw_paths()
	$UI._draw_supports()
	$GameBoardNode/FogOfWar._update_fog()

func _apply_sabotage_at(tile: Vector2i) -> bool:
	var state = _structure_state(tile)
	if state.is_empty():
		return false
	var status = str(state.get("status", ""))
	var stype = str(state.get("type", ""))
	if status == STRUCT_STATUS_BUILDING:
		buildable_structures.erase(tile)
		if stype == STRUCT_MANA_POOL:
			_clear_mana_pool_assignment(tile)
			_recalculate_mana_caps()
		return true
	if status == STRUCT_STATUS_INTACT:
		state["status"] = STRUCT_STATUS_DISABLED
		buildable_structures[tile] = state
		if stype == STRUCT_MANA_POOL:
			_recalculate_mana_caps()
		return false
	if status == STRUCT_STATUS_DISABLED:
		buildable_structures.erase(tile)
		if stype == STRUCT_MANA_POOL:
			_clear_mana_pool_assignment(tile)
			_recalculate_mana_caps()
		return true
	return false

func _apply_repair_at(player_id: String, unit, tile: Vector2i) -> void:
	if unit == null:
		return
	if tile == unit.grid_pos:
		var state = _structure_state(tile)
		if not state.is_empty():
			if str(state.get("owner", "")) != player_id:
				return
			if str(state.get("status", "")) != STRUCT_STATUS_DISABLED:
				return
			state["status"] = STRUCT_STATUS_INTACT
			buildable_structures[tile] = state
			if str(state.get("type", "")) == STRUCT_MANA_POOL:
				_recalculate_mana_caps()
			return
		var same_tile = $GameBoardNode.get_structure_unit_at(tile)
		if same_tile != null and (same_tile.is_base or same_tile.is_tower):
			if same_tile.player_id != player_id:
				return
			if same_tile.curr_health >= same_tile.max_health:
				return
			same_tile.curr_health = min(same_tile.max_health, same_tile.curr_health + REPAIR_AMOUNT)
			same_tile.set_health_bar()
		return
	var target = $GameBoardNode.get_structure_unit_at(tile)
	if target == null or not (target.is_base or target.is_tower):
		return
	if target.player_id != player_id:
		return
	if target.curr_health >= target.max_health:
		return
	target.curr_health = min(target.max_health, target.curr_health + REPAIR_AMOUNT)
	target.set_health_bar()

func _finish_structure_build(tile: Vector2i, state: Dictionary) -> void:
	var owner = str(state.get("owner", ""))
	var stype = str(state.get("type", ""))
	if stype == STRUCT_SPAWN_TOWER:
		buildable_structures.erase(tile)
		if owner == "":
			return
		if not tower_positions.has(owner):
			tower_positions[owner] = []
		if not spawn_tower_positions.has(owner):
			spawn_tower_positions[owner] = []
		tower_positions[owner].append(tile)
		spawn_tower_positions[owner].append(tile)
		structure_positions.append(tile)
		var tower_unit = unit_manager.spawn_unit("tower", tile, owner, false)
		if tower_unit != null:
			tower_unit.is_spawn_tower = true
			if tower_unit.has_method("_update_owner_overlay"):
				tower_unit._update_owner_overlay()
		return
	if stype == STRUCT_MANA_POOL and not mana_pool_mines.has(tile):
		var mine_choice = state.get("mana_mine", Vector2i(-9999, -9999))
		if typeof(mine_choice) == TYPE_VECTOR2I and mine_choice != Vector2i(-9999, -9999):
			mana_pool_mines[tile] = mine_choice
	state["status"] = STRUCT_STATUS_INTACT
	buildable_structures[tile] = state
	if stype == STRUCT_MANA_POOL:
		_recalculate_mana_caps()

func _apply_build_at(player_id: String, unit, order: Dictionary) -> void:
	if unit == null:
		return
	var raw_tile = order.get("target_tile", unit.grid_pos)
	if typeof(raw_tile) != TYPE_VECTOR2I:
		return
	var tile: Vector2i = raw_tile
	if unit.grid_pos != tile:
		return
	var struct_type = str(order.get("structure_type", ""))
	if struct_type == "":
		return
	var assigned_pool := false
	var state = _structure_state(tile)
	if state.is_empty():
		var turns = _structure_build_turns(struct_type, tile)
		var turn_cost = _structure_turn_cost(struct_type)
		state = {
			"type": struct_type,
			"owner": player_id,
			"status": STRUCT_STATUS_BUILDING,
			"build_left": turns,
			"build_total": turns,
			"turn_cost": turn_cost
		}
		if struct_type == STRUCT_MANA_POOL:
			var mine_choice = order.get("mana_mine", Vector2i(-9999, -9999))
			if typeof(mine_choice) != TYPE_VECTOR2I or mine_choice == Vector2i(-9999, -9999):
				mine_choice = _pick_mana_pool_mine(tile)
			if mine_choice == Vector2i(-9999, -9999):
				return
			state["mana_mine"] = mine_choice
			mana_pool_mines[tile] = mine_choice
			assigned_pool = true
	elif str(state.get("type", "")) == STRUCT_ROAD and str(state.get("status", "")) == STRUCT_STATUS_INTACT and struct_type == STRUCT_RAIL:
		var rail_turns = _structure_build_turns(STRUCT_RAIL, tile)
		state = {
			"type": STRUCT_RAIL,
			"owner": player_id,
			"status": STRUCT_STATUS_BUILDING,
			"build_left": rail_turns,
			"build_total": rail_turns,
			"turn_cost": _structure_turn_cost(STRUCT_RAIL)
		}
	else:
		if str(state.get("type", "")) != struct_type:
			return
		if str(state.get("status", "")) != STRUCT_STATUS_BUILDING:
			return
		if struct_type == STRUCT_MANA_POOL and not mana_pool_mines.has(tile):
			var existing_mine = state.get("mana_mine", Vector2i(-9999, -9999))
			if typeof(existing_mine) == TYPE_VECTOR2I and existing_mine != Vector2i(-9999, -9999):
				mana_pool_mines[tile] = existing_mine
	var turn_cost = int(state.get("turn_cost", _structure_turn_cost(struct_type)))
	if turn_cost > 0:
		if player_gold[player_id] < turn_cost:
			unit.auto_build = false
			unit.auto_build_type = ""
			if struct_type == STRUCT_MANA_POOL and assigned_pool:
				_clear_mana_pool_assignment(tile)
			return
		player_gold[player_id] -= turn_cost
	var remaining = int(state.get("build_left", 0)) - 1
	state["build_left"] = remaining
	if remaining <= 0:
		_finish_structure_build(tile, state)
		unit.auto_build = false
		unit.auto_build_type = ""
	else:
		buildable_structures[tile] = state

func _process_engineering() -> void:
	var sabotage_orders := []
	var repair_orders := []
	var build_orders := []
	var sabotaged_tiles := {}
	var build_tiles := {}

	for player in ["player1", "player2"]:
		var unit_ids = player_orders[player].keys()
		unit_ids.sort()
		for unit_net_id in unit_ids:
			if unit_net_id is not int:
				continue
			var order = player_orders[player][unit_net_id]
			match order.get("type", ""):
				"sabotage":
					sabotage_orders.append({"player": player, "unit_net_id": unit_net_id, "order": order})
				"repair":
					repair_orders.append({"player": player, "unit_net_id": unit_net_id, "order": order})
				"build":
					build_orders.append({"player": player, "unit_net_id": unit_net_id, "order": order})
					var raw_tile = order.get("target_tile", Vector2i(-9999, -9999))
					if typeof(raw_tile) == TYPE_VECTOR2I:
						build_tiles[raw_tile] = true

	for entry in sabotage_orders:
		var player_id = entry["player"]
		var unit = unit_manager.get_unit_by_net_id(entry["unit_net_id"])
		if unit == null or unit.curr_health <= 0:
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		var raw_tile = entry["order"].get("target_tile", unit.grid_pos)
		if typeof(raw_tile) != TYPE_VECTOR2I:
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		var tile: Vector2i = raw_tile
		if tile == unit.grid_pos:
			var state = _structure_state(tile)
			if not state.is_empty() or build_tiles.has(tile):
				sabotaged_tiles[tile] = true
			_apply_sabotage_at(tile)
		_remove_player_order(player_id, entry["unit_net_id"])

	for entry in repair_orders:
		var player_id = entry["player"]
		var unit = unit_manager.get_unit_by_net_id(entry["unit_net_id"])
		if unit == null or unit.curr_health <= 0:
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		var raw_tile = entry["order"].get("target_tile", unit.grid_pos)
		if typeof(raw_tile) == TYPE_VECTOR2I:
			_apply_repair_at(player_id, unit, raw_tile)
		_remove_player_order(player_id, entry["unit_net_id"])

	for entry in build_orders:
		var player_id = entry["player"]
		var unit = unit_manager.get_unit_by_net_id(entry["unit_net_id"])
		if unit == null or unit.curr_health <= 0:
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		var raw_tile = entry["order"].get("target_tile", unit.grid_pos)
		if typeof(raw_tile) == TYPE_VECTOR2I and sabotaged_tiles.has(raw_tile):
			_remove_player_order(player_id, entry["unit_net_id"])
			continue
		_apply_build_at(player_id, unit, entry["order"])
		_remove_player_order(player_id, entry["unit_net_id"])
	$GameBoardNode/FogOfWar._update_fog()

	refresh_structure_markers()
	$GameBoardNode/FogOfWar._update_fog()

func _process_neutral_attacks() -> void:
	var neutral_units = $GameBoardNode.get_all_units().get("neutral", [])
	if neutral_units.size() == 0:
		return
	var neutral_dmg: Dictionary = {}
	var neutral_sources: Dictionary = {}
	var retaliation_dmg: Dictionary = {}
	var retaliation_sources: Dictionary = {}

	for neutral in neutral_units:
		if neutral == null or neutral.curr_health <= 0:
			continue
		var attacked = false
		if neutral.unit_type == CAMP_ARCHER_TYPE:
			var candidates = _units_in_range_los(neutral.grid_pos, camp_archer_range)
			if candidates.size() > 0:
				var weights := []
				for unit in candidates:
					weights.append(_target_weight(unit, neutral.grid_pos))
				var idx = _pick_weighted_index(weights)
				if idx >= 0:
					_queue_neutral_attack(neutral, candidates[idx], "ranged", neutral_dmg, neutral_sources, retaliation_dmg, retaliation_sources)
					attacked = true
		elif neutral.unit_type == DRAGON_TYPE:
			var cleave_candidates = _units_adjacent(neutral.grid_pos)
			var melee_set := {}
			if cleave_candidates.size() > 0:
				var weights := []
				for unit in cleave_candidates:
					weights.append(_target_weight(unit, neutral.grid_pos))
				var idx = _pick_weighted_index(weights)
				if idx >= 0:
					var primary = cleave_candidates[idx]
					var selected := [primary]
					melee_set[primary.net_id] = true
					var remaining := cleave_candidates.duplicate()
					remaining.erase(primary)
					var extra_slots = max(0, dragon_cleave_targets - 1)
					for _i in range(extra_slots):
						var adj_candidates := []
						var adj_weights := []
						for unit in remaining:
							var adjacent = false
							for picked in selected:
								if _positions_adjacent(picked.grid_pos, unit.grid_pos):
									adjacent = true
									break
							if not adjacent:
								continue
							adj_candidates.append(unit)
							adj_weights.append(_target_weight(unit, neutral.grid_pos))
						if adj_candidates.is_empty():
							break
						var pick_idx = _pick_weighted_index(adj_weights)
						if pick_idx < 0:
							break
						var extra = adj_candidates[pick_idx]
						selected.append(extra)
						melee_set[extra.net_id] = true
						remaining.erase(extra)
					for target in selected:
						_queue_neutral_attack(neutral, target, "melee", neutral_dmg, neutral_sources, retaliation_dmg, retaliation_sources)
					attacked = true
			var fire_candidates = _units_in_range_los(neutral.grid_pos, dragon_fire_range)
			if fire_candidates.size() > 0:
				var overlap_penalty := 0.4
				var weights := []
				for unit in fire_candidates:
					var w = _target_weight(unit, neutral.grid_pos)
					if melee_set.has(unit.net_id):
						w *= overlap_penalty
					weights.append(w)
				var idx = _pick_weighted_index(weights)
				if idx >= 0:
					var primary = fire_candidates[idx]
					var selected := [primary]
					var remaining := fire_candidates.duplicate()
					remaining.erase(primary)
					var extra_slots = 1
					for _i in range(extra_slots):
						var adj_candidates := []
						var adj_weights := []
						for unit in remaining:
							var adjacent = false
							for picked in selected:
								if _positions_adjacent(picked.grid_pos, unit.grid_pos):
									adjacent = true
									break
							if not adjacent:
								continue
							var w = _target_weight(unit, neutral.grid_pos)
							if melee_set.has(unit.net_id):
								w *= overlap_penalty
							adj_candidates.append(unit)
							adj_weights.append(w)
						if adj_candidates.is_empty():
							break
						var pick_idx = _pick_weighted_index(adj_weights)
						if pick_idx < 0:
							break
						var extra = adj_candidates[pick_idx]
						selected.append(extra)
						remaining.erase(extra)
					for target in selected:
						_queue_neutral_attack(neutral, target, "ranged", neutral_dmg, neutral_sources, retaliation_dmg, retaliation_sources)
					attacked = true
		if not attacked and neutral.curr_health < neutral.max_health:
			neutral.curr_health = min(neutral.max_health, neutral.curr_health + neutral.regen)
			neutral.set_health_bar()

	var target_ids = neutral_dmg.keys()
	target_ids.sort()
	for target_net_id in target_ids:
		var target = unit_manager.get_unit_by_net_id(target_net_id)
		if target == null:
			continue
		target.curr_health -= neutral_dmg[target_net_id]
		_assign_last_damaged_by(target, neutral_sources, target_net_id)
		if target.curr_health <= 0:
			_cleanup_dead_unit(target)
		else:
			target.set_health_bar()

	var retaliation_ids = retaliation_dmg.keys()
	retaliation_ids.sort()
	for target_net_id in retaliation_ids:
		var target = unit_manager.get_unit_by_net_id(target_net_id)
		if target == null:
			continue
		target.curr_health -= retaliation_dmg[target_net_id]
		_assign_last_damaged_by(target, retaliation_sources, target_net_id)
		if target.curr_health <= 0:
			_cleanup_dead_unit(target)
		else:
			target.set_health_bar()

	$UI._draw_attacks()
	$UI._draw_paths()
	$UI._draw_supports()
	$GameBoardNode/FogOfWar._update_fog()

# Resolve a single enemy swap as a symmetric melee clash.
func _mg_resolve_enemy_swap(a_pos: Vector2i, b_pos: Vector2i) -> void:
	var ua = $GameBoardNode.get_unit_at(a_pos)
	var ub = $GameBoardNode.get_unit_at(b_pos)
	if ua == null or ub == null:
		return

	var dmg_a = calculate_damage(ua, ub, "move", 1)	# [atk_in, def_in]
	var dmg_b = calculate_damage(ub, ua, "move", 1)
	
	dealt_dmg_report(ua, ub, dmg_b[1], dmg_a[1], true, "move")
	ua.curr_health -= dmg_b[1]
	ub.curr_health -= dmg_a[1]
	ua.last_damaged_by = ub.player_id
	ub.last_damaged_by = ua.player_id
	ua.set_health_bar()
	ub.set_health_bar()

	var ua_dead = ua.curr_health <= 0
	var ub_dead = ub.curr_health <= 0
	
	if ua_dead and ub_dead:
		_cleanup_dead_unit(ua)
		_cleanup_dead_unit(ub)
		return

	if ua_dead and not ub_dead:
		_cleanup_dead_unit(ua)
		ub.set_grid_position(a_pos)
		NetworkManager.player_orders[ub.player_id].erase(ub.net_id)
		ub.is_moving = false
		return

	if ub_dead and not ua_dead:
		_cleanup_dead_unit(ub)
		ua.set_grid_position(b_pos)
		NetworkManager.player_orders[ua.player_id].erase(ua.net_id)
		ua.is_moving = false
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
func _mg_tile_fifo_commit(t: Vector2i, entrants: Array, stationary_defender: Node, retaliator_override: Node = null, fallback_defender: Node = null) -> Variant:
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
					if $GameBoardNode.is_occupied(t):
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

		# Attacker hits defender; optional retaliator can strike back after defender takes damage
		var dmg = calculate_damage(atk, stationary_defender, "move", 1)
		stationary_defender.curr_health -= dmg[1]
		stationary_defender.last_damaged_by = atk.player_id
		stationary_defender.set_health_bar()
		var retaliator = retaliator_override
		if retaliator == null:
			if stationary_defender != null and (stationary_defender.is_base or stationary_defender.is_tower):
				retaliator = null
			else:
				retaliator = stationary_defender
		var retaliate = retaliator != null and retaliator.is_defending
		var ret_dmg = 0.0
		if retaliate:
			ret_dmg = dmg[0]
			if retaliator != stationary_defender:
				ret_dmg = calculate_damage(atk, retaliator, "move", 1)[0]
			atk.curr_health -= ret_dmg
			atk.last_damaged_by = retaliator.player_id
			atk.set_health_bar()
		dealt_dmg_report(atk, stationary_defender, ret_dmg, dmg[1], retaliate, "move")

		# Attacker fought this tick -> stop and clear order
		atk.is_moving = false
		if NetworkManager.player_orders.has(atk.player_id):
			NetworkManager.player_orders[atk.player_id].erase(atk.net_id)

		# Handle deaths
		if atk.curr_health <= 0:
			_cleanup_dead_unit(atk)
			enemy_item = null
		if stationary_defender.curr_health <= 0:
			# Defender died at atk's hand; remember killer if alive
			if atk != null and atk.curr_health > 0:
				killer_item = {"from": atk.grid_pos, "unit": atk, "fought": true}
			# Remove defender from board
			_cleanup_dead_unit(stationary_defender)
			stationary_defender = null
			if fallback_defender != null and is_instance_valid(fallback_defender) and fallback_defender.curr_health > 0:
				stationary_defender = fallback_defender
				retaliator_override = null
				def_item = {"from": stationary_defender.grid_pos, "unit": stationary_defender, "fought": false, "is_defender": true}
				continue
			# loop continues; next iteration will fall into the contested-empty branch
			continue

		# Defender lives -> keep defender marker locked at the very front for next enemy
		# (do nothing: def_item is already at front)
	# unreachable
	return null

func _can_hop_over_builder(mover, blocker_tile: Vector2i, landing_tile: Vector2i) -> bool:
	if mover == null:
		return false
	if not _tile_is_road_or_rail(mover.grid_pos):
		return false
	if not _tile_is_road_or_rail(blocker_tile):
		return false
	if not _tile_is_road_or_rail(landing_tile):
		return false
	var blocker = $GameBoardNode.get_unit_at(blocker_tile)
	if blocker == null:
		return false
	if not blocker.is_builder:
		return false
	if blocker.player_id != mover.player_id:
		return false
	if blocker.is_moving:
		return false
	if $GameBoardNode.get_unit_at(landing_tile) != null:
		return false
	return true


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
		ua.last_damaged_by = ub.player_id
		ub.last_damaged_by = ua.player_id
		ua.set_health_bar()
		ub.set_health_bar()
		dealt_dmg_report(ua, ub, d21[1], d12[1], true, "move")

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
			_cleanup_dead_unit(ua)
		if ub_dead:
			_cleanup_dead_unit(ub)

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
		var structure_defender = null
		var structure_garrison = null
		var s = $GameBoardNode.get_structure_unit_at(t)
		if s != null and (s.is_base or s.is_tower):
			var has_enemy = false
			for src in entrants:
				var u = $GameBoardNode.get_unit_at(src)
				if u != null and u.player_id != s.player_id:
					has_enemy = true
					break
			if has_enemy:
				structure_defender = s
				if occ != null and occ.player_id == s.player_id and not occ.is_moving:
					structure_garrison = occ
		if structure_defender != null:
			winner_from = _mg_tile_fifo_commit(t, entrants, structure_defender, structure_garrison, structure_garrison)
		elif occ != null and not occ.is_moving:
			winner_from = _mg_tile_fifo_commit(t, entrants, occ)
		else:
			winner_from = _mg_tile_fifo_commit(t, entrants, null)

		if typeof(winner_from) == TYPE_VECTOR2I:
			# The unit that entered t came from winner_from; that tile is the next sink
			var w = $GameBoardNode.get_unit_at(winner_from)
			if w != null and w.curr_health > 0:
				var occ_now = $GameBoardNode.get_unit_at(t)
				if occ_now != null and occ_now != w:
					if not occ_now.is_moving:
						w.is_moving = false
						if NetworkManager.player_orders.has(w.player_id):
							NetworkManager.player_orders[w.player_id].erase(w.net_id)
					continue
				w.set_grid_position(t)
			#pending.append(winner_from)



func _handle_trap_trigger(unit, tile: Vector2i) -> bool:
	if unit == null:
		return false
	var state = _structure_state(tile)
	if state.is_empty():
		return false
	if str(state.get("type", "")) != STRUCT_TRAP:
		return false
	if str(state.get("status", "")) != STRUCT_STATUS_INTACT:
		return false
	var trap_owner = str(state.get("owner", ""))
	var unit_owner = unit.player_id
	if trap_owner == unit_owner:
		return false
	unit.curr_health -= TRAP_DAMAGE
	unit.last_damaged_by = trap_owner
	if unit.curr_health <= 0:
		_cleanup_dead_unit(unit)
	else:
		unit.set_health_bar()
	state["status"] = STRUCT_STATUS_DISABLED
	buildable_structures[tile] = state
	unit.is_moving = false
	_remove_player_order(unit_owner, unit.net_id)
	return true

func _process_move():
	if movement_phase_count >= MAX_MOVEMENT_PHASES:
		force_skip_movement_phase()
		if neutral_step_index == -1:
			neutral_step_index = exec_steps.size()
			exec_steps.append(func(): _process_neutral_attacks())
		return
	movement_phase_count += 1
	var units: Array = $GameBoardNode.get_all_units_flat(false)
	var hop_units := {}
	for u in units:
		if u == null or not u.is_moving:
			continue
		var orders = NetworkManager.player_orders.get(u.player_id, {})
		if not orders.has(u.net_id):
			continue
		var ord = orders[u.net_id]
		if ord.get("type", "") != "move":
			continue
		var path = ord.get("path", [])
		if not (path is Array) or path.size() < 2:
			continue
		if path[0] != u.grid_pos:
			continue
		var next_tile: Vector2i = path[1]
		var hop_tile: Vector2i = path[2] if path.size() > 2 else Vector2i(-9999, -9999)
		if path.size() > 2 and _can_hop_over_builder(u, next_tile, hop_tile):
			u.moving_to = hop_tile
			hop_units[u.net_id] = true
		else:
			u.moving_to = next_tile
	var mg = MovementGraph.new()
	mg.build(units)
	var start_positions := {}
	for u in units:
		if u != null:
			start_positions[u.net_id] = u.grid_pos
	
	# 1. Resolve enemy swaps first
	for pair in mg.detect_enemy_swaps():
		_mg_resolve_enemy_swap(pair["a"], pair["b"])

	# Rebuild after swaps
	units = $GameBoardNode.get_all_units_flat(false)
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
	var rotated_tiles := {}
	for comp in sccs:
		if mg.scc_is_uncontested_rotation(comp, winners_by_tile):
			var touched = _mg_commit_rotation(comp, mg, winners_by_tile, vacated)
			for t in touched.keys():
				rotated_tiles[t] = true
	
	units = $GameBoardNode.get_all_units_flat(false)
	mg.build(units)
	entrants_all = mg.entries_all()
	
	var sccs_all: Array = mg.strongly_connected_components(mg.graph)
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
					var winner_tile = _mg_tile_fifo_commit(node, fight_list, null)  # fight-only; ignore winner
					if winner_tile != null:
						var winner = $GameBoardNode.get_unit_at(winner_tile)
						winner.is_moving = true

	# Rebuild graph & entrants after these fights (is_moving/HP may have changed)
	units = $GameBoardNode.get_all_units_flat(false)
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

	units = $GameBoardNode.get_all_units_flat(false)
	mg.build(units)
	entrants_all = mg.entries_all()
	
	# 7. Pop one path step for every unit that moved; clear finished orders
	for u in units:
		var orders = NetworkManager.player_orders.get(u.player_id, {})
		if orders.has(u.net_id):
			var ord = orders[u.net_id]
			if ord.has("path") and ord["path"].size() > 1:
				var path = ord["path"]
				if hop_units.has(u.net_id) and path.size() > 2 and u.grid_pos == path[2]:
					path.pop_front()
					path.pop_front()
					ord["path"] = path
				elif u.grid_pos == path[1]:
					path.pop_front()
					ord["path"] = path
				else:
					continue
				if ord["path"].size() <= 1:
					u.is_moving = false
					orders.erase(u.net_id)
				else:
					u.moving_to = ord["path"][1]
				var committed = committed_orders.get(u.player_id, {})
				if committed.has(u.net_id):
					if ord.has("path") and ord["path"].size() > 1:
						committed[u.net_id]["path"] = ord["path"].duplicate()
					else:
						committed.erase(u.net_id)
	
	var triggered_trap = false
	for u in units:
		if u == null or u.curr_health <= 0:
			continue
		if start_positions.get(u.net_id, u.grid_pos) == u.grid_pos:
			continue
		if _handle_trap_trigger(u, u.grid_pos):
			triggered_trap = true
	if triggered_trap:
		refresh_structure_markers()
	var reset_respawn = false
	for u in units:
		if u == null:
			continue
		if start_positions.get(u.net_id, u.grid_pos) == u.grid_pos:
			continue
		if u.grid_pos in camps["basic"] and camp_respawns.has(u.grid_pos):
			camp_respawns[u.grid_pos] = _roll_camp_respawn()
			reset_respawn = true
		if u.grid_pos in camps["dragon"] and dragon_respawns.has(u.grid_pos):
			dragon_respawns[u.grid_pos] = _roll_dragon_respawn()
			reset_respawn = true
	if reset_respawn:
		update_neutral_markers()

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
	if neutral_step_index == -1:
		neutral_step_index = exec_steps.size()
		exec_steps.append(func(): _process_neutral_attacks())

# --------------------------------------------------------
# Phase 3: Execution — process orders
# --------------------------------------------------------
func _do_execution() -> void:
	current_phase = Phase.EXECUTION
	print("Executing orders...")
	for unit in $GameBoardNode.get_all_units_flat():
		if unit != null:
			unit.is_looking_out = false
	for player in ["player1", "player2"]:
		var orders = committed_orders.get(player, {})
		for order in orders.values():
			if order.get("type", "") != "lookout":
				continue
			var unit = unit_manager.get_unit_by_net_id(int(order.get("unit_net_id", -1)))
			if unit != null and unit.player_id == player:
				unit.is_looking_out = true
	$UI/CancelDoneButton.visible = false
	$GameBoardNode/OrderReminderMap.clear()
	for child in dmg_report.get_children():
		child.queue_free()
	damage_log = { "player1": [], "player2": [] }
	neutral_step_index = -1
	exec_steps = [
		func(): _process_spawns(),
		func(): _process_spells(),
		func(): _process_attacks(),
		func(): _process_engineering(),
		func(): _process_move()
	]
	movement_phase_count = 0
	step_index = 0
	_run_next_step()

func _run_next_step():
	$GameBoardNode/FogOfWar._update_fog()
	if step_index >= exec_steps.size():
		emit_signal("execution_complete")
		if _is_host():
			_broadcast_state()
			NetworkManager.broadcast_execution_complete()
		if get_tree().get_multiplayer().is_server():
			call_deferred("_game_loop")
		return
	exec_steps[step_index].call()
	_broadcast_state()
	emit_signal("execution_paused", step_index)
	if _is_host():
		NetworkManager.broadcast_execution_paused(step_index, neutral_step_index)

func resume_execution():
	if not _is_host():
		return
	step_index += 1
	_run_next_step()

func start_phase_locally(phase_name: String) -> void:
	print("[TurnManager] start_phase_locally:", phase_name)
	player_orders = NetworkManager.player_orders
	if not _is_host():
		match phase_name:
			"UPKEEP":
				current_phase = Phase.UPKEEP
				$UI/CancelGameButton.visible = false
				$UI/DamagePanel.visible = true
			"ORDERS":
				current_phase = Phase.ORDERS
				current_player = local_player_id
				emit_signal("orders_phase_begin", local_player_id)
			"EXECUTION":
				current_phase = Phase.EXECUTION
				emit_signal("orders_phase_end")
		return
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
func buy_unit(player: String, unit_type: String, grid_pos: Vector2i) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"cost": 0,
		"unit_net_id": -1
	}
	if not _is_host():
		result["reason"] = "not_host"
		return result
	var scene: PackedScene = null
	if unit_type.to_lower() == "archer":
		scene = archer_scene
	elif unit_type.to_lower() == "soldier":
		scene = soldier_scene
	elif unit_type.to_lower() == "scout":
		scene = scout_scene
	elif unit_type.to_lower() == "miner":
		scene = miner_scene
	elif unit_type.to_lower() == "crystal_miner":
		scene = crystal_miner_scene
	elif unit_type.to_lower() == "builder":
		scene = unit_manager.builder_scene
	elif unit_type.to_lower() == "wizard":
		scene = wizard_scene
	elif unit_type.to_lower() == "phalanx":
		scene = phalanx_scene
	elif unit_type.to_lower() == "cavalry":
		scene = cavalry_scene
	else:
		push_error("Unknown unit type '%s'" % unit_type)
		print("Unknown unit type '%s'" % unit_type)
		result["reason"] = "unknown_unit"
		return result
	if scene == null:
		push_error("Unit scene for '%s' not assigned in Inspector" % unit_type)
		print("Unit scene for '%s' not assigned in Inspector" % unit_type)
		result["reason"] = "unknown_unit"
		return result
	var spawn_limit = _spawn_limit_for_tile(player, grid_pos)
	if spawn_limit == "road" and unit_type.to_lower() not in SPAWN_TOWER_ROAD_UNITS:
		result["reason"] = "invalid_tile"
		return result

	# check cost
	var tmp_unit = scene.instantiate()
	var cost = tmp_unit.get("cost")
	tmp_unit.queue_free()
	result["cost"] = int(cost)
	if player_gold[player] < cost:
		print("%s cannot afford a %s (needs %d gold)" % [player, unit_type, cost])
		result["reason"] = "not_enough_gold"
		return result

	# deduct gold & spawn
	player_gold[player] -= cost
	var unit = unit_manager.spawn_unit(unit_type, grid_pos, player, false)
	$GameBoardNode/FogOfWar._update_fog()
	print("%s bought a %s at %s for %d gold" % [player, unit_type, grid_pos, cost])
	result["ok"] = true
	result["unit_net_id"] = unit.net_id
	return result

func undo_buy_unit(player_id: String, unit_net_id: int) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"refund": 0
	}
	if not _is_host():
		result["reason"] = "not_host"
		return result
	var unit = unit_manager.get_unit_by_net_id(unit_net_id)
	if unit == null:
		result["reason"] = "not_found"
		return result
	if unit.player_id != player_id:
		result["reason"] = "not_owner"
		return result
	if unit.is_base or unit.is_tower:
		result["reason"] = "invalid_unit"
		return result
	if not unit.just_purchased:
		result["reason"] = "not_just_purchased"
		return result
	var refund = int(unit.cost)
	player_gold[player_id] += refund
	result["refund"] = refund
	player_orders[player_id].erase(unit.net_id)
	NetworkManager.player_orders[player_id].erase(unit.net_id)
	$GameBoardNode.vacate(unit.grid_pos, unit)
	_refresh_tile_after_unit_change(unit.grid_pos)
	unit_manager.unit_by_net_id.erase(unit.net_id)
	unit.queue_free()
	result["ok"] = true
	return result

# --------------------------------------------------------
# Stub: determine if a player controls a given tile
# --------------------------------------------------------
func _controls_tile(player: String, pos: Vector2i) -> bool:
	if player == "":
		return false
	var unit = $GameBoardNode.get_unit_at(pos)
	if unit != null and unit.player_id != player:
		return false
	if base_positions.get(player, Vector2i(999999, 999999)) == pos:
		return true
	if pos in mines.get(player, []):
		return true
	return false
