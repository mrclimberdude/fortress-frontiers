class_name MapGenerator
extends Node

const DEFAULT_COLUMNS_NORMAL: int = 36
const DEFAULT_ROWS_NORMAL: int = 30
const DEFAULT_COLUMNS_SMALL: int = 24
const DEFAULT_ROWS_SMALL: int = 20

const TERRAIN_FOREST: String = "forest"
const TERRAIN_MOUNTAIN: String = "mountain"
const TERRAIN_RIVER: String = "river"
const TERRAIN_LAKE: String = "lake"

static func generate(md: MapData, rng: RandomNumberGenerator) -> Dictionary:
	var size_tag = str(md.map_size).strip_edges().to_lower()
	var columns = int(md.proc_columns)
	var rows = int(md.proc_rows)
	if columns <= 0 or rows <= 0:
		if size_tag == "small":
			columns = DEFAULT_COLUMNS_SMALL
			rows = DEFAULT_ROWS_SMALL
		else:
			columns = DEFAULT_COLUMNS_NORMAL
			rows = DEFAULT_ROWS_NORMAL

	var bounds := []
	var min_x = 0
	var min_y = 0
	var max_x = columns - 1
	var max_y = rows - 1
	if md.proc_columns <= 0 and md.proc_rows <= 0 and md.terrain_scene != null:
		var ref_inst = md.terrain_scene.instantiate()
		var ref_layer = ref_inst.get_node_or_null("UnderlyingReference")
		if ref_layer != null and ref_layer is TileMapLayer:
			bounds = (ref_layer as TileMapLayer).get_used_cells()
			if not bounds.is_empty():
				min_x = bounds[0].x
				max_x = bounds[0].x
				min_y = bounds[0].y
				max_y = bounds[0].y
				for cell in bounds:
					min_x = min(min_x, cell.x)
					max_x = max(max_x, cell.x)
					min_y = min(min_y, cell.y)
					max_y = max(max_y, cell.y)
				columns = max_x - min_x + 1
				rows = max_y - min_y + 1
		if ref_inst != null:
			ref_inst.free()
	if bounds.is_empty():
		for y in range(rows):
			for x in range(columns):
				bounds.append(Vector2i(min_x + x, min_y + y))
	var bounds_set := {}
	for cell in bounds:
		bounds_set[cell] = true

	var use_template_positions = md.proc_columns <= 0 and md.proc_rows <= 0 and md.base_positions.size() > 0 and md.tower_positions.size() > 0
	var bases: Dictionary
	var towers: Dictionary
	if use_template_positions:
		bases = md.base_positions.duplicate(true)
		towers = md.tower_positions.duplicate(true)
	else:
		bases = _default_bases(min_x, max_x, min_y, max_y, size_tag)
		towers = _default_towers(min_x, max_x, min_y, max_y, bases, size_tag)
	var structure_refs := []
	for pid in bases.keys():
		structure_refs.append(bases[pid])
	for pid in towers.keys():
		for cell in towers[pid]:
			structure_refs.append(cell)

	var mine_count = int(md.proc_mine_count)
	var camp_count = int(md.proc_camp_count)
	var dragon_count = int(md.proc_dragon_count)
	var area = columns * rows
	if mine_count <= 0:
		mine_count = max(2, int(area / 120))
	if camp_count <= 0:
		camp_count = max(2, int(area / 140))
	camp_count = min(10, camp_count)
	if dragon_count <= 0:
		dragon_count = max(1, int(area / 320))
	dragon_count = min(3, dragon_count)

	var structure_buffer = 3
	var mine_spread_min_dist = 3
	var blocked_neutral := {}
	for pid in bases.keys():
		blocked_neutral[bases[pid]] = true
	for pid in towers.keys():
		for cell in towers[pid]:
			blocked_neutral[cell] = true
	var mines_unclaimed := _place_symmetric_tiles(mine_count, bounds, bounds_set, blocked_neutral, rng, min_x, max_x, min_y, max_y, 200, structure_refs, structure_buffer, [], true, false)
	var camps_basic := _place_symmetric_tiles(camp_count, bounds, bounds_set, blocked_neutral, rng, min_x, max_x, min_y, max_y, 200, structure_refs, structure_buffer, [], true, false)
	var tower_cells := []
	for pid in towers.keys():
		for cell in towers[pid]:
			tower_cells.append(cell)
	var min_dragon_dist = 7
	var camp_dragon_min_dist = 4
	var dragon_rules = [
		{"refs": tower_cells, "min_dist": min_dragon_dist},
		{"refs": camps_basic, "min_dist": camp_dragon_min_dist}
	]
	var camps_dragon := _place_symmetric_tiles(dragon_count, bounds, bounds_set, blocked_neutral, rng, min_x, max_x, min_y, max_y, 200, [], 0, dragon_rules, false, false)
	var neutral_noise = 0.08
	var mine_rules_provider = func(current_mines):
		return [
			{"refs": structure_refs, "min_dist": structure_buffer},
			{"refs": current_mines, "min_dist": mine_spread_min_dist}
		]
	mines_unclaimed = _jitter_positions(mines_unclaimed, bounds, bounds_set, blocked_neutral, rng, neutral_noise, 200, mine_rules_provider, min_x, max_x, min_y, max_y, true)
	var camp_rules_provider = func(current_camps):
		return [
			{"refs": structure_refs, "min_dist": structure_buffer},
			{"refs": current_camps, "min_dist": camp_dragon_min_dist},
			{"refs": camps_dragon, "min_dist": camp_dragon_min_dist}
		]
	camps_basic = _jitter_positions(camps_basic, bounds, bounds_set, blocked_neutral, rng, neutral_noise, 200, camp_rules_provider, min_x, max_x, min_y, max_y, true)
	var dragon_rules_provider = func(_positions):
		return [
			{"refs": tower_cells, "min_dist": min_dragon_dist},
			{"refs": camps_basic, "min_dist": camp_dragon_min_dist}
		]
	camps_dragon = _jitter_positions(camps_dragon, bounds, bounds_set, blocked_neutral, rng, neutral_noise, 200, dragon_rules_provider, min_x, max_x, min_y, max_y, true)

	var forest_ratio = clamp(float(md.proc_forest_ratio), 0.0, 1.0)
	var mountain_ratio = clamp(float(md.proc_mountain_ratio), 0.0, 1.0)
	var river_ratio = clamp(float(md.proc_river_ratio), 0.0, 1.0)
	var lake_ratio = clamp(float(md.proc_lake_ratio), 0.0, 1.0)
	var total_ratio = forest_ratio + mountain_ratio + river_ratio + lake_ratio
	if total_ratio > 0.9:
		var scale = 0.9 / total_ratio
		forest_ratio *= scale
		mountain_ratio *= scale
		river_ratio *= scale
		lake_ratio *= scale

	var total_cells = bounds.size()
	var forest_target = int(round(total_cells * forest_ratio * 0.85))
	var mountain_target = int(round(total_cells * mountain_ratio * 0.7))
	var river_target = int(round(total_cells * river_ratio * 0.6))
	var lake_target = int(round(total_cells * lake_ratio))
	var terrain_cells := {
		TERRAIN_FOREST: [],
		TERRAIN_MOUNTAIN: [],
		TERRAIN_RIVER: [],
		TERRAIN_LAKE: []
	}
	var occupied := {}
	for pid in bases.keys():
		occupied[bases[pid]] = true
	for pid in towers.keys():
		for cell in towers[pid]:
			occupied[cell] = true
	for cell in mines_unclaimed:
		occupied[cell] = true
	for cell in camps_basic:
		occupied[cell] = true
	for cell in camps_dragon:
		occupied[cell] = true
	var buffer_radius = 2
	var river_cells = _generate_river_cells(bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, river_target, structure_refs, buffer_radius)
	for cell in river_cells:
		terrain_cells[TERRAIN_RIVER].append(cell)
	var mountain_cells = _generate_mountain_cells(bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, mountain_target, structure_refs, buffer_radius)
	for cell in mountain_cells:
		terrain_cells[TERRAIN_MOUNTAIN].append(cell)
	var lake_cells = _place_symmetric_tiles(lake_target, bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, 200, structure_refs, buffer_radius, [], false)
	for cell in lake_cells:
		terrain_cells[TERRAIN_LAKE].append(cell)
	var forest_cells = _generate_forest_cells(bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, forest_target, structure_refs, buffer_radius)
	for cell in forest_cells:
		terrain_cells[TERRAIN_FOREST].append(cell)
	_add_symmetry_noise(terrain_cells, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, structure_refs, buffer_radius)
	_prune_terrain_near_refs(terrain_cells, structure_refs, buffer_radius)

	var reserved := {}
	for pid in bases.keys():
		reserved[bases[pid]] = true
	for pid in towers.keys():
		for cell in towers[pid]:
			reserved[cell] = true
	for cell in mines_unclaimed:
		reserved[cell] = true
	for cell in camps_basic:
		reserved[cell] = true
	for cell in camps_dragon:
		reserved[cell] = true

	_remove_cells(terrain_cells, reserved)
	var blocked = _build_blocked_set(terrain_cells, bases, towers)
	for cell in mines_unclaimed:
		blocked[cell] = true
	for cell in camps_basic:
		blocked[cell] = true
	for cell in camps_dragon:
		blocked[cell] = true

	return {
		"bounds": bounds,
		"terrain_cells": terrain_cells,
		"base_positions": bases,
		"tower_positions": towers,
		"mines": {
			"unclaimed": mines_unclaimed,
			"player1": [],
			"player2": []
		},
		"camps": {
			"basic": camps_basic,
			"dragon": camps_dragon
		}
	}

