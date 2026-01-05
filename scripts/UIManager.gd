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
var current_path: Array = []
var remaining_moves: float = 0.0
var repair_tiles: Array = []
var action_mode:       String   = ""     # "move", "ranged", "melee", "support", "hold", "repair"
var move_priority: int = 0
var allow_clicks: bool = true
var last_click_pos: Vector2 = Vector2.ZERO
var _build_hover_root: Node2D = null
var _build_hover_label: Label = null
var _build_hover_cell: Vector2i = Vector2i(-99999, -99999)

var _current_exec_step_idx: int = 0
var menu_popup: PopupMenu = null
var save_slot_index: int = 0
var damage_panel_minimized: bool = false
var damage_panel_full_size: Vector2 = Vector2.ZERO
var damage_panel_full_position: Vector2 = Vector2.ZERO
var auto_pass_enabled: bool = false
var last_damage_log_count: int = 0
var done_button_default_modulate: Color = Color(1, 1, 1)

@onready var turn_mgr = get_node(turn_manager_path) as Node
@onready var unit_mgr = get_node(unit_manager_path) as Node
@onready var game_board: Node = get_node("../GameBoardNode")
@onready var hex = $"../GameBoardNode/HexTileMap"
@onready var gold_lbl = $Panel/VBoxContainer/GoldLabel as Label
@onready var income_lbl = $Panel/VBoxContainer/IncomeLabel as Label
@onready var action_menu: PopupMenu      = $Panel/ActionMenu as PopupMenu
@onready var build_menu: PopupMenu = PopupMenu.new()
@onready var exec_panel: PanelContainer  = $ExecutionPanel
@onready var phase_label   : Label       = exec_panel.get_node("ExecutionBox/PhaseLabel")
@onready var next_button   : Button      = exec_panel.get_node("ExecutionBox/ControlsRow/NextButton")
@onready var auto_pass_check = $ExecutionPanel/ExecutionBox/ControlsRow/AutoPassCheckButton as CheckButton
@onready var done_button = $Panel/VBoxContainer/DoneButton as Button
@onready var cancel_done_button = $CancelDoneButton as Button
@onready var dev_mode_toggle = get_node(dev_mode_toggle_path) as CheckButton
@onready var dev_panel = $DevPanel
@onready var respawn_timers_toggle = $DevPanel/VBoxContainer/RespawnTimersCheckButton as CheckButton
@onready var resync_button = $DevPanel/VBoxContainer/ResyncButton as Button
@onready var menu_button = $MenuButton as MenuButton
@onready var damage_panel = $DamagePanel as Panel
@onready var damage_scroll = $DamagePanel/ScrollContainer as ScrollContainer
@onready var damage_toggle_button = $DamagePanel/ToggleDamageButton as Button
@onready var finish_move_button = $Panel/FinishMoveButton

const ArrowScene = preload("res://scenes/Arrow.tscn")
const AttackArrowScene = preload("res://scenes/AttackArrow.tscn")
const SupportArrowScene = preload("res://scenes/SupportArrow.tscn")
const HealScene = preload("res://scenes/Healing.tscn")
const DefendScene = preload("res://scenes/Defending.tscn")
const BuildIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_162.png")
const RepairIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_141.png")
const SabotageIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_180.png")
const LookoutIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_134.png")
const SAVE_SLOT_COUNT_UI: int = 3

const MENU_ID_SAVE: int = 1
const MENU_ID_LOAD: int = 2
const MENU_ID_LOAD_AUTOSAVE: int = 3
const MENU_ID_UNIT_STATS: int = 10
const MENU_ID_BUILDING_STATS: int = 11
const MENU_ID_DEV_MODE: int = 12
const MENU_ID_QUIT: int = 13
const MENU_ID_SLOT_BASE: int = 100

const BUILD_OPTIONS = [
	{"id": 0, "label": "Fortification", "type": "fortification"},
	{"id": 1, "label": "Road", "type": "road"},
	{"id": 2, "label": "Railroad", "type": "rail"},
	{"id": 3, "label": "Spawn Tower", "type": "spawn_tower"},
	{"id": 4, "label": "Trap", "type": "trap"}
]

const ArcherScene = preload("res://scenes/Archer.tscn")
const SoldierScene = preload("res://scenes/Soldier.tscn")
const ScoutScene = preload("res://scenes/Scout.tscn")
const MinerScene = preload("res://scenes/Miner.tscn")
const PhalanxScene = preload("res://scenes/Tank.tscn")
const CavalryScene = preload("res://scenes/Cavalry.tscn")
const BuilderScene = preload("res://scenes/Builder.tscn")
const CampArcherScene = preload("res://scenes/CampArcher.tscn")
const DragonScene = preload("res://scenes/Dragon.tscn")

const MineScene = preload("res://scenes/GemMine.tscn")

