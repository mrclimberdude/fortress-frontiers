# UnitManager.gd
extends Node2D

# preload your two unit scenes
@export var archer_scene: PackedScene  = preload("res://scenes/Archer.tscn")
@export var soldier_scene: PackedScene = preload("res://scenes/Soldier.tscn")
@export var tile_size: Vector2 = Vector2(170, 192)   # width, height of one hex

# reference to the board node to convert coords → world
@onready var board = get_parent()  as Node2D# GameBoardNode
@onready var hex_map = get_parent().get_node("HexTileMap") as TileMapLayer

func _ready():
	print("UnitManager: hex_map =", hex_map, "script=", hex_map.get_script())

# spawns a unit by type ("archer" or "soldier") at grid_pos for owner
func spawn_unit(unit_type: String, cell: Vector2i, owner: String) -> void:
	# 1) Pick the right scene with a match statement
	var scene: PackedScene
	match unit_type.to_lower():
		"archer":
			scene = archer_scene
		"soldier":
			scene = soldier_scene
		_:
			push_error("Unknown unit type '%s'" % unit_type)
			return

	# 2) Instance & add it
	var unit = scene.instantiate() as Node2D
	add_child(unit)

	# 3) Place it using your TileMapLayer’s map_to_world
	unit.map_layer = hex_map
	unit.player_id = owner
	unit.set_grid_position(cell)

	# 4) Color the tile underneath
	#hex_map.set_player_tile(cell, owner)

	print("Spawned %s for %s at %s" % [unit_type, owner, cell])

func _input(event):
	if event.is_action_pressed("debug_move"):
		# Grab your first unit under UnitManager; adjust path/index as needed
		var unit = $".".get_child(0)
		if unit:
			unit.set_grid_position(Vector2i(4, 6))
