#UIManager.gd

extends CanvasLayer

# configure these in the Inspector
@export var turn_manager_path: NodePath
@export var map_node_path:     NodePath
@export var unit_manager_path: NodePath
@export var dev_mode_toggle_path: NodePath

# runtime state
var current_player : String = ""
var placing_unit   : String = ""
var currently_selected_unit: Node = null
var current_reachable: Dictionary = {}
var enemy_tiles: Array = []
var support_tiles = []
var action_mode:       String   = ""     # "move", "ranged", "melee", "support", "hold"
var move_priority: int = 0
var allow_clicks: bool = true

var _current_exec_step_idx: int = 0

@onready var turn_mgr = get_node(turn_manager_path) as Node
@onready var unit_mgr = get_node(unit_manager_path) as Node
@onready var game_board: Node = get_node("../GameBoardNode")
@onready var hex = $"../GameBoardNode/HexTileMap"
@onready var gold_lbl = $Panel/VBoxContainer/GoldLabel as Label
@onready var income_lbl = $Panel/VBoxContainer/IncomeLabel as Label
@onready var action_menu: PopupMenu      = $Panel/ActionMenu as PopupMenu
@onready var exec_panel: PanelContainer  = $ExecutionPanel
@onready var phase_label   : Label       = exec_panel.get_node("PhaseLabel")
@onready var next_button   : Button      = exec_panel.get_node("NextButton")
@onready var cancel_done_button = $CancelDoneButton as Button
@onready var dev_mode_toggle = get_node(dev_mode_toggle_path) as CheckButton
@onready var dev_panel = $DevPanel

const ArrowScene = preload("res://scenes/Arrow.tscn")
const AttackArrowScene = preload("res://scenes/AttackArrow.tscn")
const SupportArrowScene = preload("res://scenes/SupportArrow.tscn")
const HealScene = preload("res://scenes/Healing.tscn")
const DefendScene = preload("res://scenes/Defending.tscn")

const ArcherScene = preload("res://scenes/Archer.tscn")
const SoldierScene = preload("res://scenes/Soldier.tscn")
const ScoutScene = preload("res://scenes/Scout.tscn")
const MinerScene = preload("res://scenes/Miner.tscn")
const TankScene = preload("res://scenes/Tank.tscn")

const MineScene = preload("res://scenes/GemMine.tscn")

func _ready():
	# Enable unhandled input processing
	set_process_unhandled_input(true)
	
	$HostButton.connect("pressed",
					Callable(self, "_on_host_pressed"))
	$JoinButton.connect("pressed",
					Callable(self, "_on_join_pressed"))
	
	# dev mode connections
	dev_mode_toggle.connect("toggled",
					Callable(self, "_on_dev_mode_toggled"))
	$DevPanel/VBoxContainer/FogCheckButton.connect("toggled",
					 Callable(self, "_on_fog_toggled"))
	$DevPanel/VBoxContainer/GiveIncomeButton.connect("pressed",
					 Callable(self, "_on_give_income_pressed"))
	
	# turn flow connections
	turn_mgr.connect("orders_phase_begin",
					Callable(self, "_on_orders_phase_begin"))
	turn_mgr.connect("orders_phase_end",
					Callable(self, "_on_orders_phase_end"))
	turn_mgr.connect("execution_paused",
					Callable(self, "_on_execution_paused"))
	turn_mgr.connect("execution_complete",
					Callable(self, "_on_execution_complete"))
	next_button.connect("pressed",
					Callable(self, "_on_next_pressed"))
	
	# order button connections
	$Panel/VBoxContainer/ArcherButton.connect("pressed",
					 Callable(self, "_on_archer_pressed"))
	$Panel/VBoxContainer/SoldierButton.connect("pressed",
					 Callable(self, "_on_soldier_pressed"))
	$Panel/VBoxContainer/ScoutButton.connect("pressed",
					 Callable(self, "_on_scout_pressed"))
	$Panel/VBoxContainer/MinerButton.connect("pressed",
					 Callable(self, "_on_miner_pressed"))
	$Panel/VBoxContainer/TankButton.connect("pressed",
					 Callable(self, "_on_tank_pressed"))
	$Panel/VBoxContainer/DoneButton.connect("pressed",
					 Callable(self, "_on_done_pressed"))
	$CancelDoneButton.connect("pressed",
					 Callable(self, "_on_cancel_pressed"))
	
	# setting gold labels for units
	var temp = ArcherScene.instantiate()
	$Panel/VBoxContainer/ArcherButton.text = "Buy Archer (%dg)" % temp.cost
	temp = SoldierScene.instantiate()
	$Panel/VBoxContainer/SoldierButton.text = "Buy Soldier (%dg)" % temp.cost
	temp = ScoutScene.instantiate()
	$Panel/VBoxContainer/ScoutButton.text = "Buy Scout (%dg)" % temp.cost
	temp = MinerScene.instantiate()
	$Panel/VBoxContainer/MinerButton.text = "Buy Miner (%dg)" % temp.cost
	temp = TankScene.instantiate()
	$Panel/VBoxContainer/TankButton.text = "Buy Tank (%dg)" % temp.cost
	temp.free()
	
	# unit order menu
	action_menu.connect("id_pressed", Callable(self, "_on_action_selected"))
	action_menu.hide()
	
	# spawn mines
	var structures_node = hex.get_node("Structures")
	for tile in turn_mgr.special_tiles["unclaimed"]:
		var root = Node2D.new()
		structures_node.add_child(root)
		var mine = MineScene.instantiate() as Sprite2D
		mine.position = hex.map_to_world(tile) + hex.tile_size * 0.5
		mine.z_index = 0
		mine.grid_pos = tile
		$"../GameBoardNode".set_structure_at(tile, mine)
		root.add_child(mine)

