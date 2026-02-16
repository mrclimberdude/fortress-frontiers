extends Control

var series: Dictionary = {}
var colors := {
	"player1": Color(0.2, 0.65, 1.0),
	"player2": Color(1.0, 0.45, 0.45)
}
var padding: float = 12.0
var axis_label_padding: float = 18.0
var tick_size: float = 4.0
var tick_color: Color = Color(0.6, 0.6, 0.6, 1.0)

func set_series(new_series: Dictionary) -> void:
	series = new_series
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.15, 0.95), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.3, 0.3, 1.0), false, 1.0)
	var font = get_theme_default_font()
	var font_size = get_theme_default_font_size()
	if series.is_empty():
		_draw_axis_labels_and_ticks(font, font_size, 1.0, 1.0, 0.0, 1.0)
		return
	var min_x = 1.0
	var max_x = 1.0
	var min_y = 0.0
	var max_y = 0.0
	var has_point = false
	for pid in series.keys():
		var points: Array = series[pid]
		for pt in points:
			if typeof(pt) != TYPE_VECTOR2:
				continue
			has_point = true
			min_x = min(min_x, pt.x)
			max_x = max(max_x, pt.x)
			min_y = min(min_y, pt.y)
			max_y = max(max_y, pt.y)
	if not has_point:
		_draw_axis_labels_and_ticks(font, font_size, min_x, max_x, min_y, max_y)
		return
	if max_x == min_x:
		max_x += 1.0
	if max_y == min_y:
		max_y += 1.0
	var pad_left = padding + axis_label_padding
	var pad_bottom = padding + axis_label_padding
	var pad_right = padding
	var pad_top = padding
	var w = max(1.0, size.x - pad_left - pad_right)
	var h = max(1.0, size.y - pad_top - pad_bottom)
	for pid in series.keys():
		var points: Array = series[pid]
		var poly := PackedVector2Array()
		for pt in points:
			if typeof(pt) != TYPE_VECTOR2:
				continue
			var sx = pad_left + (pt.x - min_x) / (max_x - min_x) * w
			var sy = size.y - pad_bottom - (pt.y - min_y) / (max_y - min_y) * h
			poly.append(Vector2(sx, sy))
		if poly.size() >= 2:
			draw_polyline(poly, colors.get(pid, Color(1, 1, 1)), 2.0)
	_draw_axis_labels_and_ticks(font, font_size, min_x, max_x, min_y, max_y)

func _draw_axis_labels_and_ticks(font: Font, font_size: int, min_x: float, max_x: float, min_y: float, max_y: float) -> void:
	if font == null:
		return
	var label_color = Color(0.85, 0.85, 0.85, 1.0)
	var x_label = "Turn"
	var y_label = "Value"
	var x_size = font.get_string_size(x_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var x_pos = Vector2((size.x - x_size.x) * 0.5, size.y - 4.0)
	draw_string(font, x_pos, x_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
	var y_size = font.get_string_size(y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_set_transform(Vector2(6.0, (size.y + y_size.x) * 0.5), -PI / 2.0, Vector2.ONE)
	draw_string(font, Vector2.ZERO, y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var pad_left = padding + axis_label_padding
	var pad_bottom = padding + axis_label_padding
	var pad_right = padding
	var pad_top = padding
	var w = max(1.0, size.x - pad_left - pad_right)
	var h = max(1.0, size.y - pad_top - pad_bottom)
	var axis_x = pad_left
	var axis_y = size.y - pad_bottom

	var x_range = max_x - min_x
	var y_range = max_y - min_y
	var x_step = _nice_step(x_range, 4)
	var y_step = _nice_step(y_range, 4)
	var x_start = floor(min_x / x_step) * x_step
	var x_end = ceil(max_x / x_step) * x_step
	var y_start = floor(min_y / y_step) * y_step
	var y_end = ceil(max_y / y_step) * y_step

	var x_val = x_start
	while x_val <= x_end + (x_step * 0.5):
		var t = 0.0 if x_range == 0 else (x_val - min_x) / x_range
		var sx = axis_x + clamp(t, 0.0, 1.0) * w
		draw_line(Vector2(sx, axis_y), Vector2(sx, axis_y + tick_size), tick_color, 1.0)
		var x_text = str(int(round(x_val)))
		var xt_size = font.get_string_size(x_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, Vector2(sx - xt_size.x * 0.5, axis_y + tick_size + font_size), x_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
		x_val += x_step

	var y_val = y_start
	while y_val <= y_end + (y_step * 0.5):
		var t = 0.0 if y_range == 0 else (y_val - min_y) / y_range
		var sy = axis_y - clamp(t, 0.0, 1.0) * h
		draw_line(Vector2(axis_x - tick_size, sy), Vector2(axis_x, sy), tick_color, 1.0)
		var y_text = _format_tick(y_val, y_step)
		var yt_size = font.get_string_size(y_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, Vector2(axis_x - tick_size - 4.0 - yt_size.x, sy + font_size * 0.3), y_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
		y_val += y_step

func _nice_step(value_range: float, tick_count: int) -> float:
	if value_range <= 0.0:
		return 1.0
	var raw = value_range / float(max(1, tick_count))
	var pow10 = pow(10.0, floor(log(raw) / log(10.0)))
	var frac = raw / pow10
	var nice_frac = 1.0
	if frac <= 1.0:
		nice_frac = 1.0
	elif frac <= 2.0:
		nice_frac = 2.0
	elif frac <= 5.0:
		nice_frac = 5.0
	else:
		nice_frac = 10.0
	return nice_frac * pow10

func _format_tick(value: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(value)))
	if abs(value) >= 10.0:
		return str(int(round(value)))
	return "%0.1f" % value
