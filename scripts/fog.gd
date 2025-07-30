extends TileMapLayer

@export var columns: int      = 18
@export var rows:    int      = 15
@export var tile_size: Vector2 = Vector2(170, 192)
@export var spacing:   Vector2 = Vector2(0,  0)
@export var visiblity: Dictionary = {} # {player:{cell:0/1/2}}
# 0 unexplored, 1 explored, 2 visible
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var cells = $"../HexTileMap".used_cells
	for player in ["player1", "player2"]:
		visiblity[player] = {}
		for cell in cells:
			visiblity[player][cell] = 0
			set_cell(cell, tile_set.get_source_id(0), Vector2i(3,0))

func _update_fog():
	var units = $"..".get_all_units()
	# make all enemy units invisible
	for player in ["player1", "player2"]:
		if player == $"../..".local_player_id:
			for unit in units[player]:
				unit.visible = false
	for player in ["player1", "player2"]:
		# reset all visible cells to explored
		for cell in visiblity[player].keys():
			if visiblity[player][cell] == 2:
				visiblity[player][cell] = 1
		# set all cells within sight range of all of a players units to visible
		for unit in units[player]:
			var in_sight = $"..".get_reachable_tiles(unit.grid_pos, unit.sight_range, "visibility")
			for cell in in_sight["tiles"]:
				visiblity[player][cell] = 2
		if player == $"../..".local_player_id:
			for cell in visiblity[player]:
				var tint
				if visiblity[player][cell] == 0:
					tint = Vector2i(3,0)
					set_cell(cell, tile_set.get_source_id(0), tint)
				if visiblity[player][cell] == 1:
					tint = Vector2i(4,0)
					set_cell(cell, tile_set.get_source_id(0), tint, 1)
				if visiblity[player][cell] == 2:
					set_cell(cell, tile_set.get_source_id(0), )
					if $"..".is_occupied(cell):
						$"..".get_unit_at(cell).visible = true
