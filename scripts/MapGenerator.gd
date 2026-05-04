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
const MINE_REPULSION_EXPONENT: float = 1.1

static func _default_player_ids(player_count: int) -> Array:
	var ids: Array = []
	for i in range(max(2, player_count)):
		ids.append("player%d" % (i + 1))
	return ids

static func _proc_shape(md: MapData) -> String:
	var shape = str(md.proc_shape).strip_edges().to_lower()
	return shape if shape != "" else "rectangle"

static func _default_hex_radius(md: MapData, size_tag: String) -> int:
	if int(md.proc_hex_radius) > 0:
		return int(md.proc_hex_radius)
	return 16 if size_tag == "small" else 24

static func _cube_distance(a: Vector3i, b: Vector3i) -> int:
	return int(max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z)))

static func _cube_neighbors(cell: Vector3i) -> Array:
	var dirs = [
		Vector3i(1, -1, 0),
		Vector3i(1, 0, -1),
		Vector3i(0, 1, -1),
		Vector3i(-1, 1, 0),
		Vector3i(-1, 0, 1),
		Vector3i(0, -1, 1)
	]
	var neighbors := []
	for d in dirs:
		neighbors.append(cell + d)
	return neighbors

static func _rotate_cube_120(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.y, cell.z, cell.x)

static func _rotate_cube_240(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.z, cell.x, cell.y)

static func _cube_orbit3(cell: Vector3i) -> Array:
	var orbit := [cell]
	var r1 = _rotate_cube_120(cell)
	if not orbit.has(r1):
		orbit.append(r1)
	var r2 = _rotate_cube_240(cell)
	if not orbit.has(r2):
		orbit.append(r2)
	return orbit

static func _build_hex_geometry(radius: int) -> Dictionary:
	var cubes := []
	for x in range(-radius, radius + 1):
		var min_y = max(-radius, -x - radius)
		var max_y = min(radius, -x + radius)
		for y in range(min_y, max_y + 1):
			var z = -x - y
			cubes.append(Vector3i(x, y, z))
	var offsets := []
	var min_x = 0
	var min_y = 0
	var first = true
	for cube in cubes:
		var cell = _cube_to_offset(cube)
		offsets.append(cell)
		if first:
			min_x = cell.x
			min_y = cell.y
			first = false
		else:
			min_x = min(min_x, cell.x)
			min_y = min(min_y, cell.y)
	var shift = Vector2i(-min_x, -min_y)
	var bounds := []
	var bounds_set := {}
	var cube_to_cell := {}
	for i in range(cubes.size()):
		var shifted = offsets[i] + shift
		bounds.append(shifted)
		bounds_set[shifted] = true
		cube_to_cell[cubes[i]] = shifted
	return {
		"radius": radius,
		"bounds": bounds,
		"bounds_set": bounds_set,
		"bounds_cubes": cubes,
		"cube_to_cell": cube_to_cell,
		"center_cube": Vector3i.ZERO,
		"center_cell": _cube_to_offset(Vector3i.ZERO) + shift
	}

static func _three_player_side_center_cubes(radius: int) -> Array:
	var half_low = int(floor(float(radius) * 0.5))
	var half_high = radius - half_low
	var top = Vector3i(half_low, half_high, -radius)
	var bottom_right = _rotate_cube_120(top)
	var bottom_left = _rotate_cube_240(top)
	return [bottom_left, top, bottom_right]

static func _three_player_hex_bases(player_ids: Array, radius: int) -> Dictionary:
	var side_centers = _three_player_side_center_cubes(radius)
	var bases := {}
	for i in range(min(player_ids.size(), side_centers.size())):
		bases[player_ids[i]] = side_centers[i]
	return bases

