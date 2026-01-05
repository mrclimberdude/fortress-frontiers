extends TileMapLayer

@export var columns: int      = 18
@export var rows:    int      = 15
@export var tile_size: Vector2 = Vector2(170, 192)
@export var spacing:   Vector2 = Vector2(0,  0)
@export var visiblity: Dictionary = {} # {player:{cell:0/1/2}}
# 0 unexplored, 1 explored, 2 visible

const FOG_Z_INDEX: int = 100

func _set_base_tile_for_fog(cell: Vector2i, pid: String) -> void:
	var hex_map = $"../HexTileMap"
	var tm = $"../.."
	if hex_map == null or tm == null:
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
		if tm_root != null and tm_root.has_method("update_structure_memory_for"):
			tm_root.update_structure_memory_for(player, visiblity[player])
		if player == tm_root.local_player_id:
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
					if cell in $"../..".structure_positions:
						var structure = $"..".get_structure_at(cell)
						if structure != null and is_instance_valid(structure):
							structure.z_index = 99
					var unit = $"..".get_unit_at(cell)
					if unit != null and unit.player_id != $"../..".local_player_id:
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
							var is_camp = false
							var is_dragon = false
							if tm_root != null:
								is_camp = cell in tm_root.camps["basic"]
								is_dragon = cell in tm_root.camps["dragon"]
							if is_camp or is_dragon:
								var camp_key = "dragon" if is_dragon else "camp"
								var camp_atlas = hex_map.camp_atlas_tiles.get(camp_key, hex_map.ground_tile)
								var terrain_src = terrain_map.tile_set.get_source_id(0)
								explored.set_cell(cell, terrain_src, camp_atlas)
							else:
								explored.erase_cell(cell)
					elif explored != null:
						explored.erase_cell(cell)
						
				if visiblity[player][cell] == 2:
					erase_cell(cell)
					$"../ExploredFog".erase_cell(cell)
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
