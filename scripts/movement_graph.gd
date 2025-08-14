extends Node
class_name MovementGraph
##
# MovementGraph is a side-effect-free analysis tool for one movement *tick*.
# It builds a directed graph of intended one-step moves (from -> to) and exposes
# helpers to:
#  • list entrants per tile (including singletons),
#  • detect multi-entrants,
#  • detect cycles/rotations (from the move graph),
#  • derive internal-vs-external entrants at cycle nodes,
#  • build dependency edges among *current occupants* that are allowed to enter,
#  • compute SCC cycles for atomic commit (no lambdas; 4.4.1-safe),
#  • detect enemy 2-swaps,
#  • check whether an SCC is an uncontested rotation.
#
# Glossary:
#  • graph[from] = to             # only for units that are moving this tick
#  • unit_lookup[pos] = unit      # all units currently on the board
#
# Notes:
#  • Out-degree ≤ 1 (each mover has at most one next tile).
#  • This file performs no scene mutations; use it in your plan phase.

var graph: Dictionary = {}          # Vector2i -> Vector2i
var unit_lookup: Dictionary = {}    # Vector2i -> Unit (Node)

## Build from a flat Array of unit Nodes that expose:
##   grid_pos: Vector2i, is_moving: bool, moving_to: Vector2i (for this tick)
func build(units: Array) -> void:
	graph.clear()
	unit_lookup.clear()
	for u in units:
		if u == null:
			continue
		var from: Vector2i = u.grid_pos
		unit_lookup[from] = u
		if u.is_moving and (u.moving_to is Vector2i):
			graph[from] = u.moving_to

## Return every destination -> [sources] (singletons included).
func entries_all() -> Dictionary:
	var e := {}
	for from in graph.keys():
		var to = graph[from]
		e[to] = e.get(to, [])
		e[to].append(from)
	return e

## Return only tiles that have 2+ entrants (subset of entries_all).
func detect_multi_entries() -> Dictionary:
	var all := entries_all()
	var out := {}
	for t in all.keys():
		if all[t].size() > 1:
			out[t] = all[t]
	return out

## DFS-based cycle detection over the raw from->to graph (out-degree ≤ 1).
## Returns Array[Array[Vector2i]] where each inner array lists the cycle nodes in order.
func detect_cycles() -> Array:
	var cycles: Array = []
	var visited := {}
	var stack := {}

	for start in graph.keys():
		if visited.get(start, false):
			continue
		_dfs_cycle(start, visited, stack, [], cycles)
	return cycles

func _dfs_cycle(node: Vector2i, visited: Dictionary, stack: Dictionary, path: Array, cycles: Array) -> void:
	if visited.get(node, false):
		return
	visited[node] = true
	stack[node] = true
	path.append(node)

	var nxt: Variant = graph.get(node, null)
	if nxt != null:
		if not visited.get(nxt, false):
			_dfs_cycle(nxt, visited, stack, path, cycles)
		elif stack.get(nxt, false):
			# Found a back-edge to 'nxt': extract cycle from first occurrence of nxt.
			var idx: int = path.find(nxt)
			if idx != -1:
				var cyc := []
				for i in range(idx, path.size()):
					cyc.append(path[i])
				cycles.append(cyc)

	stack.erase(node)
	path.pop_back()

## Map each tile in all detected cycles to its internal predecessor (previous node in that cycle).
## If multiple cycles exist, later ones overwrite earlier keys; that's fine given out-degree ≤ 1.
func cycle_prev_map() -> Dictionary:
	var prev := {}
	var cycles := detect_cycles()
	for cyc in cycles:
		for i in cyc.size():
			var t: Vector2i = cyc[i]
			var p: Vector2i = cyc[(i - 1 + cyc.size()) % cyc.size()]
			prev[t] = p
	return prev

## For each tile, partition entrants into {internal, externals}.
##  internal := predecessor in a rotation (if tile is part of a cycle), else null
##  externals := everyone else that targets this tile this tick
func partition_entrants(entrants: Dictionary, cycle_prev: Dictionary) -> Dictionary:
	var out := {}
	for t in entrants.keys():
		var internal = null
		var externals := []
		var maybe_prev = cycle_prev.get(t, null)
		for src in entrants[t]:
			if maybe_prev != null and src == maybe_prev:
				internal = src
			else:
				externals.append(src)
		out[t] = {"internal": internal, "externals": externals}
	return out

## Build dependency edges among *current occupants that are also winners to their destinations*.
## winners_by_tile : Dictionary where key=DEST tile, value=FROM tile (winner source).
## Returns edges: Dictionary[SRC_TILE -> DEST_TILE]
func dependency_edges_from_winners(winners_by_tile: Dictionary) -> Dictionary:
	var edges := {}
	for s in unit_lookup.keys():
		var occ = unit_lookup[s]
		if occ == null:
			continue
		if not graph.has(s):
			continue # occupant not moving this tick
		var d: Vector2i = graph[s]
		if winners_by_tile.get(d, null) == s:
			edges[s] = d
	return edges

