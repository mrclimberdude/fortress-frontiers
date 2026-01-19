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
	for y in range(rows):
		for x in range(columns):
			bounds.append(Vector2i(x, y))

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

	var terrain_cells := {
		TERRAIN_FOREST: [],
		TERRAIN_MOUNTAIN: [],
		TERRAIN_RIVER: [],
		TERRAIN_LAKE: []
	}
	for cell in bounds:
		var roll = rng.randf()
		if roll < forest_ratio:
			terrain_cells[TERRAIN_FOREST].append(cell)
		elif roll < forest_ratio + mountain_ratio:
			terrain_cells[TERRAIN_MOUNTAIN].append(cell)
		elif roll < forest_ratio + mountain_ratio + river_ratio:
			terrain_cells[TERRAIN_RIVER].append(cell)
		elif roll < forest_ratio + mountain_ratio + river_ratio + lake_ratio:
			terrain_cells[TERRAIN_LAKE].append(cell)

	var bases = _default_bases(columns, rows)
	var towers = _default_towers(columns, rows, bases)

	var reserved := {}
	for pid in bases.keys():
		reserved[bases[pid]] = true
	for pid in towers.keys():
		for cell in towers[pid]:
			reserved[cell] = true

	_remove_cells(terrain_cells, reserved)
	var blocked = _build_blocked_set(terrain_cells, bases, towers)

	var mine_count = int(md.proc_mine_count)
	var camp_count = int(md.proc_camp_count)
	var dragon_count = int(md.proc_dragon_count)
	var area = columns * rows
	if mine_count <= 0:
		mine_count = max(2, int(area / 120))
	if camp_count <= 0:
		camp_count = max(2, int(area / 140))
	if dragon_count <= 0:
		dragon_count = max(1, int(area / 320))

	var mines_unclaimed := []
	for _i in range(mine_count):
		var tile = _pick_open_tile(bounds, blocked, rng, 200)
		if tile != Vector2i(-1, -1):
			mines_unclaimed.append(tile)
			blocked[tile] = true

	var camps_basic := []
	for _i in range(camp_count):
		var tile = _pick_open_tile(bounds, blocked, rng, 200)
		if tile != Vector2i(-1, -1):
			camps_basic.append(tile)
			blocked[tile] = true

	var camps_dragon := []
	for _i in range(dragon_count):
		var tile = _pick_open_tile(bounds, blocked, rng, 200)
		if tile != Vector2i(-1, -1):
			camps_dragon.append(tile)
			blocked[tile] = true

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

static func _default_bases(columns: int, rows: int) -> Dictionary:
	var y = int(rows / 2)
	return {
		"player1": Vector2i(1, y),
		"player2": Vector2i(columns - 2, y)
	}

static func _default_towers(columns: int, rows: int, bases: Dictionary) -> Dictionary:
	var towers := {"player1": [], "player2": []}
	var offsets = [-4, 0, 4]
	var p1 = bases.get("player1", Vector2i(1, int(rows / 2)))
	var p2 = bases.get("player2", Vector2i(columns - 2, int(rows / 2)))
	for off in offsets:
		var y1 = clamp(p1.y + off, 1, rows - 2)
		var y2 = clamp(p2.y + off, 1, rows - 2)
		towers["player1"].append(Vector2i(clamp(p1.x + 2, 1, columns - 2), y1))
		towers["player2"].append(Vector2i(clamp(p2.x - 2, 1, columns - 2), y2))
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

static func _pick_open_tile(bounds: Array, blocked: Dictionary, rng: RandomNumberGenerator, max_tries: int) -> Vector2i:
	if bounds.is_empty():
		return Vector2i(-1, -1)
	for _i in range(max_tries):
		var idx = rng.randi_range(0, bounds.size() - 1)
		var cell = bounds[idx]
		if not blocked.has(cell):
			return cell
	return Vector2i(-1, -1)
