extends Node2D

@export var tile_size: Vector2 = Vector2(170, 192)   # width, height of one hex
@export var highlight_tile_id: int = 2
@onready var hex_map: TileMapLayer = $HexTileMap
var terrain_overlay: TileMapLayer = null

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
		if tile == $"..".base_positions[player]:
			$"..".end_game(player)

func is_occupied(tile: Vector2i) -> bool:
	return occupied_tiles.has(tile)

func get_unit_at(tile: Vector2i) -> Node:
	return occupied_tiles.get(tile, null)

func set_structure_at(tile: Vector2i, structure: Node):
	structure_tiles[tile] = structure

func get_structure_at(tile: Vector2i):
	return structure_tiles[tile]

func get_all_units():
	var units: Dictionary = {"player1": [], "player2": [], "neutral": []}
	for unit in occupied_tiles.values():
		if unit.player_id == "player1":
			units["player1"].append(unit)
		elif unit.player_id == "player2":
			units["player2"].append(unit)
		elif unit.player_id == "neutral":
			units["neutral"].append(unit)
	return units

func get_all_units_flat() -> Array:
	return occupied_tiles.values()

func get_all_structures():
	var structures = []
	for structure in structure_tiles.values():
		structures.append(structure)
	return structures

func _get_terrain_overlay() -> TileMapLayer:
	if terrain_overlay != null and not is_instance_valid(terrain_overlay):
		terrain_overlay = null
	if terrain_overlay == null:
		terrain_overlay = get_node_or_null("TerrainMap")
	return terrain_overlay

func _get_terrain_tile_data(cell: Vector2i) -> TileData:
	var tmap = _get_terrain_overlay()
	if tmap == null:
		return null
	return tmap.get_cell_tile_data(cell)

func _terrain_is_impassable(cell: Vector2i) -> bool:
	var td = _get_terrain_tile_data(cell)
	if td == null:
		return false
	return bool(td.get_custom_data("impassable"))

func _terrain_move_cost(cell: Vector2i) -> int:
	var td = _get_terrain_tile_data(cell)
	if td == null:
		return 1
	var cost = int(td.get_custom_data("move_cost"))
	return 1 if cost <= 0 else cost

func _terrain_blocks_sight(cell: Vector2i) -> bool:
	var td = _get_terrain_tile_data(cell)
	if td == null:
		return false
	return bool(td.get_custom_data("blocks_sight"))

func get_move_cost(cell: Vector2i) -> int:
	return _terrain_move_cost(cell)
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
				if mode in ["visibility", "ranged"] and current != spawn and _terrain_blocks_sight(current):
					continue
				for neighbor in get_offset_neighbors(current):
					# Bounds check
					if not hex_map.is_cell_valid(neighbor):
						continue
					if mode in ["move", "place"] and _terrain_is_impassable(neighbor):
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
	if mode == "move":
		# Re-run a weighted search for movement cost
		reachable.clear()
		prev.clear()
		visited.clear()
		var open: Array = []
		visited[start] = 0
		open.append(start)
		while open.size() > 0:
			var best_idx = 0
			var best_cost = visited[open[0]]
			for i in range(1, open.size()):
				var c = visited[open[i]]
				if c < best_cost:
					best_cost = c
					best_idx = i
			var current = open.pop_at(best_idx)
			reachable.append(current)
			for neighbor in get_offset_neighbors(current):
				if not hex_map.is_cell_valid(neighbor):
					continue
				if _terrain_is_impassable(neighbor):
					continue
				var step_cost = _terrain_move_cost(neighbor)
				var new_cost = visited[current] + step_cost
				if new_cost > range:
					continue
				if not visited.has(neighbor) or new_cost < visited[neighbor]:
					visited[neighbor] = new_cost
					prev[neighbor] = current
					if neighbor not in open:
						open.append(neighbor)
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
