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
var cavalry_bonus_available: bool = false
var cavalry_bonus_used: bool = false
var cavalry_bonus_tile: Vector2i = Vector2i(-9999, -9999)
var cavalry_bonus_paths: Dictionary = {}
var repair_tiles: Array = []
var action_mode:       String   = ""     # "move", "move_to", "ranged", "melee", "support", "hold", "repair", "build_road_to", "build_rail_to"
var move_priority: int = 0
var allow_clicks: bool = true
var last_click_pos: Vector2 = Vector2.ZERO
var current_spell_type: String = ""
var spell_tiles: Array = []
var spell_caster: Node = null
var current_spell_mana_spent: int = 0
var pending_spell_type: String = ""
var _buff_input_updating: bool = false
var selected_structure_tile: Vector2i = Vector2i(-9999, -9999)
var selected_structure_type: String = ""
var _build_hover_root: Node2D = null
var _build_hover_label: Label = null
var _build_hover_cell: Vector2i = Vector2i(-99999, -99999)

var _current_exec_step_idx: int = 0
var menu_popup: PopupMenu = null
var save_slot_index: int = 0
var damage_panel_minimized: bool = false
var damage_panel_full_size: Vector2 = Vector2.ZERO
var damage_panel_dragging: bool = false
var damage_panel_drag_start: Vector2 = Vector2.ZERO
var damage_panel_start_size: Vector2 = Vector2.ZERO
var auto_pass_enabled: bool = false
var last_damage_log_count: int = 0
var done_button_default_modulate: Color = Color(1, 1, 1)
var _map_select_id: int = MAP_SELECT_RANDOM_NORMAL
var _map_select_names: Dictionary = {}
var _queue_preview_unit_id: int = -1
var _default_camera_zoom: Vector2 = Vector2.ZERO
var replay_metric_ids: Array = []

@onready var turn_mgr = get_node(turn_manager_path) as Node
@onready var unit_mgr = get_node(unit_manager_path) as Node
@onready var game_board: Node = get_node("../GameBoardNode")
@onready var hex = $"../GameBoardNode/HexTileMap"
@onready var status_lbl = $Panel/VBoxContainer/StatusLabel as Label
@onready var turn_label = $Panel/VBoxContainer/TurnLabel as Label
@onready var resource_panel = $ResourcePanel as Panel
@onready var gold_resource_lbl = $ResourcePanel/VBoxContainer/GoldResourceLabel as Label
@onready var mana_resource_lbl = $ResourcePanel/VBoxContainer/ManaResourceLabel as Label
@onready var dragon_buff_lbl = $ResourcePanel/VBoxContainer/DragonBuffLabel as Label
@onready var buff_mana_panel = $BuffManaPanel as Panel
@onready var buff_mana_slider = $BuffManaPanel/VBoxContainer/ValueRow/BuffManaSlider as HSlider
@onready var buff_mana_input = $BuffManaPanel/VBoxContainer/ValueRow/ValueInput as LineEdit
@onready var buff_mana_ok = $BuffManaPanel/VBoxContainer/Buttons/OkButton as Button
@onready var buff_mana_cancel = $BuffManaPanel/VBoxContainer/Buttons/CancelButton as Button
@onready var action_menu: PopupMenu      = $Panel/ActionMenu as PopupMenu
@onready var build_menu: PopupMenu = PopupMenu.new()
@onready var spell_menu: PopupMenu = PopupMenu.new()
@onready var exec_panel: PanelContainer  = $ExecutionPanel
@onready var phase_label   : Label       = exec_panel.get_node("ExecutionBox/PhaseLabel")
@onready var next_button   : Button      = exec_panel.get_node("ExecutionBox/ControlsRow/NextButton")
@onready var auto_pass_check = $ExecutionPanel/ExecutionBox/ControlsRow/AutoPassCheckButton as CheckButton
@onready var done_button = $Panel/VBoxContainer/DoneButton as Button
@onready var next_unordered_button = $Panel/VBoxContainer/NextUnorderedButton as Button
@onready var cancel_done_button = $CancelDoneButton as Button
@onready var confirm_done_dialog = $ConfirmDoneDialog as ConfirmationDialog
@onready var confirm_concede_dialog = $ConfirmConcedeDialog as ConfirmationDialog
@onready var dev_mode_toggle = get_node(dev_mode_toggle_path) as CheckButton
@onready var dev_panel = $DevPanel
@onready var respawn_timers_toggle = $DevPanel/VBoxContainer/RespawnTimersCheckButton as CheckButton
@onready var resync_button = $DevPanel/VBoxContainer/ResyncButton as Button
@onready var skip_movement_button = $DevPanel/VBoxContainer/SkipMovementButton as Button
@onready var menu_button = $MenuButton as MenuButton
@onready var damage_panel = $DamagePanel as Panel
@onready var damage_scroll = $DamagePanel/ScrollContainer as ScrollContainer
@onready var damage_toggle_button = $DamagePanel/ToggleDamageButton as Button
@onready var damage_resize_handle = $DamagePanel/ResizeHandle as Control
@onready var finish_move_button = $Panel/FinishMoveButton
@onready var map_select = $MapSelect as MenuButton
@onready var map_label = $MapLabel as Label
@onready var username_label = $UsernameLabel as Label
@onready var username_edit = $UsernameLineEdit as LineEdit
@onready var lobby_panel = $LobbyPanel as Panel
@onready var lobby_players = $LobbyPanel/VBoxContainer/PlayersList as VBoxContainer
@onready var lobby_add_button = $LobbyPanel/VBoxContainer/SlotsRow/AddSlotButton as Button
@onready var lobby_remove_button = $LobbyPanel/VBoxContainer/SlotsRow/RemoveSlotButton as Button
@onready var lobby_start_button = $LobbyPanel/VBoxContainer/StartGameButton as Button
@onready var proc_custom_panel = $ProcCustomPanel as Panel
@onready var proc_custom_size = $ProcCustomPanel/VBoxContainer/Grid/SizeOption as OptionButton
@onready var proc_custom_columns = $ProcCustomPanel/VBoxContainer/Grid/ColumnsEdit as LineEdit
@onready var proc_custom_rows = $ProcCustomPanel/VBoxContainer/Grid/RowsEdit as LineEdit
@onready var proc_custom_forest = $ProcCustomPanel/VBoxContainer/Grid/ForestEdit as LineEdit
@onready var proc_custom_mountain = $ProcCustomPanel/VBoxContainer/Grid/MountainEdit as LineEdit
@onready var proc_custom_river = $ProcCustomPanel/VBoxContainer/Grid/RiverEdit as LineEdit
@onready var proc_custom_lake = $ProcCustomPanel/VBoxContainer/Grid/LakeEdit as LineEdit
@onready var proc_custom_mines = $ProcCustomPanel/VBoxContainer/Grid/MineEdit as LineEdit
@onready var proc_custom_camps = $ProcCustomPanel/VBoxContainer/Grid/CampEdit as LineEdit
@onready var proc_custom_dragons = $ProcCustomPanel/VBoxContainer/Grid/DragonEdit as LineEdit
@onready var proc_custom_apply = $ProcCustomPanel/VBoxContainer/Buttons/ApplyButton as Button
@onready var proc_custom_close = $ProcCustomPanel/VBoxContainer/Buttons/CloseButton as Button
@onready var replay_panel = $ReplayPanel as Panel
@onready var replay_turn_label = $ReplayPanel/VBoxContainer/TurnLabel as Label
@onready var replay_prev_button = $ReplayPanel/VBoxContainer/ControlsRow/PrevButton as Button
@onready var replay_next_button = $ReplayPanel/VBoxContainer/ControlsRow/NextButton as Button
@onready var replay_phase_toggle = $ReplayPanel/VBoxContainer/PhaseCheckButton as CheckButton
@onready var replay_fog_option = $ReplayPanel/VBoxContainer/FogRow/FogOption as OptionButton
@onready var replay_stats_button = $ReplayPanel/VBoxContainer/StatsButton as Button
@onready var replay_exit_button = $ReplayPanel/VBoxContainer/ExitButton as Button
@onready var replay_quit_button = $ReplayPanel/VBoxContainer/QuitToLobbyButton as Button
@onready var replay_stats_panel = $ReplayStatsPanel as Window
@onready var replay_stats_metric = $ReplayStatsPanel/VBoxContainer/ControlsRow/MetricOption as OptionButton
@onready var replay_stats_player1 = $ReplayStatsPanel/VBoxContainer/ControlsRow/Player1Check as CheckButton
@onready var replay_stats_player2 = $ReplayStatsPanel/VBoxContainer/ControlsRow/Player2Check as CheckButton
@onready var replay_stats_graph = $ReplayStatsPanel/VBoxContainer/Graph as Control

const ArrowScene = preload("res://scenes/Arrow.tscn")
const AttackArrowScene = preload("res://scenes/AttackArrow.tscn")
const SupportArrowScene = preload("res://scenes/SupportArrow.tscn")
const HealScene = preload("res://scenes/Healing.tscn")
const DefendScene = preload("res://scenes/Defending.tscn")
const BuildIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_162.png")
const RepairIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_141.png")
const SabotageIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_180.png")
const LookoutIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_134.png")
const FireballIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Geometric/HSI_icon_108.png")
const BuffIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_139.png")
const LightningIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_174.png")
const GlobalVisionIcon = preload("res://assets/HK-Heightend Sensory Input v2/HSI - Icons/HSI - Icon Objects/HSI_icon_177.png")
const SAVE_SLOT_COUNT_UI: int = 3
const ORDER_ICON_Z: int = 12
const DAMAGE_PANEL_MIN_SIZE: Vector2 = Vector2(220, 120)
const USERNAME_SAVE_PATH: String = "user://user_settings.cfg"

var lobby_slots_payload: Array = []

const MENU_ID_SAVE: int = 1
const MENU_ID_LOAD: int = 2
const MENU_ID_LOAD_AUTOSAVE: int = 3
const MENU_ID_UNIT_STATS: int = 10
const MENU_ID_BUILDING_STATS: int = 11
const MENU_ID_SPELL_STATS: int = 12
const MENU_ID_DEV_MODE: int = 13
const MENU_ID_QUIT: int = 14
const MENU_ID_CONCEDE: int = 15
const MENU_ID_TERRAIN_STATS: int = 20
const MENU_ID_SLOT_BASE: int = 100
const MAP_SELECT_RANDOM_ANY: int = 1000
const MAP_SELECT_RANDOM_NORMAL: int = 1001
const MAP_SELECT_RANDOM_THEMED: int = 1002
const MAP_SELECT_RANDOM_SMALL: int = 1003
const MAP_SELECT_PROCEDURAL: int = 1004
const MAP_SELECT_PROCEDURAL_CUSTOM: int = 1005
const MAP_SELECT_MAP_BASE: int = 2000

const BUILD_OPTIONS = [
	{"id": 0, "label": "Fortification", "type": "fortification"},
	{"id": 1, "label": "Road", "type": "road"},
	{"id": 2, "label": "Railroad", "type": "rail"},
	{"id": 3, "label": "Spawn Tower", "type": "spawn_tower"},
	{"id": 4, "label": "Trap", "type": "trap"},
	{"id": 5, "label": "Mana Pool", "type": "mana_pool"},
	{"id": 7, "label": "Mana Pump", "type": "mana_pump"},
	{"id": 6, "label": "Ward", "type": "ward"}
]
const BUILD_MENU_ROAD_TO_ID: int = 100
const BUILD_MENU_RAIL_TO_ID: int = 101
const ACTION_SPELL_ID: int = 13
const ACTION_SPELL_STRUCTURE_ID: int = 14
const ACTION_WARD_VISION_ID: int = 15
const ACTION_WARD_VISION_ALWAYS_ID: int = 16
const ACTION_WARD_VISION_STOP_ID: int = 18
const ACTION_LOOKOUT_ALWAYS_ID: int = 17
const ACTION_SPELL_CANCEL_ID: int = 19

const SPELL_OPTIONS = [
	{"id": 0, "label": "Heal", "type": "heal"},
	{"id": 1, "label": "Fireball", "type": "fireball"},
	{"id": 2, "label": "Combat Buff", "type": "buff"},
	{"id": 3, "label": "Lightning", "type": "lightning"},
	{"id": 4, "label": "Global Vision", "type": "global_vision"},
	{"id": 5, "label": "Targeted Vision", "type": "targeted_vision"}
]

const ArcherScene = preload("res://scenes/Archer.tscn")
const SoldierScene = preload("res://scenes/Soldier.tscn")
const ScoutScene = preload("res://scenes/Scout.tscn")
const MinerScene = preload("res://scenes/Miner.tscn")
const CrystalMinerScene = preload("res://scenes/CrystalMiner.tscn")
const PhalanxScene = preload("res://scenes/Tank.tscn")
const CavalryScene = preload("res://scenes/Cavalry.tscn")
const BuilderScene = preload("res://scenes/Builder.tscn")
const WizardScene = preload("res://scenes/Wizard.tscn")
const CampArcherScene = preload("res://scenes/CampArcher.tscn")
const DragonScene = preload("res://scenes/Dragon.tscn")

const MineScene = preload("res://scenes/GemMine.tscn")

