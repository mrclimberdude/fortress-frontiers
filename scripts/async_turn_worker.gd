extends SceneTree

const GAME_SCENE := preload("res://scenes/game_board.tscn")


func _init() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: godot --headless --script res://scripts/async_turn_worker.gd <input.json> <output.json>")
		quit(1)
		return
	var input_path = str(args[0]).strip_edges()
	var output_path = str(args[1]).strip_edges()
	var payload = _load_json_file(input_path)
	if payload.is_empty():
		push_error("Async worker: missing or invalid input payload.")
		quit(2)
		return
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	var turn_mgr = game
	if turn_mgr == null:
		push_error("Async worker: failed to instantiate game scene.")
		quit(3)
		return
	var job_type = str(payload.get("job_type", "resolve_turn")).strip_edges()
	var result := {}
	match job_type:
		"seed_match":
			if not turn_mgr.has_method("seed_async_turn_contract"):
				push_error("Async worker: scene does not expose seed_async_turn_contract().")
				quit(3)
				return
			result = turn_mgr.seed_async_turn_contract(str(payload.get("match_id", "")).strip_edges(), payload)
		"resolve_turn":
			if not turn_mgr.has_method("resolve_async_turn_contract"):
				push_error("Async worker: scene does not expose resolve_async_turn_contract().")
				quit(3)
				return
			var snapshot = payload.get("snapshot", {})
			var submissions = payload.get("submissions", [])
			result = turn_mgr.resolve_async_turn_contract(snapshot, submissions)
		_:
			push_error("Async worker: unsupported job_type '%s'." % job_type)
			quit(3)
			return
	if not _write_json_file(output_path, result):
		push_error("Async worker: failed to write output payload.")
		quit(4)
		return
	quit(0)


func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	return parsed if parsed is Dictionary else {}


func _write_json_file(path: String, payload: Dictionary) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	return true
