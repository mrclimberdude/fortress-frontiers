extends Node2D

# -- ownership & cost
@export var player_id: String    = ""
@export var cost:      int       = 0

# -- combat stats
@export var melee_strength:  int = 1
@export var ranged_strength: int = 0
@export var move_range:      int = 2

# -- grid positioning and reference to the TileMapLayer
var grid_pos: Vector2i
var map_layer: Node

# Set which map layer this unit should use for positioning
func set_map_layer(layer: TileMapLayer) -> void:
	map_layer = layer

# Place the unit at the given grid position using the TileMapLayer’s own coordinate system
func set_grid_position(pos: Vector2i) -> void:
	grid_pos = pos
	if map_layer:
		# get top-left of the hex:
		var origin = map_layer.map_to_world(pos)
		# center it by half the tile size you exported:
		var center = map_layer.tile_size * 0.5
		position = origin + center
	else:
		push_error("Unit.gd: no valid map_layer to place unit")


func _ready():
	# if map_layer and grid_pos were set prior to ready, snap into place
	if map_layer and grid_pos:
		set_grid_position(grid_pos)