static func _default_bases(min_x: int, max_x: int, min_y: int, max_y: int, _size_tag: String) -> Dictionary:
	var y = int((min_y + max_y) / 2)
	return {
		"player1": Vector2i(min_x - 1, y),
		"player2": Vector2i(max_x, y)
	}

static func _default_towers(min_x: int, max_x: int, min_y: int, max_y: int, bases: Dictionary, size_tag: String) -> Dictionary:
	var towers := {"player1": [], "player2": []}
	var offsets = [-5, 0, 5]
	var p1 = bases.get("player1", Vector2i(min_x - 1, int((min_y + max_y) / 2)))
	var p2 = bases.get("player2", Vector2i(max_x, int((min_y + max_y) / 2)))
	var left_outer: int
	var left_mid: int
	var right_outer: int
	var right_mid: int
	if size_tag == "small":
		left_outer = p1.x + 2
		left_mid = p1.x + 3
		right_outer = p2.x - 1
		right_mid = p2.x - 3
	else:
		left_outer = p1.x + 3
		left_mid = p1.x + 3
		right_outer = p2.x - 2
		right_mid = p2.x - 3
	for off in offsets:
		var y1 = clamp(p1.y + off, min_y + 1, max_y - 1)
		var y2 = clamp(p2.y + off, min_y + 1, max_y - 1)
		var left_x = left_mid
		var right_x = right_mid
		if off != 0:
			left_x = left_outer
			right_x = right_outer
		towers["player1"].append(Vector2i(clamp(left_x, min_x + 1, max_x - 1), y1))
		towers["player2"].append(Vector2i(clamp(right_x, min_x + 1, max_x - 1), y2))
	return towers

