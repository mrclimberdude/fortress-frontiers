class_name AsyncMatchService
extends Node

signal mode_changed(enabled: bool)
signal auth_state_changed(session: Dictionary)
signal match_list_received(matches: Array)
signal match_state_received(match_state: Dictionary)
signal turn_snapshot_received(snapshot: Dictionary)
signal submit_orders_completed(ok: bool, response: Dictionary)
signal error_raised(message: String)

const DEFAULT_POLL_SECONDS: float = 10.0
const DEFAULT_SUPABASE_URL: String = "https://bddepnwnoslzoetwmcqq.supabase.co"
const DEFAULT_SUPABASE_ANON_KEY: String = "sb_publishable_2xAgHAW_lMdYbpLnQClM6A_M6vDmDtg"

var enabled: bool = false
var supabase_url: String = DEFAULT_SUPABASE_URL
var anon_key: String = DEFAULT_SUPABASE_ANON_KEY
var access_token: String = ""
var refresh_token: String = ""
var current_session: Dictionary = {}
var current_match_id: String = ""
var current_match_state: Dictionary = {}
var current_turn_snapshot: Dictionary = {}
var poll_interval_seconds: float = DEFAULT_POLL_SECONDS

var _poll_timer: Timer = null


func _ready() -> void:
	_poll_timer = Timer.new()
	_poll_timer.one_shot = false
	_poll_timer.wait_time = poll_interval_seconds
	_poll_timer.timeout.connect(_on_poll_timer_timeout)
	add_child(_poll_timer)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not enabled:
		stop_polling()
		current_match_id = ""
		current_match_state = {}
		current_turn_snapshot = {}
	emit_signal("mode_changed", enabled)


func is_enabled() -> bool:
	return enabled


func configure_backend(url: String, key: String) -> void:
	var resolved_url = url.strip_edges().trim_suffix("/")
	var resolved_key = key.strip_edges()
	supabase_url = resolved_url if resolved_url != "" else DEFAULT_SUPABASE_URL
	anon_key = resolved_key if resolved_key != "" else DEFAULT_SUPABASE_ANON_KEY


func get_default_backend_config() -> Dictionary:
	return {
		"supabase_url": DEFAULT_SUPABASE_URL,
		"anon_key": DEFAULT_SUPABASE_ANON_KEY
	}


func has_session() -> bool:
	return access_token != ""


func clear_session() -> void:
	access_token = ""
	refresh_token = ""
	current_session = {}
	emit_signal("auth_state_changed", {})


func sign_in(email: String, password: String) -> void:
	await _authenticate("/auth/v1/token?grant_type=password", {
		"email": email.strip_edges(),
		"password": password
	})


func sign_up(email: String, password: String) -> void:
	await _authenticate("/auth/v1/signup", {
		"email": email.strip_edges(),
		"password": password
	})


func sign_out() -> void:
	clear_session()


func list_matches() -> void:
	if not _ensure_ready(true):
		return
	var response = await _request_json(_function_url("list_matches"), HTTPClient.METHOD_POST, {})
	if not response.get("ok", false):
		_emit_error_response("Failed to list matches", response)
		return
	var payload = response.get("data", {})
	var matches: Array = []
	if payload is Dictionary and payload.get("matches", []) is Array:
		matches = payload.get("matches", [])
	emit_signal("match_list_received", matches)


func create_match(payload: Dictionary) -> void:
	if not _ensure_ready(true):
		return
	var response = await _request_json(_function_url("create_match"), HTTPClient.METHOD_POST, payload)
	if not response.get("ok", false):
		_emit_error_response("Failed to create match", response)
		return
	var data = response.get("data", {})
	if data is Dictionary:
		current_match_state = data.duplicate(true)
		current_match_id = str(current_match_state.get("match_id", current_match_id)).strip_edges()
		emit_signal("match_state_received", current_match_state)
		if current_match_id != "":
			fetch_turn_snapshot(current_match_id)
			start_polling()


