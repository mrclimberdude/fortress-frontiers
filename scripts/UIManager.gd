extends CanvasLayer

# configure these in the Inspector
@export var turn_manager_path: NodePath
@export var map_node_path:     NodePath

# runtime state
var current_player : String = ""
var placing_unit   : String = ""        # "archer" or "soldier"

@onready var turn_mgr = get_node(turn_manager_path) as Node
@onready var hex = $"../GameBoardNode/HexTileMap"
@onready var gold_lbl = $Panel/VBoxContainer/GoldLabel as Label

# Reference to your GameBoardNode
@onready var game_board: Node = get_node("../GameBoardNode")

# State for the currently-selected unit and its reachable tiles
var currently_selected_unit: Node = null
var current_reachable: Dictionary = {}

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


func _on_orders_phase_begin(player: String) -> void:
	# show the UI and reset state
	current_player = player
	gold_lbl.text = "Gold: %d" % turn_mgr.player_gold[current_player]
	placing_unit  = ""
	show()

func _on_orders_phase_end() -> void:
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
	var result = game_board.get_reachable_tiles(unit.grid_pos, unit.move_range)
	var tiles = result["tiles"]

	# 3) Show them
	game_board.show_highlights(tiles)

	# 4) Store for later path-drawing / order issuance
	currently_selected_unit = unit
	current_reachable = result

func _on_done_pressed():
	game_board.clear_highlights()
	# signal back to TurnManager that this player is finished
	turn_mgr.submit_player_order(current_player, {"action":"done"})
	# prevent further clicks
	placing_unit = ""

func _unhandled_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		# Convert screen click → world → map cell
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
		elif turn_mgr.current_phase == $"..".Phase.ORDERS:
			# Unit selection in orders phase
			var unit = game_board.get_unit_at(cell)
			if unit:
				_on_unit_selected(unit)