func _ready():
	# Enable unhandled input processing
	set_process_unhandled_input(true)
	set_process(true)
	if map_select != null:
		map_select.flat = false
	var cam = get_viewport().get_camera_2d()
	if cam != null:
		_default_camera_zoom = cam.zoom
	if username_edit != null:
		username_edit.text = _load_username()
	
	$HostButton.connect("pressed",
					Callable(self, "_on_host_pressed"))
	$JoinButton.connect("pressed",
					Callable(self, "_on_join_pressed"))
	$CancelGameButton.connect("pressed",
					Callable(self, "_on_cancel_game_pressed"))
	if lobby_add_button != null:
		lobby_add_button.connect("pressed",
					Callable(self, "_on_add_slot_pressed"))
	if lobby_remove_button != null:
		lobby_remove_button.connect("pressed",
					Callable(self, "_on_remove_slot_pressed"))
	if lobby_start_button != null:
		lobby_start_button.connect("pressed",
					Callable(self, "_on_start_game_pressed"))
	NetworkManager.connect("lobby_updated",
					Callable(self, "_on_lobby_updated"))
	NetworkManager.connect("player_id_assigned",
					Callable(self, "_on_player_id_assigned"))
	NetworkManager.connect("map_selection_changed",
					Callable(self, "_on_map_selection_changed"))
	_init_map_select()
	_init_proc_custom_panel()
	_show_main_menu()
	
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
	$DevPanel/VBoxContainer/SkipMovementButton.connect("pressed",
					 Callable(self, "_on_skip_movement_pressed"))
	if damage_toggle_button != null:
		damage_toggle_button.connect("pressed",
					 Callable(self, "_on_damage_toggle_pressed"))
	if buff_mana_slider != null:
		buff_mana_slider.connect("value_changed",
					Callable(self, "_on_buff_mana_value_changed"))
	if buff_mana_input != null:
		buff_mana_input.connect("text_changed",
					Callable(self, "_on_buff_mana_text_changed"))
		buff_mana_input.connect("text_submitted",
					Callable(self, "_on_buff_mana_text_submitted"))
	if buff_mana_ok != null:
		buff_mana_ok.connect("pressed",
					Callable(self, "_on_buff_mana_confirm"))
	if buff_mana_cancel != null:
		buff_mana_cancel.connect("pressed",
					Callable(self, "_on_buff_mana_cancel"))
	if confirm_done_dialog != null:
		confirm_done_dialog.connect("confirmed",
					Callable(self, "_on_done_confirmed"))
	if confirm_concede_dialog != null:
		confirm_concede_dialog.connect("confirmed",
					Callable(self, "_on_concede_confirmed"))
	if damage_resize_handle != null:
		damage_resize_handle.connect("gui_input",
					Callable(self, "_on_damage_resize_input"))
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
	turn_mgr.connect("replay_state_changed",
					Callable(self, "_on_replay_state_changed"))
	next_button.connect("pressed",
					Callable(self, "_on_next_pressed"))
	if auto_pass_check != null:
		auto_pass_check.connect("toggled",
					Callable(self, "_on_auto_pass_toggled"))
	
	# order button connections
	$Panel/VBoxContainer/ArcherButton.connect("pressed",
					 Callable(self, "_on_archer_pressed"))
	$Panel/VBoxContainer/WizardButton.connect("pressed",
					 Callable(self, "_on_wizard_pressed"))
	$Panel/VBoxContainer/SoldierButton.connect("pressed",
					 Callable(self, "_on_soldier_pressed"))
	$Panel/VBoxContainer/ScoutButton.connect("pressed",
					 Callable(self, "_on_scout_pressed"))
	$Panel/VBoxContainer/MinerButton.connect("pressed",
					 Callable(self, "_on_miner_pressed"))
	$Panel/VBoxContainer/CrystalMinerButton.connect("pressed",
					 Callable(self, "_on_crystal_miner_pressed"))
	$Panel/VBoxContainer/BuilderButton.connect("pressed",
					 Callable(self, "_on_builder_pressed"))
	$Panel/VBoxContainer/PhalanxButton.connect("pressed",
					 Callable(self, "_on_tank_pressed"))
	$Panel/VBoxContainer/CavalryButton.connect("pressed",
					 Callable(self, "_on_cavalry_pressed"))
	$Panel/VBoxContainer/DoneButton.connect("pressed",
					 Callable(self, "_on_done_pressed"))
	if next_unordered_button != null:
		next_unordered_button.connect("pressed",
					 Callable(self, "_on_next_unordered_pressed"))
	$CancelDoneButton.connect("pressed",
					 Callable(self, "_on_cancel_pressed"))
	if done_button != null:
		done_button_default_modulate = done_button.self_modulate
	$UnitStatsCheckButton.connect("toggled",
					Callable(self, "_on_stats_toggled"))
	$BuildingStatsCheckButton.connect("toggled",
					Callable(self, "_on_building_stats_toggled"))
	$SpellStatsCheckButton.connect("toggled",
					Callable(self, "_on_spell_stats_toggled"))
	$TerrainStatsCheckButton.connect("toggled",
					Callable(self, "_on_terrain_stats_toggled"))
	if $StatsPanel.has_signal("close_requested"):
		$StatsPanel.connect("close_requested",
					Callable(self, "_on_unit_stats_close_pressed"))
	if $BuildingStatsPanel.has_signal("close_requested"):
		$BuildingStatsPanel.connect("close_requested",
					Callable(self, "_on_building_stats_close_pressed"))
	if $SpellStatsPanel.has_signal("close_requested"):
		$SpellStatsPanel.connect("close_requested",
					Callable(self, "_on_spell_stats_close_pressed"))
	if $TerrainStatsPanel.has_signal("close_requested"):
		$TerrainStatsPanel.connect("close_requested",
					Callable(self, "_on_terrain_stats_close_pressed"))
	$Panel/FinishMoveButton.connect("pressed",
					Callable(self, "_on_finish_move_button_pressed"))
	if replay_prev_button != null:
		replay_prev_button.connect("pressed",
					Callable(self, "_on_replay_prev_pressed"))
	if replay_next_button != null:
		replay_next_button.connect("pressed",
					Callable(self, "_on_replay_next_pressed"))
	if replay_phase_toggle != null:
		replay_phase_toggle.connect("toggled",
					Callable(self, "_on_replay_phase_toggled"))
	if replay_fog_option != null:
		replay_fog_option.connect("item_selected",
					Callable(self, "_on_replay_fog_selected"))
	if replay_stats_button != null:
		replay_stats_button.connect("pressed",
					Callable(self, "_on_replay_stats_pressed"))
	if replay_exit_button != null:
		replay_exit_button.connect("pressed",
					Callable(self, "_on_replay_exit_pressed"))
	if replay_quit_button != null:
		replay_quit_button.connect("pressed",
					Callable(self, "_on_replay_quit_pressed"))
	if replay_stats_panel != null and replay_stats_panel.has_signal("close_requested"):
		replay_stats_panel.connect("close_requested",
					Callable(self, "_on_replay_stats_close_pressed"))
	if replay_stats_metric != null:
		replay_stats_metric.connect("item_selected",
					Callable(self, "_on_replay_metric_changed"))
	if replay_stats_player1 != null:
		replay_stats_player1.connect("toggled",
					Callable(self, "_on_replay_metric_changed"))
	if replay_stats_player2 != null:
		replay_stats_player2.connect("toggled",
					Callable(self, "_on_replay_metric_changed"))
	if replay_panel != null:
		replay_panel.visible = false
	if replay_stats_panel != null:
		replay_stats_panel.visible = false
	
	# setting gold labels and stats for units
	var base_font: FontFile = load("res://fonts/JetBrainsMono-Medium.ttf")
	var unit_scenes = [ScoutScene, MinerScene, CrystalMinerScene, BuilderScene, SoldierScene, ArcherScene, WizardScene, PhalanxScene, CavalryScene]
	var unit_names = ["Scout", "Miner", "Crystal Miner", "Builder", "Soldier", "Archer", "Wizard", "Phalanx", "Cavalry"]
	var unit_specials = [
		"Sight 3; lookout; forest cost 1; +5 melee vs ranged in forest",
		"Mine bonus +15 on mine",
		"Mine bonus +10 mana on mine",
		"Build/repair/sabotage; queue roads/rails",
		"None",
		"Ranged range 2",
		"Cast spells (range 3, +1 in tower)",
		"Defend: +20 melee, no multi-def penalty; adjacent allies +2",
		"Sight 3"
	]
	var unit_buy_buttons = [$Panel/VBoxContainer/ScoutButton,
							$Panel/VBoxContainer/MinerButton,
							$Panel/VBoxContainer/CrystalMinerButton,
							$Panel/VBoxContainer/BuilderButton,
							$Panel/VBoxContainer/SoldierButton,
							$Panel/VBoxContainer/ArcherButton,
							$Panel/VBoxContainer/WizardButton,
							$Panel/VBoxContainer/PhalanxButton,
							$Panel/VBoxContainer/CavalryButton]
	var unit_tree = $StatsPanel/Tree
	var unit_col_widths = [170.0, 70.0, 70.0, 60.0, 60.0, 90.0, 280.0]
	var unit_headers = ["Unit", "Melee", "Ranged", "Move", "Regen", "Road Spawn", "Special"]
	var unit_root = _setup_stats_tree(unit_tree, unit_headers, unit_col_widths, false, base_font)
	var road_spawn_units = turn_mgr.SPAWN_TOWER_ROAD_UNITS
	var unit_rows := []
	var temp
	for i in range(unit_scenes.size()):
		temp = unit_scenes[i].instantiate()
		unit_buy_buttons[i].text = "Buy %s (%dG)" % [unit_names[i], temp.cost]
		var special_text = unit_specials[i] if i < unit_specials.size() else temp.special_skills
		var unit_key = unit_names[i].to_lower().replace(" ", "_")
		var road_spawn = "Yes" if unit_key in road_spawn_units else "No"
		var row = [unit_names[i], str(temp.melee_strength), str(temp.ranged_strength), str(temp.move_range), str(temp.regen), road_spawn, special_text]
		_add_stats_tree_row(
			unit_tree,
			unit_root,
			row,
			false
		)
		unit_rows.append(row)
	temp.free()

	var neutral_header = ["Neutral Units", "", "", "", "", "", ""]
	_add_stats_tree_row(unit_tree, unit_root, neutral_header, false)
	unit_rows.append(neutral_header)
	var neutral_scenes = [CampArcherScene, DragonScene]
	var neutral_names = ["Camp\nArcher", "Dragon"]
	var neutral_specials = ["Ranged range 2", "Fire range 3; cleave adj up to 3"]
	for i in range(neutral_scenes.size()):
		temp = neutral_scenes[i].instantiate()
		var special_text = neutral_specials[i]
		if special_text == "":
			special_text = temp.special_skills
		var row = [neutral_names[i], str(temp.melee_strength), str(temp.ranged_strength), str(temp.move_range), str(temp.regen), "N/A", special_text]
		_add_stats_tree_row(
			unit_tree,
			unit_root,
			row,
			false
		)
		unit_rows.append(row)
		temp.free()
	_autosize_tree_columns(unit_tree, unit_headers, unit_rows, base_font)

	var build_tree = $BuildingStatsPanel/Tree
	var build_col_widths = [150.0, 80.0, 55.0, 60.0, 60.0, 60.0, 320.0]
	var build_headers = ["Building", "Cost/step", "Turns", "Forest", "River", "Lake", "Effect"]
	var build_root = _setup_stats_tree(build_tree, build_headers, build_col_widths, false, base_font)
	var short_turns = int(turn_mgr.BUILD_TURNS_SHORT)
	var tower_turns = int(turn_mgr.BUILD_TURNS_TOWER)
	var mana_turns = int(turn_mgr.BUILD_TURNS_MANA_POOL)
	var pump_turns = int(turn_mgr.BUILD_TURNS_MANA_PUMP)
	var fort_bonus = "%d/%d" % [turn_mgr.fort_melee_bonus, turn_mgr.fort_ranged_bonus]
	var build_rows = [
		{"name": "Fortification", "cost": turn_mgr.get_build_turn_cost("fortification"), "turns": short_turns, "forest": "No", "river": "No", "lake": "No", "effect": "+%s melee/ranged (atk/def)" % fort_bonus},
		{"name": "Road", "cost": turn_mgr.get_build_turn_cost("road"), "turns": short_turns, "forest": "Yes", "river": "Yes", "lake": "No", "effect": "Move x0.5; +1 turn on river; mines +10 if connected"},
		{"name": "Railroad", "cost": turn_mgr.get_build_turn_cost("rail"), "turns": short_turns, "forest": "Yes", "river": "Yes", "lake": "No", "effect": "Move x0.25; upgrade intact road; rail build counts as road; +1 turn on river; mines +20 if connected"},
		{"name": "Mana Pool", "cost": turn_mgr.get_build_turn_cost("mana_pool"), "turns": mana_turns, "forest": "Yes", "river": "No", "lake": "No", "effect": "Adjacent to mine or base; +100 mana cap; one per mine/base"},
		{"name": "Mana Pump", "cost": turn_mgr.get_build_turn_cost("mana_pump"), "turns": pump_turns, "forest": "Yes", "river": "Yes", "lake": "Yes", "effect": "Triangle with mine/base + pool; +5 mana/turn if source controlled & pool intact"},
		{"name": "Ward", "cost": turn_mgr.get_build_turn_cost("ward"), "turns": short_turns, "forest": "Yes", "river": "No", "lake": "Yes", "effect": "Hidden from enemies except wizards; spend 5 mana for vision radius 2; sees through forests"},
		{"name": "Spawn Tower", "cost": turn_mgr.get_build_turn_cost("spawn_tower"), "turns": tower_turns, "forest": "No", "river": "No", "lake": "No", "effect": "Spawn point; tower bonuses; no income; needs road/rail link"},
		{"name": "Trap", "cost": turn_mgr.get_build_turn_cost("trap"), "turns": short_turns, "forest": "Yes", "river": "Yes", "lake": "No", "effect": "Hidden from enemies; triggers to disable, stop movement, deal 30 dmg"}
	]
	var build_rows_values := []
	for i in range(build_rows.size()):
		var row = build_rows[i]
		var row_values = [row["name"], "%dg" % int(row["cost"]), str(row["turns"]), row["forest"], row["river"], row["lake"], row["effect"]]
		_add_stats_tree_row(
			build_tree,
			build_root,
			row_values,
			false
		)
		build_rows_values.append(row_values)
	_autosize_tree_columns(build_tree, build_headers, build_rows_values, base_font)
	
	var spell_tree = $SpellStatsPanel/Tree
	var spell_col_widths = [140.0, 80.0, 80.0, 320.0]
	var spell_headers = ["Spell", "Cost", "Phase", "Effect"]
	var spell_root = _setup_stats_tree(spell_tree, spell_headers, spell_col_widths, false, base_font)
	var spell_rows = [
		{"name": "Heal", "cost": turn_mgr.get_spell_cost("heal"), "phase": "Spells", "effect": "Heal 25; range 3"},
		{"name": "Fireball", "cost": turn_mgr.get_spell_cost("fireball"), "phase": "Attacks", "effect": "50 dmg units; 10 dmg tower/base; range 3"},
		{"name": "Combat Buff", "cost": "5-100", "phase": "Spells", "effect": "Spend 5-100 mana; +0.1 melee/ranged per mana; 1 turn"},
		{"name": "Lightning", "cost": turn_mgr.get_spell_cost("lightning"), "phase": "Attacks", "effect": "32 dmg + chain halving to adjacent enemies; range 3"},
		{"name": "Global Vision", "cost": turn_mgr.get_spell_cost("global_vision"), "phase": "Spawns", "effect": "Reveal all explored tiles for 1 turn"},
		{"name": "Targeted Vision", "cost": turn_mgr.get_spell_cost("targeted_vision"), "phase": "Spawns", "effect": "Ward vision radius 2 for 1 turn; cast range 3"}
	]
	var spell_rows_values := []
	for i in range(spell_rows.size()):
		var row = spell_rows[i]
		var cost_text = "%d mana" % int(row["cost"])
		if row["name"] == "Combat Buff":
			cost_text = "%s mana" % str(row["cost"])
		var row_values = [row["name"], cost_text, row["phase"], row["effect"]]
		_add_stats_tree_row(
			spell_tree,
			spell_root,
			row_values,
			false
		)
		spell_rows_values.append(row_values)
	_autosize_tree_columns(spell_tree, spell_headers, spell_rows_values, base_font)

	var terrain_tree = $TerrainStatsPanel/Tree
	var terrain_col_widths = [100.0, 70.0, 90.0, 90.0, 75.0, 80.0, 90.0]
	var terrain_headers = ["Terrain", "Move", "Blocks LOS", "Impassable", "Melee Atk", "Melee Def", "Ranged Def"]
	var terrain_root = _setup_stats_tree(terrain_tree, terrain_headers, terrain_col_widths, false, base_font)
	var terrain_rows = [
		{"name": "Open", "move": "1", "blocks": "No", "impass": "No", "atk": "0", "melee_def": "0", "ranged_def": "0"},
		{"name": "Forest", "move": "2", "blocks": "Yes", "impass": "No", "atk": "0", "melee_def": "+2", "ranged_def": "+2"},
		{"name": "River", "move": "2", "blocks": "No", "impass": "No", "atk": "-2", "melee_def": "-2", "ranged_def": "-2"},
		{"name": "Lake", "move": "2", "blocks": "No", "impass": "No", "atk": "-2", "melee_def": "+3", "ranged_def": "-3"},
		{"name": "Mountain", "move": "Imp", "blocks": "Yes", "impass": "Yes", "atk": "0", "melee_def": "0", "ranged_def": "0"}
	]
	var terrain_rows_values := []
	for i in range(terrain_rows.size()):
		var row = terrain_rows[i]
		var row_values = [row["name"], row["move"], row["blocks"], row["impass"], row["atk"], row["melee_def"], row["ranged_def"]]
		_add_stats_tree_row(
			terrain_tree,
			terrain_root,
			row_values,
			false
		)
		terrain_rows_values.append(row_values)
	_autosize_tree_columns(terrain_tree, terrain_headers, terrain_rows_values, base_font)
	
	# unit order menu
	action_menu.connect("id_pressed", Callable(self, "_on_action_selected"))
	action_menu.hide()
	build_menu.name = "BuildMenu"
	add_child(build_menu)
	build_menu.connect("id_pressed", Callable(self, "_on_build_selected"))
	build_menu.hide()
	for entry in BUILD_OPTIONS:
		build_menu.add_item(entry["label"], entry["id"])
	build_menu.add_separator()
	build_menu.add_item("Build Road To", BUILD_MENU_ROAD_TO_ID)
	build_menu.add_item("Build Railroad To", BUILD_MENU_RAIL_TO_ID)
	spell_menu.name = "SpellMenu"
	add_child(spell_menu)
	spell_menu.connect("id_pressed", Callable(self, "_on_spell_selected"))
	spell_menu.hide()
	for entry in SPELL_OPTIONS:
		spell_menu.add_item(entry["label"], entry["id"])
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
	menu_popup.add_check_item("Spell Stats", MENU_ID_SPELL_STATS)
	menu_popup.add_check_item("Terrain Stats", MENU_ID_TERRAIN_STATS)
	menu_popup.add_check_item("Dev Mode", MENU_ID_DEV_MODE)
	menu_popup.add_separator()
	for i in range(SAVE_SLOT_COUNT_UI):
		menu_popup.add_radio_check_item("Save Slot %d" % (i + 1), MENU_ID_SLOT_BASE + i)
	menu_popup.add_separator()
	menu_popup.add_item("Concede", MENU_ID_CONCEDE)
	menu_popup.add_item("Quit to Lobby", MENU_ID_QUIT)
	_sync_menu_checks()
	menu_popup.connect("id_pressed", Callable(self, "_on_menu_id_pressed"))
	damage_panel_full_size = damage_panel.size
	_apply_damage_panel_size(damage_panel_full_size)
	_update_damage_panel()