func _on_orders_phase_begin(player: String) -> void:
	# show the UI and reset state
	current_player = player
	gold_lbl.text = "%s Gold: %d" % [current_player, turn_mgr.player_gold[current_player]]
	income_lbl.text = "Income: %d" % turn_mgr.player_income[current_player]
	placing_unit  = ""
	$Panel.visible = true
	allow_clicks = true
	move_priority = 0

func _on_orders_phase_end() -> void:
	game_board.clear_highlights()
	$Panel.visible = false
	cancel_done_button.visible = false

func _on_archer_pressed():
	placing_unit = "archer"
	gold_lbl.text = "Click map to place Archer\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _on_soldier_pressed():
	placing_unit = "soldier"
	gold_lbl.text = "Click map to place Soldier\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _on_scout_pressed():
	placing_unit = "scout"
	gold_lbl.text = "Click map to place Scout\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _on_miner_pressed():
	placing_unit = "miner"
	gold_lbl.text = "Click map to place Miner\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _on_tank_pressed():
	placing_unit = "tank"
	gold_lbl.text = "Click map to place Tank\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _find_placeable():
	var base = game_board.get_unit_at(turn_mgr.base_positions[current_player])
	if dev_mode_toggle.button_pressed:
		action_mode = "dev_place"
	else:
		action_mode = "place"
	var result = game_board.get_reachable_tiles(base.grid_pos, 1, action_mode)
	var tiles = result["tiles"].slice(1)
	game_board.show_highlights(tiles)
	current_reachable = result

func _on_dev_mode_toggled(pressed:bool):
	print("Dev Mode → ", pressed)
	if pressed:
		dev_panel.visible = true
	else:
		dev_panel.visible = false

func _on_fog_toggled(pressed:bool):
	print("Fog of War -> ", pressed)
	if pressed:
		$"../GameBoardNode/FogOfWar".visible = true
		$"../GameBoardNode/ExploredFog".visible = true
	else:
		$"../GameBoardNode/FogOfWar".visible = false
		$"../GameBoardNode/ExploredFog".visible = false

func _on_give_income_pressed():
	for player in ["player1", "player2"]:
		turn_mgr.player_gold[player] += turn_mgr.player_income[player]
	gold_lbl.text = "%s Gold: %d" % [current_player, turn_mgr.player_gold[current_player]]
	

func _on_host_pressed():
	var port = $"PortLineEdit".text.strip_edges()
	NetworkManager.host_game(int(port))
	turn_mgr.local_player_id = "player1"
	$HostButton.visible = false
	$JoinButton.visible = false
	$IPLineEdit.visible = false
	$PortLineEdit.visible = false
	if not dev_mode_toggle.button_pressed:
		dev_mode_toggle.visible = false

func _on_join_pressed():
	var ip = $"IPLineEdit".text.strip_edges()
	var port = $"PortLineEdit".text.strip_edges()
	print("[UI] Joining game at %s:%d" % [ip, port])
	NetworkManager.join_game(ip, int(port))
	turn_mgr.local_player_id = "player2"
	$HostButton.visible = false
	$JoinButton.visible = false
	$IPLineEdit.visible = false
	$PortLineEdit.visible = false
	if not dev_mode_toggle.button_pressed:
		dev_mode_toggle.visible = false