## Strongly connected components for edges (tile -> tile) with out-degree ≤ 1.
## This implementation returns **only cycles** (SCCs with size ≥ 2). Singletons without self-loops
## are not included, which is fine because chains are handled via a root-to-sink pass in TurnManager.
func strongly_connected_components(edges: Dictionary) -> Array:
	var sccs: Array = []
	var visited := {}

	for start in edges.keys():
		if visited.get(start, false):
			continue

		var path: Array = []
		var on_path := {}       # node -> index in path
		var cur: Variant = start
		while cur != null and not visited.get(cur, false):
			on_path[cur] = path.size()
			path.append(cur)
			var nxt: Variant = edges.get(cur, null)
			if nxt == null:
				break
			if on_path.has(nxt):
				# Found a cycle; slice path from first occurrence of nxt
				var idx: int = int(on_path[nxt])
				var cyc := []
				for i in range(idx, path.size()):
					cyc.append(path[i])
				if cyc.size() >= 2:
					sccs.append(cyc)
				break
			cur = nxt

		# mark whole path visited
		for n in path:
			visited[n] = true

	return sccs

## Pure detection of ENEMY 2-swaps (A->B and B->A, different owners). No side effects.
## Returns Array of Dictionaries: [{"a": Vector2i, "b": Vector2i}]
func detect_enemy_swaps() -> Array:
	var pairs := []
	var seen := {}
	for a in graph.keys():
		var b = graph[a]
		if not (unit_lookup.has(a) and unit_lookup.has(b)):
			continue
		var ua = unit_lookup[a]
		var ub = unit_lookup[b]
		if ua == null or ub == null:
			continue
		if ua.player_id == ub.player_id:
			continue
		if graph.get(b, Vector2i(-999, -999)) == a:
			var k1 := str(a) + "|" + str(b)
			var k2 := str(b) + "|" + str(a)
			if not (seen.has(k1) or seen.has(k2)):
				pairs.append({"a": a, "b": b})
				seen[k1] = true
	return pairs

## Helper to check if an SCC is an uncontested rotation:
##  • every node has exactly one entrant and it's the internal predecessor, and
##  • there is NO stationary defender inside the SCC.
func scc_is_uncontested_rotation(scc: Array, winners_by_tile: Dictionary) -> bool:
	if scc.size() < 2:
		return false

	var entrants := entries_all()
	var prev := cycle_prev_map()

	for node in scc:
		if not entrants.has(node):
			return false
		# must be exactly one entrant
		if entrants[node].size() != 1:
			return false

		var internal = prev.get(node, null)
		if internal == null:
			return false

		# no stationary defender on any node in the cycle
		var occ = unit_lookup.get(node, null)
		if occ != null and not graph.has(node):
			return false

		# the chosen winner must be the internal predecessor
		if winners_by_tile.get(node, null) != internal:
			return false

	return true

# A cycle is "contested" if any node in the SCC has an external entrant
# in addition to (or instead of) its internal predecessor.
func scc_is_contested_cycle(scc: Array, entrants_all: Dictionary) -> bool:
	if scc.size() < 2:
		return false
	var in_scc := {}
	for n in scc:
		in_scc[n] = true
	var prev := cycle_prev_map()
	for node in scc:
		var arr: Array = entrants_all.get(node, [])
		if arr.size() == 0:
			continue
		var internal = prev.get(node, null)
		var has_external := false
		var only_internal := true
		for src in arr:
			if src != internal:
				only_internal = false
				if not in_scc.has(src):
					has_external = true
		# contested if we have any external entrant OR we have >1 entrant
		# (the >1 case implies internal+external)
		if has_external or (arr.size() > 1 and internal != null):
			return true
	return false

# scripts/movement_graph.gd

## Return the list of "contested entry" tiles in this SCC.
## An entry tile is a node in the SCC that:
##  • has exactly one internal predecessor in the SCC (so it's a normal cycle node),
##  • has at least one entrant from outside the SCC.
func scc_contested_entry_nodes(scc: Array, entrants_all: Dictionary) -> Array:
	if scc.size() < 2:
		return []
	# Record nodes in the SCC
	var in_scc := {}
	for n in scc:
		in_scc[n] = true
	# Build internal predecessor map: dest -> source inside SCC
	var internal_pred := {}
	for src in scc:
		var dest = graph.get(src, null)
		if dest != null and in_scc.has(dest):
			internal_pred[dest] = src
	# Identify contested entry tiles
	var entries := []
	for node in scc:
		if not internal_pred.has(node):
			continue  # node isn’t a cycle step (or internal pred missing)
		# External entrants?
		var arr = entrants_all.get(node, [])
		var has_external := false
		for src in arr:
			if not in_scc.has(src):
				has_external = true
				break
		if has_external:
			entries.append(node)
	return entries