func _init_map_select() -> void:
	if map_select == null or turn_mgr == null:
		return
	var popup = map_select.get_popup()
	if popup == null:
		return
	popup.clear()
	_map_select_names.clear()
	for name in ["ThemedMapsMenu", "NormalMapsMenu", "SmallMapsMenu"]:
		var old = popup.get_node_or_null(name)
		if old != null:
			old.queue_free()
	popup.add_item("Random (Any)", MAP_SELECT_RANDOM_ANY)
	popup.add_item("Random Normal", MAP_SELECT_RANDOM_NORMAL)
	popup.add_item("Random Themed", MAP_SELECT_RANDOM_THEMED)
	popup.add_item("Random Small", MAP_SELECT_RANDOM_SMALL)
	popup.add_item("Procedural Map", MAP_SELECT_PROCEDURAL)
	popup.add_item("Procedural (Custom)", MAP_SELECT_PROCEDURAL_CUSTOM)
	popup.add_separator()
	var themed := []
	var normal := []
	var small := []
	for i in range(turn_mgr.map_data.size()):
		var md = turn_mgr.map_data[i] as MapData
		if md == null:
			continue
		if md.procedural:
			continue
		var name = str(md.map_name)
		var category = turn_mgr._map_category_for(md)
		var size = turn_mgr._map_size_for(md)
		if size == "small":
			small.append({"name": name, "id": MAP_SELECT_MAP_BASE + i})
		elif category == "themed":
			themed.append({"name": name, "id": MAP_SELECT_MAP_BASE + i})
		else:
			normal.append({"name": name, "id": MAP_SELECT_MAP_BASE + i})
	themed.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	normal.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	small.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	_add_map_submenu(popup, "Themed Maps", "ThemedMapsMenu", themed)
	_add_map_submenu(popup, "Normal Maps", "NormalMapsMenu", normal)
	_add_map_submenu(popup, "Small Maps", "SmallMapsMenu", small)
	if not popup.is_connected("id_pressed", Callable(self, "_on_map_select_menu_pressed")):
		popup.connect("id_pressed", Callable(self, "_on_map_select_menu_pressed"))
	_sync_map_select_from_state()

func _add_map_submenu(parent_menu: PopupMenu, label: String, node_name: String, entries: Array) -> void:
	if parent_menu == null:
		return
	var submenu = PopupMenu.new()
	submenu.name = node_name
	parent_menu.add_child(submenu)
	if entries.is_empty():
		submenu.add_item("(none)", -1)
		submenu.set_item_disabled(0, true)
	else:
		for entry in entries:
			submenu.add_item(entry["name"], entry["id"])
			_map_select_names[entry["id"]] = entry["name"]
	parent_menu.add_submenu_item(label, submenu.name)
	if not submenu.is_connected("id_pressed", Callable(self, "_on_map_select_menu_pressed")):
		submenu.connect("id_pressed", Callable(self, "_on_map_select_menu_pressed"))

func _init_proc_custom_panel() -> void:
	if proc_custom_panel == null:
		return
	if proc_custom_size != null and proc_custom_size.get_item_count() == 0:
		proc_custom_size.add_item("Normal", 0)
		proc_custom_size.add_item("Small", 1)
	if proc_custom_columns != null:
		proc_custom_columns.placeholder_text = "0"
	if proc_custom_rows != null:
		proc_custom_rows.placeholder_text = "0"
	if proc_custom_forest != null:
		proc_custom_forest.placeholder_text = "0.18"
	if proc_custom_mountain != null:
		proc_custom_mountain.placeholder_text = "0.06"
	if proc_custom_river != null:
		proc_custom_river.placeholder_text = "0.04"
	if proc_custom_lake != null:
		proc_custom_lake.placeholder_text = "0.03"
	if proc_custom_mines != null:
		proc_custom_mines.placeholder_text = "0"
	if proc_custom_camps != null:
		proc_custom_camps.placeholder_text = "0"
	if proc_custom_dragons != null:
		proc_custom_dragons.placeholder_text = "0"
	if proc_custom_apply != null and not proc_custom_apply.is_connected("pressed", Callable(self, "_on_proc_custom_apply_pressed")):
		proc_custom_apply.connect("pressed", Callable(self, "_on_proc_custom_apply_pressed"))
	if proc_custom_close != null and not proc_custom_close.is_connected("pressed", Callable(self, "_on_proc_custom_close_pressed")):
		proc_custom_close.connect("pressed", Callable(self, "_on_proc_custom_close_pressed"))

func _get_procedural_map_data() -> MapData:
	if turn_mgr == null:
		return null
	for i in range(turn_mgr.map_data.size()):
		var md = turn_mgr.map_data[i] as MapData
		if md != null and md.procedural:
			return md
	return null

func _default_proc_custom_params() -> Dictionary:
	var md = _get_procedural_map_data()
	if md == null:
		return {
			"map_size": "normal",
			"proc_columns": 0,
			"proc_rows": 0,
			"proc_forest_ratio": 0.18,
			"proc_mountain_ratio": 0.06,
			"proc_river_ratio": 0.04,
			"proc_lake_ratio": 0.03,
			"proc_mine_count": 0,
			"proc_camp_count": 0,
			"proc_dragon_count": 0
		}
	return {
		"map_size": str(md.map_size),
		"proc_columns": int(md.proc_columns),
		"proc_rows": int(md.proc_rows),
		"proc_forest_ratio": float(md.proc_forest_ratio),
		"proc_mountain_ratio": float(md.proc_mountain_ratio),
		"proc_river_ratio": float(md.proc_river_ratio),
		"proc_lake_ratio": float(md.proc_lake_ratio),
		"proc_mine_count": int(md.proc_mine_count),
		"proc_camp_count": int(md.proc_camp_count),
		"proc_dragon_count": int(md.proc_dragon_count)
	}

func _ensure_proc_custom_params() -> void:
	if NetworkManager.custom_proc_params.size() > 0:
		return
	var defaults = _default_proc_custom_params()
	if NetworkManager.has_method("set_custom_proc_params"):
		NetworkManager.set_custom_proc_params(defaults)
	else:
		NetworkManager.custom_proc_params = defaults

func _set_proc_custom_panel_visible(show: bool) -> void:
	if proc_custom_panel == null:
		return
	if show:
		_ensure_proc_custom_params()
		_populate_proc_custom_fields(NetworkManager.custom_proc_params)
	proc_custom_panel.visible = show

func _populate_proc_custom_fields(params: Dictionary) -> void:
	if params.is_empty():
		return
	var size = str(params.get("map_size", "normal"))
	if proc_custom_size != null:
		proc_custom_size.select(1 if size == "small" else 0)
	if proc_custom_columns != null:
		proc_custom_columns.text = str(int(params.get("proc_columns", 0)))
	if proc_custom_rows != null:
		proc_custom_rows.text = str(int(params.get("proc_rows", 0)))
	if proc_custom_forest != null:
		proc_custom_forest.text = str(float(params.get("proc_forest_ratio", 0.18)))
	if proc_custom_mountain != null:
		proc_custom_mountain.text = str(float(params.get("proc_mountain_ratio", 0.06)))
	if proc_custom_river != null:
		proc_custom_river.text = str(float(params.get("proc_river_ratio", 0.04)))
	if proc_custom_lake != null:
		proc_custom_lake.text = str(float(params.get("proc_lake_ratio", 0.03)))
	if proc_custom_mines != null:
		proc_custom_mines.text = str(int(params.get("proc_mine_count", 0)))
	if proc_custom_camps != null:
		proc_custom_camps.text = str(int(params.get("proc_camp_count", 0)))
	if proc_custom_dragons != null:
		proc_custom_dragons.text = str(int(params.get("proc_dragon_count", 0)))

func _parse_int_edit(edit: LineEdit, fallback: int) -> int:
	if edit == null:
		return fallback
	var text = edit.text.strip_edges()
	if text == "":
		return fallback
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return int(round(float(text)))
	return fallback

func _parse_float_edit(edit: LineEdit, fallback: float) -> float:
	if edit == null:
		return fallback
	var text = edit.text.strip_edges()
	if text == "":
		return fallback
	if text.is_valid_float():
		return float(text)
	if text.is_valid_int():
		return float(int(text))
	return fallback

func _collect_proc_custom_params() -> Dictionary:
	var defaults = _default_proc_custom_params()
	var size = "normal"
	if proc_custom_size != null and proc_custom_size.selected == 1:
		size = "small"
	var columns = _parse_int_edit(proc_custom_columns, int(defaults.get("proc_columns", 0)))
	var rows = _parse_int_edit(proc_custom_rows, int(defaults.get("proc_rows", 0)))
	var forest_ratio = clamp(_parse_float_edit(proc_custom_forest, float(defaults.get("proc_forest_ratio", 0.18))), 0.0, 1.0)
	var mountain_ratio = clamp(_parse_float_edit(proc_custom_mountain, float(defaults.get("proc_mountain_ratio", 0.06))), 0.0, 1.0)
	var river_ratio = clamp(_parse_float_edit(proc_custom_river, float(defaults.get("proc_river_ratio", 0.04))), 0.0, 1.0)
	var lake_ratio = clamp(_parse_float_edit(proc_custom_lake, float(defaults.get("proc_lake_ratio", 0.03))), 0.0, 1.0)
	var mine_count = _parse_int_edit(proc_custom_mines, int(defaults.get("proc_mine_count", 0)))
	var camp_count = _parse_int_edit(proc_custom_camps, int(defaults.get("proc_camp_count", 0)))
	var dragon_count = _parse_int_edit(proc_custom_dragons, int(defaults.get("proc_dragon_count", 0)))
	return {
		"map_size": size,
		"proc_columns": columns,
		"proc_rows": rows,
		"proc_forest_ratio": forest_ratio,
		"proc_mountain_ratio": mountain_ratio,
		"proc_river_ratio": river_ratio,
		"proc_lake_ratio": lake_ratio,
		"proc_mine_count": mine_count,
		"proc_camp_count": camp_count,
		"proc_dragon_count": dragon_count
	}

func _on_proc_custom_apply_pressed() -> void:
	var params = _collect_proc_custom_params()
	if NetworkManager.has_method("set_custom_proc_params"):
		NetworkManager.set_custom_proc_params(params)
	else:
		NetworkManager.custom_proc_params = params
	_populate_proc_custom_fields(params)

func _on_proc_custom_close_pressed() -> void:
	_set_proc_custom_panel_visible(false)

func _sync_map_select_from_state() -> void:
	if map_select == null:
		return
	if NetworkManager.map_selection_mode == "":
		NetworkManager.map_selection_mode = "random_normal"
	var id = MAP_SELECT_RANDOM_NORMAL
	if NetworkManager.selected_map_index >= 0:
		id = MAP_SELECT_MAP_BASE + NetworkManager.selected_map_index
	else:
		match NetworkManager.map_selection_mode:
			"random_any":
				id = MAP_SELECT_RANDOM_ANY
			"random_themed":
				id = MAP_SELECT_RANDOM_THEMED
			"random_small":
				id = MAP_SELECT_RANDOM_SMALL
			"procedural":
				id = MAP_SELECT_PROCEDURAL
			"procedural_custom":
				id = MAP_SELECT_PROCEDURAL_CUSTOM
			"random_normal":
				id = MAP_SELECT_RANDOM_NORMAL
			_:
				id = MAP_SELECT_RANDOM_NORMAL
	_set_map_select_label(id)
	_apply_map_selection(id)

func _set_map_select_label(id: int) -> void:
	if map_select == null:
		return
	var label = ""
	match id:
		MAP_SELECT_RANDOM_ANY:
			label = "Random (Any)"
		MAP_SELECT_RANDOM_NORMAL:
			label = "Random Normal"
		MAP_SELECT_RANDOM_THEMED:
			label = "Random Themed"
		MAP_SELECT_RANDOM_SMALL:
			label = "Random Small"
		MAP_SELECT_PROCEDURAL:
			label = "Procedural Map"
		MAP_SELECT_PROCEDURAL_CUSTOM:
			label = "Procedural (Custom)"
		_:
			label = str(_map_select_names.get(id, "Map"))
	map_select.text = label

func _on_map_select_menu_pressed(id: int) -> void:
	if id < 0:
		return
	if not NetworkManager.is_host():
		return
	_set_map_select_label(id)
	_apply_map_selection(id)

func _apply_map_selection(id: int) -> void:
	_map_select_id = id
	var show_custom = id == MAP_SELECT_PROCEDURAL_CUSTOM
	_set_proc_custom_panel_visible(show_custom)
	if not show_custom and NetworkManager.custom_proc_params.size() > 0:
		if NetworkManager.has_method("set_custom_proc_params"):
			NetworkManager.set_custom_proc_params({})
		else:
			NetworkManager.custom_proc_params = {}
	if id == MAP_SELECT_RANDOM_ANY:
		NetworkManager.selected_map_index = -1
		NetworkManager.map_selection_mode = "random_any"
		if NetworkManager.is_host():
			NetworkManager.broadcast_map_selection()
		return
	if id == MAP_SELECT_RANDOM_NORMAL:
		NetworkManager.selected_map_index = -1
		NetworkManager.map_selection_mode = "random_normal"
		if NetworkManager.is_host():
			NetworkManager.broadcast_map_selection()
		return
	if id == MAP_SELECT_RANDOM_THEMED:
		NetworkManager.selected_map_index = -1
		NetworkManager.map_selection_mode = "random_themed"
		if NetworkManager.is_host():
			NetworkManager.broadcast_map_selection()
		return
	if id == MAP_SELECT_RANDOM_SMALL:
		NetworkManager.selected_map_index = -1
		NetworkManager.map_selection_mode = "random_small"
		if NetworkManager.is_host():
			NetworkManager.broadcast_map_selection()
		return
	if id == MAP_SELECT_PROCEDURAL:
		NetworkManager.selected_map_index = -1
		NetworkManager.map_selection_mode = "procedural"
		if NetworkManager.is_host():
			NetworkManager.broadcast_map_selection()
		return
	if id == MAP_SELECT_PROCEDURAL_CUSTOM:
		NetworkManager.selected_map_index = -1
		NetworkManager.map_selection_mode = "procedural_custom"
		if NetworkManager.is_host():
			NetworkManager.broadcast_map_selection()
		return
	if id >= MAP_SELECT_MAP_BASE:
		var idx = id - MAP_SELECT_MAP_BASE
		if idx >= 0 and idx < turn_mgr.map_data.size():
			NetworkManager.selected_map_index = idx
			NetworkManager.map_selection_mode = "fixed"
			if NetworkManager.is_host():
				NetworkManager.broadcast_map_selection()