static func _build_blocked_set(terrain_cells: Dictionary, bases: Dictionary, towers: Dictionary) -> Dictionary:
	var blocked := {}
	for key in terrain_cells.keys():
		for cell in terrain_cells[key]:
			blocked[cell] = true
	for pid in bases.keys():
		blocked[bases[pid]] = true
	for pid in towers.keys():
		for cell in towers[pid]:
			blocked[cell] = true
	return blocked

static func _remove_cells(terrain_cells: Dictionary, blocked: Dictionary) -> void:
	for key in terrain_cells.keys():
		var filtered := []
		for cell in terrain_cells[key]:
			if not blocked.has(cell):
				filtered.append(cell)
		terrain_cells[key] = filtered

static func _prune_terrain_near_refs(terrain_cells: Dictionary, refs: Array, radius: int) -> void:
	if refs.is_empty():
		return
	for key in terrain_cells.keys():
		var filtered := []
		for cell in terrain_cells[key]:
			var keep = true
			for ref in refs:
				if typeof(ref) != TYPE_VECTOR2I:
					continue
				if _hex_distance(cell, ref) <= radius:
					keep = false
					break
			if keep:
				filtered.append(cell)
		terrain_cells[key] = filtered

static func _generate_river_cells(bounds: Array, bounds_set: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, target: int, refs: Array, min_dist: int) -> Array:
	var river := []
	if target <= 0 or bounds.is_empty():
		return river
	var river_set := {}
	var center_guess = Vector2i(int((min_x + max_x) / 2), int((min_y + max_y) / 2))
	var center = _closest_bound_cell(center_guess, bounds)
	if center == Vector2i(-1, -1):
		return river
	var edge_cells = _edge_cells(bounds_set, min_x, max_x, min_y, max_y)
	var primary_edges := []
	for cell in edge_cells:
		var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
		if _is_primary_cell(cell, mirror):
			if _meets_min_distance(cell, refs, min_dist) and _meets_min_distance(mirror, refs, min_dist):
				primary_edges.append(cell)
	var main_start = Vector2i(-1, -1)
	if not primary_edges.is_empty() and rng.randf() < 0.6:
		main_start = primary_edges[rng.randi_range(0, primary_edges.size() - 1)]
	else:
		main_start = _pick_primary_open_cell(bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, refs, min_dist)
	if main_start == Vector2i(-1, -1):
		return river
	var main_target = _pick_primary_open_cell(bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, refs, min_dist)
	if main_target == Vector2i(-1, -1):
		main_target = center
	var main_path = _build_river_path(main_start, main_target, bounds_set, occupied, river_set, rng, min_x, max_x, min_y, max_y, refs, min_dist, false, 0.12)
	_add_river_path(main_path, river, river_set, bounds_set, occupied, min_x, max_x, min_y, max_y)
	var branch_attempts = max(3, int(target / 6))
	var tries = 0
	while river.size() < target and tries < branch_attempts * 4:
		tries += 1
		var start = _pick_branch_start(bounds, bounds_set, river_set, rng, min_x, max_x, min_y, max_y, refs, min_dist)
		if start == Vector2i(-1, -1):
			break
		var target_cell = _nearest_river_cell(start, river_set)
		if target_cell == Vector2i(-1, -1):
			break
		var path = _build_river_path(start, target_cell, bounds_set, occupied, river_set, rng, min_x, max_x, min_y, max_y, refs, min_dist, true, 0.28)
		_add_river_path(path, river, river_set, bounds_set, occupied, min_x, max_x, min_y, max_y)
	return river

