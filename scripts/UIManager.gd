#UIManager.gd

extends CanvasLayer

# configure these in the Inspector
@export var turn_manager_path: NodePath
@export var map_node_path:     NodePath

# runtime state
var current_player : String = ""
var placing_unit   : String = ""
var currently_selected_unit: Node = null
var current_reachable: Dictionary = {}
var enemy_tiles: Array = []
var action_mode:       String   = ""     # "move", "ranged", "melee", "support", "hold"


@onready var turn_mgr = get_node(turn_manager_path) as Node
@onready var hex = $"../GameBoardNode/HexTileMap"
@onready var gold_lbl = $Panel/VBoxContainer/GoldLabel as Label
@onready var game_board: Node = get_node("../GameBoardNode")
@onready var action_menu: PopupMenu      = $Panel/ActionMenu as PopupMenu

const ArrowScene = preload("res://scenes/Arrow.tscn")
const AttackArrowScene = preload("res://scenes/AttackArrow.tscn")

func _ready():
	hide()
	
	# Enable unhandled input processing
	set_process_unhandled_input(true)
	# connect using Callable(self, "method_name")
	turn_mgr.connect("orders_phase_begin",
					 Callable(self, "_on_orders_phase_begin"))
	turn_mgr.connect("orders_phase_end",
					 Callable(self, "_on_orders_phase_end"))

	$Panel/VBoxContainer/ArcherButton.connect("pressed",
					 Callable(self, "_on_archer_pressed"))
	$Panel/VBoxContainer/SoldierButton.connect("pressed",
					 Callable(self, "_on_soldier_pressed"))
	$Panel/VBoxContainer/DoneButton.connect("pressed",
					 Callable(self, "_on_done_pressed"))
					
	action_menu.connect("id_pressed", Callable(self, "_on_action_selected"))
	action_menu.hide()


func _on_orders_phase_begin(player: String) -> void:
	# show the UI and reset state
	current_player = player
	gold_lbl.text = "Gold: %d" % turn_mgr.player_gold[current_player]
	placing_unit  = ""
	show()

func _on_orders_phase_end() -> void:
	game_board.clear_highlights()
	hide()

func _on_archer_pressed():
	placing_unit = "archer"
	gold_lbl.text = "Click map to place Archer\nGold: %d" % turn_mgr.player_gold[current_player]

func _on_soldier_pressed():
	placing_unit = "soldier"
	gold_lbl.text = "Click map to place Soldier\nGold: %d" % turn_mgr.player_gold[current_player]

func _on_unit_selected(unit: Node) -> void:
	# 1) Clear any old highlights
	game_board.clear_highlights()

	# 2) Compute reachable tiles
	#var result = game_board.get_reachable_tiles(unit.grid_pos, unit.move_range)
	#var tiles = result["tiles"]
	#game_board.show_highlights(tiles)

	# 3) Store for later path-drawing / order issuance
	currently_selected_unit = unit
	#current_reachable = result
	
	# Show action selection menu
	action_menu.clear()
	action_menu.add_item("Move", 0)
	if unit.is_ranged:
		action_menu.add_item("Ranged Attack", 1)
	else:
		action_menu.add_item("Melee Attack", 2)
	action_menu.add_item("Support", 3)
	action_menu.add_item("Hold", 4)

func _on_action_selected(id: int) -> void:
	match id:
		0:
			action_mode = "move"
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, currently_selected_unit.move_range, action_mode)
			var tiles = result["tiles"].slice(1)
			game_board.show_highlights(tiles)
			current_reachable = result
			print("Move selected for %s" % currently_selected_unit.name)
			# TODO: initiate move path selection
		1:
			action_mode = "ranged"
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, currently_selected_unit.ranged_range, action_mode)
			var tiles = result["tiles"]
			enemy_tiles = []
			for tile in tiles:
				if game_board.is_occupied(tile):
					var other_unit = game_board.get_unit_at(tile)
					if other_unit.player_id != current_player:
						enemy_tiles.append(tile)
			game_board.show_highlights(enemy_tiles)
			print("Ranged Attack selected for %s" % currently_selected_unit.name)
			# TODO: initiate ranged attack UI
		2:
			print("Melee Attack selected for %s" % currently_selected_unit.name)
			# TODO: initiate melee attack UI
		3:
			print("Support selected for %s" % currently_selected_unit.name)
			# TODO: initiate support UI
		4:
			print("Hold selected for %s" % currently_selected_unit.name)
			turn_mgr.add_order(current_player, {
				"unit": currently_selected_unit,
				"type": "hold",
			})
	action_menu.hide()

func _on_done_pressed():
	game_board.clear_highlights()
	for child in hex.get_node("PathArrows").get_children():
		child.queue_free()
	for child in hex.get_node("AttackArrows").get_children():
		child.queue_free()
	# signal back to TurnManager that this player is finished
	turn_mgr.submit_player_order(current_player)
	# prevent further clicks
	placing_unit = ""