func _sync_menu_checks() -> void:
	if menu_popup == null:
		return
	_set_menu_checked(MENU_ID_UNIT_STATS, $StatsPanel.visible)
	_set_menu_checked(MENU_ID_BUILDING_STATS, $BuildingStatsPanel.visible)
	_set_menu_checked(MENU_ID_SPELL_STATS, $SpellStatsPanel.visible)
	_set_menu_checked(MENU_ID_TERRAIN_STATS, $TerrainStatsPanel.visible)
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
	if id == MENU_ID_SPELL_STATS:
		var next = not $SpellStatsPanel.visible
		if $SpellStatsCheckButton.has_method("set_pressed_no_signal"):
			$SpellStatsCheckButton.set_pressed_no_signal(next)
		else:
			$SpellStatsCheckButton.button_pressed = next
		_on_spell_stats_toggled(next)
		return
	if id == MENU_ID_TERRAIN_STATS:
		var next = not $TerrainStatsPanel.visible
		if $TerrainStatsCheckButton.has_method("set_pressed_no_signal"):
			$TerrainStatsCheckButton.set_pressed_no_signal(next)
		else:
			$TerrainStatsCheckButton.button_pressed = next
		_on_terrain_stats_toggled(next)
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
	if id == MENU_ID_CONCEDE:
		if confirm_concede_dialog != null:
			confirm_concede_dialog.popup_centered()
		elif turn_mgr != null:
			NetworkManager.request_concede(turn_mgr.local_player_id)
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
		col_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
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

func _setup_stats_tree(tree: Tree, columns: Array, widths: Array, expand_last: bool, font: FontFile) -> TreeItem:
	if tree == null:
		return null
	tree.clear()
	tree.columns = columns.size()
	tree.hide_root = true
	if tree.has_method("set_column_titles_visible"):
		tree.set_column_titles_visible(true)
	else:
		tree.column_titles_visible = true
	if tree.has_method("set_scroll_horizontal_enabled"):
		tree.set_scroll_horizontal_enabled(true)
	else:
		tree.scroll_horizontal_enabled = true
	if tree.has_method("set_scroll_vertical_enabled"):
		tree.set_scroll_vertical_enabled(true)
	if font != null:
		tree.add_theme_font_override("font", font)
	tree.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	tree.add_theme_color_override("font_color_selected", Color(0.08, 0.08, 0.08))
	tree.add_theme_color_override("font_color_title", Color(0.08, 0.08, 0.08))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.86, 0.86, 0.86)
	tree.add_theme_stylebox_override("panel", panel_style)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.76, 0.76, 0.76)
	tree.add_theme_stylebox_override("selected", selected_style)
	tree.add_theme_stylebox_override("selected_focus", selected_style)
	for i in range(columns.size()):
		tree.set_column_title(i, str(columns[i]))
		if i < widths.size():
			if tree.has_method("set_column_custom_minimum_width"):
				tree.set_column_custom_minimum_width(i, int(widths[i]))
			elif tree.has_method("set_column_min_width"):
				tree.set_column_min_width(i, int(widths[i]))
		if tree.has_method("set_column_expand"):
			tree.set_column_expand(i, expand_last and i == columns.size() - 1)
		if tree.has_method("set_column_title_alignment"):
			tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	var root = tree.create_item()
	return root

func _add_stats_tree_row(tree: Tree, root: TreeItem, columns: Array, selectable: bool) -> void:
	if tree == null or root == null:
		return
	var item = tree.create_item(root)
	for i in range(columns.size()):
		item.set_text(i, str(columns[i]))
		item.set_selectable(i, selectable)

func _autosize_tree_column(tree: Tree, column_index: int, header: String, values: Array, font: FontFile) -> void:
	if tree == null or font == null:
		return
	var max_width = font.get_string_size(header).x
	for value in values:
		var width = font.get_string_size(str(value)).x
		if width > max_width:
			max_width = width
	max_width += 20.0
	if tree.has_method("set_column_custom_minimum_width"):
		tree.set_column_custom_minimum_width(column_index, int(ceil(max_width)))
	elif tree.has_method("set_column_min_width"):
		tree.set_column_min_width(column_index, int(ceil(max_width)))

func _autosize_tree_columns(tree: Tree, headers: Array, rows: Array, font: FontFile) -> void:
	if tree == null or font == null:
		return
	if headers.is_empty():
		return
	var col_count = headers.size()
	var value_lists := []
	value_lists.resize(col_count)
	for i in range(col_count):
		value_lists[i] = []
	for row in rows:
		if row is Array:
			for i in range(min(col_count, row.size())):
				value_lists[i].append(row[i])
	for i in range(col_count):
		_autosize_tree_column(tree, i, str(headers[i]), value_lists[i], font)

func _add_unit_stats_row(container: VBoxContainer, columns: Array, widths: Array, font: FontFile, wrap_last: bool, add_separator: bool = true) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(row)
	for i in range(columns.size()):
		var col_label = Label.new()
		col_label.add_theme_font_override("font", font)
		col_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
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
	_update_queue_preview()

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

func _queue_path_index(path: Array, tile: Vector2i) -> int:
	for i in range(path.size()):
		if path[i] == tile:
			return i
	return -1

func _clear_queue_preview() -> void:
	if _queue_preview_unit_id == -1:
		return
	var preview_node = hex.get_node_or_null("PreviewPathArrows")
	if preview_node != null:
		for child in preview_node.get_children():
			child.queue_free()
	_queue_preview_unit_id = -1

func _draw_preview_path(path: Array) -> void:
	var preview_node = hex.get_node_or_null("PreviewPathArrows")
	if preview_node == null:
		return
	for child in preview_node.get_children():
		child.queue_free()
	if path.size() < 2:
		return
	var root = Node2D.new()
	preview_node.add_child(root)
	for i in range(path.size() - 1):
		var a = path[i]
		var b = path[i + 1]
		if typeof(a) != TYPE_VECTOR2I or typeof(b) != TYPE_VECTOR2I:
			continue
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

func _update_queue_preview() -> void:
	if action_mode != "" or placing_unit != "" or current_path.size() > 1:
		_clear_queue_preview()
		return
	var cam = get_viewport().get_camera_2d()
	if cam == null:
		_clear_queue_preview()
		return
	var cell = hex.world_to_map(cam.get_global_mouse_position())
	var unit = game_board.get_unit_at(cell)
	if unit == null:
		_clear_queue_preview()
		return
	if unit.player_id != turn_mgr.local_player_id:
		_clear_queue_preview()
		return
	var path: Array = []
	if unit.build_queue.size() >= 2:
		path = unit.build_queue.duplicate()
	elif unit.move_queue.size() >= 2:
		path = unit.move_queue.duplicate()
	else:
		var order := {}
		if turn_mgr.current_phase == turn_mgr.Phase.EXECUTION:
			if turn_mgr.committed_orders.has(turn_mgr.local_player_id):
				order = turn_mgr.committed_orders[turn_mgr.local_player_id].get(unit.net_id, {})
		else:
			order = turn_mgr.get_order(turn_mgr.local_player_id, unit.net_id)
		if order.is_empty() or str(order.get("type", "")) != "move":
			_clear_queue_preview()
			return
		var order_path = order.get("path", [])
		if not (order_path is Array) or order_path.size() < 2:
			_clear_queue_preview()
			return
		path = order_path
	if unit.net_id == _queue_preview_unit_id:
		return
	var idx = _queue_path_index(path, unit.grid_pos)
	if idx < 0:
		_clear_queue_preview()
		return
	if idx > 0:
		path = path.slice(idx)
	_queue_preview_unit_id = unit.net_id
	_draw_preview_path(path)

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

func _refresh_spell_menu_labels() -> void:
	for entry in SPELL_OPTIONS:
		var label = entry["label"]
		if entry["type"] == turn_mgr.SPELL_BUFF:
			label = "%s (5-100 mana)" % label
		else:
			var mana_cost = int(turn_mgr.get_spell_cost(entry["type"]))
			if mana_cost > 0:
				label = "%s (%d mana)" % [label, mana_cost]
		var idx = -1
		for i in range(spell_menu.get_item_count()):
			if spell_menu.get_item_id(i) == entry["id"]:
				idx = i
				break
		if idx >= 0:
			spell_menu.set_item_text(idx, label)

func _show_buff_mana_panel() -> void:
	if buff_mana_panel == null or buff_mana_slider == null or buff_mana_input == null:
		return
	var min_mana = int(turn_mgr.SPELL_BUFF_MIN)
	var max_mana = int(turn_mgr.SPELL_BUFF_MAX)
	var available = int(turn_mgr.player_mana.get(current_player, 0))
	max_mana = min(max_mana, available)
	if max_mana < min_mana:
		status_lbl.text = "[Not enough mana]"
		pending_spell_type = ""
		buff_mana_panel.visible = false
		return
	buff_mana_slider.min_value = float(min_mana)
	buff_mana_slider.max_value = float(max_mana)
	buff_mana_slider.step = float(turn_mgr.SPELL_BUFF_STEP)
	var start_value = clamp(int(buff_mana_slider.value), min_mana, max_mana)
	if start_value < min_mana:
		start_value = min_mana
	buff_mana_slider.value = float(start_value)
	if buff_mana_input != null:
		_buff_input_updating = true
		buff_mana_input.text = str(start_value)
		_buff_input_updating = false
	_on_buff_mana_value_changed(buff_mana_slider.value)
	var viewport_size = get_viewport().get_visible_rect().size
	var panel_size = buff_mana_panel.size
	if panel_size == Vector2.ZERO:
		panel_size = buff_mana_panel.get_minimum_size()
	var pos = last_click_pos
	pos.x = clamp(pos.x, 0.0, max(0.0, viewport_size.x - panel_size.x))
	pos.y = clamp(pos.y, 0.0, max(0.0, viewport_size.y - panel_size.y))
	buff_mana_panel.position = pos
	buff_mana_panel.visible = true

func _snap_buff_mana_value(value: int, min_mana: int, max_mana: int) -> int:
	var step = int(turn_mgr.SPELL_BUFF_STEP)
	var snapped = int(round(float(value) / float(step))) * step
	return clamp(snapped, min_mana, max_mana)

func _on_buff_mana_value_changed(value: float) -> void:
	if _buff_input_updating:
		return
	var min_mana = int(turn_mgr.SPELL_BUFF_MIN)
	var max_mana = int(turn_mgr.SPELL_BUFF_MAX)
	var snapped = _snap_buff_mana_value(int(round(value)), min_mana, max_mana)
	current_spell_mana_spent = snapped
	if buff_mana_input != null:
		_buff_input_updating = true
		buff_mana_input.text = str(snapped)
		_buff_input_updating = false

func _on_buff_mana_text_changed(text: String) -> void:
	if _buff_input_updating:
		return
	if buff_mana_slider == null:
		return
	var value = int(text) if text.is_valid_int() else -1
	if value < 0:
		return
	var min_mana = int(turn_mgr.SPELL_BUFF_MIN)
	var max_mana = int(turn_mgr.SPELL_BUFF_MAX)
	var snapped = _snap_buff_mana_value(value, min_mana, max_mana)
	_buff_input_updating = true
	buff_mana_slider.value = float(snapped)
	_buff_input_updating = false
	current_spell_mana_spent = snapped

func _on_buff_mana_text_submitted(text: String) -> void:
	_on_buff_mana_text_changed(text)

func _on_buff_mana_confirm() -> void:
	if pending_spell_type != turn_mgr.SPELL_BUFF:
		buff_mana_panel.visible = false
		return
	buff_mana_panel.visible = false
	current_spell_mana_spent = int(buff_mana_slider.value)
	action_mode = "spell"
	current_spell_type = pending_spell_type
	pending_spell_type = ""
	spell_tiles = _get_spell_target_tiles(spell_caster, current_spell_type)
	if spell_tiles.is_empty():
		status_lbl.text = "[No valid spell targets]"
		action_mode = ""
		current_spell_type = ""
		current_spell_mana_spent = 0
		spell_caster = null
		if buff_mana_input != null:
			_buff_input_updating = true
			buff_mana_input.text = str(int(turn_mgr.SPELL_BUFF_MIN))
			_buff_input_updating = false
		return
	game_board.show_highlights(spell_tiles)

func _on_buff_mana_cancel() -> void:
	pending_spell_type = ""
	current_spell_mana_spent = 0
	if buff_mana_input != null:
		_buff_input_updating = true
		buff_mana_input.text = str(int(turn_mgr.SPELL_BUFF_MIN))
		_buff_input_updating = false
	spell_caster = null
	current_spell_type = ""
	spell_tiles = []
	buff_mana_panel.visible = false

func _get_spell_target_tiles(caster: Node, spell_type: String) -> Array:
	var tiles := []
	if caster == null or not is_instance_valid(caster):
		return tiles
	var spell_range = int(turn_mgr.SPELL_RANGE)
	if turn_mgr.has_method("get_spell_range"):
		spell_range = int(turn_mgr.get_spell_range(caster))
	if spell_type == turn_mgr.SPELL_TARGETED_VISION:
		for cell in hex.used_cells:
			if turn_mgr._hex_distance(caster.grid_pos, cell) <= spell_range:
				tiles.append(cell)
		return tiles
	var seen := {}
	var all_units = game_board.get_all_units_flat()
	for unit in all_units:
		if unit == null:
			continue
		var is_enemy = unit.player_id != current_player
		if spell_type == "fireball" or spell_type == "lightning":
			if not is_enemy:
				continue
		else:
			if unit.player_id != current_player:
				continue
		if turn_mgr.is_unit_hidden_for_viewer(unit, current_player):
			continue
		if not turn_mgr._player_can_see_tile(current_player, unit.grid_pos):
			continue
		if turn_mgr._hex_distance(caster.grid_pos, unit.grid_pos) > spell_range:
			continue
		if seen.has(unit.grid_pos):
			continue
		seen[unit.grid_pos] = true
		tiles.append(unit.grid_pos)
	return tiles

func _spell_target_for_tile(tile: Vector2i, spell_type: String) -> Node:
	if spell_type == "fireball":
		var struct = game_board.get_structure_unit_at(tile)
		if struct != null and struct.player_id != current_player:
			return struct
		var unit = game_board.get_unit_at(tile)
		if unit != null and unit.player_id != current_player and not turn_mgr.is_unit_hidden_for_viewer(unit, current_player):
			return unit
		return null
	if spell_type == "lightning":
		var unit = game_board.get_unit_at(tile)
		if unit != null and unit.player_id != current_player and not turn_mgr.is_unit_hidden_for_viewer(unit, current_player):
			return unit
		return null
	var unit = game_board.get_unit_at(tile)
	if unit != null and unit.player_id == current_player:
		return unit
	var struct = game_board.get_structure_unit_at(tile)
	if struct != null and struct.player_id == current_player:
		return struct
	return null
	

func _on_orders_phase_begin(player: String) -> void:
	# show the UI and reset state
	current_player = player
	_update_turn_label()
	_refresh_resource_labels()
	placing_unit  = ""
	$Panel.visible = true
	if resource_panel != null:
		resource_panel.visible = true
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
	status_lbl.text = "Click map to place Archer"
	_find_placeable()

func _on_wizard_pressed():
	placing_unit = "wizard"
	status_lbl.text = "Click map to place Wizard"
	_find_placeable()

func _on_soldier_pressed():
	placing_unit = "soldier"
	status_lbl.text = "Click map to place Soldier"
	_find_placeable()

func _on_scout_pressed():
	placing_unit = "scout"
	status_lbl.text = "Click map to place Scout"
	_find_placeable()

func _on_miner_pressed():
	placing_unit = "miner"
	status_lbl.text = "Click map to place Miner"
	_find_placeable()

func _on_crystal_miner_pressed():
	placing_unit = "crystal_miner"
	status_lbl.text = "Click map to place Crystal Miner"
	_find_placeable()

func _on_builder_pressed():
	placing_unit = "builder"
	status_lbl.text = "Click map to place Builder"
	_find_placeable()

func _on_tank_pressed():
	placing_unit = "phalanx"
	status_lbl.text = "Click map to place Phalanx"
	_find_placeable()

func _on_cavalry_pressed():
	placing_unit = "cavalry"
	status_lbl.text = "Click map to place Cavalry"
	_find_placeable()

func _find_placeable():
	var base = game_board.get_structure_unit_at(turn_mgr.base_positions[current_player])
	if dev_mode_toggle.button_pressed:
		action_mode = "dev_place"
	else:
		action_mode = "place"
	var result = game_board.get_reachable_tiles(base.grid_pos, 1, action_mode, null, placing_unit)
	var tiles = result["tiles"]
	game_board.show_highlights(tiles)
	current_reachable = result