static func _three_player_top_tower_pattern(radius: int) -> Array:
	var outer_depth = 3 if radius <= 16 else (4 if radius <= 20 else 5)
	var center_depth = outer_depth + 1
	var spread = 3 if radius <= 16 else (5 if radius <= 20 else 6)
	var outer_z = -radius + outer_depth
	var outer_sum = radius - outer_depth
	var outer_center_x = int(floor(float(outer_sum) * 0.5))
	var outer_center_y = outer_sum - outer_center_x
	var outer_anchor = Vector3i(outer_center_x, outer_center_y, outer_z)
	var center_z = -radius + center_depth
	var center_sum = radius - center_depth
	var center_x = int(floor(float(center_sum) * 0.5))
	var center_y = center_sum - center_x
	var center_anchor = Vector3i(center_x, center_y, center_z)
	var tangent = Vector3i(1, -1, 0)
	return [
		outer_anchor - tangent * spread,
		center_anchor,
		outer_anchor + tangent * spread
	]

static func _three_player_hex_towers(player_ids: Array, base_cubes: Dictionary, bounds_set_cube: Dictionary, radius: int) -> Dictionary:
	var towers := {}
	for player_id in player_ids:
		towers[player_id] = []
	var top_pattern = _three_player_top_tower_pattern(radius)
	var top_player = player_ids[1] if player_ids.size() > 1 else (player_ids[0] if not player_ids.is_empty() else "")
	var bottom_right_player = player_ids[2] if player_ids.size() > 2 else ""
	var bottom_left_player = player_ids[0] if not player_ids.is_empty() else ""
	for cube in top_pattern:
		if bounds_set_cube.has(cube) and top_player != "":
			towers[top_player].append(cube)
		var bottom_right = _rotate_cube_120(cube)
		if bounds_set_cube.has(bottom_right) and bottom_right_player != "":
			towers[bottom_right_player].append(bottom_right)
		var bottom_left = _rotate_cube_240(cube)
		if bounds_set_cube.has(bottom_left) and bottom_left_player != "":
			towers[bottom_left_player].append(bottom_left)
	return towers

static func _cube_refs_from_structures(base_cubes: Dictionary, tower_cubes: Dictionary) -> Array:
	var refs := []
	for pid in base_cubes.keys():
		refs.append(base_cubes[pid])
	for pid in tower_cubes.keys():
		for cell in tower_cubes[pid]:
			refs.append(cell)
	return refs

static func _cube_meets_min_distance(cell: Vector3i, refs: Array, min_dist: int) -> bool:
	if min_dist <= 0 or refs.is_empty():
		return true
	for ref in refs:
		if typeof(ref) != TYPE_VECTOR3I:
			continue
		if _cube_distance(cell, ref) < min_dist:
			return false
	return true

static func _cube_meets_distance_rules(cell: Vector3i, rules: Array) -> bool:
	if rules.is_empty():
		return true
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var refs = rule.get("refs", [])
		var min_dist = int(rule.get("min_dist", 0))
		if not _cube_meets_min_distance(cell, refs, min_dist):
			return false
	return true

static func _cube_repulsion_score(cell: Vector3i, refs: Array) -> float:
	var score = 0.0
	for ref in refs:
		if typeof(ref) != TYPE_VECTOR3I:
			continue
		var dist = _cube_distance(cell, ref)
		if dist <= 0:
			continue
		score += 1.0 / pow(float(dist), MINE_REPULSION_EXPONENT)
	return score

static func _cube_orbit_score(orbit: Array, refs: Array) -> float:
	var score = 0.0
	for cell in orbit:
		score += _cube_repulsion_score(cell, refs)
	return score

static func _cube_ring_distance(cell: Vector3i) -> int:
	return _cube_distance(cell, Vector3i.ZERO)

