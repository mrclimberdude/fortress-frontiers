extends TileMapLayer

@export var columns: int      = 18
@export var rows:    int      = 15
@export var tile_size: Vector2 = Vector2(170, 192)
@export var spacing:   Vector2 = Vector2(0,  0)
@export var visiblity: Dictionary = {} # {player:{cell:0/1/2}}
# 0 unexplored, 1 explored, 2 visible

const FOG_Z_INDEX: int = 100
const DRAGON_GHOST_ICON = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Animals Light/HSI_icon_036l.png")
const DRAGON_GHOST_Z: int = 99
const DRAGON_REWARD_GOLD: String = "gold"
const DRAGON_REWARD_MELEE: String = "melee_bonus"
const DRAGON_REWARD_RANGED: String = "ranged_bonus"
const DRAGON_REWARD_MANA: String = "mana_income"
const DRAGON_GHOST_ALPHA: float = 0.75

func _dragon_reward_color(reward: String) -> Color:
	match reward:
		DRAGON_REWARD_GOLD:
			return Color(1, 0.84, 0, DRAGON_GHOST_ALPHA)
		DRAGON_REWARD_MELEE:
			return Color(0.9, 0.35, 0.25, DRAGON_GHOST_ALPHA)
		DRAGON_REWARD_RANGED:
			return Color(0.35, 0.6, 1, DRAGON_GHOST_ALPHA)
		DRAGON_REWARD_MANA:
			return Color(0.35, 0.85, 0.35, DRAGON_GHOST_ALPHA)
		_:
			return Color(1, 1, 1, DRAGON_GHOST_ALPHA)

func _get_neutral_memory_root() -> Node2D:
	var hex_map = $"../HexTileMap"
	if hex_map == null:
		return null
	var root = hex_map.get_node_or_null("NeutralMemorySprites")
	if root == null:
		root = Node2D.new()
		root.name = "NeutralMemorySprites"
		hex_map.add_child(root)
	return root

func _set_base_tile_for_fog(cell: Vector2i, pid: String) -> void:
	var hex_map = $"../HexTileMap"
	var tm = $"../.."
	if hex_map == null or tm == null:
		return
	for player in ["player1", "player2"]:
		if tm.spawn_tower_positions.has(player) and cell in tm.spawn_tower_positions[player]:
			var src = hex_map.tile_set.get_source_id(0)
			hex_map.set_cell(cell, src, hex_map.ground_tile)
			return
	var src = hex_map.tile_set.get_source_id(0)
	var ground = hex_map.ground_tile
	var tint = ground
	var is_camp = cell in tm.camps["basic"]
	var is_dragon = cell in tm.camps["dragon"]
	if is_camp or is_dragon:
		if pid in ["", "neutral", "camp", "dragon"]:
			var camp_key = "dragon" if is_dragon else "camp"
			tint = hex_map.camp_atlas_tiles.get(camp_key, ground)
		else:
			tint = hex_map.player_atlas_tiles.get(pid, ground)
	elif cell in tm.structure_positions:
		tint = hex_map.structure_atlas_tiles.get(pid, ground)
		for player in ["player1", "player2", "unclaimed"]:
			if cell in tm.mines[player]:
				tint = hex_map.structure_atlas_tiles.get(player, ground)
				break
	else:
		tint = hex_map.player_atlas_tiles.get(pid, ground)
	hex_map.set_cell(cell, src, tint)

func _spawn_tower_cell_map(tm_root) -> Dictionary:
	var cells := {}
	if tm_root == null:
		return cells
	var positions = tm_root.spawn_tower_positions
	if positions == null or not (positions is Dictionary):
		return cells
	for player_id in ["player1", "player2"]:
		if positions.has(player_id):
			for cell in positions[player_id]:
				cells[cell] = true
	return cells

func _ready() -> void:
	z_index = FOG_Z_INDEX
	reset_fog()

func reset_fog() -> void:
	var hex_map = $"../HexTileMap"
	if hex_map == null:
		return
	var cells = hex_map.used_cells
	clear()
	var explored = $"../ExploredFog"
	if explored != null:
		explored.clear()
	for player in ["player1", "player2"]:
		visiblity[player] = {}
		for cell in cells:
			visiblity[player][cell] = 0
			set_cell(cell, tile_set.get_source_id(0), Vector2i(3,0))