func _cancel_purchase_mode() -> void:
	placing_unit = ""
	action_mode = ""
	current_reachable = {}
	game_board.clear_highlights()
	_update_done_button_state()

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
	status_lbl.text = "Income granted"
	_refresh_resource_labels()

func _on_respawn_timers_toggled(pressed: bool) -> void:
	turn_mgr.set_respawn_timer_override(pressed)

func _on_resync_pressed() -> void:
	NetworkManager.request_state()

func _on_skip_movement_pressed() -> void:
	if not turn_mgr.is_host():
		status_lbl.text = "[Skip failed: host only]"
		return
	if turn_mgr.current_phase != turn_mgr.Phase.EXECUTION:
		status_lbl.text = "[Skip failed: execution only]"
		return
	turn_mgr.force_skip_movement_phase()

func _on_damage_toggle_pressed() -> void:
	damage_panel_minimized = not damage_panel_minimized
	_update_damage_panel()

func _apply_damage_panel_size(size: Vector2) -> void:
	if damage_panel == null:
		return
	damage_panel.size = size
	damage_panel.offset_left = -size.x
	damage_panel.offset_top = -size.y
	damage_panel.offset_right = 0
	damage_panel.offset_bottom = 0

func _update_damage_panel() -> void:
	if damage_scroll == null or damage_panel == null:
		return
	var header_height = 26.0
	if damage_panel_minimized:
		damage_scroll.visible = false
		damage_panel.custom_minimum_size = Vector2(damage_panel_full_size.x, header_height)
		_apply_damage_panel_size(Vector2(damage_panel_full_size.x, header_height))
		damage_toggle_button.text = "+"
	else:
		damage_scroll.visible = true
		damage_panel.custom_minimum_size = Vector2.ZERO
		_apply_damage_panel_size(damage_panel_full_size)
		damage_toggle_button.text = "-"
	if damage_resize_handle != null:
		damage_resize_handle.visible = not damage_panel_minimized

func _on_damage_resize_input(event: InputEvent) -> void:
	if damage_panel_minimized or damage_panel == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			damage_panel_dragging = true
			damage_panel_drag_start = get_viewport().get_mouse_position()
			damage_panel_start_size = damage_panel_full_size
		else:
			damage_panel_dragging = false
	elif event is InputEventMouseMotion and damage_panel_dragging:
		var delta = get_viewport().get_mouse_position() - damage_panel_drag_start
		var new_size = damage_panel_start_size - delta
		var viewport_size = get_viewport().get_visible_rect().size
		new_size.x = clamp(new_size.x, DAMAGE_PANEL_MIN_SIZE.x, viewport_size.x)
		new_size.y = clamp(new_size.y, DAMAGE_PANEL_MIN_SIZE.y, viewport_size.y)
		damage_panel_full_size = new_size
		_apply_damage_panel_size(new_size)

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
		status_lbl.text = "[Save failed: host only]"
		return
	if turn_mgr.save_game_slot(save_slot_index):
		status_lbl.text = "Game saved (slot %d)" % (save_slot_index + 1)
	else:
		status_lbl.text = "[Save failed]"

func _on_load_game_pressed() -> void:
	if not turn_mgr.is_host():
		status_lbl.text = "[Load failed: host only]"
		return
	if turn_mgr.load_game_slot(save_slot_index):
		status_lbl.text = "Game loaded (slot %d)" % (save_slot_index + 1)
	else:
		status_lbl.text = "[Load failed]"

func _on_load_autosave_pressed() -> void:
	if not turn_mgr.is_host():
		status_lbl.text = "[Load failed: host only]"
		return
	if turn_mgr.load_game_slot(-1):
		status_lbl.text = "Autosave loaded"
	else:
		status_lbl.text = "[Load failed]"

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
		"not_enough_mana":
			msg = "[Order failed: not enough mana]"
		"no_vision":
			msg = "[Order failed: no vision]"
		"no_spell_order":
			msg = "[Order failed: no spell to cancel]"
		_:
			msg = "[Order failed]"
	return _format_error_with_gold(msg)

func _format_error_with_gold(message: String) -> String:
	return message

func _current_resource_spend(player_id: String) -> Dictionary:
	var spend := {"gold": 0, "mana": 0}
	if turn_mgr == null or player_id == "":
		return spend
	var orders = turn_mgr.player_orders.get(player_id, {})
	if turn_mgr.current_phase == turn_mgr.Phase.EXECUTION:
		orders = turn_mgr.committed_orders.get(player_id, orders)
	for order in orders.values():
		var otype = str(order.get("type", ""))
		if otype == "build":
			var struct_type = str(order.get("structure_type", ""))
			spend["gold"] += int(turn_mgr.get_build_turn_cost(struct_type))
		elif otype == "spell":
			var spell_type = str(order.get("spell_type", ""))
			if spell_type == turn_mgr.SPELL_BUFF:
				spend["mana"] += int(order.get("mana_spent", 0))
			else:
				spend["mana"] += int(turn_mgr.get_spell_cost(spell_type))
		elif otype == "ward_vision":
			spend["mana"] += int(turn_mgr.WARD_VISION_MANA_COST)
	return spend

func _refresh_resource_labels() -> void:
	if turn_mgr == null or current_player == "":
		return
	var gold = int(turn_mgr.player_gold.get(current_player, 0))
	var income = int(turn_mgr.player_income.get(current_player, 0))
	var mana = int(turn_mgr.player_mana.get(current_player, 0))
	var cap = int(turn_mgr.player_mana_cap.get(current_player, 0))
	var mana_income = int(turn_mgr.player_mana_income.get(current_player, 0))
	var spend = _current_resource_spend(current_player)
	if gold_resource_lbl != null:
		gold_resource_lbl.text = "Gold: %d  Spend: %d  Income: +%d" % [gold, int(spend["gold"]), income]
	if mana_resource_lbl != null:
		mana_resource_lbl.text = "Mana: %d/%d  Spend: %d  Income: +%d" % [mana, cap, int(spend["mana"]), mana_income]
	if dragon_buff_lbl != null:
		var melee_bonus = int(turn_mgr.player_melee_bonus.get(current_player, 0))
		var ranged_bonus = int(turn_mgr.player_ranged_bonus.get(current_player, 0))
		dragon_buff_lbl.text = "Dragon Buffs: +%d melee / +%d ranged" % [melee_bonus, ranged_bonus]

func _on_buy_result(player_id: String, unit_type: String, grid_pos: Vector2i, ok: bool, reason: String, cost: int, _unit_net_id: int) -> void:
	if player_id != turn_mgr.local_player_id:
		return
	if turn_mgr.is_host():
		return
	if ok:
		_refresh_resource_labels()
	else:
		status_lbl.text = _buy_error_message(reason, cost)
		_cancel_purchase_mode()

func _on_undo_result(player_id: String, unit_net_id: int, ok: bool, reason: String, refund: int) -> void:
	if player_id != turn_mgr.local_player_id:
		return
	if turn_mgr.is_host():
		return
	if ok:
		_refresh_resource_labels()
	else:
		status_lbl.text = _undo_error_message(reason)

func _on_order_result(player_id: String, unit_net_id: int, order: Dictionary, ok: bool, reason: String) -> void:
	if player_id != turn_mgr.local_player_id:
		return
	if ok:
		if order.get("type", "") == "ward_vision_stop":
			turn_mgr.player_orders[player_id].erase(unit_net_id)
			NetworkManager.player_orders[player_id].erase(unit_net_id)
			var ward_tile = order.get("ward_tile", Vector2i(-9999, -9999))
			if typeof(ward_tile) == TYPE_VECTOR2I:
				var state = turn_mgr.buildable_structures.get(ward_tile, {})
				if not state.is_empty() and str(state.get("type", "")) == turn_mgr.STRUCT_WARD and str(state.get("owner", "")) == current_player:
					state["auto_ward"] = false
					turn_mgr.buildable_structures[ward_tile] = state
			_draw_all()
			$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
			_update_done_button_state()
			_refresh_resource_labels()
			return
		if order.get("type", "") == "spell_cancel":
			turn_mgr.player_orders[player_id].erase(unit_net_id)
			NetworkManager.player_orders[player_id].erase(unit_net_id)
			_draw_all()
			$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
			_update_done_button_state()
			_refresh_resource_labels()
			return
		turn_mgr.player_orders[player_id][unit_net_id] = order
		NetworkManager.player_orders[player_id][unit_net_id] = order
		var unit = unit_mgr.get_unit_by_net_id(unit_net_id)
		if unit != null:
			unit.is_defending = false
			unit.is_healing = false
			unit.is_moving = false
			if order.has("queue_path") and order["queue_path"] is Array:
				unit.build_queue = order["queue_path"]
				unit.build_queue_type = str(order.get("queue_type", ""))
				unit.build_queue_last_type = ""
				unit.build_queue_last_target = Vector2i(-9999, -9999)
				unit.build_queue_last_build_left = -1
				_queue_preview_unit_id = -1
			if order.has("move_queue_path") and order["move_queue_path"] is Array:
				unit.move_queue = order["move_queue_path"]
				unit.move_queue_last_target = Vector2i(-9999, -9999)
				_queue_preview_unit_id = -1
			if order.get("type", "") != "heal":
				unit.auto_heal = false
			if order.get("type", "") != "defend":
				unit.auto_defend = false
			if order.get("type", "") != "lookout":
				unit.auto_lookout = false
			match order.get("type", ""):
				"move":
					unit.is_moving = true
					var path = order.get("path", [])
					if path.size() > 1:
						unit.moving_to = path[1]
				"heal":
					unit.is_healing = true
					if bool(order.get("auto_heal", false)):
						unit.auto_heal = true
				"defend":
					unit.is_defending = true
					if bool(order.get("auto_defend", false)):
						unit.auto_defend = true
				"lookout":
					if bool(order.get("auto_lookout", false)):
						unit.auto_lookout = true
			unit.ordered = true
		_draw_all()
		$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
		_update_done_button_state()
		_refresh_resource_labels()
	else:
		status_lbl.text = _order_error_message(reason)

func _load_username() -> String:
	var cfg = ConfigFile.new()
	if cfg.load(USERNAME_SAVE_PATH) == OK:
		return str(cfg.get_value("user", "name", "")).strip_edges()
	return ""

func _save_username(name: String) -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("user", "name", name.strip_edges())
	cfg.save(USERNAME_SAVE_PATH)

func _show_main_menu() -> void:
	if username_label != null:
		username_label.visible = true
	if username_edit != null:
		username_edit.visible = true
	$HostButton.visible = true
	$JoinButton.visible = true
	$IPLineEdit.visible = true
	$PortLineEdit.visible = true
	if map_select != null:
		map_select.visible = false
	if map_label != null:
		map_label.visible = false
	if lobby_panel != null:
		lobby_panel.visible = false
	lobby_slots_payload = []
	if proc_custom_panel != null:
		proc_custom_panel.visible = false
	$CancelGameButton.visible = false
	if lobby_start_button != null:
		lobby_start_button.disabled = true

func _show_lobby(is_host: bool) -> void:
	if username_label != null:
		username_label.visible = false
	if username_edit != null:
		username_edit.visible = false
	$HostButton.visible = false
	$JoinButton.visible = false
	$IPLineEdit.visible = false
	$PortLineEdit.visible = false
	if map_select != null:
		map_select.visible = true
		map_select.disabled = not is_host
	if map_label != null:
		map_label.visible = true
	if lobby_panel != null:
		lobby_panel.visible = true
	if proc_custom_panel != null:
		proc_custom_panel.visible = false
	$CancelGameButton.visible = true
	if lobby_add_button != null:
		lobby_add_button.visible = is_host
	if lobby_remove_button != null:
		lobby_remove_button.visible = is_host
	if lobby_start_button != null:
		lobby_start_button.visible = is_host
	_update_lobby_list()
	_update_start_game_state()

func _on_add_slot_pressed() -> void:
	NetworkManager.set_lobby_slot_count(NetworkManager.lobby_slot_count + 1)

func _on_remove_slot_pressed() -> void:
	NetworkManager.set_lobby_slot_count(NetworkManager.lobby_slot_count - 1)

func _on_start_game_pressed() -> void:
	NetworkManager.start_game_for_all()

func _on_lobby_updated(slots: Array, slot_count: int) -> void:
	lobby_slots_payload = slots
	_update_lobby_list()
	_update_start_game_state()

func _on_player_id_assigned(_player_id: String) -> void:
	_update_start_game_state()

func _on_map_selection_changed() -> void:
	if NetworkManager.is_host():
		return
	_sync_map_select_from_state()

func _update_lobby_list() -> void:
	if lobby_players == null:
		return
	for child in lobby_players.get_children():
		child.queue_free()
	var idx = 1
	for slot in lobby_slots_payload:
		var label = Label.new()
		var name = str(slot.get("username", "")).strip_edges()
		var occupied = bool(slot.get("occupied", false))
		if not occupied:
			name = "Empty"
		var player_id = str(slot.get("player_id", ""))
		if player_id == "":
			player_id = "player%d" % idx
		label.text = "Slot %d: %s (%s)" % [idx, name, player_id]
		lobby_players.add_child(label)
		idx += 1

func _update_start_game_state() -> void:
	if lobby_start_button == null:
		return
	if not NetworkManager.is_host():
		lobby_start_button.disabled = true
		return
	var full = NetworkManager.is_lobby_full()
	lobby_start_button.disabled = not full
	if lobby_add_button != null:
		lobby_add_button.disabled = NetworkManager.lobby_slot_count >= NetworkManager.MAX_PLAYERS
	if lobby_remove_button != null:
		lobby_remove_button.disabled = NetworkManager.lobby_slot_count <= 2

func _on_game_started() -> void:
	if lobby_panel != null:
		lobby_panel.visible = false
	if map_select != null:
		map_select.visible = false
	if map_label != null:
		map_label.visible = false
	if proc_custom_panel != null:
		proc_custom_panel.visible = false
	if $CancelGameButton != null:
		$CancelGameButton.visible = false

func _on_host_pressed():
	var username = ""
	if username_edit != null:
		username = username_edit.text.strip_edges()
	if username == "":
		username = "Player"
	NetworkManager.set_local_username(username)
	_save_username(username)
	_apply_map_selection(_map_select_id)
	if turn_mgr != null and turn_mgr.has_method("_reset_map_state"):
		turn_mgr.current_map_index = -1
		turn_mgr._reset_map_state()
	var port = $"PortLineEdit".text.strip_edges()
	NetworkManager.host_game(int(port))
	_show_lobby(true)

func _on_join_pressed():
	var ip = $"IPLineEdit".text.strip_edges()
	var port = $"PortLineEdit".text.strip_edges()
	var username = ""
	if username_edit != null:
		username = username_edit.text.strip_edges()
	if username == "":
		username = "Player"
	NetworkManager.set_local_username(username)
	_save_username(username)
	print("[UI] Joining game at %s:%d" % [ip, port])
	NetworkManager.join_game(ip, int(port))
	_show_lobby(false)

func _on_cancel_game_pressed():
	_show_main_menu()
	if resource_panel != null:
		resource_panel.visible = false
	cancel_done_button.visible = false
	exec_panel.visible = false
	turn_mgr.reset_to_lobby()
	_reset_ui_for_snapshot()
	_on_stats_toggled(false)
	_on_building_stats_toggled(false)
	_on_spell_stats_toggled(false)
	_on_terrain_stats_toggled(false)
	_update_done_button_state()
	NetworkManager.close_connection()

func _on_finish_move_button_pressed():
	if action_mode == "build_road_to":
		finish_build_road_path()
	elif action_mode == "build_rail_to":
		finish_build_rail_path()
	elif action_mode == "move_to":
		finish_move_to_path()
	else:
		finish_current_path()

func _on_stats_toggled(toggled):
	if toggled:
		_close_other_stats_panels("unit")
		if $StatsPanel.has_method("popup"):
			$StatsPanel.popup()
		else:
			$StatsPanel.visible = true
	else:
		$StatsPanel.visible = false
	_set_menu_checked(MENU_ID_UNIT_STATS, toggled)