func _ready():
	# Enable unhandled input processing
	set_process_unhandled_input(true)
	set_process(true)
	
	$HostButton.connect("pressed",
					Callable(self, "_on_host_pressed"))
	$JoinButton.connect("pressed",
					Callable(self, "_on_join_pressed"))
	$CancelGameButton.connect("pressed",
					Callable(self, "_on_cancel_game_pressed"))
	
	# dev mode connections
	dev_mode_toggle.connect("toggled",
					Callable(self, "_on_dev_mode_toggled"))
	$DevPanel/VBoxContainer/FogCheckButton.connect("toggled",
					 Callable(self, "_on_fog_toggled"))
	$DevPanel/VBoxContainer/GiveIncomeButton.connect("pressed",
					 Callable(self, "_on_give_income_pressed"))
	$DevPanel/VBoxContainer/RespawnTimersCheckButton.connect("toggled",
					 Callable(self, "_on_respawn_timers_toggled"))
	$DevPanel/VBoxContainer/ResyncButton.connect("pressed",
					 Callable(self, "_on_resync_pressed"))
	if damage_toggle_button != null:
		damage_toggle_button.connect("pressed",
					 Callable(self, "_on_damage_toggle_pressed"))
	NetworkManager.connect("buy_result",
					Callable(self, "_on_buy_result"))
	NetworkManager.connect("undo_result",
					Callable(self, "_on_undo_result"))
	NetworkManager.connect("order_result",
					Callable(self, "_on_order_result"))
	
	# turn flow connections
	turn_mgr.connect("orders_phase_begin",
					Callable(self, "_on_orders_phase_begin"))
	turn_mgr.connect("orders_phase_end",
					Callable(self, "_on_orders_phase_end"))
	turn_mgr.connect("state_applied",
					Callable(self, "_on_state_applied"))
	turn_mgr.connect("execution_paused",
					Callable(self, "_on_execution_paused"))
	turn_mgr.connect("execution_complete",
					Callable(self, "_on_execution_complete"))
	next_button.connect("pressed",
					Callable(self, "_on_next_pressed"))
	if auto_pass_check != null:
		auto_pass_check.connect("toggled",
					Callable(self, "_on_auto_pass_toggled"))
	
	# order button connections
	$Panel/VBoxContainer/ArcherButton.connect("pressed",
					 Callable(self, "_on_archer_pressed"))
	$Panel/VBoxContainer/SoldierButton.connect("pressed",
					 Callable(self, "_on_soldier_pressed"))
	$Panel/VBoxContainer/ScoutButton.connect("pressed",
					 Callable(self, "_on_scout_pressed"))
	$Panel/VBoxContainer/MinerButton.connect("pressed",
					 Callable(self, "_on_miner_pressed"))
	$Panel/VBoxContainer/BuilderButton.connect("pressed",
					 Callable(self, "_on_builder_pressed"))
	$Panel/VBoxContainer/PhalanxButton.connect("pressed",
					 Callable(self, "_on_tank_pressed"))
	$Panel/VBoxContainer/CavalryButton.connect("pressed",
					 Callable(self, "_on_cavalry_pressed"))
	$Panel/VBoxContainer/DoneButton.connect("pressed",
					 Callable(self, "_on_done_pressed"))
	$CancelDoneButton.connect("pressed",
					 Callable(self, "_on_cancel_pressed"))
	if done_button != null:
		done_button_default_modulate = done_button.self_modulate
	$UnitStatsCheckButton.connect("toggled",
					Callable(self, "_on_stats_toggled"))
	$BuildingStatsCheckButton.connect("toggled",
					Callable(self, "_on_building_stats_toggled"))
	$StatsPanel/CloseButton.connect("pressed",
					Callable(self, "_on_unit_stats_close_pressed"))
	$BuildingStatsPanel/CloseButton.connect("pressed",
					Callable(self, "_on_building_stats_close_pressed"))
	$Panel/FinishMoveButton.connect("pressed",
					Callable(self, "_on_finish_move_button_pressed"))
	
	# setting gold labels and stats for units
	var base_font: FontFile = load("res://fonts/JetBrainsMono-Medium.ttf")
	var unit_scenes = [ScoutScene, SoldierScene, MinerScene, BuilderScene, ArcherScene, PhalanxScene, CavalryScene]
	var unit_names = ["Scout", "Soldier", "Miner", "Builder", "Archer", "Phalanx", "Cavalry"]
	var unit_buy_buttons = [$Panel/VBoxContainer/ScoutButton,
							$Panel/VBoxContainer/SoldierButton,
							$Panel/VBoxContainer/MinerButton,
							$Panel/VBoxContainer/BuilderButton,
							$Panel/VBoxContainer/ArcherButton,
							$Panel/VBoxContainer/PhalanxButton,
							$Panel/VBoxContainer/CavalryButton]
	var unit_container = $StatsPanel/VBoxContainer
	var unit_col_widths = [80.0, 60.0, 60.0, 60.0, 60.0]
	_add_unit_stats_row(unit_container, ["Unit", "Melee", "Ranged", "Move", "Regen", "Special"], unit_col_widths, base_font, true, true)
	var temp
	for i in range(unit_scenes.size()):
		temp = unit_scenes[i].instantiate()
		unit_buy_buttons[i].text = "Buy %s (%dG)" % [unit_names[i], temp.cost]
		_add_unit_stats_row(
			unit_container,
			[unit_names[i], str(temp.melee_strength), str(temp.ranged_strength), str(temp.move_range), str(temp.regen), temp.special_skills],
			unit_col_widths,
			base_font,
			true,
			i < unit_scenes.size() - 1
		)
	temp.free()

	_add_unit_stats_row(unit_container, ["Neutral Units", "", "", "", "", ""], unit_col_widths, base_font, true, true)
	var neutral_scenes = [CampArcherScene, DragonScene]
	var neutral_names = ["Camp\nArcher", "Dragon"]
	var neutral_specials = ["", "Ranged fire; melee cleave"]
	for i in range(neutral_scenes.size()):
		temp = neutral_scenes[i].instantiate()
		var special_text = neutral_specials[i]
		if special_text == "":
			special_text = temp.special_skills
		_add_unit_stats_row(
			unit_container,
			[neutral_names[i], str(temp.melee_strength), str(temp.ranged_strength), str(temp.move_range), str(temp.regen), special_text],
			unit_col_widths,
			base_font,
			true,
			i < neutral_scenes.size() - 1
		)
		temp.free()

	var build_container = $BuildingStatsPanel/VBoxContainer
	var build_col_widths = [140.0, 90.0, 60.0]
	_add_build_stats_row(build_container, ["Building", "Cost", "Turns", "Effect"], build_col_widths, base_font, true, true)
	var short_turns = int(turn_mgr.BUILD_TURNS_SHORT)
	var tower_turns = int(turn_mgr.BUILD_TURNS_TOWER)
	var fort_bonus = "%d/%d" % [turn_mgr.fort_melee_bonus, turn_mgr.fort_ranged_bonus]
	var build_rows = [
		{"name": "Fortification", "cost": turn_mgr.get_build_turn_cost("fortification"), "turns": short_turns, "effect": "+%s melee/ranged" % fort_bonus},
		{"name": "Road", "cost": turn_mgr.get_build_turn_cost("road"), "turns": short_turns, "effect": "Move x0.5; +1 turn on river"},
		{"name": "Railroad", "cost": turn_mgr.get_build_turn_cost("rail"), "turns": short_turns, "effect": "Move x0.25; upgrade road; +1 turn on river"},
		{"name": "Spawn Tower", "cost": turn_mgr.get_build_turn_cost("spawn_tower"), "turns": tower_turns, "effect": "Spawns units; needs road link"},
		{"name": "Trap", "cost": turn_mgr.get_build_turn_cost("trap"), "turns": short_turns, "effect": "Hidden; triggered by enemy: becomes disabled, stops movement, deals 30 dmg"}
	]
	for i in range(build_rows.size()):
		var row = build_rows[i]
		var add_sep = i < build_rows.size() - 1
		_add_build_stats_row(
			build_container,
			[row["name"], "%dg/step" % int(row["cost"]), str(row["turns"]), row["effect"]],
			build_col_widths,
			base_font,
			true,
			add_sep
		)
	
	# unit order menu
	action_menu.connect("id_pressed", Callable(self, "_on_action_selected"))
	action_menu.hide()
	build_menu.name = "BuildMenu"
	add_child(build_menu)
	build_menu.connect("id_pressed", Callable(self, "_on_build_selected"))
	build_menu.hide()
	for entry in BUILD_OPTIONS:
		build_menu.add_item(entry["label"], entry["id"])
	_init_build_hover()
	_init_menu()

