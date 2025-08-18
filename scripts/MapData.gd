class_name MapData
extends Resource


@export var map_name: String = "New Map"

@export var terrain_scene: PackedScene

@export var base_positions := {
	"player1": Vector2i(-1,7),
	"player2": Vector2i(17,7)
}

@export var tower_positions := {
	"player1": [],
	"player2": []
}

@export var mine_tiles := {
	"unclaimed": [],
	"player1": [],
	"player2": []
}
