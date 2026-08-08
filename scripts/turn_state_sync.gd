class_name TurnStateSync
extends RefCounted

var tm


func _init(turn_manager) -> void:
	tm = turn_manager


func serialize_unit(unit) -> Dictionary:
	return {
		"net_id": unit.net_id,
		"player_id": unit.player_id,
		"unit_type": unit.unit_type,
		"grid_pos": unit.grid_pos,
		"curr_health": unit.curr_health,
		"max_health": unit.max_health,
		"is_defending": unit.is_defending,
		"is_healing": unit.is_healing,
		"auto_heal": unit.auto_heal,
		"auto_defend": unit.auto_defend,
		"auto_lookout": unit.auto_lookout,
		"auto_build": unit.auto_build,
		"auto_build_type": unit.auto_build_type,
		"build_queue": unit.build_queue,
		"build_queue_type": unit.build_queue_type,
		"build_queue_last_type": unit.build_queue_last_type,
		"build_queue_last_target": unit.build_queue_last_target,
		"build_queue_last_build_left": unit.build_queue_last_build_left,
		"move_queue": unit.move_queue,
		"move_queue_last_target": unit.move_queue_last_target,
		"is_moving": unit.is_moving,
		"is_looking_out": unit.is_looking_out,
		"moving_to": unit.moving_to,
		"just_purchased": unit.just_purchased,
		"first_turn_move": unit.first_turn_move,
		"ordered": unit.ordered,
		"last_damaged_by": unit.last_damaged_by,
		"spell_buff_melee": unit.spell_buff_melee,
		"spell_buff_ranged": unit.spell_buff_ranged,
		"spell_buff_turns": unit.spell_buff_turns
	}


func collect_state() -> Dictionary:
	var units := []
	for unit in tm.get_node("GameBoardNode").get_all_units_flat():
		if unit == null:
			continue
		units.append(serialize_unit(unit))
	return {
		"state_seq": tm.state_seq,
		"map_index": tm.current_map_index,
		"match_seed": NetworkManager.match_seed,
		"active_players": tm.active_players,
		"living_players": tm.living_players,
		"pending_eliminations": tm.pending_eliminations,
		"turn_number": tm.turn_number,
		"current_phase": int(tm.current_phase),
		"current_player": tm.current_player,
		"player_gold": tm.player_gold,
		"player_income": tm.player_income,
		"player_mana": tm.player_mana,
		"player_mana_income": tm.player_mana_income,
		"player_mana_cap": tm.player_mana_cap,
		"player_melee_bonus": tm.player_melee_bonus,
		"player_ranged_bonus": tm.player_ranged_bonus,
		"player_mana_bonus": tm.player_mana_bonus,
		"player_mana_cap_bonus": tm.player_mana_cap_bonus,
		"camp_respawns": tm.camp_respawns,
		"dragon_respawns": tm.dragon_respawns,
		"camp_respawn_counts": tm.camp_respawn_counts,
		"dragon_rewards": tm.dragon_rewards,
		"dragon_spawn_counts": tm.dragon_spawn_counts,
		"camps": tm.camps,
		"mines": tm.mines,
		"structure_positions": tm.structure_positions,
		"buildable_structures": tm.buildable_structures,
		"mana_pool_mines": tm.mana_pool_mines,
		"ward_vision_active": tm.ward_vision_active,
		"player_global_vision_until": tm.player_global_vision_until,
		"targeted_vision_active": tm.targeted_vision_active,
		"next_ward_id": tm._next_ward_id,
		"structure_memory": tm.structure_memory,
		"neutral_tile_memory": tm.neutral_tile_memory,
		"spawn_tower_positions": tm.spawn_tower_positions,
		"income_tower_positions": tm.income_tower_positions,
		"base_positions": tm.base_positions,
		"tower_positions": tm.tower_positions,
		"neutral_step_index": tm.neutral_step_index,
		"committed_orders": tm.committed_orders,
		"units": units,
		"damage_log": tm.damage_log,
		"damage_log_entries": tm.damage_log_entries
	}