func _init_menu() -> void:
	if menu_button == null:
		return
	menu_popup = menu_button.get_popup()
	menu_popup.clear()
	menu_popup.add_item("Save", MENU_ID_SAVE)
	menu_popup.add_item("Load", MENU_ID_LOAD)
	menu_popup.add_item("Load Autosave", MENU_ID_LOAD_AUTOSAVE)
	menu_popup.add_separator()
	menu_popup.add_check_item("Unit Stats", MENU_ID_UNIT_STATS)
	menu_popup.add_check_item("Building Stats", MENU_ID_BUILDING_STATS)
	menu_popup.add_check_item("Dev Mode", MENU_ID_DEV_MODE)
	menu_popup.add_separator()
	for i in range(SAVE_SLOT_COUNT_UI):
		menu_popup.add_radio_check_item("Save Slot %d" % (i + 1), MENU_ID_SLOT_BASE + i)
	menu_popup.add_separator()
	menu_popup.add_item("Quit to Lobby", MENU_ID_QUIT)
	_sync_menu_checks()
	menu_popup.connect("id_pressed", Callable(self, "_on_menu_id_pressed"))
	damage_panel_full_size = damage_panel.size
	damage_panel_full_position = damage_panel.position
	_update_damage_panel()

func _sync_menu_checks() -> void:
	if menu_popup == null:
		return
	_set_menu_checked(MENU_ID_UNIT_STATS, $StatsPanel.visible)
	_set_menu_checked(MENU_ID_BUILDING_STATS, $BuildingStatsPanel.visible)
	_set_menu_checked(MENU_ID_DEV_MODE, dev_mode_toggle.button_pressed)
	for i in range(SAVE_SLOT_COUNT_UI):
		_set_menu_checked(MENU_ID_SLOT_BASE + i, i == save_slot_index)

func _set_menu_checked(id: int, checked: bool) -> void:
	if menu_popup == null:
		return
	var idx = menu_popup.get_item_index(id)
	if idx >= 0:
		menu_popup.set_item_checked(idx, checked)

func _should_draw_unit(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit.player_id == turn_mgr.local_player_id:
		return true
	return unit.visible

func _on_menu_id_pressed(id: int) -> void:
	if id == MENU_ID_SAVE:
		_on_save_game_pressed()
		return
	if id == MENU_ID_LOAD:
		_on_load_game_pressed()
		return
	if id == MENU_ID_LOAD_AUTOSAVE:
		_on_load_autosave_pressed()
		return
	if id == MENU_ID_UNIT_STATS:
		var next = not $StatsPanel.visible
		if $UnitStatsCheckButton.has_method("set_pressed_no_signal"):
			$UnitStatsCheckButton.set_pressed_no_signal(next)
		else:
			$UnitStatsCheckButton.button_pressed = next
		_on_stats_toggled(next)
		return
	if id == MENU_ID_BUILDING_STATS:
		var next = not $BuildingStatsPanel.visible
		if $BuildingStatsCheckButton.has_method("set_pressed_no_signal"):
			$BuildingStatsCheckButton.set_pressed_no_signal(next)
		else:
			$BuildingStatsCheckButton.button_pressed = next
		_on_building_stats_toggled(next)
		return
	if id == MENU_ID_DEV_MODE:
		var next = not dev_mode_toggle.button_pressed
		if dev_mode_toggle.has_method("set_pressed_no_signal"):
			dev_mode_toggle.set_pressed_no_signal(next)
		else:
			dev_mode_toggle.button_pressed = next
		_on_dev_mode_toggled(next)
		_set_menu_checked(MENU_ID_DEV_MODE, next)
		return
	if id == MENU_ID_QUIT:
		_on_cancel_game_pressed()
		return
	if id >= MENU_ID_SLOT_BASE and id < MENU_ID_SLOT_BASE + SAVE_SLOT_COUNT_UI:
		save_slot_index = id - MENU_ID_SLOT_BASE
		_sync_menu_checks()

func _add_build_stats_row(container: VBoxContainer, columns: Array, widths: Array, font: FontFile, wrap_last: bool, add_separator: bool = true) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(row)
	for i in range(columns.size()):
		var col_label = Label.new()
		col_label.add_theme_font_override("font", font)
		col_label.text = str(columns[i])
		if i == columns.size() - 1 and wrap_last:
			col_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			col_label.custom_minimum_size = Vector2(float(widths[i]), 0.0)
			col_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(col_label)
	if add_separator:
		var sep = HSeparator.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sep.custom_minimum_size = Vector2(0.0, 2.0)
		container.add_child(sep)

func _add_unit_stats_row(container: VBoxContainer, columns: Array, widths: Array, font: FontFile, wrap_last: bool, add_separator: bool = true) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(row)
	for i in range(columns.size()):
		var col_label = Label.new()
		col_label.add_theme_font_override("font", font)
		col_label.text = str(columns[i])
		if i == columns.size() - 1 and wrap_last:
			col_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			col_label.custom_minimum_size = Vector2(float(widths[i]), 0.0)
			col_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(col_label)
	if add_separator:
		var sep = HSeparator.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sep.custom_minimum_size = Vector2(0.0, 2.0)
		container.add_child(sep)

func _init_build_hover() -> void:
	_build_hover_root = Node2D.new()
	_build_hover_root.name = "BuildHover"
	_build_hover_root.z_index = 12
	hex.add_child(_build_hover_root)
	_build_hover_label = Label.new()
	_build_hover_label.visible = false
	_build_hover_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.2))
	_build_hover_label.add_theme_font_size_override("font_size", 14)
	_build_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_build_hover_label.z_index = 12
	_build_hover_root.add_child(_build_hover_label)