static func _generate_mountain_cells(bounds: Array, bounds_set: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, target: int, refs: Array, min_dist: int) -> Array:
	var mountains := []
	if target <= 0 or bounds.is_empty():
		return mountains
	var attempts = 0
	var max_attempts = max(12, target * 2)
	while mountains.size() < target and attempts < max_attempts:
		attempts += 1
		var seed = _pick_primary_open_cell(bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, refs, min_dist)
		if seed == Vector2i(-1, -1):
			break
		var remaining = target - mountains.size()
		var cluster_limit = min(remaining, rng.randi_range(3, 6))
		var cluster = _grow_symmetric_cluster(seed, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, cluster_limit, refs, min_dist)
		for cell in cluster:
			mountains.append(cell)
	return mountains

static func _generate_forest_cells(bounds: Array, bounds_set: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, target: int, refs: Array, min_dist: int) -> Array:
	var forests := []
	if target <= 0 or bounds.is_empty():
		return forests
	var attempts = 0
	var max_attempts = max(30, target * 5)
	while forests.size() < target and attempts < max_attempts:
		attempts += 1
		var seed = _pick_primary_open_cell(bounds, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, refs, min_dist)
		if seed == Vector2i(-1, -1):
			break
		var remaining = target - forests.size()
		var cluster_limit = min(remaining, rng.randi_range(2, 4))
		var cluster = _grow_symmetric_cluster(seed, bounds_set, occupied, rng, min_x, max_x, min_y, max_y, cluster_limit, refs, min_dist)
		for cell in cluster:
			forests.append(cell)
	return forests