func _on_building_stats_toggled(toggled):
	if toggled:
		_close_other_stats_panels("building")
		if $BuildingStatsPanel.has_method("popup"):
			$BuildingStatsPanel.popup()
		else:
			$BuildingStatsPanel.visible = true
	else:
		$BuildingStatsPanel.visible = false
	_set_menu_checked(MENU_ID_BUILDING_STATS, toggled)

func _on_spell_stats_toggled(toggled):
	if toggled:
		_close_other_stats_panels("spell")
		if $SpellStatsPanel.has_method("popup"):
			$SpellStatsPanel.popup()
		else:
			$SpellStatsPanel.visible = true
	else:
		$SpellStatsPanel.visible = false
	_set_menu_checked(MENU_ID_SPELL_STATS, toggled)

func _on_terrain_stats_toggled(toggled):
	if toggled:
		_close_other_stats_panels("terrain")
		if $TerrainStatsPanel.has_method("popup"):
			$TerrainStatsPanel.popup()
		else:
			$TerrainStatsPanel.visible = true
	else:
		$TerrainStatsPanel.visible = false
	_set_menu_checked(MENU_ID_TERRAIN_STATS, toggled)

func _on_unit_stats_close_pressed() -> void:
	$StatsPanel.visible = false
	$UnitStatsCheckButton.button_pressed = false
	_set_menu_checked(MENU_ID_UNIT_STATS, false)

func _on_building_stats_close_pressed() -> void:
	$BuildingStatsPanel.visible = false
	$BuildingStatsCheckButton.button_pressed = false
	_set_menu_checked(MENU_ID_BUILDING_STATS, false)

func _on_spell_stats_close_pressed() -> void:
	$SpellStatsPanel.visible = false
	$SpellStatsCheckButton.button_pressed = false
	_set_menu_checked(MENU_ID_SPELL_STATS, false)

func _on_terrain_stats_close_pressed() -> void:
	$TerrainStatsPanel.visible = false
	$TerrainStatsCheckButton.button_pressed = false
	_set_menu_checked(MENU_ID_TERRAIN_STATS, false)

func _close_other_stats_panels(active_panel: String) -> void:
	if active_panel != "unit" and $StatsPanel.visible:
		$StatsPanel.visible = false
		if $UnitStatsCheckButton.has_method("set_pressed_no_signal"):
			$UnitStatsCheckButton.set_pressed_no_signal(false)
		else:
			$UnitStatsCheckButton.button_pressed = false
		_set_menu_checked(MENU_ID_UNIT_STATS, false)
	if active_panel != "building" and $BuildingStatsPanel.visible:
		$BuildingStatsPanel.visible = false
		if $BuildingStatsCheckButton.has_method("set_pressed_no_signal"):
			$BuildingStatsCheckButton.set_pressed_no_signal(false)
		else:
			$BuildingStatsCheckButton.button_pressed = false
		_set_menu_checked(MENU_ID_BUILDING_STATS, false)
	if active_panel != "spell" and $SpellStatsPanel.visible:
		$SpellStatsPanel.visible = false
		if $SpellStatsCheckButton.has_method("set_pressed_no_signal"):
			$SpellStatsCheckButton.set_pressed_no_signal(false)
		else:
			$SpellStatsCheckButton.button_pressed = false
		_set_menu_checked(MENU_ID_SPELL_STATS, false)
	if active_panel != "terrain" and $TerrainStatsPanel.visible:
		$TerrainStatsPanel.visible = false
		if $TerrainStatsCheckButton.has_method("set_pressed_no_signal"):
			$TerrainStatsCheckButton.set_pressed_no_signal(false)
		else:
			$TerrainStatsCheckButton.button_pressed = false
		_set_menu_checked(MENU_ID_TERRAIN_STATS, false)

func _get_next_unordered_unit() -> Node:
	var units = game_board.get_all_units().get(current_player, [])
	var best_unit: Node = null
	var best_id: int = 0
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.is_base or unit.is_tower:
			continue
		if unit.just_purchased:
			continue
		if unit.ordered:
			continue
		if best_unit == null or unit.net_id < best_id:
			best_unit = unit
			best_id = unit.net_id
	return best_unit

func _world_to_screen(world_pos: Vector2) -> Vector2:
	var viewport = get_viewport()
	if viewport == null:
		return world_pos
	return viewport.get_canvas_transform() * world_pos

func _center_camera_on(cam: Camera2D, world_pos: Vector2) -> void:
	if cam == null:
		return
	cam.global_position = world_pos

func _show_action_menu_for_unit(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var cam = get_viewport().get_camera_2d()
	var world_pos = unit.global_position
	if cam != null:
		if _default_camera_zoom == Vector2.ZERO:
			_default_camera_zoom = cam.zoom
		cam.zoom = _default_camera_zoom
		_center_camera_on(cam, world_pos)
	call_deferred("_finish_show_action_menu_for_unit", unit)

func _finish_show_action_menu_for_unit(unit: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if unit == null or not is_instance_valid(unit):
		return
	_on_unit_selected(unit)
	var world_pos = unit.global_position
	var screen_pos = _world_to_screen(world_pos)
	last_click_pos = screen_pos
	var menu_size = Vector2(action_menu.size)
	if menu_size == Vector2.ZERO:
		menu_size = action_menu.get_minimum_size()
	var viewport_size = get_viewport().get_visible_rect().size
	var unit_half_width = hex.tile_size.x * 0.5
	var screen_right = _world_to_screen(world_pos + Vector2(unit_half_width, 0.0))
	var menu_pos = Vector2(screen_right.x, screen_pos.y - menu_size.y * 0.5)
	menu_pos.x = clamp(menu_pos.x, 0.0, max(0.0, viewport_size.x - menu_size.x))
	menu_pos.y = clamp(menu_pos.y, 0.0, max(0.0, viewport_size.y - menu_size.y))
	action_menu.set_position(menu_pos)
	action_menu.show()

func _on_next_unordered_pressed() -> void:
	if turn_mgr == null or turn_mgr.current_phase != turn_mgr.Phase.ORDERS:
		return
	if not $Panel.visible:
		return
	var unit = _get_next_unordered_unit()
	if unit == null:
		status_lbl.text = "All units have orders"
		return
	_show_action_menu_for_unit(unit)

func _on_unit_selected(unit: Node) -> void:
	game_board.clear_highlights()
	currently_selected_unit = unit
	selected_structure_tile = Vector2i(-9999, -9999)
	selected_structure_type = ""
	# Show action selection menu
	action_menu.clear()
	if unit.is_base or unit.is_tower:
		action_menu.add_item("Cast Spell", ACTION_SPELL_ID)
		var orders = turn_mgr.player_orders.get(current_player, {})
		var existing = orders.get(unit.net_id, {})
		if str(existing.get("type", "")) == "spell":
			action_menu.add_item("Cancel Spell", ACTION_SPELL_CANCEL_ID)
		return
	if unit.just_purchased:
		action_menu.add_item("Undo Buy", 0)
		if unit.first_turn_move:
			action_menu.add_item("Move", 1)
			action_menu.add_item("Move To", 12)
		return
	action_menu.add_item("Move", 1)
	action_menu.add_item("Move To", 12)
	if unit.is_ranged:
		action_menu.add_item("Ranged Attack", 2)
	if unit.can_melee:
		action_menu.add_item("Melee Attack", 3)
	action_menu.add_item("Heal", 4)
	action_menu.add_item("Heal Until Full", 10)
	action_menu.add_item("Defend", 5)
	action_menu.add_item("Always Defend", 11)
	if str(unit.unit_type).to_lower() == "scout":
		action_menu.add_item("Lookout", 9)
		action_menu.add_item("Always Lookout", ACTION_LOOKOUT_ALWAYS_ID)
	action_menu.add_item("Sabotage", 6)
	if unit.is_builder:
		action_menu.add_item("Build", 7)
		action_menu.add_item("Repair", 8)
	if unit.is_wizard:
		action_menu.add_item("Cast Spell", ACTION_SPELL_ID)
	var struct = game_board.get_structure_unit_at(unit.grid_pos)
	if struct != null and struct.player_id == current_player and (struct.is_base or struct.is_tower):
		action_menu.add_item("Cast Spell (Structure)", ACTION_SPELL_STRUCTURE_ID)
	var ward_state = turn_mgr.buildable_structures.get(unit.grid_pos, {})
	if not ward_state.is_empty():
		if str(ward_state.get("type", "")) == turn_mgr.STRUCT_WARD and str(ward_state.get("owner", "")) == current_player and str(ward_state.get("status", "")) == turn_mgr.STRUCT_STATUS_INTACT:
			selected_structure_tile = unit.grid_pos
			selected_structure_type = "ward"
			action_menu.add_item("Ward Vision", ACTION_WARD_VISION_ID)
			if bool(ward_state.get("auto_ward", false)):
				action_menu.add_item("Stop Vision", ACTION_WARD_VISION_STOP_ID)
			else:
				action_menu.add_item("Always Vision", ACTION_WARD_VISION_ALWAYS_ID)

func _on_action_selected(id: int) -> void:
	if id == ACTION_WARD_VISION_ID:
		if selected_structure_type != "ward" or selected_structure_tile == Vector2i(-9999, -9999):
			action_menu.hide()
			return
		NetworkManager.request_order(current_player, {
			"type": "ward_vision",
			"ward_tile": selected_structure_tile
		})
		selected_structure_tile = Vector2i(-9999, -9999)
		selected_structure_type = ""
		action_menu.hide()
		return
	if id == ACTION_WARD_VISION_ALWAYS_ID:
		if selected_structure_type != "ward" or selected_structure_tile == Vector2i(-9999, -9999):
			action_menu.hide()
			return
		NetworkManager.request_order(current_player, {
			"type": "ward_vision_always",
			"ward_tile": selected_structure_tile
		})
		selected_structure_tile = Vector2i(-9999, -9999)
		selected_structure_type = ""
		action_menu.hide()
		return
	if id == ACTION_WARD_VISION_STOP_ID:
		if selected_structure_type != "ward" or selected_structure_tile == Vector2i(-9999, -9999):
			action_menu.hide()
			return
		NetworkManager.request_order(current_player, {
			"type": "ward_vision_stop",
			"ward_tile": selected_structure_tile
		})
		selected_structure_tile = Vector2i(-9999, -9999)
		selected_structure_type = ""
		action_menu.hide()
		return
	if id == ACTION_SPELL_CANCEL_ID:
		if currently_selected_unit == null or not is_instance_valid(currently_selected_unit):
			action_menu.hide()
			return
		NetworkManager.request_order(current_player, {
			"unit_net_id": currently_selected_unit.net_id,
			"type": "spell_cancel"
		})
		action_menu.hide()
		return
	if currently_selected_unit == null or not is_instance_valid(currently_selected_unit):
		action_menu.hide()
		return
	match id:
		0:
			var player_id = currently_selected_unit.player_id
			var unit_id = currently_selected_unit.net_id
			if turn_mgr.is_host():
				if NetworkManager.request_undo_buy(player_id, unit_id):
					_refresh_resource_labels()
			else:
				NetworkManager.request_undo_buy(player_id, unit_id)
			currently_selected_unit = null
			$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
			_update_done_button_state()
		1:
			action_mode = "move"
			current_path = [currently_selected_unit.grid_pos]
			remaining_moves = float(currently_selected_unit.move_range)
			_reset_cavalry_bonus_state()
			var result = game_board.get_reachable_tiles(currently_selected_unit.grid_pos, currently_selected_unit.move_range, action_mode, currently_selected_unit)
			var tiles = result["tiles"].slice(1)
			_append_cavalry_bonus_highlights(currently_selected_unit.grid_pos, result, tiles)
			game_board.show_highlights(tiles)
			current_reachable = result
			print("Move selected for %s" % currently_selected_unit.name)
		12:
			_start_move_to()

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
		
		10:
			print("Heal-until-full selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "heal_until_full",
			})
			action_mode = ""

		5:
			print("Defend selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "defend",
			})
			action_mode = ""
		11:
			print("Always-defend selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "defend_always",
			})
			action_mode = ""
		9:
			print("Lookout selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "lookout",
			})
			action_mode = ""
		ACTION_LOOKOUT_ALWAYS_ID:
			print("Always-lookout selected for %s" % currently_selected_unit.name)
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "lookout_always",
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
				status_lbl.text = "[Nothing to repair]"
				action_menu.hide()
				return
			NetworkManager.request_order(current_player, {
				"unit_net_id": currently_selected_unit.net_id,
				"type": "repair",
				"target_tile": currently_selected_unit.grid_pos
			})
			action_mode = ""
		ACTION_SPELL_ID:
			spell_caster = currently_selected_unit
			_refresh_spell_menu_labels()
			spell_menu.set_position(last_click_pos)
			spell_menu.popup()
		ACTION_SPELL_STRUCTURE_ID:
			var struct = game_board.get_structure_unit_at(currently_selected_unit.grid_pos)
			if struct == null or struct.player_id != current_player:
				action_menu.hide()
				return
			spell_caster = struct
			_refresh_spell_menu_labels()
			spell_menu.set_position(last_click_pos)
			spell_menu.popup()
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
	var ward_node = hex.get_node_or_null("WardSprites")
	if ward_node != null:
		for child in ward_node.get_children():
			child.queue_free()
	_queue_preview_unit_id = -1

func _reset_ui_for_snapshot() -> void:
	action_menu.hide()
	build_menu.hide()
	spell_menu.hide()
	finish_move_button.visible = false
	_clear_queue_preview()
	placing_unit = ""
	currently_selected_unit = null
	action_mode = ""
	current_path = []
	current_reachable = {}
	enemy_tiles = []
	support_tiles = []
	repair_tiles = []
	current_spell_type = ""
	current_spell_mana_spent = 0
	pending_spell_type = ""
	if buff_mana_panel != null:
		buff_mana_panel.visible = false
	spell_tiles = []
	spell_caster = null
	selected_structure_tile = Vector2i(-9999, -9999)
	selected_structure_type = ""
	selected_structure_tile = Vector2i(-9999, -9999)
	selected_structure_type = ""
	remaining_moves = 0.0
	_reset_cavalry_bonus_state()
	game_board.clear_highlights()
	_clear_all_drawings()
	_hide_build_hover()

func _submit_orders() -> void:
	game_board.clear_highlights()
	$Panel.visible = false
	cancel_done_button.visible = true
	NetworkManager.submit_orders(current_player, [])
	# prevent further clicks
	placing_unit = ""
	allow_clicks = false

func _on_done_pressed():
	if _has_unordered_units(current_player):
		if confirm_done_dialog != null:
			confirm_done_dialog.popup_centered()
			return
	_submit_orders()

func _on_done_confirmed() -> void:
	_submit_orders()

func _on_concede_confirmed() -> void:
	if turn_mgr != null:
		NetworkManager.request_concede(turn_mgr.local_player_id)

func _on_cancel_pressed():
	NetworkManager.cancel_orders(current_player)
	status_lbl.text = "Orders unsubmitted"
	_draw_all()
	currently_selected_unit = null
	action_mode = ""
	current_path = []
	current_spell_type = ""
	spell_tiles = []
	spell_caster = null
	remaining_moves = 0
	_reset_cavalry_bonus_state()
	finish_move_button.visible = false
	game_board.clear_highlights()
	allow_clicks = true
	$Panel.visible = true
	cancel_done_button.visible = false