func _process(_delta: float) -> void:
	_update_build_hover()

func _update_build_hover() -> void:
	if _build_hover_label == null:
		return
	var cam = get_viewport().get_camera_2d()
	if cam == null:
		_hide_build_hover()
		return
	var world_pos = cam.get_global_mouse_position()
	var cell = hex.world_to_map(world_pos)
	var text = turn_mgr.get_build_hover_text(cell)
	if text == "":
		_hide_build_hover()
		return
	_build_hover_cell = cell
	var tile_size = hex.tile_size
	_build_hover_label.text = text
	_build_hover_label.size = Vector2(tile_size.x, tile_size.y * 0.25)
	_build_hover_label.position = hex.map_to_world(cell) + Vector2(0, tile_size.y * 0.05)
	_build_hover_label.visible = true

func _hide_build_hover() -> void:
	_build_hover_cell = Vector2i(-99999, -99999)
	if _build_hover_label != null:
		_build_hover_label.visible = false

func _refresh_build_menu_labels() -> void:
	for entry in BUILD_OPTIONS:
		var label = entry["label"]
		var cost = int(turn_mgr.get_build_turn_cost(entry["type"]))
		if cost > 0:
			label = "%s (%dg/step)" % [label, cost]
		var idx = -1
		for i in range(build_menu.get_item_count()):
			if build_menu.get_item_id(i) == entry["id"]:
				idx = i
				break
		if idx >= 0:
			build_menu.set_item_text(idx, label)
	

func _on_orders_phase_begin(player: String) -> void:
	# show the UI and reset state
	current_player = player
	gold_lbl.text = "Current Gold: %d" % [turn_mgr.player_gold[current_player]]
	income_lbl.text = "Income: %d per turn" % turn_mgr.player_income[current_player]
	placing_unit  = ""
	$Panel.visible = true
	allow_clicks = true
	move_priority = 0
	_update_done_button_state()

func _on_orders_phase_end() -> void:
	game_board.clear_highlights()
	$"../GameBoardNode/OrderReminderMap".clear()
	$Panel.visible = false
	cancel_done_button.visible = false
	_update_done_button_state()

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

func _on_builder_pressed():
	placing_unit = "builder"
	gold_lbl.text = "Click map to place Builder\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _on_tank_pressed():
	placing_unit = "phalanx"
	gold_lbl.text = "Click map to place Phalanx\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _on_cavalry_pressed():
	placing_unit = "cavalry"
	gold_lbl.text = "Click map to place cavalry\nGold: %d" % turn_mgr.player_gold[current_player]
	_find_placeable()

func _find_placeable():
	var base = game_board.get_structure_unit_at(turn_mgr.base_positions[current_player])
	if dev_mode_toggle.button_pressed:
		action_mode = "dev_place"
	else:
		action_mode = "place"
	var result = game_board.get_reachable_tiles(base.grid_pos, 1, action_mode)
	var tiles = result["tiles"]
	game_board.show_highlights(tiles)
	current_reachable = result

func _on_dev_mode_toggled(pressed:bool):
	print("Dev Mode → ", pressed)
	if pressed:
		dev_panel.visible = true
	else:
		dev_panel.visible = false
		respawn_timers_toggle.button_pressed = false
		_on_respawn_timers_toggled(false)
	_set_menu_checked(MENU_ID_DEV_MODE, pressed)

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

func _on_respawn_timers_toggled(pressed: bool) -> void:
	turn_mgr.set_respawn_timer_override(pressed)

func _on_resync_pressed() -> void:
	NetworkManager.request_state()

func _on_damage_toggle_pressed() -> void:
	damage_panel_minimized = not damage_panel_minimized
	_update_damage_panel()

func _update_damage_panel() -> void:
	if damage_scroll == null or damage_panel == null:
		return
	var header_height = 26.0
	if damage_panel_minimized:
		damage_scroll.visible = false
		damage_panel.custom_minimum_size = Vector2(damage_panel_full_size.x, header_height)
		damage_panel.size = Vector2(damage_panel_full_size.x, header_height)
		damage_panel.position = Vector2(
			damage_panel_full_position.x,
			damage_panel_full_position.y + damage_panel_full_size.y - header_height
		)
		damage_toggle_button.text = "+"
	else:
		damage_scroll.visible = true
		damage_panel.custom_minimum_size = Vector2.ZERO
		damage_panel.size = damage_panel_full_size
		damage_panel.position = damage_panel_full_position
		damage_toggle_button.text = "-"

func _on_auto_pass_toggled(pressed: bool) -> void:
	auto_pass_enabled = pressed
	last_damage_log_count = _damage_log_count()

func _damage_log_count() -> int:
	if turn_mgr == null:
		return 0
	var local_id = turn_mgr.local_player_id
	if local_id == "":
		return 0
	var lines = turn_mgr.damage_log.get(local_id, [])
	return lines.size()

func _update_auto_pass_for_damage() -> void:
	if not auto_pass_enabled:
		last_damage_log_count = _damage_log_count()
		return
	var current = _damage_log_count()
	if current > last_damage_log_count:
		auto_pass_enabled = false
		if auto_pass_check != null:
			if auto_pass_check.has_method("set_pressed_no_signal"):
				auto_pass_check.set_pressed_no_signal(false)
			else:
				auto_pass_check.button_pressed = false
	last_damage_log_count = current

func _has_unordered_units(player_id: String) -> bool:
	if player_id == "":
		return false
	if game_board == null:
		return false
	var all_units = game_board.get_all_units()
	var units = all_units.get(player_id, [])
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.is_base or unit.is_tower:
			continue
		if unit.just_purchased:
			continue
		if not unit.ordered:
			return true
	return false

func _update_done_button_state() -> void:
	if done_button == null:
		return
	if turn_mgr == null:
		done_button.self_modulate = done_button_default_modulate
		return
	if not $Panel.visible or turn_mgr.current_phase != turn_mgr.Phase.ORDERS:
		done_button.self_modulate = done_button_default_modulate
		return
	if _has_unordered_units(current_player):
		done_button.self_modulate = Color(1.0, 0.6, 0.6)
	else:
		done_button.self_modulate = done_button_default_modulate

