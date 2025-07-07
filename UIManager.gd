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

func _ready():
	hide()

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

func _on_done_pressed():
	# signal back to TurnManager that this player is finished
	turn_mgr.submit_player_order(current_player, {"action":"done"})
	# prevent further clicks
	placing_unit = ""

func _unhandled_input(ev):
	if placing_unit != "" and ev is InputEventMouseButton \
	and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:

		# 1) Screen → world (includes Camera2D pan/zoom)
		var world_pos = get_viewport().get_camera_2d().get_global_mouse_position()

		# 2) World → map‐layer’s local → cell
		var cell = hex.world_to_map(world_pos)
		print("click → cell", cell)

		# 3) place & color
		if turn_mgr.buy_unit(current_player, placing_unit, cell):
			gold_lbl.text = "Gold: %d" % turn_mgr.player_gold[current_player]
			placing_unit = ""
		else:
			gold_lbl.text = "[Not enough gold]\nGold: %d" % turn_mgr.player_gold[current_player]
