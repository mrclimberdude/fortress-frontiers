extends Control

var series: Dictionary = {}
var colors := {
	"player1": Color(0.2, 0.65, 1.0),
	"player2": Color(1.0, 0.45, 0.45)
}
var padding: float = 12.0

func set_series(new_series: Dictionary) -> void:
	series = new_series
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.15, 0.95), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.3, 0.3, 1.0), false, 1.0)
	if series.is_empty():
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
		return
	if max_x == min_x:
		max_x += 1.0
	if max_y == min_y:
		max_y += 1.0
	var w = max(1.0, size.x - padding * 2.0)
	var h = max(1.0, size.y - padding * 2.0)
	for pid in series.keys():
		var points: Array = series[pid]
		var poly := PackedVector2Array()
		for pt in points:
			if typeof(pt) != TYPE_VECTOR2:
				continue
			var sx = padding + (pt.x - min_x) / (max_x - min_x) * w
			var sy = size.y - padding - (pt.y - min_y) / (max_y - min_y) * h
			poly.append(Vector2(sx, sy))
		if poly.size() >= 2:
			draw_polyline(poly, colors.get(pid, Color(1, 1, 1)), 2.0)