static func _pick_rotational_orbit3(bounds_cubes: Array, bounds_set_cube: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, max_tries: int, rules: Array = [], score_refs: Array = [], min_ring: int = -1, max_ring: int = -1, target_ring: float = -1.0, ring_weight: float = 1.0) -> Array:
	var best_orbit: Array = []
	var best_score = INF
	for _i in range(max_tries):
		if bounds_cubes.is_empty():
			break
		var cell: Vector3i = bounds_cubes[rng.randi_range(0, bounds_cubes.size() - 1)]
		var ring = _cube_ring_distance(cell)
		if min_ring >= 0 and ring < min_ring:
			continue
		if max_ring >= 0 and ring > max_ring:
			continue
		var orbit = _cube_orbit3(cell)
		if orbit.size() != 3:
			continue
		var valid = true
		for orbit_cell in orbit:
			if not bounds_set_cube.has(orbit_cell):
				valid = false
				break
			if blocked.has(orbit_cell):
				valid = false
				break
			if not _cube_meets_distance_rules(orbit_cell, rules):
				valid = false
				break
		if not valid:
			continue
		if score_refs.is_empty():
			if target_ring < 0.0:
				return orbit
		var score = _cube_orbit_score(orbit, score_refs)
		if target_ring >= 0.0:
			score += abs(float(ring) - target_ring) * ring_weight
		if score < best_score:
			best_score = score
			best_orbit = orbit
	return best_orbit

static func _cube_orbit_key(orbit: Array) -> String:
	var parts := []
	for cell in orbit:
		if typeof(cell) != TYPE_VECTOR3I:
			continue
		parts.append("%d,%d,%d" % [cell.x, cell.y, cell.z])
	parts.sort()
	return "|".join(parts)

static func _orbit3_is_valid(orbit: Array, bounds_set_cube: Dictionary, blocked: Dictionary, rules: Array = [], min_ring: int = -1, max_ring: int = -1) -> bool:
	if orbit.size() != 3:
		return false
	for orbit_cell in orbit:
		if not bounds_set_cube.has(orbit_cell):
			return false
		if blocked.has(orbit_cell):
			return false
		var ring = _cube_ring_distance(orbit_cell)
		if min_ring >= 0 and ring < min_ring:
			return false
		if max_ring >= 0 and ring > max_ring:
			return false
		if not _cube_meets_distance_rules(orbit_cell, rules):
			return false
	return true

static func _place_rotational_tiles3(count: int, bounds_cubes: Array, bounds_set_cube: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, max_tries: int, rules: Array = [], score_refs: Array = [], min_ring: int = -1, max_ring: int = -1, target_ring: float = -1.0, ring_weight: float = 1.0) -> Array:
	var placed := []
	var remaining = count
	while remaining >= 3:
		var orbit_score_refs = score_refs + placed
		var orbit = _pick_rotational_orbit3(bounds_cubes, bounds_set_cube, blocked, rng, max_tries, rules, orbit_score_refs, min_ring, max_ring, target_ring, ring_weight)
		if orbit.is_empty():
			break
		for cell in orbit:
			placed.append(cell)
			blocked[cell] = true
		remaining -= 3
	return placed

static func _grow_rotational_cluster3(seed_orbit: Array, bounds_set_cube: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, rules: Array, max_orbits: int, min_ring: int = -1, max_ring: int = -1) -> Array:
	var cluster := []
	if seed_orbit.is_empty() or max_orbits <= 0:
		return cluster
	var frontier: Array = seed_orbit.duplicate()
	var seen_orbits := {}
	var orbits_added = 0
	while not frontier.is_empty() and orbits_added < max_orbits:
		var idx = rng.randi_range(0, frontier.size() - 1)
		var cell: Vector3i = frontier.pop_at(idx)
		var orbit = _cube_orbit3(cell)
		var orbit_key = _cube_orbit_key(orbit)
		if seen_orbits.has(orbit_key):
			continue
		seen_orbits[orbit_key] = true
		if not _orbit3_is_valid(orbit, bounds_set_cube, blocked, rules, min_ring, max_ring):
			continue
		for orbit_cell in orbit:
			cluster.append(orbit_cell)
			blocked[orbit_cell] = true
		orbits_added += 1
		for orbit_cell in orbit:
			for neighbor in _cube_neighbors(orbit_cell):
				var neighbor_orbit = _cube_orbit3(neighbor)
				var neighbor_key = _cube_orbit_key(neighbor_orbit)
				if seen_orbits.has(neighbor_key):
					continue
				frontier.append(neighbor)
	return cluster

