extends TileMapLayer

const ORDER_REMINDER_SOURCE_ID: int = 2
const ORDER_REMINDER_ALT_ID: int = 1
const ORDER_REMINDER_TILE: Vector2i = Vector2i(1, 1)
const ORDER_REMINDER_NEW_TILE: Vector2i = Vector2i(0, 2)

func _ready() -> void:
	pass

func highlight_unordered_units(player_id):
	clear()
	var units = $"..".get_all_units()[player_id]
	for unit in units:
		if not unit.is_base and not unit.is_tower and not unit.ordered:
			var coords = ORDER_REMINDER_NEW_TILE if unit.just_purchased else ORDER_REMINDER_TILE
			set_cell(unit.grid_pos, ORDER_REMINDER_SOURCE_ID, coords, ORDER_REMINDER_ALT_ID)