func collect_state_for(viewer_id: String) -> Dictionary:
	var state = collect_state()
	if viewer_id == "":
		return state
	var fog = tm.get_node("GameBoardNode").get_node_or_null("FogOfWar")
	var viewer_vis: Dictionary = {}
	if fog != null and fog.visiblity.has(viewer_id) and fog.visiblity[viewer_id] is Dictionary:
		viewer_vis = fog.visiblity[viewer_id].duplicate(true)
	var filtered := []
	for data in state.get("units", []):
		var owner = str(data.get("player_id", ""))
		var just_purchased = bool(data.get("just_purchased", false))
		var pos = tm._state_tile_from_value(data.get("grid_pos", Vector2i(-9999, -9999)))
		var visible_to_viewer = owner == viewer_id or tm._viewer_can_see_snapshot_tile(viewer_id, viewer_vis, pos)
		if just_purchased and owner != viewer_id:
			continue
		if not visible_to_viewer:
			continue
		filtered.append(data)
	state["units"] = filtered
	state["base_positions"] = tm._filter_player_pos_dict_for_viewer(state.get("base_positions", {}), viewer_id, viewer_vis)
	state["tower_positions"] = tm._filter_player_tile_dict_for_viewer(state.get("tower_positions", {}), viewer_id, viewer_vis)
	state["spawn_tower_positions"] = tm._filter_player_tile_dict_for_viewer(state.get("spawn_tower_positions", {}), viewer_id, viewer_vis)
	state["income_tower_positions"] = tm._filter_player_tile_dict_for_viewer(state.get("income_tower_positions", {}), viewer_id, viewer_vis)
	state["mines"] = tm._filter_mines_for_viewer(state.get("mines", {}), viewer_id, viewer_vis)
	state["camps"] = tm._filter_camps_for_viewer(state.get("camps", {}), viewer_id, viewer_vis)
	state["buildable_structures"] = tm._filter_buildable_structures_for_viewer(viewer_id, viewer_vis)
	state["structure_positions"] = tm._filtered_structure_positions_for_viewer(state)
	state["player_gold"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_gold", {}), viewer_id, 0)
	state["player_income"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_income", {}), viewer_id, 0)
	state["player_mana"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_mana", {}), viewer_id, 0)
	state["player_mana_income"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_mana_income", {}), viewer_id, 0)
	state["player_mana_cap"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_mana_cap", {}), viewer_id, tm.BASE_MANA_CAP)
	state["player_melee_bonus"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_melee_bonus", {}), viewer_id, 0)
	state["player_ranged_bonus"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_ranged_bonus", {}), viewer_id, 0)
	state["player_mana_bonus"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_mana_bonus", {}), viewer_id, 0)
	state["player_mana_cap_bonus"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_mana_cap_bonus", {}), viewer_id, 0)
	state["player_global_vision_until"] = tm._filter_player_scalar_dict_for_viewer(state.get("player_global_vision_until", {}), viewer_id, 0)
	state["ward_vision_active"] = tm._filter_player_dict_entry_for_viewer(state.get("ward_vision_active", {}), viewer_id, {})
	state["targeted_vision_active"] = tm._filter_player_dict_entry_for_viewer(state.get("targeted_vision_active", {}), viewer_id, {})
	state["structure_memory"] = tm._filter_player_dict_entry_for_viewer(state.get("structure_memory", {}), viewer_id, {})
	state["neutral_tile_memory"] = tm._filter_player_dict_entry_for_viewer(state.get("neutral_tile_memory", {}), viewer_id, {})
	state["mana_pool_mines"] = tm._filter_vec2i_key_dict_for_viewer(state.get("mana_pool_mines", {}), viewer_id, viewer_vis, false)
	state["camp_respawns"] = tm._filter_vec2i_key_dict_for_viewer(state.get("camp_respawns", {}), viewer_id, viewer_vis, false)
	state["dragon_respawns"] = tm._filter_vec2i_key_dict_for_viewer(state.get("dragon_respawns", {}), viewer_id, viewer_vis, false)
	state["camp_respawn_counts"] = tm._filter_vec2i_key_dict_for_viewer(state.get("camp_respawn_counts", {}), viewer_id, viewer_vis, false)
	state["dragon_rewards"] = tm._filter_vec2i_key_dict_for_viewer(state.get("dragon_rewards", {}), viewer_id, viewer_vis, false)
	state["dragon_spawn_counts"] = tm._filter_vec2i_key_dict_for_viewer(state.get("dragon_spawn_counts", {}), viewer_id, viewer_vis, false)
	var viewer_orders := {}
	viewer_orders[viewer_id] = tm.player_orders.get(viewer_id, {}).duplicate(true)
	state["player_orders"] = viewer_orders
	state["committed_orders"] = tm._filter_player_dict_entry_for_viewer(tm.committed_orders, viewer_id, {})
	if not viewer_vis.is_empty():
		state["fog_visibility"] = {viewer_id: viewer_vis}
	state["damage_log"] = {viewer_id: tm.damage_log.get(viewer_id, []).duplicate(true)}
	state["damage_log_entries"] = {viewer_id: tm.damage_log_entries.get(viewer_id, []).duplicate(true)}
	return state


func collect_procedural_map_state() -> Dictionary:
	if tm.current_map_index < 0 or tm.current_map_index >= tm.map_data.size():
		return {}
	var md = tm.map_data[tm.current_map_index] as MapData
	if md == null or not md.procedural:
		return {}
	var map_state := {}
	var hex = tm.get_node("GameBoardNode/HexTileMap")
	if hex != null:
		map_state["bounds"] = hex.get_used_cells()
	if tm.terrain_overlay != null:
		var terrain := {
			"forest": [],
			"mountain": [],
			"river": [],
			"lake": []
		}
		var forest_src = 1
		var mountain_src = 2
		var river_src = 3
		var lake_src = 4
		for cell in tm.terrain_overlay.get_used_cells():
			var src_id = tm.terrain_overlay.get_cell_source_id(cell)
			match src_id:
				forest_src:
					terrain["forest"].append(cell)
				mountain_src:
					terrain["mountain"].append(cell)
				river_src:
					terrain["river"].append(cell)
				lake_src:
					terrain["lake"].append(cell)
		map_state["terrain"] = terrain
	return map_state


func apply_procedural_map_state(map_state: Dictionary, reset_fog: bool = false) -> void:
	if map_state.is_empty():
		return
	var hex = tm.get_node("GameBoardNode/HexTileMap")
	if hex != null and map_state.has("bounds"):
		var bounds = map_state["bounds"]
		if bounds is Array and hex.has_method("apply_bounds"):
			hex.apply_bounds(bounds)
			if reset_fog:
				var fog = tm.get_node("GameBoardNode").get_node_or_null("FogOfWar")
				if fog != null and fog.has_method("reset_fog"):
					fog.reset_fog()
	if tm.terrain_overlay != null and map_state.has("terrain"):
		var terrain = map_state["terrain"]
		if terrain is Dictionary:
			tm.terrain_overlay.clear()
			var forest_src = 1
			var mountain_src = 2
			var river_src = 3
			var lake_src = 4
			for cell in terrain.get("forest", []):
				tm.terrain_overlay.set_cell(cell, forest_src, Vector2i(0, 0))
			for cell in terrain.get("mountain", []):
				tm.terrain_overlay.set_cell(cell, mountain_src, Vector2i(0, 0))
			for cell in terrain.get("river", []):
				tm.terrain_overlay.set_cell(cell, river_src, Vector2i(0, 0))
			for cell in terrain.get("lake", []):
				tm.terrain_overlay.set_cell(cell, lake_src, Vector2i(0, 0))
			tm.terrain_overlay.update_internals()


func apply_state(state: Dictionary, force_host: bool = false) -> void:
	if tm._is_host() and not force_host:
		return
	if state.is_empty():
		return
	state = tm._normalize_state_snapshot(state)
	var incoming_seq = int(state.get("state_seq", -1))
	var force_apply = bool(state.get("force_apply", false))
	if incoming_seq >= 0:
		if not force_apply and incoming_seq <= tm.last_state_seq_applied:
			return
		tm.last_state_seq_applied = incoming_seq
		tm.state_seq = max(tm.state_seq, incoming_seq)
	var map_index = int(state.get("map_index", tm.current_map_index))
	var match_seed = int(state.get("match_seed", NetworkManager.match_seed))
	if match_seed > 0:
		NetworkManager.match_seed = match_seed
	tm.configure_match_players(state.get("active_players", tm.active_players), false)
	var map_state = {}
	if state.has("procedural_map") and state["procedural_map"] is Dictionary:
		map_state = state["procedural_map"]
	if map_index != tm.current_map_index:
		tm._reset_map_state()
		var should_apply_generated = not (not tm._is_host() and not map_state.is_empty())
		tm._load_map_by_index(map_index, should_apply_generated)
	if not map_state.is_empty():
		apply_procedural_map_state(map_state, true)
	if state.has("base_positions"):
		tm.base_positions = state["base_positions"]
	if state.has("tower_positions"):
		tm.tower_positions = state["tower_positions"]
	if state.has("living_players") and state["living_players"] is Array:
		var restored_living = tm._normalize_player_ids(state["living_players"])
		tm.living_players = []
		for player_id in restored_living:
			if player_id in tm.active_players and not tm.living_players.has(player_id):
				tm.living_players.append(player_id)
		if tm.living_players.is_empty():
			tm.living_players = tm.active_players.duplicate()
	tm.pending_eliminations = tm._normalize_player_ids(state.get("pending_eliminations", []))
	if state.has("structure_positions"):
		tm.structure_positions = state["structure_positions"]
	if state.has("buildable_structures"):
		tm.buildable_structures = state["buildable_structures"]
	if state.has("mana_pool_mines"):
		tm.mana_pool_mines = state["mana_pool_mines"]
	else:
		tm._rebuild_mana_pool_assignments()
	if state.has("ward_vision_active"):
		tm.ward_vision_active = state["ward_vision_active"]
	else:
		tm.ward_vision_active = tm._build_player_dict(tm.active_players, {})
	if state.has("player_global_vision_until"):
		tm.player_global_vision_until = state["player_global_vision_until"]
	else:
		tm.player_global_vision_until = tm._build_player_dict(tm.active_players, 0)
	if state.has("targeted_vision_active"):
		tm.targeted_vision_active = state["targeted_vision_active"]
	else:
		tm.targeted_vision_active = tm._build_player_dict(tm.active_players, {})
	tm._next_ward_id = int(state.get("next_ward_id", tm._next_ward_id))
	tm._rebuild_ward_ids()
	if state.has("structure_memory"):
		tm.structure_memory = state["structure_memory"]
	if state.has("neutral_tile_memory"):
		tm.neutral_tile_memory = state["neutral_tile_memory"]
	if state.has("spawn_tower_positions"):
		tm.spawn_tower_positions = state["spawn_tower_positions"]
	if state.has("income_tower_positions"):
		tm.income_tower_positions = state["income_tower_positions"]
	if state.has("camps"):
		tm.camps = state["camps"]
	if state.has("mines"):
		tm.mines = state["mines"]
	tm.turn_number = int(state.get("turn_number", tm.turn_number))
	tm.current_phase = int(state.get("current_phase", int(tm.current_phase)))
	tm.current_player = state.get("current_player", tm.current_player)
	tm.player_gold = state.get("player_gold", tm.player_gold)
	tm.player_income = state.get("player_income", tm.player_income)
	tm.player_mana = state.get("player_mana", tm.player_mana)
	tm.player_mana_income = state.get("player_mana_income", tm.player_mana_income)
	tm.player_mana_cap = state.get("player_mana_cap", tm.player_mana_cap)
	tm.player_mana_bonus = state.get("player_mana_bonus", tm.player_mana_bonus)
	tm.player_mana_cap_bonus = state.get("player_mana_cap_bonus", tm.player_mana_cap_bonus)
	tm.player_melee_bonus = state.get("player_melee_bonus", tm.player_melee_bonus)
	tm.player_ranged_bonus = state.get("player_ranged_bonus", tm.player_ranged_bonus)
	tm.camp_respawns = state.get("camp_respawns", tm.camp_respawns)
	tm.dragon_respawns = state.get("dragon_respawns", tm.dragon_respawns)
	tm.camp_respawn_counts = state.get("camp_respawn_counts", tm.camp_respawn_counts)
	tm.dragon_rewards = state.get("dragon_rewards", tm.dragon_rewards)
	tm.dragon_spawn_counts = state.get("dragon_spawn_counts", tm.dragon_spawn_counts)
	tm.damage_log = state.get("damage_log", tm._build_player_dict(tm.active_players, []))
	tm.damage_log_entries = state.get("damage_log_entries", tm._build_player_dict(tm.active_players, []))
	tm.neutral_step_index = int(state.get("neutral_step_index", tm.neutral_step_index))
	_reconcile_units(state.get("units", []))
	tm.player_orders = tm._build_player_dict(tm.active_players, {})
	if state.has("player_orders"):
		var incoming_orders = state["player_orders"]
		if incoming_orders is Dictionary:
			for pid in incoming_orders.keys():
				tm.player_orders[pid] = incoming_orders[pid]
	NetworkManager.player_orders = tm.player_orders
	tm.committed_orders = state.get("committed_orders", tm._build_player_dict(tm.active_players, {}))
	tm._recalculate_mana_caps()
	tm._prune_dead_units_after_apply()
	if state.has("fog_visibility"):
		var fog = tm.get_node("GameBoardNode").get_node_or_null("FogOfWar")
		var fog_data = state["fog_visibility"]
		if fog != null and fog_data is Dictionary:
			if fog.visiblity == null or fog.visiblity.is_empty():
				fog.reset_fog()
			for pid in fog_data.keys():
				if fog_data[pid] is Dictionary:
					var decoded := {}
					for cell_key in fog_data[pid].keys():
						var cell = tm._decode_log_vec2i(cell_key)
						if cell == Vector2i(-9999, -9999):
							continue
						decoded[cell] = fog_data[pid][cell_key]
					fog.visiblity[pid] = decoded
	tm.get_node("GameBoardNode/FogOfWar")._update_fog()
	tm.update_neutral_markers()
	tm.refresh_structure_markers()
	tm.refresh_mine_tiles()
	tm.emit_signal("damage_log_refresh_requested")
	tm.emit_signal("state_applied")
	if not tm.replay_mode and not tm._is_host() and tm.current_phase == tm.Phase.UPKEEP and tm.turn_number != tm.last_state_hash_turn:
		tm._ensure_dev_log_open()
		tm._devlog({
			"type": "state_hash",
			"phase_name": "UPKEEP",
			"value": tm._state_hash()
		})
		tm.last_state_hash_turn = tm.turn_number
	if not tm.replay_mode and not tm._is_host() and tm.current_phase == tm.Phase.UPKEEP and tm.turn_number != tm.last_snapshot_turn:
		tm._ensure_dev_log_open()
		tm._devlog_snapshot("upkeep_start_sync")
	if not tm.replay_mode and not tm._is_host() and tm.current_phase == tm.Phase.UPKEEP and tm.turn_number != tm.last_stats_turn:
		tm._record_turn_stats()
	if not tm._is_host() and NetworkManager != null and NetworkManager.has_method("notify_local_state_applied"):
		NetworkManager.notify_local_state_applied()


func _reconcile_units(units_data: Array) -> void:
	var unit_mgr = tm.unit_manager
	var board = tm.get_node("GameBoardNode")
	var incoming_by_id := {}
	var incoming_ids := {}
	for raw in units_data:
		if not (raw is Dictionary):
			continue
		var data = raw as Dictionary
		var unit_id = int(data.get("net_id", -1))
		if unit_id <= 0:
			continue
		incoming_by_id[unit_id] = data
		incoming_ids[unit_id] = true
	var existing_ids = unit_mgr.unit_by_net_id.keys().duplicate()
	for unit_id in existing_ids:
		if incoming_ids.has(unit_id):
			continue
		var stale = unit_mgr.unit_by_net_id.get(unit_id, null)
		if stale != null:
			_remove_unit_for_sync(stale)
	for unit_id in incoming_by_id.keys():
		var data = incoming_by_id[unit_id]
		var unit = unit_mgr.get_unit_by_net_id(unit_id)
		if unit != null:
			var owner = str(data.get("player_id", ""))
			var unit_type = str(data.get("unit_type", ""))
			if str(unit.player_id) != owner or str(unit.unit_type) != unit_type:
				_remove_unit_for_sync(unit)
				unit = null
		if unit == null:
			var spawn_pos = _decode_tile(data.get("grid_pos", Vector2i.ZERO))
			unit = unit_mgr.spawn_unit(
				str(data.get("unit_type", "")),
				spawn_pos,
				str(data.get("player_id", "")),
				false,
				unit_id
			)
		if unit == null:
			continue
		_apply_unit_snapshot(unit, data)
	_rebuild_unit_indexes(board, unit_mgr)


func _decode_tile(raw_tile) -> Vector2i:
	if typeof(raw_tile) == TYPE_VECTOR2I:
		return raw_tile
	return tm._decode_log_vec2i(raw_tile)


func _apply_unit_snapshot(unit, data: Dictionary) -> void:
	unit.structure_tiles = tm.structure_positions
	unit.map_layer = tm.get_node("GameBoardNode/HexTileMap")
	unit.player_id = str(data.get("player_id", unit.player_id))
	unit.unit_type = str(data.get("unit_type", unit.unit_type))
	var target_pos = _decode_tile(data.get("grid_pos", unit.grid_pos))
	if unit.grid_pos != target_pos or unit.position == Vector2.ZERO:
		_set_unit_position_for_sync(unit, target_pos)
	unit.curr_health = int(data.get("curr_health", unit.curr_health))
	unit.max_health = int(data.get("max_health", unit.max_health))
	unit.is_defending = bool(data.get("is_defending", false))
	unit.is_healing = bool(data.get("is_healing", false))
	unit.auto_heal = bool(data.get("auto_heal", false))
	unit.auto_defend = bool(data.get("auto_defend", false))
	unit.auto_lookout = bool(data.get("auto_lookout", false))
	unit.auto_build = bool(data.get("auto_build", false))
	unit.auto_build_type = str(data.get("auto_build_type", ""))
	var queue_data = data.get("build_queue", [])
	unit.build_queue = tm._decode_log_vec2i_array(queue_data) if queue_data is Array else []
	unit.build_queue_type = str(data.get("build_queue_type", ""))
	unit.build_queue_last_type = str(data.get("build_queue_last_type", ""))
	unit.build_queue_last_target = tm._decode_log_vec2i(data.get("build_queue_last_target", Vector2i(-9999, -9999)))
	unit.build_queue_last_build_left = int(data.get("build_queue_last_build_left", -1))
	var move_queue_data = data.get("move_queue", [])
	unit.move_queue = tm._decode_log_vec2i_array(move_queue_data) if move_queue_data is Array else []
	unit.move_queue_last_target = tm._decode_log_vec2i(data.get("move_queue_last_target", Vector2i(-9999, -9999)))
	unit.is_moving = bool(data.get("is_moving", false))
	unit.is_looking_out = bool(data.get("is_looking_out", false))
	unit.moving_to = tm._decode_log_vec2i(data.get("moving_to", unit.grid_pos))
	unit.just_purchased = bool(data.get("just_purchased", false))
	unit.first_turn_move = bool(data.get("first_turn_move", false))
	unit.ordered = bool(data.get("ordered", false))
	unit.last_damaged_by = data.get("last_damaged_by", "")
	unit.spell_buff_melee = float(data.get("spell_buff_melee", 0.0))
	unit.spell_buff_ranged = float(data.get("spell_buff_ranged", 0.0))
	unit.spell_buff_turns = int(data.get("spell_buff_turns", 0))
	unit.set_health_bar()
	if unit.is_tower:
		unit.is_spawn_tower = false
		if tm.spawn_tower_positions.has(unit.player_id) and unit.grid_pos in tm.spawn_tower_positions[unit.player_id]:
			unit.is_spawn_tower = true
		if unit.has_method("_update_owner_overlay"):
			unit._update_owner_overlay()
	if str(unit.unit_type) == tm.DRAGON_TYPE:
		var reward = tm.dragon_rewards.get(unit.grid_pos, "")
		if reward == "" and tm.dragon_spawn_counts.has(unit.grid_pos):
			var count = int(tm.dragon_spawn_counts.get(unit.grid_pos, 1)) - 1
			reward = tm._dragon_reward_for_pos(unit.grid_pos, max(count, 0))
		tm._apply_dragon_reward_color(unit, reward)


func _set_unit_position_for_sync(unit, pos: Vector2i) -> void:
	var board = tm.get_node("GameBoardNode")
	var old_pos = unit.grid_pos
	var had_old_pos = false
	if unit.is_base or unit.is_tower:
		had_old_pos = board.structure_units.get(old_pos) == unit or board.structure_tiles.get(old_pos) == unit
	else:
		had_old_pos = board.occupied_tiles.get(old_pos) == unit
	if had_old_pos:
		if unit.is_base or unit.is_tower:
			if board.structure_units.get(old_pos) == unit:
				board.structure_units.erase(old_pos)
			if board.structure_tiles.get(old_pos) == unit:
				board.structure_tiles.erase(old_pos)
		else:
			if board.occupied_tiles.get(old_pos) == unit:
				board.occupied_tiles.erase(old_pos)
		tm._refresh_tile_after_unit_change(old_pos)
	unit.grid_pos = pos
	var map_layer = tm.get_node("GameBoardNode/HexTileMap")
	unit.map_layer = map_layer
	unit.position = map_layer.map_to_world(pos) + map_layer.tile_size * 0.5
	if unit.is_base or unit.is_tower:
		board.structure_units[pos] = unit
		board.set_structure_at(pos, unit)
	else:
		board.occupied_tiles[pos] = unit
	tm._refresh_tile_after_unit_change(pos)


func _remove_unit_for_sync(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var board = tm.get_node("GameBoardNode")
	if unit.is_base or unit.is_tower:
		if board.structure_units.get(unit.grid_pos) == unit:
			board.structure_units.erase(unit.grid_pos)
		if board.structure_tiles.get(unit.grid_pos) == unit:
			board.structure_tiles.erase(unit.grid_pos)
	else:
		if board.occupied_tiles.get(unit.grid_pos) == unit:
			board.occupied_tiles.erase(unit.grid_pos)
	tm._refresh_tile_after_unit_change(unit.grid_pos)
	tm.unit_manager.unit_by_net_id.erase(unit.net_id)
	unit.queue_free()


func _rebuild_unit_indexes(board, unit_mgr) -> void:
	var max_player = 1
	var max_neutral = 1000001
	unit_mgr.unit_by_net_id.clear()
	for unit in unit_mgr.get_children():
		if unit == null or not is_instance_valid(unit):
			continue
		unit_mgr.unit_by_net_id[int(unit.net_id)] = unit
		if unit.player_id == tm.NEUTRAL_PLAYER_ID:
			max_neutral = max(max_neutral, int(unit.net_id))
		else:
			max_player = max(max_player, int(unit.net_id))
	board.occupied_tiles.clear()
	board.structure_units.clear()
	for unit in unit_mgr.get_children():
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.is_base or unit.is_tower:
			board.structure_units[unit.grid_pos] = unit
			board.set_structure_at(unit.grid_pos, unit)
		else:
			board.occupied_tiles[unit.grid_pos] = unit
	unit_mgr._next_net_id_player = max_player + 1
	unit_mgr._next_net_id_neutral = max_neutral + 1
