class_name MapData
extends Resource


@export var map_name: String = "New Map"
@export var map_category: String = "" # "normal" or "themed"; empty = infer from name
@export var map_size: String = "normal" # "normal" or "small"
@export var procedural: bool = false
@export var proc_columns: int = 0
@export var proc_rows: int = 0
@export var proc_forest_ratio: float = 0.14
@export var proc_mountain_ratio: float = 0.06
@export var proc_river_ratio: float = 0.04
@export var proc_lake_ratio: float = 0.03
@export var proc_mine_count: int = 0
@export var proc_camp_count: int = 0
@export var proc_dragon_count: int = 0

@export var terrain_scene: PackedScene

@export var base_positions := {
	"player1": Vector2i(-1,15),
	"player2": Vector2i(35,15)
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

@export var mines := {
	"unclaimed": [],
	"player1": [],
	"player2": []
}

@export var camps := {
	"basic" : [],
	"dragon": []
}

func populate_from_terrain(tmap: TileMapLayer) -> void:
	var mine_tiles = []
	var basic_camps = []
	var dragons = []
	for cell in tmap.get_used_cells():
		var td = tmap.get_cell_tile_data(cell)
		if td ==null:
			continue
		if bool(td.get_custom_data("is_mine")):
			mine_tiles.append(cell)
		elif bool(td.get_custom_data("is_camp")):
			basic_camps.append(cell)
		elif bool(td.get_custom_data("is_dragon")):
			dragons.append(cell)
	mines["unclaimed"] = mine_tiles
	camps["basic"] = basic_camps
	camps["dragon"] = dragons