func _auto_pass_continue() -> void:
	if not auto_pass_enabled:
		return
	if not exec_panel.visible:
		return
	_auto_pass_step()

func _auto_pass_step() -> void:
	await get_tree().create_timer(1.0).timeout
	if auto_pass_enabled and exec_panel.visible:
		_on_next_pressed()

func _on_save_game_pressed() -> void:
	if not turn_mgr.is_host():
		gold_lbl.text = "[Save failed: host only]"
		return
	if turn_mgr.save_game_slot(save_slot_index):
		gold_lbl.text = "Game saved (slot %d)" % (save_slot_index + 1)
	else:
		gold_lbl.text = "[Save failed]"

func _on_load_game_pressed() -> void:
	if not turn_mgr.is_host():
		gold_lbl.text = "[Load failed: host only]"
		return
	if turn_mgr.load_game_slot(save_slot_index):
		gold_lbl.text = "Game loaded (slot %d)" % (save_slot_index + 1)
	else:
		gold_lbl.text = "[Load failed]"

func _on_load_autosave_pressed() -> void:
	if not turn_mgr.is_host():
		gold_lbl.text = "[Load failed: host only]"
		return
	if turn_mgr.load_game_slot(-1):
		gold_lbl.text = "Autosave loaded"
	else:
		gold_lbl.text = "[Load failed]"

func _buy_error_message(reason: String, cost: int) -> String:
	var msg := ""
	match reason:
		"not_enough_gold":
			if cost > 0:
				msg = "[Not enough gold] Need %d" % cost
			else:
				msg = "[Not enough gold]"
		"unknown_unit":
			msg = "[Unknown unit]"
		_:
			msg = "[Purchase failed]"
	return _format_error_with_gold(msg)

func _undo_error_message(reason: String) -> String:
	var msg := ""
	match reason:
		"not_owner":
			msg = "[Undo failed: not owner]"
		"not_just_purchased":
			msg = "[Undo failed: not a fresh buy]"
		"not_found":
			msg = "[Undo failed: unit missing]"
		_:
			msg = "[Undo failed]"
	return _format_error_with_gold(msg)

func _order_error_message(reason: String) -> String:
	var msg := ""
	match reason:
		"wrong_phase":
			msg = "[Orders closed]"
		"not_owner":
			msg = "[Order failed: not owner]"
		"not_builder":
			msg = "[Order failed: builder only]"
		"unit_missing":
			msg = "[Order failed: unit missing]"
		"invalid_unit":
			msg = "[Order failed: invalid unit]"
		"invalid_path":
			msg = "[Order failed: invalid path]"
		"invalid_target":
			msg = "[Order failed: invalid target]"
		"invalid_structure":
			msg = "[Order failed: invalid structure]"
		"invalid_tile":
			msg = "[Order failed: invalid tile]"
		"out_of_range":
			msg = "[Order failed: out of range]"
		"not_ready":
			msg = "[Order failed: unit not ready]"
		"not_enough_gold":
			msg = "[Order failed: not enough gold]"
		_:
			msg = "[Order failed]"
	return _format_error_with_gold(msg)

func _format_error_with_gold(message: String) -> String:
	if turn_mgr == null or current_player == "":
		return message
	var gold = turn_mgr.player_gold.get(current_player, 0)
	return "%s\nGold: %d" % [message, gold]

func _on_buy_result(player_id: String, unit_type: String, grid_pos: Vector2i, ok: bool, reason: String, cost: int) -> void:
	if player_id != turn_mgr.local_player_id:
		return
	if turn_mgr.is_host():
		return
	if ok:
		gold_lbl.text = "%s Gold: %d" % [current_player, turn_mgr.player_gold[current_player]]
	else:
		gold_lbl.text = _buy_error_message(reason, cost)

func _on_undo_result(player_id: String, unit_net_id: int, ok: bool, reason: String, refund: int) -> void:
	if player_id != turn_mgr.local_player_id:
		return
	if turn_mgr.is_host():
		return
	if ok:
		gold_lbl.text = "%s Gold: %d" % [current_player, turn_mgr.player_gold[current_player]]
	else:
		gold_lbl.text = _undo_error_message(reason)

func _on_order_result(player_id: String, unit_net_id: int, order: Dictionary, ok: bool, reason: String) -> void:
	if player_id != turn_mgr.local_player_id:
		return
	if ok:
		turn_mgr.player_orders[player_id][unit_net_id] = order
		NetworkManager.player_orders[player_id][unit_net_id] = order
		var unit = unit_mgr.get_unit_by_net_id(unit_net_id)
		if unit != null:
			unit.is_defending = false
			unit.is_healing = false
			unit.is_moving = false
			match order.get("type", ""):
				"move":
					unit.is_moving = true
					var path = order.get("path", [])
					if path.size() > 1:
						unit.moving_to = path[1]
				"heal":
					unit.is_healing = true
				"defend":
					unit.is_defending = true
			unit.ordered = true
		_draw_all()
		$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
		_update_done_button_state()
	else:
		gold_lbl.text = _order_error_message(reason)
	

func _on_host_pressed():
	var port = $"PortLineEdit".text.strip_edges()
	NetworkManager.host_game(int(port))
	turn_mgr.local_player_id = "player1"
	$HostButton.visible = false
	$JoinButton.visible = false
	$IPLineEdit.visible = false
	$PortLineEdit.visible = false
	$CancelGameButton.visible = true

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
	$CancelGameButton.visible = true

func _on_cancel_game_pressed():
	$HostButton.visible = true
	$JoinButton.visible = true
	$IPLineEdit.visible = true
	$PortLineEdit.visible = true
	$CancelGameButton.visible = false
	$Panel.visible = false
	cancel_done_button.visible = false
	turn_mgr.reset_to_lobby()
	_reset_ui_for_snapshot()
	_on_stats_toggled(false)
	_on_building_stats_toggled(false)
	_update_done_button_state()
	NetworkManager.close_connection()

func _on_finish_move_button_pressed():
	finish_current_path()

func _on_stats_toggled(toggled):
	if toggled:
		$StatsPanel.visible = true
	else:
		$StatsPanel.visible = false
	_set_menu_checked(MENU_ID_UNIT_STATS, toggled)

