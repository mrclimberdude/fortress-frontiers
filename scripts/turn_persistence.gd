class_name TurnPersistence
extends RefCounted

var tm


func _init(turn_manager) -> void:
	tm = turn_manager


func save_path_for_slot(slot: int) -> String:
	if slot < 0:
		return tm.SAVE_AUTOSAVE_PATH
	if slot >= tm.SAVE_SLOT_COUNT:
		slot = tm.SAVE_SLOT_COUNT - 1
	return "user://save_slot_%d.json" % (slot + 1)


func encode_key(key) -> String:
	var t = typeof(key)
	if t == TYPE_STRING:
		return tm.SAVE_KEY_PREFIX_STR + key
	if t == TYPE_INT:
		return tm.SAVE_KEY_PREFIX_INT + str(key)
	if t == TYPE_VECTOR2I:
		return tm.SAVE_KEY_PREFIX_VEC2I + str(key.x) + "," + str(key.y)
	return tm.SAVE_KEY_PREFIX_STR + str(key)


func decode_key(key: String):
	if key.begins_with(tm.SAVE_KEY_PREFIX_STR):
		return key.substr(tm.SAVE_KEY_PREFIX_STR.length())
	if key.begins_with(tm.SAVE_KEY_PREFIX_INT):
		return int(key.substr(tm.SAVE_KEY_PREFIX_INT.length()))
	if key.begins_with(tm.SAVE_KEY_PREFIX_VEC2I):
		var coords = key.substr(tm.SAVE_KEY_PREFIX_VEC2I.length()).split(",")
		if coords.size() >= 2:
			return Vector2i(int(coords[0]), int(coords[1]))
		return Vector2i.ZERO
	return key


func encode_value(value):
	var t = typeof(value)
	if t == TYPE_VECTOR2I:
		return {tm.SAVE_MARKER_VEC2I: [value.x, value.y]}
	if t == TYPE_VECTOR2:
		return {tm.SAVE_MARKER_VEC2: [value.x, value.y]}
	if t == TYPE_DICTIONARY:
		var out := {}
		for k in value.keys():
			out[encode_key(k)] = encode_value(value[k])
		return out
	if t == TYPE_ARRAY:
		var arr := []
		for v in value:
			arr.append(encode_value(v))
		return arr
	return value


func decode_value(value):
	var t = typeof(value)
	if t == TYPE_DICTIONARY:
		if value.size() == 1 and value.has(tm.SAVE_MARKER_VEC2I):
			var vec = value[tm.SAVE_MARKER_VEC2I]
			if vec is Array and vec.size() >= 2:
				return Vector2i(int(vec[0]), int(vec[1]))
		if value.size() == 1 and value.has(tm.SAVE_MARKER_VEC2):
			var v = value[tm.SAVE_MARKER_VEC2]
			if v is Array and v.size() >= 2:
				return Vector2(float(v[0]), float(v[1]))
		var out := {}
		for k in value.keys():
			var decoded_key = k
			if k is String:
				decoded_key = decode_key(k)
			out[decoded_key] = decode_value(value[k])
		return out
	if t == TYPE_ARRAY:
		var arr := []
		for v in value:
			arr.append(decode_value(v))
		return arr
	return value


func save_game(path: String = "", allow_non_orders: bool = false) -> bool:
	var save_path = path if path != "" else tm.SAVE_DEFAULT_PATH
	if not tm._is_host():
		push_error("Save failed: host only.")
		return false
	if tm.current_phase != tm.Phase.ORDERS and not allow_non_orders:
		push_error("Save failed: only supported during the orders phase.")
		return false
	var state = tm._collect_state()
	var map_state = tm._collect_procedural_map_state()
	if not map_state.is_empty():
		state["procedural_map"] = map_state
	var fog = tm.get_node("GameBoardNode").get_node_or_null("FogOfWar")
	if fog != null:
		state["fog_visibility"] = fog.visiblity.duplicate(true)
	var payload = {
		"save_version": tm.SAVE_VERSION,
		"state": encode_value(state)
	}
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: could not open file %s" % save_path)
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	return true


func load_game(path: String = "") -> bool:
	var load_path = path if path != "" else tm.SAVE_DEFAULT_PATH
	if not tm._is_host():
		push_error("Load failed: host only.")
		return false
	if not FileAccess.file_exists(load_path):
		push_error("Load failed: file not found %s" % load_path)
		return false
	var file = FileAccess.open(load_path, FileAccess.READ)
	if file == null:
		push_error("Load failed: could not open file %s" % load_path)
		return false
	var content = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Load failed: invalid save format.")
		return false
	var payload = parsed as Dictionary
	var version = int(payload.get("save_version", 0))
	if version != tm.SAVE_VERSION:
		push_error("Load failed: unsupported save version.")
		return false
	var state = decode_value(payload.get("state", {}))
	if typeof(state) != TYPE_DICTIONARY or state.is_empty():
		push_error("Load failed: missing state data.")
		return false
	state["force_apply"] = true
	var map_state = {}
	if state.has("procedural_map") and state["procedural_map"] is Dictionary:
		map_state = state["procedural_map"]
	var phase = int(state.get("current_phase", int(tm.Phase.ORDERS)))
	if phase != int(tm.Phase.ORDERS):
		push_error("Load failed: only orders-phase saves are supported.")
		return false
	var map_index = int(state.get("map_index", 0))
	var match_seed = int(state.get("match_seed", -1))
	NetworkManager.selected_map_index = map_index
	if match_seed > 0:
		NetworkManager.match_seed = match_seed
	tm._ensure_dev_log_open()
	tm._reset_map_state()
	tm._load_map_by_index(map_index)
	if not map_state.is_empty():
		tm._apply_procedural_map_state(map_state, true)
	tm.apply_state(state, true)
	tm._rebuild_orders_after_load()
	tm._devlog({
		"type": "game_loaded",
		"path": load_path,
		"map_index": map_index
	})
	tm._devlog_snapshot("load")
	tm.call_deferred("_refresh_fog_after_load")
	NetworkManager.reset_match_tracking(tm.get_submission_players())
	NetworkManager._step_ready_counts = {}
	tm.pending_broadcast_map_state = map_state
	tm._broadcast_state(true)
	tm.call_deferred("_broadcast_state", true)
	return true