static func _add_symmetry_noise(terrain_cells: Dictionary, bounds_set: Dictionary, blocked_cells: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, refs: Array, min_dist: int) -> void:
	var noise_rate = 0.08
	var target_types = [TERRAIN_FOREST, TERRAIN_MOUNTAIN, TERRAIN_RIVER, TERRAIN_LAKE]
	var empty := {}
	var occupied_all := {}
	for key in terrain_cells.keys():
		for cell in terrain_cells.get(key, []):
			occupied_all[cell] = true
	if blocked_cells != null:
		for cell in blocked_cells.keys():
			occupied_all[cell] = true
	for t in target_types:
		var cells: Array = terrain_cells.get(t, [])
		if cells.is_empty():
			continue
		var remove_count = int(round(cells.size() * noise_rate))
		var removed := {}
		var attempts = 0
		while removed.size() < remove_count and attempts < remove_count * 6:
			attempts += 1
			var idx = rng.randi_range(0, cells.size() - 1)
			var cell = cells[idx]
			var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
			if cell == mirror:
				continue
			if blocked_cells != null and blocked_cells.has(cell):
				continue
			if not bounds_set.has(cell):
				continue
			removed[cell] = true
		if removed.is_empty():
			continue
		var kept := []
		for cell in cells:
			if removed.has(cell):
				continue
			kept.append(cell)
		for cell in removed.keys():
			occupied_all.erase(cell)
		terrain_cells[t] = kept
		var add_attempts = remove_count * 10
		var added := 0
		while added < remove_count and add_attempts > 0:
			add_attempts -= 1
			var cell = _pick_primary_open_cell(bounds_set.keys(), bounds_set, empty, rng, min_x, max_x, min_y, max_y, refs, min_dist)
			if cell == Vector2i(-1, -1):
				break
			if cell in kept:
				continue
			if occupied_all.has(cell):
				continue
			if blocked_cells != null and blocked_cells.has(cell):
				continue
			if not _meets_min_distance(cell, refs, min_dist):
				continue
			kept.append(cell)
			occupied_all[cell] = true
			added += 1
		terrain_cells[t] = kept

static func _build_river_path(start: Vector2i, target: Vector2i, bounds_set: Dictionary, occupied: Dictionary, river_set: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, refs: Array, min_dist: int, stop_on_river: bool, early_stop_bias: float) -> Array:
	var path := []
	var current = start
	var visited := {}
	var max_steps = max(20, int(bounds_set.size() / 3))
	var last_dir = Vector3i.ZERO
	var start_dist = _hex_distance(start, target)
	var max_len = max(6, int(float(start_dist) * 1.2) + 4)
	for _i in range(max_steps):
		if not bounds_set.has(current):
			break
		path.append(current)
		if early_stop_bias > 0.0 and path.size() >= max_len:
			if rng.randf() < early_stop_bias:
				break
		if current == target:
			break
		if stop_on_river and river_set.has(current):
			break
		if early_stop_bias > 0.0 and _hex_distance(current, target) <= 2:
			if rng.randf() < early_stop_bias * 0.6:
				break
		visited[current] = true
		var neighbors = _offset_neighbors_in_bounds(current, bounds_set)
		if neighbors.is_empty():
			break
		var prev_dir = last_dir
		var best = Vector2i(-1, -1)
		var best_score = INF
		var candidate_scores := []
		var current_cube = _offset_to_cube(current)
		for n in neighbors:
			if visited.has(n):
				continue
			var mirror = _mirror_cell(n, min_x, max_x, min_y, max_y)
			if not bounds_set.has(mirror):
				continue
			if not _meets_min_distance(n, refs, min_dist):
				continue
			if not _meets_min_distance(mirror, refs, min_dist):
				continue
			if occupied.has(n) and not river_set.has(n):
				continue
			if occupied.has(mirror) and not river_set.has(mirror):
				continue
			var dist = _hex_distance(n, target)
			if river_set.has(n):
				dist = max(0, dist - 2)
			var n_cube = _offset_to_cube(n)
			var dir = n_cube - current_cube
			var score = float(dist) + rng.randf() * 0.55
			if prev_dir != Vector3i.ZERO:
				if dir == prev_dir:
					score += 0.8
				else:
					score -= 0.15
			candidate_scores.append({"pos": n, "score": score, "dir": dir})
			if score < best_score:
				best_score = score
				best = n
		if best == Vector2i(-1, -1):
			break
		if candidate_scores.size() > 1 and rng.randf() < 0.3:
			candidate_scores.sort_custom(func(a, b): return a["score"] < b["score"])
			var pick_count = min(3, candidate_scores.size())
			var choice = candidate_scores[rng.randi_range(0, pick_count - 1)]
			best = choice["pos"]
			last_dir = choice["dir"]
		else:
			for entry in candidate_scores:
				if entry["pos"] == best:
					last_dir = entry["dir"]
					break
		current = best
	return path

