class_name MapData
extends Resource


@export var map_name: String = "New Map"

@export var terrain_scene: PackedScene

@export var base_positions := {
	"player1": Vector2i(-1,7),
	"player2": Vector2i(17,7)
}

@export var tower_positions := {
	"player1": [Vector2i(2,10),
				Vector2i(2,15),
				Vector2i(2,20)
				],
	"player2": [Vector2i(33,10),
				Vector2i(32,15),
				Vector2i(33,20)
				],
}

@export var mine_tiles := {
	"unclaimed": [],
	"player1": [],
	"player2": []
}
