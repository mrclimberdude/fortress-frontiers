# UnitManager.gd
extends Node2D

# preload your two unit scenes
@export var base_scene: PackedScene    = preload("res://scenes/Base.tscn")
@export var archer_scene: PackedScene  = preload("res://scenes/Archer.tscn")
@export var soldier_scene: PackedScene = preload("res://scenes/Soldier.tscn")
@export var scout_scene: PackedScene = preload("res://scenes/Scout.tscn")
@export var miner_scene: PackedScene = preload("res://scenes/Miner.tscn")
@export var tank_scene: PackedScene = preload("res://scenes/Tank.tscn")

@export var tile_size: Vector2 = Vector2(170, 192)   # width, height of one hex

# reference to the board node to convert coords → world
@onready var board = get_parent()  as Node2D# GameBoardNode
@onready var hex_map = get_parent().get_node("HexTileMap") as TileMapLayer
@export var turn_manager_path: NodePath
@onready var turn_mgr = get_node(turn_manager_path) as Node

var _next_net_id_odd: int  = 1
var _next_net_id_even: int = 2

var unit_by_net_id: Dictionary = {}

func _ready():
	print("UnitManager: hex_map =", hex_map, "script=", hex_map.get_script())

# spawns a unit by type ("archer" or "soldier") at grid_pos for owner
func spawn_unit(unit_type: String, cell: Vector2i, owner: String) -> Node2D:
	# 1) Pick the right scene with a match statement
	var scene: PackedScene
	match unit_type.to_lower():
		"base":
			scene = base_scene
		"archer":
			scene = archer_scene
		"soldier":
			scene = soldier_scene
		"scout":
			scene = scout_scene
		"miner":
			scene = miner_scene
		"tank":
			scene = tank_scene
		_:
			push_error("Unknown unit type '%s'" % unit_type)
			return

	# 2) Instance & add it
	var unit = scene.instantiate() as Node2D
	if owner == "player1":
		unit.scale = Vector2(-1,1)
		var health_bar = unit.get_node("HealthBar")
		health_bar.scale = Vector2(-1,1)
		health_bar.position[0] += health_bar.size[0]
		unit.net_id = _next_net_id_odd
		_next_net_id_odd += 2
	else:
		unit.net_id = _next_net_id_even
		_next_net_id_even +=2
	add_child(unit)

	# 3) Place it using your TileMapLayer’s map_to_world
	unit.map_layer = hex_map
	unit.player_id = owner
	unit.set_grid_position(cell)
	
	unit_by_net_id[unit.net_id] = unit
	
	print("Spawned %s for %s at %s" % [unit_type, owner, cell])
	return unit

func find_end(unit, path, enemy, enemy_flag):
	if enemy:
		enemy_flag = true
	if unit.is_moving:
		path.append(unit.moving_to)
		if unit.moving_to == path[0]:
			return [path, enemy_flag]
		if $"..".is_occupied(unit.moving_to):
			var obstacle = $"..".get_unit_at(unit.moving_to)
			if not obstacle.is_moving:
				return [path, enemy_flag]
			if obstacle.player_id == unit.player_id:
				return find_end(obstacle, path, false, enemy_flag)
			else:
				return find_end(obstacle, path, true, enemy_flag)
	return [path, enemy_flag]

func get_unit_by_net_id(id: int) -> Node:
	return unit_by_net_id.get(id, null)

func _input(event):
	if event.is_action_pressed("debug_move"):
		# Grab your first unit under UnitManager; adjust path/index as needed
		var unit = $".".get_child(0)
		if unit:
			unit.set_grid_position(Vector2i(4, 6))