func _on_building_stats_toggled(toggled):
	if toggled:
		$BuildingStatsPanel.visible = true
	else:
		$BuildingStatsPanel.visible = false
	_set_menu_checked(MENU_ID_BUILDING_STATS, toggled)

func _on_unit_stats_close_pressed() -> void:
	$StatsPanel.visible = false
	$UnitStatsCheckButton.button_pressed = false
	_set_menu_checked(MENU_ID_UNIT_STATS, false)

func _on_building_stats_close_pressed() -> void:
	$BuildingStatsPanel.visible = false
	$BuildingStatsCheckButton.button_pressed = false
	_set_menu_checked(MENU_ID_BUILDING_STATS, false)

func _on_unit_selected(unit: Node) -> void:
	game_board.clear_highlights()
	currently_selected_unit = unit
	# Show action selection menu
	action_menu.clear()
	if unit.just_purchased:
		action_menu.add_item("Undo Buy", 0)
		if unit.first_turn_move:
			action_menu.add_item("Move", 1)
		return
	action_menu.add_item("Move", 1)
	if unit.is_ranged:
		action_menu.add_item("Ranged Attack", 2)
	if unit.can_melee:
		action_menu.add_item("Melee Attack", 3)
	action_menu.add_item("Heal", 4)
	action_menu.add_item("Defend", 5)
	if str(unit.unit_type).to_lower() == "scout":
		action_menu.add_item("Lookout", 9)
	action_menu.add_item("Sabotage", 6)
	if unit.is_builder:
		action_menu.add_item("Build", 7)
		action_menu.add_item("Repair", 8)

func _on_action_selected(id: int) -> void:
	if currently_selected_unit == null or not is_instance_valid(currently_selected_unit):
		action_menu.hide()
		return
	match id:
		0:
			var player_id = currently_selected_unit.player_id
			var unit_id = currently_selected_unit.net_id
			if turn_mgr.is_host():
				if NetworkManager.request_undo_buy(player_id, unit_id):
					gold_lbl.text = "%s Gold: %d" % [current_player, turn_mgr.player_gold[current_player]]
			else:
				NetworkManager.request_undo_buy(player_id, unit_id)
			currently_selected_unit = null
			$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
			_update_done_button_state()
		1:
			action_mode = "move"
			current_path = [currently_selected_unit.grid_pos]
			remaining_moves = float(currently_selected_unit.move_range)
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, currently_selected_unit.move_range, action_mode)
			var tiles = result["tiles"].slice(1)
			game_board.show_highlights(tiles)
			current_reachable = result
			print("Move selected for %s" % currently_selected_unit.name)
		
		2:
			action_mode = "ranged"
			var ranged_range = turn_mgr.get_effective_ranged_range(currently_selected_unit)
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, ranged_range, action_mode)
			var tiles = result["tiles"]
			enemy_tiles = []
			for tile in tiles:
				var target = game_board.get_primary_attack_target(tile, current_player)
				if target != null:
					enemy_tiles.append(tile)
			game_board.show_highlights(enemy_tiles)
			print("Ranged Attack selected for %s" % currently_selected_unit.name)
		
		3:
			action_mode = "melee"
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, 1, action_mode)
			var tiles = result["tiles"]
			enemy_tiles = []
			for tile in tiles:
				var target = game_board.get_primary_attack_target(tile, current_player)
				if target != null:
					enemy_tiles.append(tile)
			game_board.show_highlights(enemy_tiles)
			print("Melee Attack selected for %s" % currently_selected_unit.name)
		
		4:
			print("Heal selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "heal",
			})
			action_mode = ""
		
		5:
			print("Defend selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "defend",
			})
			action_mode = ""
		9:
			print("Lookout selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "lookout",
			})
			action_mode = ""
		6:
			print("Sabotage selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "sabotage",
				"target_tile": currently_selected_unit.grid_pos
			})
			action_mode = ""
		7:
			print("Build selected for %s" % currently_selected_unit.name)
			_refresh_build_menu_labels()
			build_menu.set_position(last_click_pos)
			build_menu.popup()
		8:
			print("Repair selected for %s" % currently_selected_unit.name)
			if not _has_repair_target_here(currently_selected_unit):
				gold_lbl.text = "[Nothing to repair]"
				action_menu.hide()
				return
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "repair",
				"target_tile": currently_selected_unit.grid_pos
			})
			action_mode = ""
	action_menu.hide()

func _clear_all_drawings():
	var preview_node = hex.get_node_or_null("PreviewPathArrows")
	if preview_node != null:
		for child in preview_node.get_children():
			child.queue_free()
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
	var lookout_node = hex.get_node_or_null("LookoutSprites")
	if lookout_node != null:
		for child in lookout_node.get_children():
			child.queue_free()
	var build_node = hex.get_node_or_null("BuildingSprites")
	if build_node != null:
		for child in build_node.get_children():
			child.queue_free()
	var repair_node = hex.get_node_or_null("RepairSprites")
	if repair_node != null:
		for child in repair_node.get_children():
			child.queue_free()
	var sabotage_node = hex.get_node_or_null("SabotageSprites")
	if sabotage_node != null:
		for child in sabotage_node.get_children():
			child.queue_free()

func _reset_ui_for_snapshot() -> void:
	action_menu.hide()
	build_menu.hide()
	finish_move_button.visible = false
	placing_unit = ""
	currently_selected_unit = null
	action_mode = ""
	current_path = []
	current_reachable = {}
	enemy_tiles = []
	support_tiles = []
	repair_tiles = []
	remaining_moves = 0.0
	game_board.clear_highlights()
	_clear_all_drawings()
	_hide_build_hover()

func _on_done_pressed():
	game_board.clear_highlights()
	#_clear_all_drawings()
	$Panel.visible = false
	cancel_done_button.visible = true
	NetworkManager.submit_orders(current_player, [])
	# prevent further clicks
	placing_unit = ""
	allow_clicks = false

func _on_cancel_pressed():
	NetworkManager.cancel_orders(current_player)
	gold_lbl.text = "Orders unsubmitted - edit and resubmit"
	_draw_all()
	currently_selected_unit = null
	action_mode = ""
	current_path = []
	remaining_moves = 0
	finish_move_button.visible = false
	game_board.clear_highlights()
	allow_clicks = true
	$Panel.visible = true
	cancel_done_button.visible = false