static func _generate_clustered_rotational_tiles3(target: int, bounds_cubes: Array, bounds_set_cube: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, max_tries: int, rules: Array = [], score_refs: Array = [], cluster_orbit_min: int = 1, cluster_orbit_max: int = 2, min_ring: int = -1, max_ring: int = -1, target_ring: float = -1.0, ring_weight: float = 1.0) -> Array:
	var placed := []
	var remaining = target
	while remaining >= 3:
		var seed_refs = score_refs + placed
		var seed_orbit = _pick_rotational_orbit3(bounds_cubes, bounds_set_cube, blocked, rng, max_tries, rules, seed_refs, min_ring, max_ring, target_ring, ring_weight)
		if seed_orbit.is_empty():
			break
		var orbit_limit = min(int(remaining / 3), rng.randi_range(cluster_orbit_min, cluster_orbit_max))
		var cluster = _grow_rotational_cluster3(seed_orbit, bounds_set_cube, blocked, rng, rules, orbit_limit, min_ring, max_ring)
		if cluster.is_empty():
			break
		for cell in cluster:
			placed.append(cell)
		remaining -= cluster.size()
	return placed

static func _quantize_orbit_count(count: int, orbit_size: int = 3) -> int:
	if count <= 0:
		return 0
	return max(orbit_size, int(ceil(float(count) / float(orbit_size))) * orbit_size)

static func _convert_cube_positions(cubes: Array, cube_to_cell: Dictionary) -> Array:
	var cells := []
	for cube in cubes:
		if cube_to_cell.has(cube):
			cells.append(cube_to_cell[cube])
	return cells

static func _convert_cube_dict_positions(input: Dictionary, cube_to_cell: Dictionary) -> Dictionary:
	var output := {}
	for key in input.keys():
		var value = input[key]
		if typeof(value) == TYPE_VECTOR3I:
			output[key] = cube_to_cell.get(value, Vector2i.ZERO)
		elif value is Array:
			output[key] = _convert_cube_positions(value, cube_to_cell)
	return output