func _on_unit_selected(unit: Node) -> void:
	game_board.clear_highlights()
	currently_selected_unit = unit
	# Show action selection menu
	action_menu.clear()
	action_menu.add_item("Move", 0)
	if not unit.just_purchased:
		if unit.is_ranged:
			action_menu.add_item("Ranged Attack", 1)
		if unit.can_melee:
			action_menu.add_item("Melee Attack", 2)
		#action_menu.add_item("Support", 3)
		action_menu.add_item("Heal", 4)
		action_menu.add_item("Defend", 5)

func _on_action_selected(id: int) -> void:
	currently_selected_unit.is_defending = false
	currently_selected_unit.is_healing = false
	currently_selected_unit.is_moving = false
	match id:
		0:
			action_mode = "move"
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, currently_selected_unit.move_range, action_mode)
			var tiles = result["tiles"].slice(1)
			game_board.show_highlights(tiles)
			current_reachable = result
			print("Move selected for %s" % currently_selected_unit.name)

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

		2:
			action_mode = "melee"
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, 1, action_mode)
			var tiles = result["tiles"]
			enemy_tiles = []
			for tile in tiles:
				if game_board.is_occupied(tile):
					var other_unit = game_board.get_unit_at(tile)
					if other_unit.player_id != current_player:
						enemy_tiles.append(tile)
			game_board.show_highlights(enemy_tiles)
			print("Melee Attack selected for %s" % currently_selected_unit.name)

		3:
			action_mode = "support"
			var result: Dictionary = {}
			if currently_selected_unit.is_ranged:
				result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, currently_selected_unit.ranged_range, action_mode)
			else:
				result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, 1, action_mode)
			var tiles = result["tiles"]
			support_tiles = []
			var orders = turn_mgr.get_all_orders(current_player)
			for order in orders:
				if order["type"] == "move":
					for tile in order["path"].slice(1):
						if tile in tiles:
							support_tiles.append(tile)
			game_board.show_highlights(support_tiles)
			print("Support selected for %s" % currently_selected_unit.name)
		4:
			print("Heal selected for %s" % currently_selected_unit.name)
			currently_selected_unit.is_healing = true
			turn_mgr.add_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "heal",
			})
			_draw_all()
		5:
			print("Defend selected for %s" % currently_selected_unit.name)
			turn_mgr.add_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "defend",
			})
			currently_selected_unit.is_defending = true
			_draw_all()
	action_menu.hide()

func _clear_all_drawings():
	for child in hex.get_node("PathArrows").get_children():
		child.queue_free()
	for child in hex.get_node("AttackArrows").get_children():
		child.queue_free()
	for child in hex.get_node("SupportArrows").get_children():
		child.queue_free()
	for child in hex.get_node("HealingSprites").get_children():
		child.queue_free()
	for child in hex.get_node("DefendingSprites").get_children():
		child.queue_free()

func _on_done_pressed():
	game_board.clear_highlights()
	#_clear_all_drawings()
	$Panel.visible = false
	cancel_done_button.visible = true
	var my_orders = turn_mgr.get_all_orders(current_player)
	NetworkManager.submit_orders(current_player, my_orders)
	# prevent further clicks
	placing_unit = ""
	allow_clicks = false

func _on_cancel_pressed():
	NetworkManager.cancel_orders(current_player)
	_draw_all()
	allow_clicks = true
	$Panel.visible = true
	cancel_done_button.visible = false

func _on_execution_paused(phase_idx):
	_current_exec_step_idx = phase_idx
	exec_panel.visible = true
	var phase_names = ["Unit Spawns", "Ranged Attacks","Melee","Movement"]
	if phase_idx >= phase_names.size():
		for i in range(phase_idx - phase_names.size()+1):
			phase_names.append("Movement")
	phase_label.text = "Processed: %s\n(Click Next to continue)" % phase_names[phase_idx]

func _on_next_pressed():
	exec_panel.visible = false
	print("[UI] Next pressed for step %d" % _current_exec_step_idx)
	NetworkManager.rpc("rpc_step_ready", _current_exec_step_idx)
	
	if get_tree().get_multiplayer().is_server():
		NetworkManager.rpc_step_ready(_current_exec_step_idx)