static func _add_river_path(path: Array, river: Array, river_set: Dictionary, bounds_set: Dictionary, occupied: Dictionary, min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	for cell in path:
		_add_river_cell(cell, river, river_set, bounds_set, occupied, min_x, max_x, min_y, max_y)

static func _add_river_cell(cell: Vector2i, river: Array, river_set: Dictionary, bounds_set: Dictionary, occupied: Dictionary, min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
	if bounds_set.has(cell):
		if not river_set.has(cell):
			river.append(cell)
			river_set[cell] = true
		occupied[cell] = true
	if mirror != cell and bounds_set.has(mirror):
		if not river_set.has(mirror):
			river.append(mirror)
			river_set[mirror] = true
		occupied[mirror] = true

static func _pick_branch_start(bounds: Array, bounds_set: Dictionary, river_set: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, refs: Array, min_dist: int) -> Vector2i:
	if bounds.is_empty():
		return Vector2i(-1, -1)
	for _i in range(200):
		var cell = bounds[rng.randi_range(0, bounds.size() - 1)]
		var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
		if not _is_primary_cell(cell, mirror):
			continue
		if not bounds_set.has(mirror):
			continue
		if river_set.has(cell) or river_set.has(mirror):
			continue
		if not _meets_min_distance(cell, refs, min_dist):
			continue
		if not _meets_min_distance(mirror, refs, min_dist):
			continue
		if _min_distance_to_river(cell, river_set) < 3:
			continue
		return cell
	return Vector2i(-1, -1)

static func _pick_primary_open_cell(bounds: Array, bounds_set: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, refs: Array, min_dist: int) -> Vector2i:
	if bounds.is_empty():
		return Vector2i(-1, -1)
	for _i in range(200):
		var cell = bounds[rng.randi_range(0, bounds.size() - 1)]
		var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
		if not _is_primary_cell(cell, mirror):
			continue
		if not bounds_set.has(mirror):
			continue
		if occupied.has(cell) or occupied.has(mirror):
			continue
		if not _meets_min_distance(cell, refs, min_dist):
			continue
		if not _meets_min_distance(mirror, refs, min_dist):
			continue
		return cell
	return Vector2i(-1, -1)

static func _grow_symmetric_cluster(seed: Vector2i, bounds_set: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, limit: int, refs: Array, min_dist: int) -> Array:
	var cluster := []
	if limit <= 0:
		return cluster
	var frontier := [seed]
	var seen := {}
	var remaining = limit
	while frontier.size() > 0 and remaining > 0:
		var idx = rng.randi_range(0, frontier.size() - 1)
		var cell = frontier.pop_at(idx)
		if seen.has(cell):
			continue
		seen[cell] = true
		var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
		if not bounds_set.has(cell) or not bounds_set.has(mirror):
			continue
		if occupied.has(cell) or occupied.has(mirror):
			continue
		if not _meets_min_distance(cell, refs, min_dist):
			continue
		if not _meets_min_distance(mirror, refs, min_dist):
			continue
		var add_count = 1 if mirror == cell else 2
		if add_count > remaining:
			continue
		cluster.append(cell)
		occupied[cell] = true
		remaining -= 1
		if mirror != cell:
			cluster.append(mirror)
			occupied[mirror] = true
			remaining -= 1
		for n in _offset_neighbors_in_bounds(cell, bounds_set):
			if not seen.has(n):
				frontier.append(n)
	return cluster

static func _closest_bound_cell(target: Vector2i, bounds: Array) -> Vector2i:
	if bounds.is_empty():
		return Vector2i(-1, -1)
	var best = bounds[0]
	var best_dist = _hex_distance(best, target)
	for cell in bounds:
		var dist = _hex_distance(cell, target)
		if dist < best_dist:
			best = cell
			best_dist = dist
	return best

static func _edge_cells(bounds_set: Dictionary, min_x: int, max_x: int, min_y: int, max_y: int) -> Array:
	var edges := []
	for cell in bounds_set.keys():
		if cell.x == min_x or cell.x == max_x or cell.y == min_y or cell.y == max_y:
			edges.append(cell)
	return edges

static func _nearest_river_cell(cell: Vector2i, river_set: Dictionary) -> Vector2i:
	if river_set.is_empty():
		return Vector2i(-1, -1)
	var best = Vector2i(-1, -1)
	var best_dist = INF
	for key in river_set.keys():
		var dist = _hex_distance(cell, key)
		if dist < best_dist:
			best = key
			best_dist = dist
	return best

static func _min_distance_to_river(cell: Vector2i, river_set: Dictionary) -> int:
	if river_set.is_empty():
		return 999
	var best = 999
	for key in river_set.keys():
		var dist = _hex_distance(cell, key)
		if dist < best:
			best = dist
	return best

static func _offset_neighbors_in_bounds(cell: Vector2i, bounds_set: Dictionary) -> Array:
	var neighbors := []
	for n in _offset_neighbors(cell):
		if bounds_set.has(n):
			neighbors.append(n)
	return neighbors

static func _offset_neighbors(cell: Vector2i) -> Array:
	var dirs = [
		Vector3i(1, -1, 0),
		Vector3i(1, 0, -1),
		Vector3i(0, 1, -1),
		Vector3i(-1, 1, 0),
		Vector3i(-1, 0, 1),
		Vector3i(0, -1, 1)
	]
	var neighbors := []
	var cube = _offset_to_cube(cell)
	for d in dirs:
		var nc = cube + d
		neighbors.append(_cube_to_offset(nc))
	return neighbors

static func _cube_to_offset(cube: Vector3i) -> Vector2i:
	var x = cube.x + (cube.z - (cube.z & 1)) / 2
	var y = cube.z
	return Vector2i(x, y)

static func _pick_open_tile(bounds: Array, blocked: Dictionary, rng: RandomNumberGenerator, max_tries: int) -> Vector2i:
	if bounds.is_empty():
		return Vector2i(-1, -1)
	for _i in range(max_tries):
		var idx = rng.randi_range(0, bounds.size() - 1)
		var cell = bounds[idx]
		if not blocked.has(cell):
			return cell
	return Vector2i(-1, -1)

static func _pick_open_cell_with_rules(bounds: Array, bounds_set: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, rules: Array, max_tries: int) -> Vector2i:
	if bounds.is_empty():
		return Vector2i(-1, -1)
	for _i in range(max_tries):
		var cell = bounds[rng.randi_range(0, bounds.size() - 1)]
		if not bounds_set.has(cell):
			continue
		if blocked.has(cell):
			continue
		if not _meets_distance_rules(cell, rules):
			continue
		return cell
	return Vector2i(-1, -1)

static func _pick_open_tile_pair(bounds: Array, bounds_set: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, max_tries: int, min_x: int, max_x: int, min_y: int, max_y: int, refs: Array, min_dist: int, rules: Array = []) -> Array:
	if bounds.is_empty():
		return []
	for _i in range(max_tries):
		var idx = rng.randi_range(0, bounds.size() - 1)
		var cell = bounds[idx]
		var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
		if mirror == cell:
			continue
		if not bounds_set.has(mirror):
			continue
		if blocked.has(cell) or blocked.has(mirror):
			continue
		if not _meets_min_distance(cell, refs, min_dist):
			continue
		if not _meets_min_distance(mirror, refs, min_dist):
			continue
		if not _meets_distance_rules(cell, rules):
			continue
		if not _meets_distance_rules(mirror, rules):
			continue
		return [cell, mirror]
	return []

static func _jitter_positions(positions: Array, bounds: Array, bounds_set: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, noise_rate: float, max_tries: int, rules_provider: Callable, min_x: int = 0, max_x: int = 0, min_y: int = 0, max_y: int = 0, enforce_symmetry: bool = false) -> Array:
	if positions.is_empty():
		return positions
	var count = int(round(positions.size() * noise_rate))
	if not enforce_symmetry:
		for _i in range(count):
			if positions.is_empty():
				break
			var idx = rng.randi_range(0, positions.size() - 1)
			var original = positions.pop_at(idx)
			blocked.erase(original)
			var rules: Array = []
			if rules_provider.is_valid():
				rules = rules_provider.call(positions)
			var cell = _pick_open_cell_with_rules(bounds, bounds_set, blocked, rng, rules, max_tries)
			if cell != Vector2i(-1, -1):
				positions.append(cell)
				blocked[cell] = true
			else:
				positions.append(original)
				blocked[original] = true
		return positions
	var positions_set := {}
	for cell in positions:
		positions_set[cell] = true
	var pairs := []
	for cell in positions:
		var mirror = _mirror_cell(cell, min_x, max_x, min_y, max_y)
		if not positions_set.has(mirror):
			continue
		if _is_primary_cell(cell, mirror):
			pairs.append(cell)
	var pair_count = int(round(pairs.size() * noise_rate))
	for _i in range(pair_count):
		if pairs.is_empty():
			break
		var idx = rng.randi_range(0, pairs.size() - 1)
		var primary = pairs.pop_at(idx)
		var mirror = _mirror_cell(primary, min_x, max_x, min_y, max_y)
		var removed = [primary]
		if mirror != primary:
			removed.append(mirror)
		for cell in removed:
			positions.erase(cell)
			positions_set.erase(cell)
			blocked.erase(cell)
		var rules: Array = []
		if rules_provider.is_valid():
			rules = rules_provider.call(positions)
		var new_primary = _pick_open_cell_with_rules(bounds, bounds_set, blocked, rng, rules, max_tries)
		var new_mirror = Vector2i(-1, -1)
		var valid = true
		if new_primary == Vector2i(-1, -1):
			valid = false
		else:
			new_mirror = _mirror_cell(new_primary, min_x, max_x, min_y, max_y)
			if not bounds_set.has(new_mirror):
				valid = false
			elif blocked.has(new_mirror):
				valid = false
			elif not _meets_distance_rules(new_mirror, rules):
				valid = false
		if valid:
			positions.append(new_primary)
			positions_set[new_primary] = true
			blocked[new_primary] = true
			if new_mirror != new_primary:
				positions.append(new_mirror)
				positions_set[new_mirror] = true
				blocked[new_mirror] = true
		else:
			for cell in removed:
				positions.append(cell)
				positions_set[cell] = true
				blocked[cell] = true
	return positions

static func _place_symmetric_tiles(count: int, bounds: Array, bounds_set: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, max_tries: int, refs: Array = [], min_dist: int = 0, rules: Array = [], avoid_self: bool = false, allow_center: bool = true) -> Array:
	var placed := []
	if count <= 0:
		return placed
	var remaining = count
	var center = Vector2i(int((min_x + max_x) / 2), int((min_y + max_y) / 2))
	var dynamic_refs = refs
	if avoid_self and min_dist > 0:
		dynamic_refs = refs.duplicate()
	if remaining % 2 == 1:
		remaining -= 1
		if allow_center and _mirror_cell(center, min_x, max_x, min_y, max_y) == center:
			if bounds_set.has(center) and not blocked.has(center) and _meets_min_distance(center, dynamic_refs, min_dist) and _meets_distance_rules(center, rules):
				placed.append(center)
				blocked[center] = true
				if avoid_self and min_dist > 0:
					dynamic_refs.append(center)
	var pair_count = int(remaining / 2)
	for _i in range(pair_count):
		var pair = _pick_open_tile_pair(bounds, bounds_set, blocked, rng, max_tries, min_x, max_x, min_y, max_y, dynamic_refs, min_dist, rules)
		if pair.is_empty():
			break
		for cell in pair:
			placed.append(cell)
			blocked[cell] = true
			if avoid_self and min_dist > 0:
				dynamic_refs.append(cell)
	return placed

static func _mirror_cell(cell: Vector2i, min_x: int, max_x: int, min_y: int, max_y: int) -> Vector2i:
	return Vector2i(min_x + max_x - cell.x, min_y + max_y - cell.y)

static func _is_primary_cell(cell: Vector2i, mirror: Vector2i) -> bool:
	if cell.x < mirror.x:
		return true
	if cell.x > mirror.x:
		return false
	return cell.y <= mirror.y

static func _meets_distance_rules(cell: Vector2i, rules: Array) -> bool:
	if rules.is_empty():
		return true
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var refs = rule.get("refs", [])
		var min_dist = int(rule.get("min_dist", 0))
		if min_dist <= 0 or refs.is_empty():
			continue
		if not _meets_min_distance(cell, refs, min_dist):
			return false
	return true

static func _meets_min_distance(cell: Vector2i, refs: Array, min_dist: int) -> bool:
	if refs.is_empty():
		return true
	for ref in refs:
		if typeof(ref) != TYPE_VECTOR2I:
			continue
		if _hex_distance(cell, ref) < min_dist:
			return false
	return true

static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac = _offset_to_cube(a)
	var bc = _offset_to_cube(b)
	return int(max(abs(ac.x - bc.x), abs(ac.y - bc.y), abs(ac.z - bc.z)))

static func _offset_to_cube(cell: Vector2i) -> Vector3i:
	var x = cell.x - (cell.y - (cell.y & 1)) / 2
	var z = cell.y
	var y = -x - z
	return Vector3i(x, y, z)
