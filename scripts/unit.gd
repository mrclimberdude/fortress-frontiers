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
@export var auto_heal:       bool = false
@export var auto_defend:     bool = false
@export var auto_build:      bool = false
@export var auto_build_type: String = ""
@export var is_moving:       bool = false
@export var is_looking_out:  bool = false
@export var moving_to:       Vector2i

@export var just_purchased:  bool = true
@export var first_turn_move: bool = false

@export var is_base:         bool = false
@export var is_miner:        bool = false
@export var is_builder:      bool = false
@export var is_phalanx:      bool = false
@export var is_tower:        bool = false
@export var unit_type:       String = ""
@export var special_skills:  String = ""
@export var last_damaged_by: String = ""

# -- grid positioning and reference to the TileMapLayer
var grid_pos: Vector2i
var map_layer: Node

@onready var unit_mgr = get_parent() as Node2D
@onready var turn_mgr = unit_mgr.turn_mgr

var structure_tiles: Array
var owner_overlay: Sprite2D = null

func _ready():
	structure_tiles = turn_mgr.structure_positions
	# if map_layer and grid_pos were set prior to ready, snap into place
	if map_layer and grid_pos:
		set_grid_position(grid_pos)
	set_health_bar()
	self.z_index = 7
	$HealthBar.z_index = 20
	owner_overlay = get_node_or_null("OwnerOverlay")
	_update_owner_overlay()

func _atlas_region_for(atlas: TileSetAtlasSource, coords: Vector2i) -> Rect2:
	var margin = atlas.margins
	var sep = atlas.separation
	var size = atlas.texture_region_size
	var x = margin.x + coords.x * (size.x + sep.x)
	var y = margin.y + coords.y * (size.y + sep.y)
	return Rect2(x, y, size.x, size.y)

func _update_owner_overlay() -> void:
	if owner_overlay == null:
		return
	if map_layer == null:
		owner_overlay.visible = false
		return
	if player_id not in ["player1", "player2"] or is_base or is_tower:
		owner_overlay.visible = false
		return
	var source_id = map_layer.tile_set.get_source_id(0)
	var source = map_layer.tile_set.get_source(source_id)
	if source == null or not (source is TileSetAtlasSource):
		owner_overlay.visible = false
		return
	var atlas = source as TileSetAtlasSource
	var coords = map_layer.player_atlas_tiles.get(player_id, map_layer.ground_tile)
	owner_overlay.texture = atlas.texture
	owner_overlay.region_enabled = true
	owner_overlay.region_rect = _atlas_region_for(atlas, coords)
	owner_overlay.z_index = -2
	var region_size = atlas.texture_region_size
	if region_size.x > 0 and region_size.y > 0:
		var scale_x = float(map_layer.tile_size.x) / float(region_size.x)
		var scale_y = float(map_layer.tile_size.y) / float(region_size.y)
		owner_overlay.scale = Vector2(scale_x, scale_y)
	owner_overlay.visible = true

# Set which map layer this unit should use for positioning
func set_map_layer(layer: TileMapLayer) -> void:
	map_layer = layer
	_update_owner_overlay()

func set_grid_position(pos: Vector2i) -> void:
	var board   = map_layer.get_parent()
	var old_pos = grid_pos
	# 1) Clear previous tile
	if board and board.has_method("vacate") and old_pos:
		board.vacate(old_pos, self)
		if old_pos in turn_mgr.camps["basic"]:
			map_layer.set_player_tile(old_pos, "camp")
		elif old_pos in turn_mgr.camps["dragon"]:
			map_layer.set_player_tile(old_pos, "dragon")
		elif old_pos not in structure_tiles:
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
		if pos in structure_tiles:
			if pos in turn_mgr.mines["unclaimed"]:
				var idx = turn_mgr.mines["unclaimed"].find(pos)
				turn_mgr.mines["unclaimed"].remove_at(idx)
				turn_mgr.mines[player_id].append(pos)
			elif pos in turn_mgr.mines["player1"]:
				var idx = turn_mgr.mines["player1"].find(pos)
				turn_mgr.mines["player1"].remove_at(idx)
				turn_mgr.mines[player_id].append(pos)
			elif pos in turn_mgr.mines["player2"]:
				var idx = turn_mgr.mines["player2"].find(pos)
				turn_mgr.mines["player2"].remove_at(idx)
				turn_mgr.mines[player_id].append(pos)
		if pos in structure_tiles:
			map_layer.set_player_tile(pos, player_id)
	else:
		push_error("Unit.gd: could not find GameBoardNode to occupy()")
	_update_owner_overlay()

func set_health_bar():
	$HealthBar.value = curr_health
