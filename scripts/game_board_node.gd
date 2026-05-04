extends Node2D

@export var tile_size: Vector2 = Vector2(170, 192)   # width, height of one hex
@export var highlight_tile_id: int = 2
@onready var hex_map: TileMapLayer = $HexTileMap
var terrain_overlay: TileMapLayer = null

# Maps a Vector2i tile coordinate → the Unit node standing there
var occupied_tiles: Dictionary = {}
var structure_tiles: Dictionary = {}
var structure_units: Dictionary = {}
var damage_hover_highlight_map: TileMapLayer = null

func _get_player_ids() -> Array:
	var tm = $".."
	if tm != null and tm.has_method("get_match_players"):
		return tm.get_match_players()
	return ["player1", "player2"]

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
		for player in _get_player_ids():
			if unit.is_tower and tile in $"..".tower_positions.get(player, []):
				$"..".tower_positions[player].erase(tile)
				$"..".structure_positions.erase(tile)
				if $"..".has_method("get_spawn_points"):
					if $"..".spawn_tower_positions.has(player) and tile in $"..".spawn_tower_positions[player]:
						$"..".spawn_tower_positions[player].erase(tile)
					if $"..".income_tower_positions.has(player) and tile in $"..".income_tower_positions[player]:
						$"..".income_tower_positions[player].erase(tile)
			if unit.is_base and tile == $"..".base_positions.get(player, Vector2i(-9999, -9999)):
				if $"..".has_method("queue_player_elimination"):
					$"..".queue_player_elimination(player)
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
	var units: Dictionary = {"neutral": []}
	for player_id in _get_player_ids():
		units[player_id] = []
	for unit in occupied_tiles.values():
		var owner = str(unit.player_id)
		if not units.has(owner):
			units[owner] = []
		units[owner].append(unit)
	for unit in structure_units.values():
		var owner = str(unit.player_id)
		if not units.has(owner):
			units[owner] = []
		units[owner].append(unit)
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

func get_visibility_state_for_player(cell: Vector2i, player_id: String) -> int:
	if player_id == "":
		return 2
	var fog = get_node_or_null("FogOfWar")
	if fog == null or not fog.visiblity.has(player_id):
		return 2
	return int(fog.visiblity[player_id].get(cell, 0))

func is_tile_unseen_for_player(cell: Vector2i, player_id: String) -> bool:
	return get_visibility_state_for_player(cell, player_id) == 0

func is_move_tile_passable_for_orders(cell: Vector2i, player_id: String) -> bool:
	var tm = $".."
	if tm != null and tm.current_phase == tm.Phase.ORDERS and is_tile_unseen_for_player(cell, player_id):
		return true
	return not _terrain_is_impassable(cell)

func get_order_move_cost(cell: Vector2i, unit = null, player_id: String = "") -> float:
	var effective_player = player_id
	if effective_player == "" and unit != null:
		effective_player = str(unit.player_id)
	var tm = $".."
	if tm != null and tm.current_phase == tm.Phase.ORDERS and effective_player != "" and is_tile_unseen_for_player(cell, effective_player):
		return 1.0
	return get_move_cost(cell, unit)

func get_move_cost(cell: Vector2i, unit = null) -> float:
	var tm = $".."
	if tm != null and unit != null and tm.current_phase == tm.Phase.ORDERS:
		var fog = get_node_or_null("FogOfWar")
		if fog != null and fog.visiblity.has(unit.player_id):
			var vis = int(fog.visiblity[unit.player_id].get(cell, 0))
			if vis == 0:
				return 1.0
	var cost = float(_terrain_move_cost_for_unit(cell, unit))
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

func get_reachable_tiles(start: Vector2i, range: float, mode: String, mover_override = null, place_unit_type: String = "") -> Dictionary:
	var reachable: Array = []
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	var queue: Array = []
	var spawns = [start]
	var mover_player: String = ""
	var mover = null
	var place_player: String = ""
	
	if mode == "dev_place":
		return {"tiles": hex_map.used_cells, "prev": start}
	
	if mode == "place":
		var start_unit = get_any_unit_at(start)
		var player = start_unit.player_id if start_unit != null else ""
		place_player = player
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
						if not visited.has(neighbor):
							visited[neighbor] = dist + 1
							prev[neighbor] = current
							reachable.append(neighbor)
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
	if mode == "place" and place_unit_type != "":
		var tm = $".."
		if tm != null and tm.has_method("can_spawn_unit_at"):
			var filtered := []
			for tile in reachable:
				if tm.can_spawn_unit_at(place_player, place_unit_type, tile):
					filtered.append(tile)
			reachable = filtered
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
				if not is_move_tile_passable_for_orders(neighbor, mover_player):
					continue
				var step_cost: float = get_order_move_cost(neighbor, mover, mover_player)
				var new_cost: float = float(visited[current]) + step_cost
				if new_cost > range_limit:
					continue
				if is_enemy_structure_tile(neighbor, mover_player):
					if not visited.has(neighbor) or new_cost < visited[neighbor]:
						visited[neighbor] = new_cost
						prev[neighbor] = current
					if neighbor not in reachable:
						reachable.append(neighbor)
					continue
				if not visited.has(neighbor) or new_cost < visited[neighbor]:
					visited[neighbor] = new_cost
					prev[neighbor] = current
					if neighbor not in open:
						open.append(neighbor)
	# Return both the reachable set and the back-pointer map
	return {"tiles": reachable, "prev": prev}