func _on_execution_paused(phase_idx):
	_current_exec_step_idx = phase_idx
	exec_panel.visible = true
	var phase_names = ["Unit Spawns", "Spells", "Attacks", "Engineering", "Movement"]
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
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS and current_player != "":
		var units = game_board.get_all_units().get(current_player, [])
		for unit in units:
			if unit == null or unit.is_base or unit.is_tower:
				continue
			if not _should_draw_unit(unit):
				continue
			var existing = turn_mgr.get_order(current_player, unit.net_id)
			if not existing.is_empty():
				continue
			var queued = turn_mgr.get_move_queue_front_order(unit, current_player)
			if queued.is_empty():
				continue
			var path = queued.get("path", [])
			if not (path is Array) or path.size() < 2:
				continue
			var root = Node2D.new()
			path_arrows_node.add_child(root)
			for i in range(path.size() - 1):
				var a = path[i]
				var b = path[i + 1]
				var p1 = hex.map_to_world(a) + hex.tile_size * 0.5
				var p2 = hex.map_to_world(b) + hex.tile_size * 0.5
				var arrow = ArrowScene.instantiate() as Sprite2D
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
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS and current_player != "":
		var units = game_board.get_all_units().get(current_player, [])
		for unit in units:
			if unit == null or not unit.is_builder:
				continue
			if not _should_draw_unit(unit):
				continue
			var existing = turn_mgr.get_order(current_player, unit.net_id)
			if not existing.is_empty():
				continue
			var queued = turn_mgr.get_queue_front_order(unit, current_player)
			if queued.is_empty():
				continue
			if str(queued.get("type", "")) != "move":
				continue
			var path = queued.get("path", [])
			if not (path is Array) or path.size() < 2:
				continue
			var root = Node2D.new()
			path_arrows_node.add_child(root)
			for i in range(path.size() - 1):
				var a = path[i]
				var b = path[i + 1]
				var p1 = hex.map_to_world(a) + hex.tile_size * 0.5
				var p2 = hex.map_to_world(b) + hex.tile_size * 0.5
				var arrow = ArrowScene.instantiate() as Sprite2D
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
	var attack_counts := {}
	var buff_by_target := {}
	for player in players:
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			var order_type = str(order.get("type", ""))
			if order_type == "ranged" or order_type == "melee":
				var target_id = int(order.get("target_unit_net_id", -1))
				if target_id != -1:
					attack_counts[target_id] = int(attack_counts.get(target_id, 0)) + 1
			elif order_type == "spell" and str(order.get("spell_type", "")) == turn_mgr.SPELL_BUFF:
				var buff_target = int(order.get("target_unit_net_id", -1))
				if buff_target == -1:
					continue
				var mana_spent = int(order.get("mana_spent", 0))
				if mana_spent < turn_mgr.SPELL_BUFF_MIN or mana_spent > turn_mgr.SPELL_BUFF_MAX:
					continue
				if mana_spent % turn_mgr.SPELL_BUFF_STEP != 0:
					continue
				var buff_amount = snappedf(float(mana_spent) * 0.1, 0.1)
				buff_by_target[buff_target] = buff_amount
	for player in players:
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			var is_attack = order["type"] == "ranged" or order["type"] == "melee"
			var is_fireball = order["type"] == "spell" and str(order.get("spell_type", "")) == turn_mgr.SPELL_FIREBALL
			var is_lightning = order["type"] == "spell" and str(order.get("spell_type", "")) == turn_mgr.SPELL_LIGHTNING
			if is_attack or is_fireball or is_lightning:
				var root = Node2D.new()
				attack_arrows_node.add_child(root)
				
				# calculate direction and size for attack arrow
				var attacker = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				var target = unit_mgr.get_unit_by_net_id(order["target_unit_net_id"])
				if not _should_draw_unit(attacker) or target == null:
					continue
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
				if is_attack:
					var num_attackers = int(attack_counts.get(target.net_id, 1))
					if num_attackers < 1:
						num_attackers = 1
					var atk_override = buff_by_target.has(attacker.net_id)
					var def_override = buff_by_target.has(target.net_id)
					var atk_buff_orig_melee = 0.0
					var atk_buff_orig_ranged = 0.0
					var atk_buff_orig_turns = 0
					if atk_override:
						atk_buff_orig_melee = float(attacker.spell_buff_melee)
						atk_buff_orig_ranged = float(attacker.spell_buff_ranged)
						atk_buff_orig_turns = int(attacker.spell_buff_turns)
						var atk_buff_amt = float(buff_by_target[attacker.net_id])
						attacker.spell_buff_melee = atk_buff_amt
						attacker.spell_buff_ranged = atk_buff_amt
						attacker.spell_buff_turns = 1
					var def_buff_orig_melee = 0.0
					var def_buff_orig_ranged = 0.0
					var def_buff_orig_turns = 0
					if def_override:
						def_buff_orig_melee = float(target.spell_buff_melee)
						def_buff_orig_ranged = float(target.spell_buff_ranged)
						def_buff_orig_turns = int(target.spell_buff_turns)
						var def_buff_amt = float(buff_by_target[target.net_id])
						target.spell_buff_melee = def_buff_amt
						target.spell_buff_ranged = def_buff_amt
						target.spell_buff_turns = 1
					var dmg = $"..".calculate_damage(attacker, target, order["type"], num_attackers)
					if atk_override:
						attacker.spell_buff_melee = atk_buff_orig_melee
						attacker.spell_buff_ranged = atk_buff_orig_ranged
						attacker.spell_buff_turns = atk_buff_orig_turns
					if def_override:
						target.spell_buff_melee = def_buff_orig_melee
						target.spell_buff_ranged = def_buff_orig_ranged
						target.spell_buff_turns = def_buff_orig_turns
					var dmg_label = Label.new()
					dmg_label.text = "%d (%d)" % [dmg[1], dmg[0]]
					dmg_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.08))
					var normal := Vector2(-dir.y, dir.x)
					dmg_label.position = p1 + normal * 8.0 + dir * 6.0
					dmg_label.z_index = 11
					root.add_child(dmg_label)
				elif is_fireball:
					var fireball_icon = Sprite2D.new()
					fireball_icon.texture = FireballIcon
					fireball_icon.scale = Vector2(0.3, 0.3)
					var icon_offset = distance * 0.1
					fireball_icon.position = p2 - dir * icon_offset
					fireball_icon.z_index = ORDER_ICON_Z
					root.add_child(fireball_icon)
				elif is_lightning:
					var lightning_icon = Sprite2D.new()
					lightning_icon.texture = LightningIcon
					lightning_icon.scale = Vector2(0.3, 0.3)
					var icon_offset = distance * 0.1
					lightning_icon.position = p2 - dir * icon_offset
					lightning_icon.z_index = ORDER_ICON_Z
					root.add_child(lightning_icon)

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
			elif order["type"] == "spell" and str(order.get("spell_type", "")) in [turn_mgr.SPELL_HEAL, turn_mgr.SPELL_BUFF]:
				var root = Node2D.new()
				support_arrows_node.add_child(root)
				var caster = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				var target = unit_mgr.get_unit_by_net_id(order["target_unit_net_id"])
				if not _should_draw_unit(caster) or target == null:
					continue
				var p1 = hex.map_to_world(caster.grid_pos) + hex.tile_size * 0.5
				var p2 = hex.map_to_world(order["target_tile"]) + hex.tile_size * 0.5
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
				var icon_offset = distance * 0.1
				if str(order.get("spell_type", "")) == turn_mgr.SPELL_HEAL:
					var heart = HealScene.instantiate() as Sprite2D
					heart.position = p2 - dir * icon_offset
					heart.z_index = ORDER_ICON_Z
					root.add_child(heart)
				else:
					var buff_icon = Sprite2D.new()
					buff_icon.texture = BuffIcon
					buff_icon.scale = Vector2(0.3, 0.3)
					buff_icon.position = p2 - dir * icon_offset
					buff_icon.z_index = ORDER_ICON_Z
					root.add_child(buff_icon)
					var mana_spent = int(order.get("mana_spent", 0))
					if mana_spent > 0:
						var buff_amount = snappedf(float(mana_spent) * 0.1, 0.1)
						var buff_label = Label.new()
						buff_label.text = "+%.1f" % buff_amount
						buff_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.2))
						var normal := Vector2(-dir.y, dir.x)
						buff_label.position = p2 + normal * 8.0
						buff_label.z_index = 11
						root.add_child(buff_label)
			elif order["type"] == "spell" and str(order.get("spell_type", "")) == turn_mgr.SPELL_TARGETED_VISION:
				var caster = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(caster):
					continue
				var target_tile = order.get("target_tile", Vector2i(-9999, -9999))
				if typeof(target_tile) != TYPE_VECTOR2I:
					continue
				var root = Node2D.new()
				support_arrows_node.add_child(root)
				var p1 = hex.map_to_world(caster.grid_pos) + hex.tile_size * 0.5
				var p2 = hex.map_to_world(target_tile) + hex.tile_size * 0.5
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
				var vision_icon = Sprite2D.new()
				vision_icon.texture = GlobalVisionIcon
				var vision_size = GlobalVisionIcon.get_size()
				if vision_size.x > 0:
					var scale = (hex.tile_size.x * 0.18) / vision_size.x
					vision_icon.scale = Vector2(scale, scale)
				vision_icon.position = p2
				vision_icon.z_index = ORDER_ICON_Z
				root.add_child(vision_icon)
			elif order["type"] == "spell" and str(order.get("spell_type", "")) == turn_mgr.SPELL_GLOBAL_VISION:
				var caster = unit_mgr.get_unit_by_net_id(order["unit_net_id"])
				if not _should_draw_unit(caster):
					continue
				var root = Node2D.new()
				support_arrows_node.add_child(root)
				var icon = Sprite2D.new()
				icon.texture = GlobalVisionIcon
				var tex_size = GlobalVisionIcon.get_size()
				if tex_size.x > 0:
					var scale = (hex.tile_size.x * 0.18) / tex_size.x
					icon.scale = Vector2(scale, scale)
				icon.position = hex.map_to_world(caster.grid_pos) + (hex.tile_size * Vector2(0.5, 0.6))
				icon.z_index = ORDER_ICON_Z
				root.add_child(icon)

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
				heart.z_index = ORDER_ICON_Z
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
				defend.z_index = ORDER_ICON_Z
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
				lookout_icon.z_index = ORDER_ICON_Z
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

func _get_ward_sprites_root() -> Node2D:
	var root = hex.get_node_or_null("WardSprites")
	if root == null:
		root = Node2D.new()
		root.name = "WardSprites"
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
				build_icon.z_index = ORDER_ICON_Z
				root.add_child(build_icon)
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS and current_player != "":
		var units = game_board.get_all_units().get(current_player, [])
		for unit in units:
			if unit == null or not unit.is_builder:
				continue
			if not _should_draw_unit(unit):
				continue
			var existing = turn_mgr.get_order(current_player, unit.net_id)
			if not existing.is_empty():
				continue
			var queued = turn_mgr.get_queue_front_order(unit, current_player)
			if queued.is_empty():
				continue
			if str(queued.get("type", "")) != "build":
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
			build_icon.z_index = ORDER_ICON_Z
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
				repair_icon.z_index = ORDER_ICON_Z
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
				sabotage_icon.z_index = ORDER_ICON_Z
				root.add_child(sabotage_icon)

func _draw_ward_orders():
	var ward_node = _get_ward_sprites_root()
	for child in ward_node.get_children():
		child.queue_free()
	var players = []
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		players.append(current_player)
	else:
		players = ["player1", "player2"]
	for player in players:
		var all_orders = turn_mgr.get_all_orders_for_phase(player)
		for order in all_orders:
			if order.get("type", "") == "ward_vision":
				var ward_tile = order.get("ward_tile", Vector2i(-9999, -9999))
				if typeof(ward_tile) != TYPE_VECTOR2I:
					continue
				var ward_state = turn_mgr.buildable_structures.get(ward_tile, {})
				if ward_state.is_empty() or str(ward_state.get("type", "")) != turn_mgr.STRUCT_WARD:
					continue
				if not turn_mgr._structure_is_visible_to_viewer(ward_state, turn_mgr.local_player_id, ward_tile):
					continue
				var root = Node2D.new()
				ward_node.add_child(root)
				var dot = Polygon2D.new()
				var points := PackedVector2Array()
				var segments = 12
				var radius = hex.tile_size.x * 0.06
				for i in range(segments):
					var ang = TAU * float(i) / float(segments)
					points.append(Vector2(cos(ang), sin(ang)) * radius)
				dot.polygon = points
				dot.color = Color(1, 0.92, 0.2, 0.9)
				dot.position = hex.map_to_world(ward_tile) + hex.tile_size * 0.5
				dot.z_index = ORDER_ICON_Z
				root.add_child(dot)

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
	_draw_ward_orders()

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
	if id == BUILD_MENU_ROAD_TO_ID:
		if currently_selected_unit != null:
			_start_build_road_to()
		build_menu.hide()
		return
	if id == BUILD_MENU_RAIL_TO_ID:
		if currently_selected_unit != null:
			_start_build_rail_to()
		build_menu.hide()
		return
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

func _on_spell_selected(id: int) -> void:
	if spell_caster == null or not is_instance_valid(spell_caster):
		spell_menu.hide()
		return
	var spell_type = ""
	for entry in SPELL_OPTIONS:
		if entry["id"] == id:
			spell_type = entry["type"]
			break
	if spell_type == "":
		spell_menu.hide()
		return
	if spell_type == turn_mgr.SPELL_GLOBAL_VISION:
		NetworkManager.request_order(current_player, {
			"unit_net_id": spell_caster.net_id,
			"type": "spell",
			"spell_type": spell_type
		})
		spell_menu.hide()
		current_spell_type = ""
		spell_tiles = []
		spell_caster = null
		current_spell_mana_spent = 0
		game_board.clear_highlights()
		_draw_all()
		$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
		_update_done_button_state()
		_refresh_resource_labels()
		return
	if spell_type == turn_mgr.SPELL_BUFF:
		spell_menu.hide()
		pending_spell_type = spell_type
		_show_buff_mana_panel()
		return
	action_mode = "spell"
	current_spell_type = spell_type
	spell_tiles = _get_spell_target_tiles(spell_caster, spell_type)
	if spell_tiles.is_empty():
		status_lbl.text = "[No valid spell targets]"
		action_mode = ""
		current_spell_type = ""
		spell_caster = null
		spell_menu.hide()
		return
	game_board.show_highlights(spell_tiles)
	spell_menu.hide()

func _get_build_road_reachable(start: Vector2i) -> Dictionary:
	if currently_selected_unit == null:
		return {"tiles": [], "prev": {}}
	return game_board.get_reachable_tiles(start, currently_selected_unit.move_range, "move", currently_selected_unit)

func _reset_cavalry_bonus_state() -> void:
	cavalry_bonus_available = false
	cavalry_bonus_used = false
	cavalry_bonus_tile = Vector2i(-9999, -9999)
	cavalry_bonus_paths.clear()

func _is_cavalry_unit(unit: Node) -> bool:
	if unit == null:
		return false
	return str(unit.unit_type).to_lower() == "cavalry"

func _append_cavalry_bonus_highlights(start: Vector2i, reachable: Dictionary, tiles: Array) -> void:
	cavalry_bonus_paths.clear()
	if not _is_cavalry_unit(currently_selected_unit):
		return
	var max_budget = float(currently_selected_unit.move_range)
	var base_tiles = reachable.get("tiles", [])
	for dir_idx in range(6):
		var path := [start]
		var prev = start
		var cost := 0.0
		while true:
			var neighbors = game_board.get_offset_neighbors(prev)
			if dir_idx < 0 or dir_idx >= neighbors.size():
				break
			var step = neighbors[dir_idx]
			if not hex.is_cell_valid(step):
				break
			if game_board._terrain_is_impassable(step):
				break
			var step_cost = float(game_board.get_move_cost(step, currently_selected_unit))
			var new_cost = cost + step_cost
			if new_cost > max_budget + 1.0 + 0.001:
				break
			if new_cost > max_budget + 0.001:
				if step_cost <= (max_budget - cost) + 1.0 + 0.001:
					if step not in base_tiles:
						var bonus_path = path.duplicate()
						bonus_path.append(step)
						cavalry_bonus_paths[step] = bonus_path
						base_tiles.append(step)
						if not tiles.has(step):
							tiles.append(step)
				break
			if game_board.is_enemy_structure_tile(step, current_player):
				break
			cost = new_cost
			path.append(step)
			prev = step