func join_match(payload: Dictionary) -> void:
	if not _ensure_ready(true):
		return
	var response = await _request_json(_function_url("join_match"), HTTPClient.METHOD_POST, payload)
	if not response.get("ok", false):
		_emit_error_response("Failed to join match", response)
		return
	var data = response.get("data", {})
	if data is Dictionary:
		current_match_state = data.duplicate(true)
		current_match_id = str(current_match_state.get("match_id", current_match_id)).strip_edges()
		emit_signal("match_state_received", current_match_state)
		if current_match_id != "":
			fetch_turn_snapshot(current_match_id)
			start_polling()


func fetch_match_state(match_id: String = "") -> void:
	if not _ensure_ready(true):
		return
	var resolved_match_id = _resolve_match_id(match_id)
	if resolved_match_id == "":
		emit_signal("error_raised", "No async match selected.")
		return
	var response = await _request_json(_function_url("get_match_state"), HTTPClient.METHOD_POST, {
		"match_id": resolved_match_id
	})
	if not response.get("ok", false):
		_emit_error_response("Failed to fetch match state", response)
		return
	var data = response.get("data", {})
	if data is Dictionary:
		current_match_state = data.duplicate(true)
		current_match_id = str(current_match_state.get("match_id", resolved_match_id)).strip_edges()
		emit_signal("match_state_received", current_match_state)


func fetch_turn_snapshot(match_id: String = "") -> void:
	if not _ensure_ready(true):
		return
	var resolved_match_id = _resolve_match_id(match_id)
	if resolved_match_id == "":
		emit_signal("error_raised", "No async match selected.")
		return
	var response = await _request_json(_function_url("get_turn_snapshot"), HTTPClient.METHOD_POST, {
		"match_id": resolved_match_id
	})
	if not response.get("ok", false):
		var data = response.get("data", {})
		if int(response.get("status", 0)) == 404 and data is Dictionary and str(data.get("error", "")).strip_edges() == "snapshot_not_found":
			current_turn_snapshot = {
				"match_id": resolved_match_id,
				"viewer_id": str(current_match_state.get("local_player_id", "")).strip_edges(),
				"turn_number": int(current_match_state.get("current_turn", -1)),
				"snapshot_version": -1,
				"pending": true
			}
			emit_signal("turn_snapshot_received", current_turn_snapshot)
			return
		elif int(response.get("status", 0)) == 202 and data is Dictionary:
			current_turn_snapshot = data.duplicate(true)
			current_match_id = str(current_turn_snapshot.get("match_id", resolved_match_id)).strip_edges()
			emit_signal("turn_snapshot_received", current_turn_snapshot)
			return
		_emit_error_response("Failed to fetch turn snapshot", response)
		return
	var data = response.get("data", {})
	if data is Dictionary:
		current_turn_snapshot = data.duplicate(true)
		current_match_id = str(current_turn_snapshot.get("match_id", resolved_match_id)).strip_edges()
		emit_signal("turn_snapshot_received", current_turn_snapshot)


func submit_orders(payload: Dictionary) -> void:
	if not _ensure_ready(true):
		return
	var response = await _request_json(_function_url("submit_orders"), HTTPClient.METHOD_POST, payload)
	if not response.get("ok", false):
		_emit_error_response("Failed to submit orders", response)
		emit_signal("submit_orders_completed", false, response)
		return
	var data = response.get("data", {})
	if data is Dictionary and str(data.get("match_id", "")).strip_edges() != "":
		current_match_id = str(data.get("match_id", current_match_id)).strip_edges()
	emit_signal("submit_orders_completed", true, data if data is Dictionary else {})


func fetch_turn_result(match_id: String = "", turn_number: int = -1) -> void:
	if not _ensure_ready(true):
		return
	var resolved_match_id = _resolve_match_id(match_id)
	if resolved_match_id == "":
		emit_signal("error_raised", "No async match selected.")
		return
	var response = await _request_json(_function_url("get_turn_result"), HTTPClient.METHOD_POST, {
		"match_id": resolved_match_id,
		"turn_number": turn_number
	})
	if not response.get("ok", false):
		_emit_error_response("Failed to fetch turn result", response)
		return
	var data = response.get("data", {})
	if data is Dictionary:
		current_match_state = data.duplicate(true)
		emit_signal("match_state_received", current_match_state)


func set_current_match(match_id: String) -> void:
	current_match_id = match_id.strip_edges()


