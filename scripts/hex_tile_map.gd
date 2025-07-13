## hex_tile_map.gd
extends TileMapLayer

@export var columns: int      = 18
@export var rows:    int      = 15
@export var tile_size: Vector2 = Vector2(170, 192)
@export var spacing:   Vector2 = Vector2(4,  4)

# (Re-)draw your board however you like…
func _ready():
	_generate_board()

func _generate_board():
	clear()
	var src = tile_set.get_source_id(0)
	var ground = Vector2i(2,0)
	for x in range(columns):
		for y in range(rows):
			set_cell(Vector2i(x,y), src, ground)
	update_internals()

# Pointy-top axial → pixel (exactly how this layer draws its cells)
func axial_to_world(q: int, r: int) -> Vector2:
	var x = tile_size.x * (q + 0.5 * r)
	var y = tile_size.y * (3.0/4.0) * r
	return Vector2(x, y)

# Inverse of that: pixel → axial
func world_to_axial(p: Vector2) -> Vector2i:
	# undo the math of axial_to_world
	var rf = p.y / (tile_size.y * 0.75)
	var qf = (p.x / tile_size.x) - (rf * 0.5)
	# convert via cube‐coords rounding
	var xf = qf
	var zf = rf
	var yf = -xf - zf

	var rx = round(xf)
	var ry = round(yf)
	var rz = round(zf)
	var x_diff = abs(rx - xf)
	var y_diff = abs(ry - yf)
	var z_diff = abs(rz - zf)

	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector2i(rx, rz)

# Coloring API you already have:
@export var ground_tile: Vector2i = Vector2i(2, 0)
@export var player_tiles := {
	"player1": Vector2i(0, 1),
	"player2": Vector2i(2, 1)
}

func set_player_tile(pos: Vector2i, pid: String) -> void:
	var src = tile_set.get_source_id(0)
	var axial = offset_to_axial(pos)
	var corrected = axial_to_offset(axial)
	var tint = player_tiles.get(pid, ground_tile)
	set_cell(corrected, src, tint)
	$"..".clear_highlights()
	update_internals()
	
# convert an offset-coordinate cell → world pixels
func map_to_world(cell: Vector2i) -> Vector2:
	# first repair it back to axial
	var axial = offset_to_axial(cell)
	# then your existing pointy-top math
	return axial_to_world(axial.x, axial.y)

# convert a world-position → offset-coordinate cell
func world_to_map(world_pos: Vector2) -> Vector2i:
	# bring into this node’s local space
	var local = to_local(world_pos)
	# get the raw axial
	var axial = world_to_axial(local)
	# then snap into offset coords
	return axial_to_offset(axial)

# Axial to odd-r offset
func axial_to_offset(a: Vector2i) -> Vector2i:
	# a.x = q, a.y = r
	var col = a.x + (a.y - (a.y & 1)) / 2
	var row = a.y
	return Vector2i(col, row)

# Odd-r offset to axial
func offset_to_axial(o: Vector2i) -> Vector2i:
	# o.x = col, o.y = row
	var q = o.x - (o.y - (o.y & 1)) / 2
	var r = o.y -1
	return Vector2i(q, r)