static func _generate_hex_3p(md: MapData, rng: RandomNumberGenerator, player_ids: Array, size_tag: String) -> Dictionary:
	var radius = _default_hex_radius(md, size_tag)
	var geom = _build_hex_geometry(radius)
	var bounds_cubes: Array = geom["bounds_cubes"]
	var cube_to_cell: Dictionary = geom["cube_to_cell"]
	var bounds = geom["bounds"]
	var bounds_set = geom["bounds_set"]
	var bounds_set_cube := {}
	for cube in bounds_cubes:
		bounds_set_cube[cube] = true
	var base_cubes = _three_player_hex_bases(player_ids, radius)
	var tower_cubes = _three_player_hex_towers(player_ids, base_cubes, bounds_set_cube, radius)
	var structure_refs = _cube_refs_from_structures(base_cubes, tower_cubes)
	var blocked_neutral := {}
	for cell in structure_refs:
		blocked_neutral[cell] = true

	var area = bounds.size()
	var mine_count = int(md.proc_mine_count)
	var camp_count = int(md.proc_camp_count)
	var dragon_count = int(md.proc_dragon_count)
	if mine_count <= 0:
		mine_count = max(3, int(area / 120))
	if camp_count <= 0:
		camp_count = max(3, int(area / 145))
	if dragon_count <= 0:
		dragon_count = max(1, int(area / 320))
	mine_count = _quantize_orbit_count(mine_count, 3)
	camp_count = _quantize_orbit_count(camp_count, 3)
	dragon_count = _quantize_orbit_count(dragon_count, 3)
	var inner_ring = max(3, int(round(float(radius) * 0.16)))
	var neutral_edge_ring = max(inner_ring + 3, radius - 4)
	var terrain_edge_ring = radius
	var terrain_target_ring = float(radius) * 0.54
	var forest_target_ring = terrain_target_ring
	var mountain_target_ring = terrain_target_ring - 0.5
	var lake_target_ring = terrain_target_ring - 0.25

	var mines_cube = _place_rotational_tiles3(
		mine_count,
		bounds_cubes,
		bounds_set_cube,
		blocked_neutral,
		rng,
		300,
		[{"refs": structure_refs, "min_dist": 4}],
		structure_refs,
		inner_ring,
		neutral_edge_ring
	)
	var camps_basic_cube = _place_rotational_tiles3(
		camp_count,
		bounds_cubes,
		bounds_set_cube,
		blocked_neutral,
		rng,
		300,
		[
			{"refs": structure_refs, "min_dist": 5},
			{"refs": mines_cube, "min_dist": 3}
		],
		mines_cube + structure_refs,
		inner_ring + 1,
		neutral_edge_ring
	)
	var camps_dragon_cube = _place_rotational_tiles3(
		dragon_count,
		bounds_cubes,
		bounds_set_cube,
		blocked_neutral,
		rng,
		300,
		[
			{"refs": structure_refs, "min_dist": 6},
			{"refs": camps_basic_cube, "min_dist": 4}
		],
		camps_basic_cube + structure_refs,
		inner_ring,
		max(inner_ring + 3, radius - 6)
	)

	var forest_ratio = clamp(float(md.proc_forest_ratio), 0.0, 1.0)
	var mountain_ratio = clamp(float(md.proc_mountain_ratio), 0.0, 1.0)
	var lake_ratio = clamp(float(md.proc_lake_ratio), 0.0, 1.0)
	var total_ratio = forest_ratio + mountain_ratio + lake_ratio
	if total_ratio > 0.65:
		var scale = 0.65 / total_ratio
		forest_ratio *= scale
		mountain_ratio *= scale
		lake_ratio *= scale
	var forest_target = _quantize_orbit_count(int(round(float(area) * forest_ratio)), 3)
	var mountain_target = _quantize_orbit_count(int(round(float(area) * mountain_ratio)), 3)
	var lake_target = _quantize_orbit_count(int(round(float(area) * lake_ratio)), 3)
	var terrain_blocked = blocked_neutral.duplicate(true)
	var terrain_cells := {
		TERRAIN_FOREST: _generate_clustered_rotational_tiles3(
			forest_target,
			bounds_cubes,
			bounds_set_cube,
			terrain_blocked,
			rng,
			400,
			[{"refs": structure_refs, "min_dist": 2}],
			mines_cube + camps_basic_cube + camps_dragon_cube,
			1,
			2,
			max(1, inner_ring - 1),
			terrain_edge_ring,
			forest_target_ring,
			0.4
		),
		TERRAIN_MOUNTAIN: _generate_clustered_rotational_tiles3(
			mountain_target,
			bounds_cubes,
			bounds_set_cube,
			terrain_blocked,
			rng,
			400,
			[{"refs": structure_refs, "min_dist": 3}],
			mines_cube + camps_basic_cube + camps_dragon_cube,
			1,
			2,
			inner_ring,
			terrain_edge_ring,
			mountain_target_ring,
			0.45
		),
		TERRAIN_RIVER: [],
		TERRAIN_LAKE: _generate_clustered_rotational_tiles3(
			lake_target,
			bounds_cubes,
			bounds_set_cube,
			terrain_blocked,
			rng,
			400,
			[{"refs": structure_refs, "min_dist": 3}],
			camps_basic_cube + camps_dragon_cube,
			1,
			1,
			inner_ring,
			max(inner_ring + 2, radius - 1),
			lake_target_ring,
			0.35
		)
	}

	var mine_owners := {"unclaimed": _convert_cube_positions(mines_cube, cube_to_cell)}
	for pid in player_ids:
		mine_owners[pid] = []
	return {
		"bounds": bounds,
		"terrain_cells": {
			TERRAIN_FOREST: _convert_cube_positions(terrain_cells[TERRAIN_FOREST], cube_to_cell),
			TERRAIN_MOUNTAIN: _convert_cube_positions(terrain_cells[TERRAIN_MOUNTAIN], cube_to_cell),
			TERRAIN_RIVER: [],
			TERRAIN_LAKE: _convert_cube_positions(terrain_cells[TERRAIN_LAKE], cube_to_cell)
		},
		"base_positions": _convert_cube_dict_positions(base_cubes, cube_to_cell),
		"tower_positions": _convert_cube_dict_positions(tower_cubes, cube_to_cell),
		"mines": mine_owners,
		"camps": {
			"basic": _convert_cube_positions(camps_basic_cube, cube_to_cell),
			"dragon": _convert_cube_positions(camps_dragon_cube, cube_to_cell)
		}
	}

