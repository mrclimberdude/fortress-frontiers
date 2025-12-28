## hex_tile_map.gd
@tool
extends TileMapLayer

@export var use_editor_paint: bool = true
@export var columns: int      = 18
@export var rows:    int      = 15
@export var tile_size: Vector2 = Vector2(170, 192)
@export var spacing:   Vector2 = Vector2(0,  0)

var used_cells = get_used_cells_by_id()
var valid_cells := {}

# Coloring API you already have:
var ground_tile: Vector2i = Vector2i(2, 0)
var player_atlas_tiles := {
	"player1": Vector2i(0, 1),
	"player2": Vector2i(2, 2)
}
var structure_atlas_tiles:= {
	"unclaimed": Vector2i(1,1),
	"player1": Vector2i(1, 3),
	"player2": Vector2i(3, 3)
}
var camp_atlas_tiles := {
	"camp": Vector2i(1, 2),
	"dragon": Vector2i(4, 1)
}

var structure_tiles : Array


func _ready():
	structure_tiles = $"../..".structure_positions
	if Engine.is_editor_hint() or use_editor_paint:
		for cell in used_cells:
			valid_cells[cell] = true
		return
	_generate_board()

func _generate_board():
	clear()
	var src = tile_set.get_source_id(0)
	var ground = Vector2i(2,0)
	for x in range(columns):
		for y in range(rows):
			set_cell(Vector2i(x,y), src, ground)
	update_internals()

func is_cell_valid(cell: Vector2i) -> bool:
	return valid_cells.has(cell)

func set_player_tile(pos: Vector2i, pid: String) -> void:
	var src = tile_set.get_source_id(0)
	var tint
	structure_tiles = $"../..".structure_positions
	var is_camp = pos in $"../..".camps["basic"]
	var is_dragon = pos in $"../..".camps["dragon"]
	if is_camp or is_dragon:
		if pid in ["", "neutral", "camp", "dragon"]:
			var camp_key = "dragon" if is_dragon else "camp"
			tint = camp_atlas_tiles.get(camp_key, ground_tile)
		else:
			tint = player_atlas_tiles.get(pid, ground_tile)
	elif pos in structure_tiles:
		tint = structure_atlas_tiles.get(pid, ground_tile)
		for player in ["player1", "player2", "unclaimed"]:
			if pos in $"../..".mines[player]:
				tint = structure_atlas_tiles.get(player, ground_tile)
	else:
		tint = player_atlas_tiles.get(pid, ground_tile)
	set_cell(pos, src, tint)
	if is_camp or is_dragon:
		var terrain_map = get_parent().get_node_or_null("TerrainMap") as TileMapLayer
		if terrain_map:
			var terrain_src = terrain_map.tile_set.get_source_id(0)
			var terrain_tint
			if pid in ["", "neutral", "camp", "dragon"]:
				var camp_key = "dragon" if is_dragon else "camp"
				terrain_tint = camp_atlas_tiles.get(camp_key, ground_tile)
			else:
				terrain_tint = player_atlas_tiles.get(pid, ground_tile)
			terrain_map.set_cell(pos, terrain_src, terrain_tint)
	$"..".clear_highlights()
	update_internals()

# convert an offset-coordinate cell → world pixels
func map_to_world(cell: Vector2i) -> Vector2:
	var fw = tile_size.x + spacing.x
	var fh = tile_size.y * 0.75 + spacing.y
	var x = fw * (cell.x + 0.5 * (cell.y & 1))
	var y = fh * cell.y
	return Vector2(x, y)
	

# convert a world-position → offset-coordinate cell
func world_to_map(world_pos: Vector2) -> Vector2i:
	# Convert a world position to an offset cell, using floor-based rounding for consistency
	var local = to_local(world_pos)
	var fw = tile_size.x + spacing.x
	var fh = tile_size.y * 0.75 + spacing.y

	# Determine row by flooring rather than rounding to avoid off-by-one when clicking edges
	var row_f = local.y / fh
	var row = int(clamp(floor(row_f), 0, rows - 1))

	# Determine column, adjusting for odd-r offset
	var col_f = local.x / fw - 0.5 * (row & 1)
	var col = int(clamp(floor(col_f), -1, columns - 1))

	return Vector2i(col, row)
