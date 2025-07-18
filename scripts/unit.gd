extends Node2D

# -- ownership & cost
@export var player_id: String    = ""
@export var cost:      int       = 0

# -- combat stats
@export var is_ranged:       bool = false
@export var melee_strength:  int = 1
@export var ranged_strength: int = 0
@export var move_range:      int = 2
@export var ranged_range:    int = 0
@export var max_health:      int = 100
@export var curr_health:     int = 100
@export var regen:           int = 10
@export var num_attacks:     int = 0
@export var defending:       bool = false

# -- grid positioning and reference to the TileMapLayer
var grid_pos: Vector2i
var map_layer: Node

# Set which map layer this unit should use for positioning
func set_map_layer(layer: TileMapLayer) -> void:
	map_layer = layer

func set_grid_position(pos: Vector2i) -> void:
	var board   = map_layer.get_parent()
	var old_pos = grid_pos

	# 1) Clear previous tile
	if board and board.has_method("vacate") and old_pos:
		board.vacate(old_pos)
		# reset the old tile to ground (empty) by passing an unknown pid
		map_layer.set_player_tile(old_pos, "")

	# 2) Update our stored grid_pos
	grid_pos = pos

	# 3) Snap our world position
	if map_layer:
		var origin = map_layer.map_to_world(pos)
		var center = map_layer.tile_size * 0.5
		position = origin + center
	else:
		push_error("Unit.gd: no valid map_layer to place unit")

	# 4) Register the new tile & recolor it for our player
	if board and board.has_method("occupy"):
		board.occupy(pos, self)
		map_layer.set_player_tile(pos, player_id)
	else:
		push_error("Unit.gd: could not find GameBoardNode to occupy()")

func set_health_bar():
	$HealthBar.value = curr_health

func _ready():
	# if map_layer and grid_pos were set prior to ready, snap into place
	if map_layer and grid_pos:
		set_grid_position(grid_pos)
	set_health_bar()