func _update_fog():
	var units = $"..".get_all_units()
	var all_units = $"..".get_all_units_flat()
	var explored = $"../ExploredFog"
	var terrain_map = $"../TerrainMap"
	var hex_map = $"../HexTileMap"
	var tm_root = $"../.."
	var neutral_root = _get_neutral_memory_root()
	var spawn_tower_cells := _spawn_tower_cell_map(tm_root)
	if neutral_root != null:
		for child in neutral_root.get_children():
			child.queue_free()
	if terrain_map != null and explored != null:
		if explored.tile_set != terrain_map.tile_set:
			explored.tile_set = terrain_map.tile_set
	# make all non-local units invisible (including neutrals)
	for unit in all_units:
		if unit.player_id != tm_root.local_player_id:
			unit.visible = false
	for structure in $"..".get_all_structures():
		if structure == null or not is_instance_valid(structure):
			continue
		structure.z_index = 6
	for player in ["player1", "player2"]:
		# reset all visible cells to explored
		for cell in visiblity[player].keys():
			if visiblity[player][cell] == 2:
				visiblity[player][cell] = 1
		# set all cells within sight range of all of a players units to visible
		for unit in units[player]:
			var in_sight
			if unit.just_purchased and not unit.is_base and not unit.is_tower:
				in_sight = $"..".get_reachable_tiles(unit.grid_pos, 0, "visibility")
			else:
				if unit.is_looking_out:
					in_sight = $"..".get_reachable_tiles(unit.grid_pos, unit.sight_range + 1, "visibility_over_trees")
				else:
					in_sight = $"..".get_reachable_tiles(unit.grid_pos, unit.sight_range, "visibility")
			for cell in in_sight["tiles"]:
				visiblity[player][cell] = 2
		if tm_root != null and tm_root.has_method("get_ward_vision_tiles"):
			var ward_tiles = tm_root.get_ward_vision_tiles(player)
			for cell in ward_tiles:
				visiblity[player][cell] = 2
		if tm_root != null and tm_root.has_method("update_structure_memory_for"):
			tm_root.update_structure_memory_for(player, visiblity[player])
		if tm_root != null and tm_root.has_method("update_neutral_tile_memory_for"):
			tm_root.update_neutral_tile_memory_for(player, visiblity[player])
		if player == tm_root.local_player_id:
			var neutral_memory = {}
			if tm_root != null and tm_root.has_method("_get_neutral_tile_memory"):
				neutral_memory = tm_root._get_neutral_tile_memory(player)
			for cell in visiblity[player]:
				var tint
				# unexplored tiles set to black
				if visiblity[player][cell] == 0:
					tint = Vector2i(3,0)
					set_cell(cell, tile_set.get_source_id(0), tint)
				# explored tiles set to mist, exploredfog tile set to base board tile
				if visiblity[player][cell] == 1:
					tint = Vector2i(4,0)
					set_cell(cell, tile_set.get_source_id(0), tint, 1)
					if spawn_tower_cells.has(cell) and hex_map != null:
						var base_src = hex_map.tile_set.get_source_id(0)
						hex_map.set_cell(cell, base_src, hex_map.ground_tile)
					if cell in $"../..".structure_positions:
						var structure = $"..".get_structure_at(cell)
						if structure != null and is_instance_valid(structure):
							structure.z_index = 99
					var unit = $"..".get_unit_at(cell)
					if unit != null:
						if unit.player_id != $"../..".local_player_id:
							var pid = ""
							var structure_unit = $"..".get_structure_unit_at(cell)
							if structure_unit != null:
								pid = structure_unit.player_id
							elif cell in $"../..".mines["player1"]:
								pid = "player1"
							elif cell in $"../..".mines["player2"]:
								pid = "player2"
							elif cell in $"../..".mines["unclaimed"]:
								pid = "unclaimed"
							_set_base_tile_for_fog(cell, pid)
					if explored != null and terrain_map != null:
						var src_id = terrain_map.get_cell_source_id(cell)
						if src_id >= 0:
							var atlas = terrain_map.get_cell_atlas_coords(cell)
							var alt = terrain_map.get_cell_alternative_tile(cell)
							explored.set_cell(cell, src_id, atlas, alt)
						else:
							explored.erase_cell(cell)
						if neutral_memory.has(cell):
							var entry = neutral_memory[cell]
							var neutral_type = ""
							var neutral_unit = ""
							var neutral_reward = ""
							if entry is Dictionary:
								neutral_type = str(entry.get("tile", ""))
								neutral_unit = str(entry.get("unit", ""))
								neutral_reward = str(entry.get("reward", ""))
							else:
								neutral_type = str(entry)
							if neutral_type in ["camp", "dragon"]:
								var camp_atlas = hex_map.camp_atlas_tiles.get(neutral_type, hex_map.ground_tile)
								var terrain_src = terrain_map.tile_set.get_source_id(0)
								explored.set_cell(cell, terrain_src, camp_atlas)
							if neutral_unit == "dragon" and neutral_root != null and hex_map != null:
								var ghost = Sprite2D.new()
								ghost.texture = DRAGON_GHOST_ICON
								ghost.modulate = _dragon_reward_color(neutral_reward)
								ghost.position = hex_map.map_to_world(cell) + hex_map.tile_size * 0.5
								ghost.z_index = DRAGON_GHOST_Z
								neutral_root.add_child(ghost)
					elif explored != null:
						explored.erase_cell(cell)
						
				if visiblity[player][cell] == 2:
					erase_cell(cell)
					$"../ExploredFog".erase_cell(cell)
					if spawn_tower_cells.has(cell) and hex_map != null:
						var base_src = hex_map.tile_set.get_source_id(0)
						hex_map.set_cell(cell, base_src, hex_map.ground_tile)
					if cell in $"../..".structure_positions:
						var structure = $"..".get_structure_at(cell)
						if structure != null and is_instance_valid(structure):
							structure.z_index = 6
					var unit = $"..".get_unit_at(cell)
					if unit != null:
						if tm_root != null and tm_root.has_method("is_unit_hidden_to_local") and tm_root.is_unit_hidden_to_local(unit):
							unit.visible = false
						else:
							unit.visible = true
							if unit.player_id == "neutral" and str(unit.unit_type) == "dragon":
								unit.z_index = 7
					var structure_unit = $"..".get_structure_unit_at(cell)
					if structure_unit != null:
						structure_unit.visible = true
	if not $"../../UI/DevPanel/VBoxContainer/FogCheckButton".button_pressed:
		for unit in all_units:
			if tm_root != null and tm_root.has_method("is_unit_hidden_to_local") and tm_root.is_unit_hidden_to_local(unit):
				unit.visible = false
			else:
				unit.visible = true
	if tm_root != null and tm_root.has_method("update_neutral_markers"):
		tm_root.update_neutral_markers()
	if tm_root != null and tm_root.has_method("refresh_structure_markers"):
		tm_root.refresh_structure_markers()