func _on_execution_paused(phase_idx):
	_current_exec_step_idx = phase_idx
	exec_panel.visible = true
	var phase_names = ["Unit Spawns", "Attacks", "Engineering", "Movement"]
	if phase_idx == turn_mgr.neutral_step_index:
		phase_label.text = "Processed: Neutral Attacks\n(Click here to continue)"
		_update_auto_pass_for_damage()
		_auto_pass_continue()
		return
	if phase_idx >= phase_names.size():
		for i in range(phase_idx - phase_names.size()+1):
			phase_names.append("Movement")
	phase_label.text = "Processed: %s\n(Click here to continue)" % phase_names[phase_idx]
	_update_auto_pass_for_damage()
	_auto_pass_continue()

func _on_next_pressed():
	exec_panel.visible = false
	print("[UI] Next pressed for step %d" % _current_exec_step_idx)
	NetworkManager.rpc("rpc_step_ready", _current_exec_step_idx)
	
	if get_tree().get_multiplayer().is_server():
		NetworkManager.rpc_step_ready(_current_exec_step_idx)

func _on_execution_complete():
	exec_panel.visible = false
	_update_auto_pass_for_damage()

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
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order["type"] == "move":
				var mover = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(mover):
					continue
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

func _draw_partial_path() -> void:
	var preview_node = hex.get_node("PreviewPathArrows")
	# clear previous preview arrows
	for child in preview_node.get_children():
		child.queue_free()
	# draw arrows along current_path
	if current_path.size() > 1:
		var root = Node2D.new()
		preview_node.add_child(root)
		for i in range(current_path.size() - 1):
			var a = current_path[i]
			var b = current_path[i + 1]
			var p1 = hex.map_to_world(a) + hex.tile_size * 0.5
			var p2 = hex.map_to_world(b) + hex.tile_size * 0.5
			var arrow = SupportArrowScene.instantiate() as Sprite2D
			var dir = (p2 - p1).normalized()
			var tex_size = arrow.texture.get_size()
			var distance: float = (p2 - p1).length()
			var scale_x: float = distance / tex_size.x
			arrow.scale = Vector2(scale_x, 1)
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
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order["type"] == "ranged" or order["type"] == "melee":
				var root = Node2D.new()
				attack_arrows_node.add_child(root)
				
				# calculate direction and size for attack arrow
				var attacker = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				var target = unit_mgr.get_unit_by_net_id(order["target_unit_net_id"])
				if not _should_draw_unit(attacker) or target == null:
					continue
				var dmg = $"..".calculate_damage(attacker, target, order["type"], 1)
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
				var dmg_label = Label.new()
				dmg_label.text = "%d (%d)" % [dmg[1], dmg[0]]
				dmg_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.08))
				var normal := Vector2(-dir.y, dir.x)
				dmg_label.position = p1 + normal * 8.0 + dir * 6.0
				dmg_label.z_index = 11
				root.add_child(dmg_label)

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
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order["type"] == "support":
				var root = Node2D.new()
				support_arrows_node.add_child(root)
				
				# calculate direction and size for support arrow
				var supporter = order["unit"]
				if not _should_draw_unit(supporter):
					continue
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
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order["type"] == "heal":
				var root = Node2D.new()
				heal_node.add_child(root)
				var heart = HealScene.instantiate() as Sprite2D
				var unit = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(unit):
					continue
				heart.position = hex.map_to_world(unit.grid_pos) + hex.tile_size * 0.65
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
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order["type"] == "defend":
				var root = Node2D.new()
				defend_node.add_child(root)
				var defend = DefendScene.instantiate() as Sprite2D
				var unit = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(unit):
					continue
				defend.position = hex.map_to_world(unit.grid_pos) + hex.tile_size * 0.5
				defend.z_index = 0
				root.add_child(defend)

func _get_lookout_sprites_root() -> Node2D:
	var root = hex.get_node_or_null("LookoutSprites")
	if root == null:
		root = Node2D.new()
		root.name = "LookoutSprites"
		hex.add_child(root)
	return root

func _draw_lookouts():
	var lookout_node = _get_lookout_sprites_root()
	for child in lookout_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order.get("type", "") == "lookout":
				var unit = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(unit):
					continue
				var root = Node2D.new()
				lookout_node.add_child(root)
				var lookout_icon = Sprite2D.new()
				lookout_icon.texture = LookoutIcon
				var tex_size = LookoutIcon.get_size()
				if tex_size.x > 0:
					var scale = (hex.tile_size.x * 0.3) / tex_size.x
					lookout_icon.scale = Vector2(scale, scale)
				lookout_icon.position = hex.map_to_world(unit.grid_pos) + (hex.tile_size * Vector2(0.5, 0.7))
				lookout_icon.z_index = 10
				root.add_child(lookout_icon)

func _get_building_sprites_root() -> Node2D:
	var root = hex.get_node_or_null("BuildingSprites")
	if root == null:
		root = Node2D.new()
		root.name = "BuildingSprites"
		hex.add_child(root)
	return root

func _get_repair_sprites_root() -> Node2D:
	var root = hex.get_node_or_null("RepairSprites")
	if root == null:
		root = Node2D.new()
		root.name = "RepairSprites"
		hex.add_child(root)
	return root

func _get_sabotage_sprites_root() -> Node2D:
	var root = hex.get_node_or_null("SabotageSprites")
	if root == null:
		root = Node2D.new()
		root.name = "SabotageSprites"
		hex.add_child(root)
	return root

func _draw_builds():
	var build_node = _get_building_sprites_root()
	for child in build_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order.get("type", "") == "build":
				var unit = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(unit):
					continue
				var root = Node2D.new()
				build_node.add_child(root)
				var build_icon = Sprite2D.new()
				build_icon.texture = BuildIcon
				var tex_size = BuildIcon.get_size()
				if tex_size.x > 0:
					var scale = (hex.tile_size.x * 0.3) / tex_size.x
					build_icon.scale = Vector2(scale, scale)
				build_icon.position = hex.map_to_world(unit.grid_pos) + (hex.tile_size * Vector2(0.5, 0.7))
				build_icon.z_index = 10
				root.add_child(build_icon)