func get_queue_reachable(start: Vector2i, mode: String, unit: Node, player_id: String) -> Dictionary:
	var result := {"tiles": [], "prev": {}, "costs": {}}
	if unit == null or player_id == "":
		return result
	if not hex_map.is_cell_valid(start):
		return result
	var tm = $".."
	if tm == null:
		return result
	var queue_mode = str(mode).to_lower()
	var prev := {}
	var costs := {start: 0.0}
	var open: Array = [start]
	while open.size() > 0:
		var best_idx = 0
		var best_cost = float(costs[open[0]])
		for i in range(1, open.size()):
			var cost = float(costs[open[i]])
			if cost < best_cost:
				best_cost = cost
				best_idx = i
		var current: Vector2i = open.pop_at(best_idx)
		var current_cost = float(costs[current])
		var neighbors = get_offset_neighbors(current)
		var expand_neighbors = true
		var edge_cost = 0.0
		match queue_mode:
			"move_to":
				if is_enemy_structure_tile(current, player_id):
					expand_neighbors = false
			"build_road_to":
				var road_status = tm._road_queue_tile_status(current, player_id, current == start)
				if road_status == "invalid":
					expand_neighbors = false
				else:
					edge_cost = 1.0
					if road_status == "build":
						var road_state = tm._structure_state(current)
						var road_build_left = int(road_state.get("build_left", 0)) if road_state is Dictionary else 0
						if road_build_left > 0:
							edge_cost += float(road_build_left)
						else:
							edge_cost += float(tm._structure_build_turns("road", current))
			"build_rail_to":
				var rail_status = tm._rail_queue_tile_status(current, player_id, current == start)
				if rail_status == "invalid":
					expand_neighbors = false
				else:
					edge_cost = 1.0
					if rail_status == "build":
						var rail_state = tm._structure_state(current)
						var rail_build_left = int(rail_state.get("build_left", 0)) if rail_state is Dictionary else 0
						if rail_build_left > 0:
							edge_cost += float(rail_build_left)
						else:
							edge_cost += float(tm._structure_build_turns("rail", current))
			_:
				return result
		if not expand_neighbors:
			continue
		for neighbor in neighbors:
			if not hex_map.is_cell_valid(neighbor):
				continue
			var next_cost = current_cost
			match queue_mode:
				"move_to":
					if not is_move_tile_passable_for_orders(neighbor, player_id):
						continue
					next_cost += float(get_order_move_cost(neighbor, unit, player_id))
				"build_road_to":
					if not tm.is_road_queue_tile_valid(neighbor, player_id, false):
						continue
					next_cost += edge_cost
				"build_rail_to":
					if not tm.is_rail_queue_tile_valid(neighbor, player_id, false):
						continue
					next_cost += edge_cost
			if not costs.has(neighbor) or next_cost < float(costs[neighbor]):
				costs[neighbor] = next_cost
				prev[neighbor] = current
				if neighbor not in open:
					open.append(neighbor)
	result["tiles"] = costs.keys()
	result["prev"] = prev
	result["costs"] = costs
	return result


func clear_highlights() -> void:
	$HighlightMap.clear()

func show_highlights(tiles: Array) -> void:
	clear_highlights()
	for tile in tiles:
		$HighlightMap.set_cell(tile, highlight_tile_id, Vector2i(0,0))

func _get_damage_hover_highlight_map() -> TileMapLayer:
	if damage_hover_highlight_map != null and is_instance_valid(damage_hover_highlight_map):
		return damage_hover_highlight_map
	damage_hover_highlight_map = get_node_or_null("DamageHoverHighlightMap")
	if damage_hover_highlight_map != null and is_instance_valid(damage_hover_highlight_map):
		return damage_hover_highlight_map
	var highlight_map = get_node_or_null("HighlightMap")
	if highlight_map == null:
		return null
	var hover_map = TileMapLayer.new()
	hover_map.name = "DamageHoverHighlightMap"
	hover_map.tile_set = highlight_map.tile_set
	hover_map.top_level = true
	hover_map.z_index = 102
	hover_map.self_modulate = Color(1.0, 0.72, 0.32, 0.7)
	add_child(hover_map)
	damage_hover_highlight_map = hover_map
	return damage_hover_highlight_map

func clear_damage_hover_highlights() -> void:
	var hover_map = _get_damage_hover_highlight_map()
	if hover_map != null:
		hover_map.clear()

func show_damage_hover_highlights(tiles: Array) -> void:
	var hover_map = _get_damage_hover_highlight_map()
	if hover_map == null:
		return
	hover_map.clear()
	for tile in tiles:
		if typeof(tile) == TYPE_VECTOR2I:
			hover_map.set_cell(tile, highlight_tile_id, Vector2i(0, 0))
