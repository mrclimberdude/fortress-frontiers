extends Node2D

@export var tile_size: Vector2 = Vector2(170, 192)   # width, height of one hex
@export var highlight_tile_id: int = 2
@onready var hex_map: TileMapLayer = $HexTileMap
var terrain_overlay: TileMapLayer = null

# Maps a Vector2i tile coordinate → the Unit node standing there
var occupied_tiles: Dictionary = {}
var structure_tiles: Dictionary = {}
var structure_units: Dictionary = {}

func _ready() -> void:
	pass

# ─── Occupancy methods ─────────────────────────────────────────────────────────
func occupy(tile: Vector2i, unit: Node) -> void:
	if unit == null:
		return
	if unit.is_base or unit.is_tower:
		structure_units[tile] = unit
	else:
		occupied_tiles[tile] = unit

func vacate(tile: Vector2i, unit: Node = null) -> void:
	if unit != null and (unit.is_base or unit.is_tower):
		if structure_units.get(tile) == unit:
			structure_units.erase(tile)
		if structure_tiles.get(tile) == unit:
			structure_tiles.erase(tile)
		for player in ["player1", "player2"]:
			if unit.is_tower and tile in $"..".tower_positions[player]:
				$"..".tower_positions[player].erase(tile)
				$"..".structure_positions.erase(tile)
				if $"..".has_method("get_spawn_points"):
					if $"..".spawn_tower_positions.has(player) and tile in $"..".spawn_tower_positions[player]:
						$"..".spawn_tower_positions[player].erase(tile)
					if $"..".income_tower_positions.has(player) and tile in $"..".income_tower_positions[player]:
						$"..".income_tower_positions[player].erase(tile)
			if unit.is_base and tile == $"..".base_positions[player]:
				$"..".end_game(player)
		return
	if unit != null:
		if occupied_tiles.get(tile) == unit:
			occupied_tiles.erase(tile)
		return
	occupied_tiles.erase(tile)

func is_occupied(tile: Vector2i) -> bool:
	return occupied_tiles.has(tile)

func get_unit_at(tile: Vector2i) -> Node:
	return occupied_tiles.get(tile, null)

func get_structure_unit_at(tile: Vector2i) -> Node:
	return structure_units.get(tile, null)

func get_any_unit_at(tile: Vector2i) -> Node:
	var unit = get_unit_at(tile)
	if unit != null:
		return unit
	return get_structure_unit_at(tile)

func get_primary_attack_target(tile: Vector2i, attacker_player: String) -> Node:
	var structure = get_structure_unit_at(tile)
	if structure != null and structure.player_id != attacker_player:
		return structure
	var mobile = get_unit_at(tile)
	if mobile != null and mobile.player_id != attacker_player:
		var tm = $".."
		if tm != null and tm.has_method("is_unit_hidden_to_local") and tm.is_unit_hidden_to_local(mobile):
			return null
		return mobile
	return null

func is_enemy_structure_tile(tile: Vector2i, player_id: String) -> bool:
	if player_id == "":
		return false
	var structure = get_structure_unit_at(tile)
	if structure == null:
		return false
	if structure.player_id == player_id:
		return false
	return structure.is_base or structure.is_tower

func set_structure_at(tile: Vector2i, structure: Node):
	structure_tiles[tile] = structure

func get_structure_at(tile: Vector2i):
	var structure = structure_tiles.get(tile, null)
	if structure != null and not is_instance_valid(structure):
		structure_tiles.erase(tile)
		return null
	return structure

func get_all_units():
	var units: Dictionary = {"player1": [], "player2": [], "neutral": []}
	for unit in occupied_tiles.values():
		if unit.player_id == "player1":
			units["player1"].append(unit)
		elif unit.player_id == "player2":
			units["player2"].append(unit)
		elif unit.player_id == "neutral":
			units["neutral"].append(unit)
	for unit in structure_units.values():
		if unit.player_id == "player1":
			units["player1"].append(unit)
		elif unit.player_id == "player2":
			units["player2"].append(unit)
		elif unit.player_id == "neutral":
			units["neutral"].append(unit)
	return units

func get_all_units_flat(include_structures: bool = true) -> Array:
	var units := []
	for unit in occupied_tiles.values():
		units.append(unit)
	if include_structures:
		for unit in structure_units.values():
			units.append(unit)
	return units

func get_all_mobile_units() -> Array:
	return occupied_tiles.values()