func _draw_repairs():
	var repair_node = _get_repair_sprites_root()
	for child in repair_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order.get("type", "") == "repair":
				var unit = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(unit):
					continue
				var root = Node2D.new()
				repair_node.add_child(root)
				var repair_icon = Sprite2D.new()
				repair_icon.texture = RepairIcon
				var tex_size = RepairIcon.get_size()
				if tex_size.x > 0:
					var scale = (hex.tile_size.x * 0.18) / tex_size.x
					repair_icon.scale = Vector2(scale, scale)
				repair_icon.position = hex.map_to_world(unit.grid_pos) + (hex.tile_size * Vector2(0.5, 0.7))
				repair_icon.z_index = 10
				root.add_child(repair_icon)

func _draw_sabotages():
	var sabotage_node = _get_sabotage_sprites_root()
	for child in sabotage_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order.get("type", "") == "sabotage":
				var unit = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(unit):
					continue
				var root = Node2D.new()
				sabotage_node.add_child(root)
				var sabotage_icon = Sprite2D.new()
				sabotage_icon.texture = SabotageIcon
				var tex_size = SabotageIcon.get_size()
				if tex_size.x > 0:
					var scale = (hex.tile_size.x * 0.18) / tex_size.x
					sabotage_icon.scale = Vector2(scale, scale)
				sabotage_icon.position = hex.map_to_world(unit.grid_pos) + (hex.tile_size * Vector2(0.5, 0.7))
				sabotage_icon.z_index = 10
				root.add_child(sabotage_icon)

func _draw_all():
	_draw_attacks()
	_draw_heals()
	_draw_paths()
	_draw_supports()
	_draw_defends()
	_draw_lookouts()
	_draw_builds()
	_draw_repairs()
	_draw_sabotages()

func _get_repair_targets(unit: Node) -> Array:
	var targets := []
	if unit == null or not unit.is_builder:
		return targets
	var state = turn_mgr.buildable_structures.get(unit.grid_pos, {})
	if state.size() > 0:
		if str(state.get("owner", "")) == current_player and str(state.get("status", "")) == "disabled":
			targets.append(unit.grid_pos)
	var target_unit = game_board.get_structure_unit_at(unit.grid_pos)
	if target_unit != null:
		if (target_unit.is_base or target_unit.is_tower) and target_unit.player_id == current_player:
			if target_unit.curr_health < target_unit.max_health:
				targets.append(unit.grid_pos)
	return targets

func _has_repair_target_here(unit: Node) -> bool:
	return _get_repair_targets(unit).size() > 0

func _on_build_selected(id: int) -> void:
	var struct_type = ""
	for entry in BUILD_OPTIONS:
		if entry["id"] == id:
			struct_type = entry["type"]
			break
	if struct_type == "" or currently_selected_unit == null:
		return
	NetworkManager.request_order(current_player, {
		"unit_net_id": currently_selected_unit.net_id,
		"type": "build",
		"structure_type": struct_type,
		"target_tile": currently_selected_unit.grid_pos
	})
	action_mode = ""
	build_menu.hide()

func finish_current_path():
	if current_path.size() == 1:
		action_mode = ""
		return
	move_priority +=1
	NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "move",
				"path": current_path,
				"priority": move_priority
			})
	var preview_node = hex.get_node("PreviewPathArrows")
	for child in preview_node.get_children():
		child.queue_free()
	finish_move_button.visible = false
	action_mode = ""
	current_path = []
	remaining_moves = 0
	game_board.clear_highlights()
	$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
	_update_done_button_state()
	
func _on_state_applied() -> void:
	_reset_ui_for_snapshot()
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		current_player = turn_mgr.local_player_id
		gold_lbl.text = "Current Gold: %d" % [turn_mgr.player_gold.get(current_player, 0)]
		income_lbl.text = "Income: %d per turn" % turn_mgr.player_income.get(current_player, 0)
		$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
		_update_done_button_state()
	_draw_all()
	_update_auto_pass_for_damage()


func _unhandled_input(ev):
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE) and exec_panel.visible:
			_on_next_pressed()
			return
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
			if turn_mgr.is_host():
				if NetworkManager.request_buy_unit(current_player, placing_unit, cell):
					gold_lbl.text = "%s Gold: %d" % [current_player, turn_mgr.player_gold[current_player]]
					placing_unit = ""
					$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
					_update_done_button_state()
				else:
					gold_lbl.text = "[Not enough gold]\nGold: %d" % turn_mgr.player_gold[current_player]
			else:
				NetworkManager.request_buy_unit(current_player, placing_unit, cell)
				placing_unit = ""
				gold_lbl.text = "Purchase requested"
				$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
				_update_done_button_state()
		else:
			gold_lbl.text = "[Can't place there]\nGold: %d" % turn_mgr.player_gold[current_player]
		return
	
	# Order phase: if waiting for destination (move mode)
	if action_mode == "move" and currently_selected_unit:
		if cell not in current_reachable["tiles"]:
			finish_current_path()
			return
		var path = []
		var prev = current_reachable["prev"]
		var cur = cell
		while cur in prev:
			path.insert(0, cur)
			cur = prev[cur]
		
		current_path += path
		var cost_used: float = 0.0
		for step_cell in path:
			cost_used += game_board.get_move_cost(step_cell, currently_selected_unit)
		remaining_moves -= cost_used
		
		_draw_partial_path()
		finish_move_button.set_position(ev.position)
		finish_move_button.visible = true
		if remaining_moves <= 0.001:
			finish_current_path()
			return
		
		var result = game_board.get_reachable_tiles(cell, remaining_moves, action_mode)
		var tiles = result["tiles"]
		if tiles.has(cell):
			tiles.erase(cell)
		game_board.show_highlights(tiles)
		current_reachable = result
		return

	if action_mode == "ranged" or action_mode == "melee" and currently_selected_unit:
		if cell in enemy_tiles:
			move_priority += 1
			var target_unit = game_board.get_primary_attack_target(cell, current_player)
			if target_unit == null:
				action_mode = ""
				return
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": action_mode,
				"target_tile": cell,
				"target_unit_net_id": target_unit.net_id,
				"priority": move_priority
			})
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
				_on_unit_selected(unit)
				last_click_pos = ev.position
				action_menu.set_position(ev.position)
				action_menu.show()
