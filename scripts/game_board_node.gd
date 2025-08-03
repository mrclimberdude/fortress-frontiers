extends Node2D

@export var tile_size: Vector2 = Vector2(170, 192)   # width, height of one hex
@export var highlight_tile_id: int = 2
@onready var hex_map: TileMapLayer = $HexTileMap

# Maps a Vector2i tile coordinate → the Unit node standing there
var occupied_tiles: Dictionary = {}
var structure_tiles: Dictionary = {}

func _ready() -> void:
	pass

# ─── Occupancy methods ─────────────────────────────────────────────────────────
func occupy(tile: Vector2i, unit: Node) -> void:
	occupied_tiles[tile] = unit

func vacate(tile: Vector2i) -> void:
	occupied_tiles.erase(tile)
	for player in ["player1", "player2"]:
		if tile in $"..".tower_positions[player]:
			$"..".tower_positions[player].erase(tile)
			$"..".structure_positions.erase(tile)
		if tile in $"..".base_positions:
			$"..".end_game()

func is_occupied(tile: Vector2i) -> bool:
	return occupied_tiles.has(tile)

func get_unit_at(tile: Vector2i) -> Node:
	return occupied_tiles.get(tile, null)

func set_structure_at(tile: Vector2i, structure: Node):
	structure_tiles[tile] = structure

func get_structure_at(tile: Vector2i):
	return structure_tiles[tile]

func get_all_units():
	var units: Dictionary = {"player1": [], "player2": []}
	for unit in occupied_tiles.values():
		if unit.player_id == "player1":
			units["player1"].append(unit)
		else:
			units["player2"].append(unit)
	return units

func get_all_structures():
	var structures = []
	for structure in structure_tiles.values():
		structures.append(structure)
	return structures
# ────────────────────────────────────────────────────────────────────────────────

# ─── Hex neighbor & reachability ───────────────────────────────────────────────
func get_offset_neighbors(tile: Vector2i) -> Array:
	# Define neighbor offsets for even- and odd-row hexes (horizontal layout)
	var dirs_even = [
		Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	var dirs_odd = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)
	]
	# Choose based on row parity
	var dirs = dirs_even if tile.y % 2 == 0 else dirs_odd

	var neighbors: Array = []
	for d in dirs:
		neighbors.append(tile + d)
	return neighbors

func get_reachable_tiles(start: Vector2i, range: int, mode: String) -> Dictionary:
	var reachable: Array = []
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	var queue: Array = []
	var spawns = [start]
	
	if mode == "dev_place":
		return {"tiles": hex_map.used_cells, "prev": start}
	
	if mode == "place":
		var player = get_unit_at(start).player_id
		for tile in $"..".tower_positions[player]:
			spawns.append(tile)
	
	for spawn in spawns:
		# Initialize BFS
		visited[spawn] = 0
		queue.append(spawn)
		
		while queue.size() > 0:
			var current: Vector2i = queue.pop_front()
			var dist: int = visited[current]
			reachable.append(current)

			# Expand neighbors if under move range
			if dist < range:
				for neighbor in get_offset_neighbors(current):
					# Bounds check
					if not hex_map.is_cell_valid(neighbor):
						continue
					if visited.has(neighbor):
						continue
					if mode == "place":
						if is_occupied(neighbor):
							continue
					# Mark and enqueue
					visited[neighbor] = dist + 1
					prev[neighbor] = current
					queue.append(neighbor)
	if mode == "place":
		for spawn in spawns:
			if spawn in reachable:
				reachable.erase(spawn)
	# Return both the reachable set and the back-pointer map
	return {"tiles": reachable, "prev": prev}


func clear_highlights() -> void:
	$HighlightMap.clear()

func show_highlights(tiles: Array) -> void:
	clear_highlights()
	for tile in tiles:
		$HighlightMap.set_cell(tile, highlight_tile_id, Vector2i(0,0))