func start_polling(seconds: float = -1.0) -> void:
	if seconds > 0.0:
		poll_interval_seconds = seconds
	if _poll_timer == null:
		return
	_poll_timer.wait_time = max(2.0, poll_interval_seconds)
	if enabled and has_session() and current_match_id != "":
		_poll_timer.start()


func stop_polling() -> void:
	if _poll_timer != null:
		_poll_timer.stop()


func _on_poll_timer_timeout() -> void:
	if not enabled or not has_session() or current_match_id == "":
		return
	fetch_match_state(current_match_id)
	fetch_turn_snapshot(current_match_id)


func _authenticate(path: String, payload: Dictionary) -> void:
	if not _ensure_ready(false):
		return
	var response = await _request_json(_absolute_url(path), HTTPClient.METHOD_POST, payload, false, true)
	if not response.get("ok", false):
		_emit_error_response("Async authentication failed", response)
		return
	var data = response.get("data", {})
	if not (data is Dictionary):
		emit_signal("error_raised", "Async authentication returned an invalid response.")
		return
	access_token = str(data.get("access_token", "")).strip_edges()
	refresh_token = str(data.get("refresh_token", "")).strip_edges()
	var user_info = data.get("user", {})
	current_session = {
		"access_token": access_token,
		"refresh_token": refresh_token,
		"user": user_info,
		"user_id": str((user_info if user_info is Dictionary else {}).get("id", "")).strip_edges()
	}
	emit_signal("auth_state_changed", current_session)


func _ensure_ready(require_auth: bool) -> bool:
	if not enabled:
		emit_signal("error_raised", "Async mode is not enabled.")
		return false
	if supabase_url == "" or anon_key == "":
		emit_signal("error_raised", "Supabase URL and anon key are required.")
		return false
	if require_auth and not has_session():
		emit_signal("error_raised", "Sign in before using async match actions.")
		return false
	return true


func _resolve_match_id(match_id: String) -> String:
	var candidate = match_id.strip_edges()
	if candidate != "":
		return candidate
	return current_match_id


func _function_url(name: String) -> String:
	return _absolute_url("/functions/v1/%s" % name)


func _absolute_url(path: String) -> String:
	return "%s%s" % [supabase_url, path]


func _default_headers(include_auth: bool, auth_is_supabase: bool = false) -> PackedStringArray:
	var headers := PackedStringArray()
	headers.append("Content-Type: application/json")
	if anon_key != "":
		headers.append("apikey: %s" % anon_key)
	if include_auth and access_token != "":
		headers.append("Authorization: Bearer %s" % access_token)
	elif auth_is_supabase and access_token != "":
		headers.append("Authorization: Bearer %s" % access_token)
	return headers


func _request_json(url: String, method: int, payload: Variant = null, include_auth: bool = true, auth_is_supabase: bool = false) -> Dictionary:
	var request = HTTPRequest.new()
	add_child(request)
	var body_text := ""
	if payload != null:
		body_text = JSON.stringify(payload)
	var err = request.request(url, _default_headers(include_auth, auth_is_supabase), method, body_text)
	if err != OK:
		request.queue_free()
		return {
			"ok": false,
			"status": 0,
			"error": "request_failed_%d" % err
		}
	var result = await request.request_completed
	request.queue_free()
	if result.size() < 4:
		return {
			"ok": false,
			"status": 0,
			"error": "request_incomplete"
		}
	var response_code = int(result[1])
	var body: PackedByteArray = result[3]
	var text = body.get_string_from_utf8()
	var parsed = {}
	if text.strip_edges() != "":
		var json = JSON.parse_string(text)
		if json != null:
			parsed = json
	return {
		"ok": response_code >= 200 and response_code < 300,
		"status": response_code,
		"data": parsed,
		"raw": text
	}


func _emit_error_response(prefix: String, response: Dictionary) -> void:
	var status = int(response.get("status", 0))
	var suffix = ""
	var data = response.get("data", {})
	if data is Dictionary:
		var message = str(data.get("error", data.get("message", ""))).strip_edges()
		if message != "":
			suffix = ": %s" % message
	elif str(response.get("raw", "")).strip_edges() != "":
		suffix = ": %s" % str(response.get("raw", "")).strip_edges()
	var message_text = "%s (HTTP %d)%s" % [prefix, status, suffix]
	emit_signal("error_raised", message_text)
