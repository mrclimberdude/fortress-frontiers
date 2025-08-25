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
	# make all enemy units invisible
	for player in ["player1", "player2"]:
		if player != $"../..".local_player_id:
			for unit in units[player]:
				unit.visible = false
	for structure in $"..".get_all_structures():
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
						structure.z_index = 99
						if cell in $"../..".mines["unclaimed"]:
							tint = Vector2i(1,1)
						elif cell in $"../..".mines["player1"]:
							tint = Vector2i(1,3)
						elif cell in $"../..".mines["player2"]:
							tint = Vector2i(3,3)
						elif structure.player_id == "player1":
							tint = Vector2i(1,3)
						elif structure.player_id == "player2":
							tint = Vector2i(3,3)
						else:
							tint = Vector2i(2,0)
					$"../ExploredFog".set_cell(cell, tile_set.get_source_id(0), tint)
						
				if visiblity[player][cell] == 2:
					erase_cell(cell)
					$"../ExploredFog".erase_cell(cell)
					if cell in $"../..".structure_positions:
						var structure = $"..".get_structure_at(cell)
						structure.z_index = 6
					if $"..".is_occupied(cell):
						$"..".get_unit_at(cell).visible = true
	for player in ["player1", "player2"]:
		if not $"../../UI/DevPanel/VBoxContainer/FogCheckButton".button_pressed:
			for unit in units[player]:
				unit.visible = true