func calculate_path(dest: Vector2i) -> Array:
	# Build path array
	var path = []
	var prev = current_reachable["prev"]
	var cur = dest
	while cur in prev:
		path.insert(0, cur)
		cur = prev[cur]
	# include start
	path.insert(0, currently_selected_unit.grid_pos)
	return path
	

# Backtrack and draw arrow sprites along the path to `dest`
func _draw_paths() -> void:
	var path_arrows_node = hex.get_node("PathArrows")
	for child in path_arrows_node.get_children():
		child.queue_free()
	var all_orders = turn_mgr.get_all_orders(current_player)
	for order in all_orders:
		if order["type"] == "move":
			var root = Node2D.new()
			path_arrows_node.add_child(root)
			var path = order["path"]
			
			# Draw arrows between consecutive cells
			for i in range(path.size() - 1):
				var a = path[i]
				var b = path[i + 1]
				var p1 = hex.map_to_world(a) + hex.tile_size * 0.5
				var p2 = hex.map_to_world(b) + hex.tile_size * 0.5

				var arrow = ArrowScene.instantiate() as Sprite2D
				# Calculate direction and texture size
				var dir = (p2 - p1).normalized()
				var tex_size = arrow.texture.get_size()
				var distance: float = (p2 - p1).length()
				var scale_x: float = distance / tex_size.x
				arrow.scale = Vector2(scale_x, 1)
				# After scaling, offset so the arrow's tail (pivot) sits at the source tile center
				var half_length = tex_size.x * scale_x * 0.5
				arrow.position = p1 + dir * half_length
				arrow.rotation = (p2 - p1).angle()
				
				arrow.z_index = 10
				root.add_child(arrow)

func _draw_attacks():
	var attack_arrows_node = hex.get_node("AttackArrows")
	for child in attack_arrows_node.get_children():
		child.queue_free()
	var all_orders = turn_mgr.get_all_orders(current_player)
	for order in all_orders:
		if order["type"] == "ranged":
			var root = Node2D.new()
			attack_arrows_node.add_child(root)
			
			# calculate direction and size for attack arrow
			var attacker = order["unit"]
			var p1 = hex.map_to_world(attacker.grid_pos) + hex.tile_size * 0.5
			var p2 = hex.map_to_world(order["target_tile"]) + hex.tile_size * 0.5
			var arrow = AttackArrowScene.instantiate() as Sprite2D
			var dir = (p2 - p1).normalized()
			var tex_size = arrow.texture.get_size()
			var distance: float = (p2 - p1).length()
			var scale_x: float = distance / tex_size.x
			arrow.scale = Vector2(scale_x, 1)
			# set position to center of tile
			var half_length = tex_size.x * scale_x * 0.5
			arrow.position = p1 + dir * half_length
			arrow.rotation = (p2 - p1).angle()
			arrow.z_index = 10
			root.add_child(arrow)

func _unhandled_input(ev):
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	
	game_board.clear_highlights()
	var world_pos = get_viewport().get_camera_2d().get_global_mouse_position()
	var cell = hex.world_to_map(world_pos)

	if placing_unit != "":
		# Placement logic
		if turn_mgr.buy_unit(current_player, placing_unit, cell):
			gold_lbl.text = "Gold: %d" % turn_mgr.player_gold[current_player]
			placing_unit = ""
		else:
			gold_lbl.text = "[Not enough gold]\nGold: %d" % turn_mgr.player_gold[current_player]
		return
	
	# Order phase: if waiting for destination (move mode)
	if action_mode == "move" and currently_selected_unit:
		var path = []
		# Only allow valid reachable cells
		if cell in current_reachable["tiles"] and cell != currently_selected_unit.grid_pos:
			path = calculate_path(cell)
			turn_mgr.add_order(current_player, {
				"unit": currently_selected_unit,
				"type": "move",
				"path": path
			})
			_draw_paths()
			_draw_attacks()
		action_mode = ""
		# TODO: enqueue move order via turn_mgr.enqueue_order(...)
		return
	
	if action_mode == "ranged" and currently_selected_unit:
		if cell in enemy_tiles:
			turn_mgr.add_order(current_player, {
				"unit": currently_selected_unit,
				"type": "ranged",
				"target_tile": cell,
				"target_unit": game_board.get_unit_at(cell)
			})
		_draw_paths()
		_draw_attacks()
		action_mode = ""
		return
	
	if turn_mgr.current_phase == $"..".Phase.ORDERS:
		# Unit selection in orders phase
		var unit = game_board.get_unit_at(cell)
		if unit:
			if unit.player_id == current_player:
				_on_unit_selected(unit)
				action_menu.set_position(ev.position)
				action_menu.show()
