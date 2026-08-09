extends Node

const GAME_SCENE := preload("res://scenes/game_board.tscn")


func _ready() -> void:
	call_deferred("_run_worker")


func _run_worker() -> void:
	var args = OS.get_cmdline_user_args()
	print("[async_worker_main] args size=", args.size())
	if args.size() < 2:
		push_error("Usage: godot --headless --path <project> res://scenes/async_worker_main.tscn -- <input.json> <output.json>")
		get_tree().quit(1)
		return
	var input_path = str(args[0]).strip_edges()
	var output_path = str(args[1]).strip_edges()
	print("[async_worker_main] input=", input_path)
	print("[async_worker_main] output=", output_path)
	var payload = _load_json_file(input_path)
	if payload.is_empty():
		push_error("Async worker: missing or invalid input payload.")
		get_tree().quit(2)
		return
	print("[async_worker_main] loaded payload for job_type=", str(payload.get("job_type", "resolve_turn")))
	var game = GAME_SCENE.instantiate()
	print("[async_worker_main] instantiated game scene")
	add_child(game)
	print("[async_worker_main] added game scene to tree")
	var turn_mgr = game
	if turn_mgr == null:
		push_error("Async worker: failed to instantiate game scene.")
		get_tree().quit(3)
		return
	var job_type = str(payload.get("job_type", "resolve_turn")).strip_edges()
	var result: Dictionary = {}
	match job_type:
		"seed_match":
			if not turn_mgr.has_method("seed_async_turn_contract"):
				push_error("Async worker: scene does not expose seed_async_turn_contract().")
				get_tree().quit(3)
				return
			print("[async_worker_main] starting seed_async_turn_contract")
			result = turn_mgr.seed_async_turn_contract(str(payload.get("match_id", "")).strip_edges(), payload)
			print("[async_worker_main] finished seed_async_turn_contract")
		"resolve_turn":
			if not turn_mgr.has_method("resolve_async_turn_contract"):
				push_error("Async worker: scene does not expose resolve_async_turn_contract().")
				get_tree().quit(3)
				return
			var snapshot = payload.get("snapshot", {})
			var submissions = payload.get("submissions", [])
			print("[async_worker_main] starting resolve_async_turn_contract")
			result = turn_mgr.resolve_async_turn_contract(snapshot, submissions)
			print("[async_worker_main] finished resolve_async_turn_contract")
		_:
			push_error("Async worker: unsupported job_type '%s'." % job_type)
			get_tree().quit(3)
			return
	if not _write_json_file(output_path, result):
		push_error("Async worker: failed to write output payload.")
		get_tree().quit(4)
		return
	print("[async_worker_main] wrote output payload")
	get_tree().quit(0)


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