static func generate(md: MapData, rng: RandomNumberGenerator, player_ids: Array = []) -> Dictionary:
	if player_ids.is_empty():
		player_ids = _default_player_ids(2)
	var player_count = max(2, player_ids.size())
	var size_tag = str(md.map_size).strip_edges().to_lower()
	if player_count == 3 and _proc_shape(md) == "hex_3p":
		return _generate_hex_3p(md, rng, player_ids, size_tag)
	var columns = int(md.proc_columns)
	var rows = int(md.proc_rows)
	if columns <= 0 or rows <= 0:
		if size_tag == "small":
			columns = DEFAULT_COLUMNS_SMALL
			rows = DEFAULT_ROWS_SMALL
			if player_count >= 3:
				columns = 32
				rows = 26
		else:
			columns = DEFAULT_COLUMNS_NORMAL
			rows = DEFAULT_ROWS_NORMAL
			if player_count >= 3:
				columns = 48
				rows = 36

	var bounds := []
	var min_x = 0
	var min_y = 0
	var max_x = columns - 1
	var max_y = rows - 1
	var use_template_bounds = md.proc_columns <= 0 and md.proc_rows <= 0 and md.terrain_scene != null and player_count <= 2
	if use_template_bounds:
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
	if use_template_positions:
		for pid in player_ids:
			if not md.base_positions.has(pid) or not md.tower_positions.has(pid):
				use_template_positions = false
				break
	var bases: Dictionary
	var towers: Dictionary
	if use_template_positions:
		bases = md.base_positions.duplicate(true)
		towers = md.tower_positions.duplicate(true)
	else:
		bases = _default_bases(player_ids, min_x, max_x, min_y, max_y, size_tag)
		towers = _default_towers(player_ids, min_x, max_x, min_y, max_y, bases, size_tag)
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

	var structure_buffer = 4
	var mine_spread_min_dist = 3
	var blocked_neutral := {}
	for pid in bases.keys():
		blocked_neutral[bases[pid]] = true
	for pid in towers.keys():
		for cell in towers[pid]:
			blocked_neutral[cell] = true
	var mines_unclaimed := _place_symmetric_tiles(mine_count, bounds, bounds_set, blocked_neutral, rng, min_x, max_x, min_y, max_y, 200, structure_refs, structure_buffer, [], true, false, [], 0)
	var camps_basic := _place_symmetric_tiles(camp_count, bounds, bounds_set, blocked_neutral, rng, min_x, max_x, min_y, max_y, 200, structure_refs, structure_buffer, [], true, false)
	var tower_cells := []
	var base_cells := []
	for pid in bases.keys():
		base_cells.append(bases[pid])
	for pid in towers.keys():
		for cell in towers[pid]:
			tower_cells.append(cell)
	var min_dragon_dist = 7
	var camp_dragon_min_dist = 4
	var dragon_rules = [
		{"refs": base_cells, "min_dist": structure_buffer},
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
	mines_unclaimed = _jitter_positions(mines_unclaimed, bounds, bounds_set, blocked_neutral, rng, neutral_noise, 200, mine_rules_provider, min_x, max_x, min_y, max_y, true, 0)
	var camp_rules_provider = func(current_camps):
		return [
			{"refs": structure_refs, "min_dist": structure_buffer},
			{"refs": current_camps, "min_dist": camp_dragon_min_dist},
			{"refs": camps_dragon, "min_dist": camp_dragon_min_dist}
		]
	camps_basic = _jitter_positions(camps_basic, bounds, bounds_set, blocked_neutral, rng, neutral_noise, 200, camp_rules_provider, min_x, max_x, min_y, max_y, true)
	var dragon_rules_provider = func(_positions):
		return [
			{"refs": base_cells, "min_dist": structure_buffer},
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

	var mine_owners := {"unclaimed": mines_unclaimed}
	for pid in player_ids:
		mine_owners[pid] = []
	return {
		"bounds": bounds,
		"terrain_cells": terrain_cells,
		"base_positions": bases,
		"tower_positions": towers,
		"mines": mine_owners,
		"camps": {
			"basic": camps_basic,
			"dragon": camps_dragon
		}
	}

static func _default_bases(player_ids: Array, min_x: int, max_x: int, min_y: int, max_y: int, size_tag: String) -> Dictionary:
	var player_count = player_ids.size()
	var y = int((min_y + max_y) / 2)
	if player_count <= 2:
		return {
			player_ids[0]: Vector2i(min_x - 1, y),
			player_ids[1]: Vector2i(max_x, y)
		}
	if player_count == 3:
		var center_x = int((min_x + max_x) / 2)
		var side_y = clampi(y + max(2, int((max_y - min_y) / 7)), min_y + 2, max_y - 2)
		if size_tag == "small":
			side_y = clampi(y + 2, min_y + 2, max_y - 2)
		return {
			player_ids[0]: Vector2i(min_x - 1, side_y),
			player_ids[1]: Vector2i(max_x, side_y),
			player_ids[2]: Vector2i(center_x, min_y - 1)
		}
	return {
		player_ids[0]: Vector2i(min_x - 1, y),
		player_ids[1]: Vector2i(max_x, y)
	}

static func _default_towers(player_ids: Array, min_x: int, max_x: int, min_y: int, max_y: int, bases: Dictionary, size_tag: String) -> Dictionary:
	var towers := {}
	for pid in player_ids:
		towers[pid] = []
	var player_count = player_ids.size()
	var offsets = [-5, 0, 5]
	if size_tag == "small":
		offsets = [-3, 0, 3]
	var p1 = bases.get(player_ids[0], Vector2i(min_x - 1, int((min_y + max_y) / 2)))
	var p2 = bases.get(player_ids[1], Vector2i(max_x, int((min_y + max_y) / 2)))
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
		towers[player_ids[0]].append(Vector2i(clamp(left_x, min_x + 1, max_x - 1), y1))
		towers[player_ids[1]].append(Vector2i(clamp(right_x, min_x + 1, max_x - 1), y2))
	if player_count == 3:
		var p3 = bases.get(player_ids[2], Vector2i(int((min_x + max_x) / 2), min_y - 1))
		var top_y = min_y + (2 if size_tag == "small" else 3)
		for off in offsets:
			var x3 = clampi(p3.x + off, min_x + 1, max_x - 1)
			towers[player_ids[2]].append(Vector2i(x3, clampi(top_y, min_y + 1, max_y - 1)))
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

static func _jitter_positions(positions: Array, bounds: Array, bounds_set: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, noise_rate: float, max_tries: int, rules_provider: Callable, min_x: int = 0, max_x: int = 0, min_y: int = 0, max_y: int = 0, enforce_symmetry: bool = false, score_sample: int = 0) -> Array:
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
		var new_primary = Vector2i(-1, -1)
		var new_mirror = Vector2i(-1, -1)
		var valid = true
		if score_sample > 0:
			var pair = _pick_open_tile_pair_scored(bounds, bounds_set, blocked, rng, max_tries, min_x, max_x, min_y, max_y, [], 0, rules, positions, score_sample)
			if pair.is_empty():
				valid = false
			else:
				new_primary = pair[0]
				new_mirror = pair[1]
		else:
			new_primary = _pick_open_cell_with_rules(bounds, bounds_set, blocked, rng, rules, max_tries)
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

static func _place_symmetric_tiles(count: int, bounds: Array, bounds_set: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, min_x: int, max_x: int, min_y: int, max_y: int, max_tries: int, refs: Array = [], min_dist: int = 0, rules: Array = [], avoid_self: bool = false, allow_center: bool = true, score_refs: Array = [], score_sample: int = 0) -> Array:
	var placed := []
	if count <= 0:
		return placed
	var remaining = count
	var center = Vector2i(int((min_x + max_x) / 2), int((min_y + max_y) / 2))
	var dynamic_refs = refs
	var scoring_refs: Array = []
	if score_sample > 0:
		scoring_refs = score_refs.duplicate()
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
		var pair: Array
		if score_sample > 0:
			pair = _pick_open_tile_pair_scored(bounds, bounds_set, blocked, rng, max_tries, min_x, max_x, min_y, max_y, dynamic_refs, min_dist, rules, scoring_refs, score_sample)
		else:
			pair = _pick_open_tile_pair(bounds, bounds_set, blocked, rng, max_tries, min_x, max_x, min_y, max_y, dynamic_refs, min_dist, rules)
		if pair.is_empty():
			break
		for cell in pair:
			placed.append(cell)
			blocked[cell] = true
			if avoid_self and min_dist > 0:
				dynamic_refs.append(cell)
			if score_sample > 0:
				scoring_refs.append(cell)
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

static func _repulsion_score(cell: Vector2i, refs: Array) -> float:
	var score = 0.0
	for ref in refs:
		if typeof(ref) != TYPE_VECTOR2I:
			continue
		var dist = _hex_distance(cell, ref)
		if dist <= 0:
			continue
		score += 1.0 / pow(float(dist), MINE_REPULSION_EXPONENT)
	return score

static func _pair_repulsion_score(cell: Vector2i, mirror: Vector2i, refs: Array) -> float:
	var score = _repulsion_score(cell, refs)
	if mirror != cell:
		score += _repulsion_score(mirror, refs)
	return score

static func _pick_open_tile_pair_scored(bounds: Array, bounds_set: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator, max_tries: int, min_x: int, max_x: int, min_y: int, max_y: int, refs: Array, min_dist: int, rules: Array, score_refs: Array, score_sample: int) -> Array:
	if bounds.is_empty():
		return []
	var candidates := []
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
		var score = _pair_repulsion_score(cell, mirror, score_refs)
		candidates.append({"pair": [cell, mirror], "score": score})
	if candidates.is_empty():
		return []
	var total_weight = 0.0
	for entry in candidates:
		var score = float(entry["score"])
		entry["weight"] = 1.0 / max(score, 0.001)
		total_weight += float(entry["weight"])
	if total_weight <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]["pair"]
	var roll = rng.randf_range(0.0, total_weight)
	var running = 0.0
	for entry in candidates:
		running += float(entry["weight"])
		if roll <= running:
			return entry["pair"]
	return candidates[candidates.size() - 1]["pair"]

static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac = _offset_to_cube(a)
	var bc = _offset_to_cube(b)
	return int(max(abs(ac.x - bc.x), abs(ac.y - bc.y), abs(ac.z - bc.z)))

static func _offset_to_cube(cell: Vector2i) -> Vector3i:
	var x = cell.x - (cell.y - (cell.y & 1)) / 2
	var z = cell.y
	var y = -x - z
	return Vector3i(x, y, z)