func get_all_structures():
	var structures = []
	var to_remove := []
	for tile in structure_tiles.keys():
		var structure = structure_tiles.get(tile, null)
		if structure == null or not is_instance_valid(structure):
			to_remove.append(tile)
			continue
		structures.append(structure)
	for tile in to_remove:
		structure_tiles.erase(tile)
	return structures

func _get_terrain_overlay() -> TileMapLayer:
	if terrain_overlay != null and not is_instance_valid(terrain_overlay):
		terrain_overlay = null
	if terrain_overlay == null:
		terrain_overlay = get_node_or_null("TerrainMap")
		if terrain_overlay == null:
			var tm = get_parent()
			if tm != null:
				var overlay = tm.get("terrain_overlay")
				if overlay != null:
					terrain_overlay = overlay
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

func _terrain_move_cost_for_unit(cell: Vector2i, unit) -> int:
	var cost = _terrain_move_cost(cell)
	if unit == null:
		return cost
	var td = _get_terrain_tile_data(cell)
	var terrain = "" if td == null else str(td.get_custom_data("terrain"))
	if terrain == "forest":
		var unit_type = str(unit.unit_type).to_lower()
		if unit_type == "scout":
			return 1
	return cost

func _terrain_blocks_sight(cell: Vector2i) -> bool:
	var td = _get_terrain_tile_data(cell)
	if td == null:
		return false
	return bool(td.get_custom_data("blocks_sight"))

func get_move_cost(cell: Vector2i, unit = null) -> float:
	var cost = float(_terrain_move_cost_for_unit(cell, unit))
	var tm = $".."
	if tm != null and tm.has_method("get_structure_move_cost"):
		cost = float(tm.get_structure_move_cost(cell, cost))
	return cost
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

func get_reachable_tiles(start: Vector2i, range: float, mode: String, mover_override = null) -> Dictionary:
	var reachable: Array = []
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	var queue: Array = []
	var spawns = [start]
	var mover_player: String = ""
	var mover = null
	
	if mode == "dev_place":
		return {"tiles": hex_map.used_cells, "prev": start}
	
	if mode == "place":
		var start_unit = get_any_unit_at(start)
		var player = start_unit.player_id if start_unit != null else ""
		var spawn_points = []
		if $"..".has_method("get_spawn_points"):
			spawn_points = $"..".get_spawn_points(player)
		else:
			spawn_points = $"..".tower_positions[player]
		for tile in spawn_points:
			spawns.append(tile)
	elif mode == "move":
		if mover_override != null:
			mover = mover_override
		else:
			mover = get_unit_at(start)
		if mover != null:
			mover_player = mover.player_id
	
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
				if mode in ["visibility", "ranged", "visibility_over_trees"] and current != spawn and _terrain_blocks_sight(current):
					if mode == "visibility_over_trees":
						var td = _get_terrain_tile_data(current)
						var terrain = "" if td == null else str(td.get_custom_data("terrain"))
						if terrain != "forest":
							continue
					else:
						continue
				for neighbor in get_offset_neighbors(current):
					# Bounds check
					if not hex_map.is_cell_valid(neighbor):
						continue
					if mode in ["move", "place"] and _terrain_is_impassable(neighbor):
						continue
					if mode == "move" and is_enemy_structure_tile(neighbor, mover_player):
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
		var range_limit: float = float(range)
		visited[start] = 0.0
		open.append(start)
		while open.size() > 0:
			var best_idx = 0
			var best_cost = float(visited[open[0]])
			for i in range(1, open.size()):
				var c = float(visited[open[i]])
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
				if is_enemy_structure_tile(neighbor, mover_player):
					continue
				var step_cost: float = get_move_cost(neighbor, mover)
				var new_cost: float = float(visited[current]) + step_cost
				if new_cost > range_limit:
					continue
				if not visited.has(neighbor) or new_cost < visited[neighbor]:
					visited[neighbor] = new_cost
					prev[neighbor] = current
					if neighbor not in open:
						open.append(neighbor)
	# Return both the reachable set and the back-pointer map
	return {"tiles": reachable, "prev": prev}


func clear_highlights() -> void:
	$HighlightMap.clear()

func show_highlights(tiles: Array) -> void:
	clear_highlights()
	for tile in tiles:
		$HighlightMap.set_cell(tile, highlight_tile_id, Vector2i(0,0))
