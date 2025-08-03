extends TileMapLayer


func _ready() -> void:
	pass

func highlight_unordered_units(player_id):
	clear()
	var units = $"..".get_all_units()[player_id]
	for unit in units:
		if not unit.is_base and not unit.is_tower and not unit.ordered:
			set_cell(unit.grid_pos, 2, Vector2i(1,1), 1)
