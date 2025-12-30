extends TileMapLayer

@export var columns: int      = 18
@export var rows:    int      = 15
@export var tile_size: Vector2 = Vector2(170, 192)
@export var spacing:   Vector2 = Vector2(0,  0)
@export var visiblity: Dictionary = {} # {player:{cell:0/1/2}}
# 0 unexplored, 1 explored, 2 visible

const FOG_Z_INDEX: int = 100

func _ready() -> void:
	var cells = $"../HexTileMap".used_cells
	z_index = FOG_Z_INDEX
	for player in ["player1", "player2"]:
		visiblity[player] = {}
		for cell in cells:
			visiblity[player][cell] = 0
			set_cell(cell, tile_set.get_source_id(0), Vector2i(3,0))

func _update_fog():
	var units = $"..".get_all_units()
	var all_units = $"..".get_all_units_flat()
	# make all non-local units invisible (including neutrals)
	for unit in all_units:
		if unit.player_id != $"../..".local_player_id:
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
				in_sight = $"..".get_reachable_tiles(unit.grid_pos, unit.sight_range, "visibility")
			for cell in in_sight["tiles"]:
				visiblity[player][cell] = 2
		if player == $"../..".local_player_id:
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
						if cell in $"../..".mines["unclaimed"]:
							tint = Vector2i(1,1)
						elif cell in $"../..".mines["player1"]:
							tint = Vector2i(1,3)
						elif cell in $"../..".mines["player2"]:
							tint = Vector2i(3,3)
						elif structure != null and structure.player_id == "player1":
							tint = Vector2i(1,3)
						elif structure != null and structure.player_id == "player2":
							tint = Vector2i(3,3)
						else:
							tint = Vector2i(2,0)
					$"../ExploredFog".set_cell(cell, tile_set.get_source_id(0), tint)
						
				if visiblity[player][cell] == 2:
					erase_cell(cell)
					$"../ExploredFog".erase_cell(cell)
					if cell in $"../..".structure_positions:
						var structure = $"..".get_structure_at(cell)
						if structure != null and is_instance_valid(structure):
							structure.z_index = 6
					var unit = $"..".get_unit_at(cell)
					if unit != null:
						var tm = $"../.."
						if tm != null and tm.has_method("is_unit_hidden_to_local") and tm.is_unit_hidden_to_local(unit):
							unit.visible = false
						else:
							unit.visible = true
					var structure_unit = $"..".get_structure_unit_at(cell)
					if structure_unit != null:
						structure_unit.visible = true
	if not $"../../UI/DevPanel/VBoxContainer/FogCheckButton".button_pressed:
		for unit in all_units:
			var tm = $"../.."
			if tm != null and tm.has_method("is_unit_hidden_to_local") and tm.is_unit_hidden_to_local(unit):
				unit.visible = false
			else:
				unit.visible = true
	if $"../..".has_method("update_neutral_markers"):
		$"../..".update_neutral_markers()
	if $"../..".has_method("refresh_structure_markers"):
		$"../..".refresh_structure_markers()