func _on_execution_complete():
	exec_panel.visible = false

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
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders(player)
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
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders(player)
		for order in all_orders:
			if order["type"] == "ranged" or order["type"] == "melee":
				var root = Node2D.new()
				attack_arrows_node.add_child(root)
				
				# calculate direction and size for attack arrow
				var attacker = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
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

func _draw_supports():
	var support_arrows_node = hex.get_node("SupportArrows")
	for child in support_arrows_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders(player)
		for order in all_orders:
			if order["type"] == "support":
				var root = Node2D.new()
				support_arrows_node.add_child(root)
				
				# calculate direction and size for support arrow
				var supporter = order["unit"]
				var p1 = hex.map_to_world(supporter.grid_pos) + hex.tile_size * 0.5
				var p2 = hex.map_to_world(order["target_tile"]) + hex.tile_size * 0.5
				var arrow = SupportArrowScene.instantiate() as Sprite2D
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

func _draw_heals():
	var heal_node = hex.get_node("HealingSprites")
	for child in heal_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders(player)
		for order in all_orders:
			if order["type"] == "heal":
				var root = Node2D.new()
				heal_node.add_child(root)
				var heart = HealScene.instantiate() as Sprite2D
				heart.position = hex.map_to_world(unit_mgr.get_unit_by_net_id(order["unit_net_id"]).grid_pos) + hex.tile_size * 0.65
				heart.z_index = 10
				root.add_child(heart)

func _draw_defends():
	var defend_node = hex.get_node("DefendingSprites")
	for child in defend_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders(player)
		for order in all_orders:
			if order["type"] == "defend":
				var root = Node2D.new()
				defend_node.add_child(root)
				var defend = DefendScene.instantiate() as Sprite2D
				defend.position = hex.map_to_world(unit_mgr.get_unit_by_net_id(order["unit_net_id"]).grid_pos) + hex.tile_size * 0.5
				defend.z_index = 0
				root.add_child(defend)

func _draw_all():
	_draw_attacks()
	_draw_heals()
	_draw_paths()
	_draw_supports()
	_draw_defends()

func _unhandled_input(ev):
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if not allow_clicks:
		return
	game_board.clear_highlights()
	var world_pos = get_viewport().get_camera_2d().get_global_mouse_position()
	var cell = hex.world_to_map(world_pos)

	if placing_unit != "":
		# Placement logic
		if cell in current_reachable["tiles"]:
			if turn_mgr.buy_unit(turn_mgr.local_player_id, placing_unit, cell):
				gold_lbl.text = "%s Gold: %d" % [current_player, turn_mgr.player_gold[current_player]]
				placing_unit = ""
			else:
				gold_lbl.text = "[Not enough gold]\nGold: %d" % turn_mgr.player_gold[current_player]
		else:
			gold_lbl.text = "[Can't place there]\nGold: %d" % turn_mgr.player_gold[current_player]
		return
	
	# Order phase: if waiting for destination (move mode)
	if action_mode == "move" and currently_selected_unit:
		var path = []
		# Only allow valid reachable cells
		if cell in current_reachable["tiles"] and cell != currently_selected_unit.grid_pos:
			path = calculate_path(cell)
			move_priority += 1
			currently_selected_unit.is_moving = true
			currently_selected_unit.moving_to = path[1]
			turn_mgr.add_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "move",
				"path": path,
				"priority": move_priority
			})
			_draw_all()
		action_mode = ""
		return
	
	if action_mode == "ranged" or action_mode == "melee" and currently_selected_unit:
		if cell in enemy_tiles:
			move_priority += 1
			if action_mode == "melee":
				currently_selected_unit.is_moving = true
				currently_selected_unit.moving_to = cell
			turn_mgr.add_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": action_mode,
				"target_tile": cell,
				"target_unit_net_id": game_board.get_unit_at(cell).net_id,
				"priority": move_priority
			})
		_draw_all()
		action_mode = ""
		return
	
	if action_mode == "support" and currently_selected_unit:
		if cell in support_tiles:
			turn_mgr.add_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": action_mode,
				"target_tile": cell
			})
		_draw_all()
		action_mode = ""
		return
	
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		# Unit selection in orders phase
		var unit = game_board.get_unit_at(cell)
		if unit:
			if unit.player_id == current_player:
				if unit.is_base:
					return
				if unit.is_tower:
					return
				if unit.just_purchased and not unit.first_turn_move:
					return
				_on_unit_selected(unit)
				action_menu.set_position(ev.position)
				action_menu.show()
