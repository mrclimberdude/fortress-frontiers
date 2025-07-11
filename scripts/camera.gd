extends Camera2D

@export var zoom_speed := 0.1
@export var pan_sensitivity := 1.0  # Higher = more responsive

var dragging := false
var last_mouse_position := Vector2.ZERO

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= 1.0 - zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= 1.0 + zoom_speed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				dragging = true
				last_mouse_position = get_viewport().get_mouse_position()
			else:
				dragging = false

	elif event is InputEventMouseMotion and dragging:
		var mouse_pos = get_viewport().get_mouse_position()
		var delta = mouse_pos - last_mouse_position
		var zoom_factor = (1.0 / zoom.x + 1.0 / zoom.y) / 2.0
		position -= delta * zoom_factor * pan_sensitivity
		last_mouse_position = mouse_pos