func _append_cavalry_bonus_step(cell: Vector2i, remaining: float, reachable: Dictionary, tiles: Array) -> void:
	if not _is_cavalry_unit(currently_selected_unit):
		return
	if cavalry_bonus_used:
		return
	var dir_idx = _cavalry_straight_dir(current_path)
	if dir_idx == -1:
		return
	var neighbors = game_board.get_offset_neighbors(cell)
	if dir_idx < 0 or dir_idx >= neighbors.size():
		return
	var bonus = neighbors[dir_idx]
	if not hex.is_cell_valid(bonus):
		return
	if game_board._terrain_is_impassable(bonus):
		return
	var bonus_cost = float(game_board.get_move_cost(bonus, currently_selected_unit))
	if bonus_cost <= remaining + 0.001:
		return
	if bonus_cost > remaining + 1.0 + 0.001:
		return
	var reach_tiles = reachable.get("tiles", [])
	if not reach_tiles.has(bonus):
		reach_tiles.append(bonus)
		tiles.append(bonus)
	var prev_map = reachable.get("prev", {})
	prev_map[bonus] = cell
	reachable["prev"] = prev_map

func _cavalry_straight_dir(path: Array) -> int:
	if path.size() < 2:
		return -1
	var dir_idx = -1
	for i in range(1, path.size()):
		var prev = path[i - 1]
		var step = path[i]
		if typeof(prev) != TYPE_VECTOR2I or typeof(step) != TYPE_VECTOR2I:
			return -1
		var neighbors = game_board.get_offset_neighbors(prev)
		var step_dir = neighbors.find(step)
		if step_dir == -1:
			return -1
		if dir_idx == -1:
			dir_idx = step_dir
		elif step_dir != dir_idx:
			return -1
	return dir_idx

func _set_cavalry_bonus_reachable(button_pos: Vector2) -> bool:
	_reset_cavalry_bonus_state()
	if not _is_cavalry_unit(currently_selected_unit):
		return false
	var dir_idx = _cavalry_straight_dir(current_path)
	if dir_idx == -1:
		return false
	var last = current_path[current_path.size() - 1]
	var neighbors = game_board.get_offset_neighbors(last)
	if dir_idx < 0 or dir_idx >= neighbors.size():
		return false
	var bonus_tile: Vector2i = neighbors[dir_idx]
	if not hex.is_cell_valid(bonus_tile):
		return false
	if game_board._terrain_is_impassable(bonus_tile):
		return false
	var bonus_cost = float(game_board.get_move_cost(bonus_tile, currently_selected_unit))
	if bonus_cost > 1.0 + 0.001:
		return false
	cavalry_bonus_available = true
	cavalry_bonus_tile = bonus_tile
	current_reachable = {"tiles": [bonus_tile], "prev": {bonus_tile: last}}
	game_board.show_highlights([bonus_tile])
	finish_move_button.set_position(button_pos)
	finish_move_button.visible = true
	return true

func _start_move_to() -> void:
	action_mode = "move_to"
	current_path = [currently_selected_unit.grid_pos]
	var result = _get_build_road_reachable(currently_selected_unit.grid_pos)
	var tiles = result["tiles"]
	if tiles.has(currently_selected_unit.grid_pos):
		tiles.erase(currently_selected_unit.grid_pos)
	game_board.show_highlights(tiles)
	current_reachable = result
	finish_move_button.visible = false

func _start_build_road_to() -> void:
	action_mode = "build_road_to"
	current_path = [currently_selected_unit.grid_pos]
	var result = _get_build_road_reachable(currently_selected_unit.grid_pos)
	var tiles = result["tiles"]
	if tiles.has(currently_selected_unit.grid_pos):
		tiles.erase(currently_selected_unit.grid_pos)
	game_board.show_highlights(tiles)
	current_reachable = result
	finish_move_button.visible = false

func _start_build_rail_to() -> void:
	action_mode = "build_rail_to"
	current_path = [currently_selected_unit.grid_pos]
	var result = _get_build_road_reachable(currently_selected_unit.grid_pos)
	var tiles = result["tiles"]
	if tiles.has(currently_selected_unit.grid_pos):
		tiles.erase(currently_selected_unit.grid_pos)
	game_board.show_highlights(tiles)
	current_reachable = result
	finish_move_button.visible = false

func finish_build_road_path():
	if current_path.size() == 1:
		action_mode = ""
		return
	NetworkManager.request_order(current_player, {
		"unit_net_id": currently_selected_unit.net_id,
		"type": "build_road_to",
		"path": current_path
	})
	var preview_node = hex.get_node("PreviewPathArrows")
	for child in preview_node.get_children():
		child.queue_free()
	_queue_preview_unit_id = -1
	finish_move_button.visible = false
	action_mode = ""
	current_path = []
	remaining_moves = 0
	game_board.clear_highlights()
	$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
	_update_done_button_state()

func finish_build_rail_path():
	if current_path.size() == 1:
		action_mode = ""
		return
	NetworkManager.request_order(current_player, {
		"unit_net_id": currently_selected_unit.net_id,
		"type": "build_rail_to",
		"path": current_path
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

func finish_move_to_path():
	if current_path.size() == 1:
		action_mode = ""
		return
	NetworkManager.request_order(current_player, {
		"unit_net_id": currently_selected_unit.net_id,
		"type": "move_to",
		"path": current_path
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

func finish_current_path():
	if current_path.size() == 1:
		action_mode = ""
		_reset_cavalry_bonus_state()
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
	_queue_preview_unit_id = -1
	finish_move_button.visible = false
	action_mode = ""
	current_path = []
	remaining_moves = 0
	_reset_cavalry_bonus_state()
	game_board.clear_highlights()
	$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
	_update_done_button_state()
	
func _on_state_applied() -> void:
	_reset_ui_for_snapshot()
	_update_turn_label()
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		current_player = turn_mgr.local_player_id
		_refresh_resource_labels()
		$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
		_update_done_button_state()
	_draw_all()
	_update_auto_pass_for_damage()

func _update_turn_label() -> void:
	if turn_label == null or turn_mgr == null:
		return
	turn_label.text = "Turn %d" % int(turn_mgr.turn_number)


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
					_refresh_resource_labels()
					_cancel_purchase_mode()
					$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
					_update_done_button_state()
				else:
					status_lbl.text = "[Not enough gold]"
					_cancel_purchase_mode()
			else:
				NetworkManager.request_buy_unit(current_player, placing_unit, cell)
				_cancel_purchase_mode()
				status_lbl.text = "Purchase requested"
				$"../GameBoardNode/OrderReminderMap".highlight_unordered_units(current_player)
				_update_done_button_state()
		else:
			status_lbl.text = "[Can't place there]"
			_cancel_purchase_mode()
		return
	
	if (action_mode == "build_road_to" or action_mode == "build_rail_to" or action_mode == "move_to") and currently_selected_unit:
		if cell not in current_reachable["tiles"]:
			if action_mode == "build_road_to":
				finish_build_road_path()
			elif action_mode == "build_rail_to":
				finish_build_rail_path()
			else:
				finish_move_to_path()
			return
		var path = []
		var prev = current_reachable["prev"]
		var cur = cell
		while cur in prev:
			path.insert(0, cur)
			cur = prev[cur]
		if path.is_empty():
			var tiles = current_reachable.get("tiles", []).duplicate()
			if tiles.has(currently_selected_unit.grid_pos):
				tiles.erase(currently_selected_unit.grid_pos)
			game_board.show_highlights(tiles)
			finish_move_button.visible = false
			return
		current_path += path
		_draw_partial_path()
		var result = _get_build_road_reachable(cell)
		var tiles = result["tiles"]
		if tiles.has(cell):
			tiles.erase(cell)
		if tiles.size() == 0:
			finish_build_road_path()
			return
		game_board.show_highlights(tiles)
		current_reachable = result
		finish_move_button.set_position(ev.position)
		finish_move_button.visible = true
		return

	# Order phase: if waiting for destination (move mode)
	if action_mode == "move" and currently_selected_unit:
		if cell not in current_reachable["tiles"]:
			finish_current_path()
			return
		var path = []
		if current_path.size() == 1 and cavalry_bonus_paths.has(cell):
			path = cavalry_bonus_paths[cell].slice(1)
			cavalry_bonus_used = true
			cavalry_bonus_available = false
			cavalry_bonus_paths.clear()
		else:
			var prev = current_reachable["prev"]
			var cur = cell
			while cur in prev:
				path.insert(0, cur)
				cur = prev[cur]
			if current_path.size() == 1:
				cavalry_bonus_paths.clear()
		if path.is_empty():
			var tiles = current_reachable.get("tiles", []).duplicate()
			if tiles.has(currently_selected_unit.grid_pos):
				tiles.erase(currently_selected_unit.grid_pos)
			game_board.show_highlights(tiles)
			finish_move_button.visible = false
			return
		
		current_path += path
		if cavalry_bonus_available and cell == cavalry_bonus_tile:
			cavalry_bonus_used = true
			cavalry_bonus_available = false
		var cost_used: float = 0.0
		for step_cell in path:
			cost_used += game_board.get_move_cost(step_cell, currently_selected_unit)
		remaining_moves -= cost_used
		if remaining_moves < -0.001:
			cavalry_bonus_used = true
		
		_draw_partial_path()
		if cavalry_bonus_used:
			finish_current_path()
			return
		
		var result = game_board.get_reachable_tiles(cell, remaining_moves, action_mode, currently_selected_unit)
		var tiles = result["tiles"]
		if tiles.has(cell):
			tiles.erase(cell)
		_append_cavalry_bonus_step(cell, remaining_moves, result, tiles)
		if tiles.size() == 0:
			finish_current_path()
			return
		game_board.show_highlights(tiles)
		current_reachable = result
		finish_move_button.set_position(ev.position)
		finish_move_button.visible = true
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

	if action_mode == "spell" and spell_caster != null:
		if cell in spell_tiles:
			if current_spell_type == turn_mgr.SPELL_TARGETED_VISION:
				NetworkManager.request_order(current_player, {
					"unit_net_id": spell_caster.net_id,
					"type": "spell",
					"spell_type": current_spell_type,
					"target_tile": cell
				})
			elif current_spell_type == turn_mgr.SPELL_BUFF:
				var target_unit = _spell_target_for_tile(cell, current_spell_type)
				if target_unit == null:
					action_mode = ""
					return
				NetworkManager.request_order(current_player, {
					"unit_net_id": spell_caster.net_id,
					"type": "spell",
					"spell_type": current_spell_type,
					"target_tile": cell,
					"target_unit_net_id": target_unit.net_id,
					"mana_spent": current_spell_mana_spent
				})
			else:
				var target_unit = _spell_target_for_tile(cell, current_spell_type)
				if target_unit == null:
					action_mode = ""
					return
				NetworkManager.request_order(current_player, {
					"unit_net_id": spell_caster.net_id,
					"type": "spell",
					"spell_type": current_spell_type,
					"target_tile": cell,
					"target_unit_net_id": target_unit.net_id
				})
		action_mode = ""
		current_spell_type = ""
		current_spell_mana_spent = 0
		spell_tiles = []
		spell_caster = null
		return
	
	if turn_mgr.current_phase == turn_mgr.Phase.ORDERS:
		# Unit selection in orders phase
		var unit = game_board.get_unit_at(cell)
		if unit:
			if unit.player_id == current_player:
				_on_unit_selected(unit)
				last_click_pos = ev.position
				var menu_pos = ev.position
				var menu_size = action_menu.size
				var viewport_size = get_viewport().get_visible_rect().size
				if menu_pos.y + menu_size.y > viewport_size.y:
					menu_pos.y = max(0.0, menu_pos.y - menu_size.y)
				action_menu.set_position(menu_pos)
				action_menu.show()
				return
		var struct = game_board.get_structure_unit_at(cell)
		if struct != null and struct.player_id == current_player and (struct.is_base or struct.is_tower):
			_on_unit_selected(struct)
			last_click_pos = ev.position
			var struct_menu_pos = ev.position
			var struct_menu_size = action_menu.size
			var struct_viewport_size = get_viewport().get_visible_rect().size
			if struct_menu_pos.y + struct_menu_size.y > struct_viewport_size.y:
				struct_menu_pos.y = max(0.0, struct_menu_pos.y - struct_menu_size.y)
			action_menu.set_position(struct_menu_pos)
			action_menu.show()
			return

func _enter_replay_mode() -> void:
	allow_clicks = false
	$Panel.visible = false
	exec_panel.visible = false
	resource_panel.visible = false
	damage_panel.visible = false
	cancel_done_button.visible = false
	menu_button.visible = false
	if replay_panel != null:
		replay_panel.visible = true
	if replay_fog_option != null and replay_fog_option.item_count == 0:
		replay_fog_option.add_item("Player 1", 0)
		replay_fog_option.add_item("Player 2", 1)
		replay_fog_option.add_item("No Fog", 2)
	if replay_fog_option != null:
		replay_fog_option.select(0)
	if replay_phase_toggle != null:
		replay_phase_toggle.button_pressed = false

func _exit_replay_mode() -> void:
	allow_clicks = true
	$Panel.visible = false
	exec_panel.visible = false
	resource_panel.visible = false
	damage_panel.visible = false
	cancel_done_button.visible = false
	menu_button.visible = true
	if replay_panel != null:
		replay_panel.visible = false
	if replay_stats_panel != null:
		replay_stats_panel.visible = false

func _on_replay_prev_pressed() -> void:
	if turn_mgr != null:
		turn_mgr.replay_step_back()

func _on_replay_next_pressed() -> void:
	if turn_mgr != null:
		turn_mgr.replay_step_forward()

func _on_replay_phase_toggled(enabled: bool) -> void:
	if turn_mgr != null:
		turn_mgr.set_replay_phase_mode(enabled)

func _on_replay_fog_selected(index: int) -> void:
	if turn_mgr == null:
		return
	match index:
		0:
			turn_mgr.set_replay_fog_mode("player1")
		1:
			turn_mgr.set_replay_fog_mode("player2")
		2:
			turn_mgr.set_replay_fog_mode("none")

func _on_replay_stats_pressed() -> void:
	_show_replay_stats()

func _show_replay_stats() -> void:
	if replay_stats_panel == null or turn_mgr == null:
		return
	replay_stats_panel.visible = true
	replay_metric_ids.clear()
	if replay_stats_metric != null:
		replay_stats_metric.clear()
		var metrics = turn_mgr.get_replay_metric_list()
		for entry in metrics:
			replay_stats_metric.add_item(str(entry.get("label", "")))
			replay_metric_ids.append(str(entry.get("id", "")))
		if replay_stats_metric.item_count > 0:
			replay_stats_metric.select(0)
	_update_replay_stats_graph()

func _on_replay_stats_close_pressed() -> void:
	if replay_stats_panel != null:
		replay_stats_panel.visible = false

func _on_replay_metric_changed(_value: Variant = null) -> void:
	_update_replay_stats_graph()

func _update_replay_stats_graph() -> void:
	if replay_stats_graph == null or turn_mgr == null:
		return
	if replay_metric_ids.is_empty():
		return
	var idx = 0
	if replay_stats_metric != null:
		idx = replay_stats_metric.get_selected_id()
		if idx < 0:
			idx = replay_stats_metric.get_selected()
	var metric_id = replay_metric_ids[min(idx, replay_metric_ids.size() - 1)]
	var include_p1 = replay_stats_player1 == null or replay_stats_player1.button_pressed
	var include_p2 = replay_stats_player2 == null or replay_stats_player2.button_pressed
	var series = turn_mgr.get_replay_series(metric_id, include_p1, include_p2)
	if replay_stats_graph.has_method("set_series"):
		replay_stats_graph.set_series(series)

func _on_replay_exit_pressed() -> void:
	if turn_mgr != null:
		turn_mgr.exit_replay_to_game_over()

func _on_replay_quit_pressed() -> void:
	if turn_mgr != null and turn_mgr.has_method("exit_replay_to_lobby"):
		turn_mgr.exit_replay_to_lobby()

func _on_replay_state_changed(turn: int, phase: int) -> void:
	if replay_turn_label == null:
		return
	var phase_name = "Execution"
	if phase == 0:
		phase_name = "Upkeep"
	elif phase == 1:
		phase_name = "Orders"
	replay_turn_label.text = "Turn %d - %s" % [turn, phase_name]
