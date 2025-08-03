extends Node2D

# -- ownership & cost
@export var player_id: String    = ""
@export var net_id:    int       = 0
@export var cost:      int       = 0

# -- combat stats
@export var is_ranged:       bool = false
@export var melee_strength:  int = 1
@export var ranged_strength: int = 0
@export var move_range:      int = 2
@export var ranged_range:    int = 0
@export var sight_range:     int = 2
@export var max_health:      int = 100
@export var curr_health:     int = 100
@export var regen:           int = 10
@export var multi_def_penalty:int = 2
@export var can_melee:       bool = true

@export var ordered:         bool = false
@export var is_defending:    bool = false
@export var is_healing:      bool = false
@export var is_moving:       bool = false
@export var moving_to:       Vector2i

@export var just_purchased:  bool = true
@export var first_turn_move: bool = false

@export var is_base:         bool = false
@export var is_miner:        bool = false
@export var is_tank:         bool = false
@export var is_tower:        bool = false

# -- grid positioning and reference to the TileMapLayer
var grid_pos: Vector2i
var map_layer: Node

@onready var unit_mgr = get_parent() as Node2D
@onready var turn_mgr = unit_mgr.turn_mgr

var structure_tiles: Array

func _ready():
	structure_tiles = turn_mgr.structure_positions
	# if map_layer and grid_pos were set prior to ready, snap into place
	if map_layer and grid_pos:
		set_grid_position(grid_pos)
	set_health_bar()

# Set which map layer this unit should use for positioning
func set_map_layer(layer: TileMapLayer) -> void:
	map_layer = layer

func set_grid_position(pos: Vector2i) -> void:
	var board   = map_layer.get_parent()
	var old_pos = grid_pos
	# 1) Clear previous tile
	if board and board.has_method("vacate") and old_pos:
		board.vacate(old_pos)
		if old_pos not in structure_tiles:
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
		if pos in structure_tiles:
			if pos in turn_mgr.special_tiles["unclaimed"]:
				var idx = turn_mgr.special_tiles["unclaimed"].find(pos)
				turn_mgr.special_tiles["unclaimed"].remove_at(idx)
				turn_mgr.special_tiles[player_id].append(pos)
			elif pos in turn_mgr.special_tiles["player1"]:
				var idx = turn_mgr.special_tiles["player1"].find(pos)
				turn_mgr.special_tiles["player1"].remove_at(idx)
				turn_mgr.special_tiles[player_id].append(pos)
			elif pos in turn_mgr.special_tiles["player2"]:
				var idx = turn_mgr.special_tiles["player2"].find(pos)
				turn_mgr.special_tiles["player2"].remove_at(idx)
				turn_mgr.special_tiles[player_id].append(pos)
	else:
		push_error("Unit.gd: could not find GameBoardNode to occupy()")

func set_health_bar():
	$HealthBar.value = curr_health
