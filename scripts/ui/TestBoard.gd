# res://scripts/ui/TestBoard.gd
# Rough playable One Piece TCG testboard.
# - Player is always P0. Opponent (P1) is driven by MtDummyAI.
# - Click your field/leader card to select it / declare an attacker, then
#   click an opponent card to attack it. Hand clicks select for Play/Counter.
# - Buttons: Attach Don / Play / Activate / Counter / Pass Battle / End Turn.
#   Headless verification: call start_headless_auto() so AI drives both sides.

extends Control
class_name MtTestBoard

const AI_DELAY := 0.35
const BACK_SCENE := "res://scenes/ui/PostLogin.tscn"
const MAT_CFG := "user://playfield.cfg"
const MAT_CUSTOM_DIR := "res://assets/mats/Custom"

var engine: MtMatch
var ai := MtDummyAI.new()
var ai_mcts := MtMctsAi.new()
var ai_levels := MtAiLevels.new(MtAiLevels.ADV)
var ai_auto := MtAiLevels.new(MtAiLevels.NEW)
var ai_policy := 1 # 0 = New, 1 = Adv, 2 = Pro (Phase 2 difficulties)
# Watch mode (spectate AI vs AI on the real board): per-side policies,
# slowed pace, opponent hand visible. Set up via start_watch_duel().
var watch := false
var spectate := false
var _watch_delay := 0.8
var _watch_cd := 0.0
var watch_pa := MtAiLevels.new(MtAiLevels.NEW)
var watch_pb := MtAiLevels.new(MtAiLevels.NEW)
var human_seat := 0
var lan_mode := false
var replay_mode := false
var _replay_queue: Array = []
var _replay_wait := 0.0
var _replay_paused := false
var _replay_pace := 0.45
var _replay_pause: Button
var _replay_step: Button
var _replay_speed: Button
var _report_kind: OptionButton
var series_wins: Array = [0, 0]
var _series_deck_a: Dictionary = {}
var _series_deck_b: Dictionary = {}
var _series_ai := 1
var _series_box: VBoxContainer
var _replay_actions: Array = []
var _match_seed := 0
var _opp_hand: HBoxContainer
var selected_uid := ""
var attacker_uid := ""

var _started := false
var _over_shown := false
var _auto := false
var _ai_timer := 0.0
var _dirty := true
var _shown_log := 0
var _safety := 0

enum CtxAction {
	HAND_PLAY = 1,
	HAND_TRASH = 2,
	HAND_ADD_LIFE = 3,
	FIELD_REST_STAND = 10,
	FIELD_ATTACH_DON = 11,
	FIELD_DETACH_DON = 12,
	FIELD_ACTIVATE = 13,
	FIELD_TRASH = 14,
	FIELD_RETURN_HAND = 15,
	FIELD_ATTACK_LEADER = 16,
	FIELD_ATTACK_TARGET = 17,
	DECK_DRAW_1 = 20,
	DECK_DRAW_2 = 21,
	DECK_MILL = 22,
	DECK_LOOK_TOP = 23,
	DECK_SHUFFLE = 24,
	DON_GIVE_ACTIVE = 30,
	DON_GIVE_2_ACTIVE = 31,
	DON_GIVE_RESTED = 32,
	LIFE_TAKE_TO_HAND = 40,
	LIFE_TRASH = 41,
	LIFE_ADD_FROM_DECK = 42,
	TRASH_RECOVER_TOP = 50,
	TRASH_VIEW = 51,
	CHOOSE_THIS = 60,
	COUNTER_THIS = 61,
	BLOCK_THIS = 62,
	SKIP_OPTION = 63,
	CHOOSE_OPT0 = 70,
	CHOOSE_OPT1 = 71,
	CHOOSE_OPT2 = 72,
	CHOOSE_OPT3 = 73,
}

var _hand: HBoxContainer
var _log_view: RichTextLabel
var _status: Label
var _clock_label: Label
var _tourney_left := 0.0
var _time_up := false
var _series_live := false
var _context_menu: PopupMenu
var _ctx_target_card: MtMatchCard = null
var _ctx_target_role := ""
var _ctx_zone := ""
var _ctx_player_idx := 0
var _over_label: Label
var _don_opp: Label
var _don_me: Label
var _sub_opp: Label
var _sub_me: Label
var _phase_label: Label
var _placed: Array = []
var _trigger_dialog: ConfirmationDialog
var _mulligan_dialog: ConfirmationDialog
var _mat_pick: OptionButton
var _mat_paths: Array = []
var _mat_auto := true
var is_puzzle_mode := false:
	set(v):
		is_puzzle_mode = v
		if _header != null:
			_header.visible = is_puzzle_mode
		if _puzzle_banner != null:
			_puzzle_banner.visible = is_puzzle_mode
var _header: HBoxContainer
var _puzzle_pick: OptionButton
var _puzzle_entries: Array = []
var _puzzle := {}
var _puzzle_banner: Label
var _ai_info := ""
var _rightbar: VBoxContainer
var _ctrl_panel: PanelContainer
var _battle_banner: Label
var _resolve_banner: Label
var _battle_panel: VBoxContainer
var _battle_title: Label
var _battle_go: Button
var _battle_pass: Button
var _center_battle_prompt: PanelContainer
var _center_battle_title: Label
var _center_battle_sub: Label
var _center_battle_go: Button
var _center_battle_pass: Button
var _choice_opts: VBoxContainer
var _look_build: Array = []
var _look_key := ""
var _arrow: Line2D
var _back_style: StyleBoxFlat
var _insp_art: TextureRect
var _insp_name: Label
var _insp_stats: Label
var _insp_text: RichTextLabel
var _inspector_hover := ""
var _tablebg: MtTableBg
var _bg_pick: OptionButton
var _bar_name := []
var _bar_life := []
var _bar_bar := []
var _shown_life := [5.0, 5.0]
var _playfield: MtPlayField
var _drag_ghost: MtMatCard = null
var _drag_uid := ""
var _drag_role := ""
var _committed_don: int = 0
var _slot_dialog: ConfirmationDialog
var _slot_buttons: Array = []
var _slot_pending_uid := ""
var _attack_dialog: ConfirmationDialog
var _attack_target_box: HBoxContainer
var _attack_pending_atk_uid := ""
var _give_don_dialog: Control
var _give_don_box: VBoxContainer
var _card_slot_map: Dictionary = {}
var chat_ui: Control = null
var _hand_tween: Tween = null
var _hand_lowered := false

func set_previous_scene(_prev: String) -> void:
	pass

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	build_ui()
	load_chat_ui()
	var net := get_node_or_null("/root/Lan")
	if net != null and not net.action_requested.is_connected(_on_lan_request):
		net.action_requested.connect(_on_lan_request)
		net.action_broadcast.connect(_on_lan_broadcast)
	# Belt-and-suspenders: no updater panel may ever cover the board.
	for n in get_tree().root.find_children("UpdaterPanel", "PanelContainer", true, false):
		(n as Control).visible = false

func load_chat_ui() -> void:
	if OS.get_name() == "Android" or chat_ui:
		return
	var chat_scene = load("res://scenes/ui/ChatUI.tscn")
	if chat_scene is PackedScene:
		chat_ui = chat_scene.instantiate()
		chat_ui.mouse_filter = Control.MOUSE_FILTER_PASS
		chat_ui.z_index = 100
		add_child(chat_ui)

func _on_don_hover_changed(hovered: bool) -> void:
	if _hand == null:
		return
	if hovered == _hand_lowered:
		return
	_hand_lowered = hovered
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	_hand_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_y := 105.0 if _hand_lowered else -15.0
	_hand_tween.tween_property(_hand, "position:y", target_y, 0.22)
	# Loud self-check: halves missing = stale global class cache in the
	# editor (run --import once). Never fail silently with an empty table.
	if _playfield == null or _playfield.zone_total() < 8:
		printerr("TestBoard: PlayField halves failed to build (zone_total=%s). If running in the editor, reimport the project (godot --headless --path <project> --import) to refresh script classes." % str(0 if _playfield == null else _playfield.zone_total()))

func build_ui() -> void:
	# Table surface first (parallax ship / wood / dark, player-switchable).
	_tablebg = MtTableBg.new()
	add_child(_tablebg)
	_tablebg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tablebg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tablebg.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tablebg.offset_left = 0
	_tablebg.offset_top = 0
	_tablebg.offset_right = 0
	_tablebg.offset_bottom = 0
	# Mirrored 2-player mat sits behind everything (purely visual layer).
	var packed: PackedScene = load("res://scenes/PlayField.tscn")
	_playfield = packed.instantiate() as MtPlayField
	add_child(_playfield)
	_playfield.set_anchors_preset(Control.PRESET_FULL_RECT)
	_playfield.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_playfield.grow_vertical = Control.GROW_DIRECTION_BOTH
	_playfield.offset_left = 0
	_playfield.offset_top = 0
	_playfield.offset_right = 0
	_playfield.offset_bottom = 0
	_playfield.set_table_mode(_tablebg.mode)
	if _playfield.has_signal("don_hover_changed"):
		_playfield.don_hover_changed.connect(_on_don_hover_changed)
	if _playfield.has_signal("mat_drag_started"):
		_playfield.mat_drag_started.connect(_on_mat_drag_started)
	if _playfield.has_signal("mat_drag_moved"):
		_playfield.mat_drag_moved.connect(_on_mat_drag_moved)
	if _playfield.has_signal("mat_drag_ended"):
		_playfield.mat_drag_ended.connect(_on_mat_drag_ended)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var header := HBoxContainer.new()
	_header = header
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.visible = is_puzzle_mode
	root.add_child(_header)
	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.pressed.connect(_on_back)
	_header.add_child(back_btn)
	_phase_label = Label.new()
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_child(_phase_label)
	_mat_pick = OptionButton.new()
	_mat_pick.tooltip_text = "Your play mat (bottom half)"
	_mat_pick.item_selected.connect(_on_mat_pick)
	_header.add_child(_mat_pick)
	_populate_mats()
	_bg_pick = OptionButton.new()
	_bg_pick.tooltip_text = "Table background"
	_bg_pick.add_item("Ship & Clouds", 0)
	_bg_pick.add_item("Wood", 1)
	_bg_pick.add_item("Dark", 2)
	_bg_pick.item_selected.connect(_on_bg_pick)
	_header.add_child(_bg_pick)
	_sync_bg_pick()
	var ai_pick := OptionButton.new()
	ai_pick.tooltip_text = "Opponent AI (P1): Easy / Medium / Pro"
	ai_pick.add_item("AI: Easy", 0)
	ai_pick.add_item("AI: Medium", 1)
	ai_pick.add_item("AI: Pro", 2)
	ai_pick.select(1)
	ai_pick.item_selected.connect(_on_ai_pick)
	_header.add_child(ai_pick)
	_puzzle_pick = OptionButton.new()
	_puzzle_pick.tooltip_text = "Lethal puzzles (win this turn)"
	_header.add_child(_puzzle_pick)
	_populate_puzzles()
	var load_puzzle_btn := Button.new()
	load_puzzle_btn.text = "Load Puzzle"
	load_puzzle_btn.tooltip_text = "Load the selected lethal puzzle (win this turn)"
	load_puzzle_btn.pressed.connect(_on_puzzle_load)
	_header.add_child(load_puzzle_btn)
	var new_btn := Button.new()
	new_btn.text = "Reset"
	new_btn.pressed.connect(_on_puzzle_load)
	_header.add_child(new_btn)

	# In puzzle mode, only show the puzzle controls: Back, Puzzle Picker, Load, Reset
	_mat_pick.visible = false
	_bg_pick.visible = false
	ai_pick.visible = false
	_phase_label.visible = false

	_puzzle_banner = Label.new()
	_puzzle_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puzzle_banner.add_theme_font_size_override("font_size", 16)
	_puzzle_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_puzzle_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_puzzle_banner.visible = is_puzzle_mode
	root.add_child(_puzzle_banner)
	_build_player_bars(root)

	# YGO table row: card inspector left, field center, combat log & controls right.
	# Cards live on the PlayField behind the transparent center column.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)

	# --- Left column: Card Inspector (top left) ---
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(460, 0)
	left_col.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(left_col)

	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 8)
	left_col.add_child(nav_row)
	var back_always := Button.new()
	back_always.text = "< Back"
	back_always.custom_minimum_size = Vector2(88, 32)
	back_always.pressed.connect(_on_back)
	nav_row.add_child(back_always)
	_report_kind = OptionButton.new()
	for label in ["Chat", "Person", "Deck", "Game", "Mat", "Sleeve", "Avatar"]:
		_report_kind.add_item(label)
	_report_kind.tooltip_text = "What this report is about"
	nav_row.add_child(_report_kind)
	var report_b := Button.new()
	report_b.text = "Report"
	report_b.tooltip_text = "Save a conduct report. Match chat stays in the replay. This report is stored with the other records."
	report_b.pressed.connect(_file_board_report)
	nav_row.add_child(report_b)
	_clock_label = Label.new()
	_clock_label.text = ""
	_clock_label.visible = false
	nav_row.add_child(_clock_label)
	_replay_pause = Button.new()
	_replay_pause.text = "Pause"
	_replay_pause.tooltip_text = "Pause or resume the replay (Space)"
	_replay_pause.visible = false
	_replay_pause.pressed.connect(_on_replay_pause)
	nav_row.add_child(_replay_pause)
	_replay_step = Button.new()
	_replay_step.text = "Step"
	_replay_step.tooltip_text = "Play the next action and stay paused"
	_replay_step.visible = false
	_replay_step.pressed.connect(_on_replay_step)
	nav_row.add_child(_replay_step)
	_replay_speed = Button.new()
	_replay_speed.text = "Faster"
	_replay_speed.tooltip_text = "Cycle replay speed"
	_replay_speed.visible = false
	_replay_speed.pressed.connect(_on_replay_speed)
	nav_row.add_child(_replay_speed)

	var left_panel := PanelContainer.new()
	left_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left_panel.custom_minimum_size = Vector2(440, 0)
	var insp_style := StyleBoxFlat.new()
	insp_style.bg_color = Color(0.08, 0.10, 0.14, 0.82)
	insp_style.border_color = Color(0.40, 0.45, 0.55, 0.5)
	insp_style.set_border_width_all(1)
	insp_style.set_corner_radius_all(8)
	insp_style.content_margin_left = 10
	insp_style.content_margin_right = 10
	insp_style.content_margin_top = 10
	insp_style.content_margin_bottom = 10
	left_panel.add_theme_stylebox_override("panel", insp_style)
	left_col.add_child(left_panel)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left_panel.add_child(left)
	_insp_art = TextureRect.new()
	_insp_art.custom_minimum_size = Vector2(400, 560)
	_insp_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_insp_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_insp_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_insp_art)
	_insp_name = Label.new()
	_insp_name.add_theme_font_size_override("font_size", 18)
	_insp_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_insp_name)
	_insp_stats = Label.new()
	_insp_stats.add_theme_font_size_override("font_size", 12)
	left.add_child(_insp_stats)
	_insp_text = RichTextLabel.new()
	_insp_text.bbcode_enabled = true
	_insp_text.custom_minimum_size = Vector2(0, 200)
	_insp_text.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_insp_text.add_theme_font_size_override("normal_font_size", 14)
	left.add_child(_insp_text)

	var left_spacer := Control.new()
	left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(left_spacer)

	# --- Center column: Opponent Hand (top), Field Spacer, Battle Banner, Player Hand (bottom) ---
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(center)
	_opp_hand = HBoxContainer.new()
	_opp_hand.add_theme_constant_override("separation", 6)
	_opp_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	_opp_hand.custom_minimum_size = Vector2(0, 100)
	_opp_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_opp_hand)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(spacer)
	_battle_banner = Label.new()
	_battle_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_banner.add_theme_font_size_override("font_size", 20)
	_battle_banner.add_theme_color_override("font_color", Color(1.0, 0.6, 0.8))
	_battle_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_battle_banner.add_theme_constant_override("outline_size", 8)
	_battle_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_banner.visible = false
	center.add_child(_battle_banner)
	_resolve_banner = Label.new()
	_resolve_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resolve_banner.add_theme_font_size_override("font_size", 28)
	_resolve_banner.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	_resolve_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_resolve_banner.add_theme_constant_override("outline_size", 10)
	_resolve_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resolve_banner.visible = false
	center.add_child(_resolve_banner)

	var prompt_panel := PanelContainer.new()
	var prompt_style := StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.08, 0.10, 0.14, 0.94)
	prompt_style.border_color = Color(1.0, 0.85, 0.3, 0.9)
	prompt_style.set_border_width_all(2)
	prompt_style.set_corner_radius_all(10)
	prompt_style.content_margin_left = 18
	prompt_style.content_margin_right = 18
	prompt_style.content_margin_top = 10
	prompt_style.content_margin_bottom = 10
	prompt_panel.add_theme_stylebox_override("panel", prompt_style)
	prompt_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prompt_panel.visible = false
	center.add_child(prompt_panel)
	_center_battle_prompt = prompt_panel

	var prompt_vbox := VBoxContainer.new()
	prompt_vbox.add_theme_constant_override("separation", 6)
	prompt_panel.add_child(prompt_vbox)

	_center_battle_title = Label.new()
	_center_battle_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_battle_title.add_theme_font_size_override("font_size", 16)
	_center_battle_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	prompt_vbox.add_child(_center_battle_title)

	_center_battle_sub = Label.new()
	_center_battle_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_battle_sub.add_theme_font_size_override("font_size", 13)
	_center_battle_sub.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	prompt_vbox.add_child(_center_battle_sub)

	var prompt_btn_box := HBoxContainer.new()
	prompt_btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_btn_box.add_theme_constant_override("separation", 14)
	prompt_vbox.add_child(prompt_btn_box)

	_choice_opts = VBoxContainer.new()
	_choice_opts.add_theme_constant_override("separation", 6)
	prompt_vbox.add_child(_choice_opts)

	_center_battle_go = Button.new()
	_center_battle_go.custom_minimum_size = Vector2(210, 42)
	_center_battle_go.add_theme_font_size_override("font_size", 14)
	var style_go := StyleBoxFlat.new()
	style_go.bg_color = Color(0.18, 0.38, 0.65, 0.9)
	style_go.border_color = Color(0.4, 0.7, 1.0, 0.9)
	style_go.set_border_width_all(1)
	style_go.set_corner_radius_all(6)
	_center_battle_go.add_theme_stylebox_override("normal", style_go)
	var style_go_h := style_go.duplicate()
	style_go_h.bg_color = Color(0.25, 0.52, 0.85, 1.0)
	_center_battle_go.add_theme_stylebox_override("hover", style_go_h)
	_center_battle_go.pressed.connect(_on_battle_go)
	prompt_btn_box.add_child(_center_battle_go)

	_center_battle_pass = Button.new()
	_center_battle_pass.custom_minimum_size = Vector2(240, 42)
	_center_battle_pass.add_theme_font_size_override("font_size", 14)
	var style_pass := StyleBoxFlat.new()
	style_pass.bg_color = Color(0.48, 0.16, 0.16, 0.9)
	style_pass.border_color = Color(0.95, 0.35, 0.35, 0.9)
	style_pass.set_border_width_all(1)
	style_pass.set_corner_radius_all(6)
	_center_battle_pass.add_theme_stylebox_override("normal", style_pass)
	var style_pass_h := style_pass.duplicate()
	style_pass_h.bg_color = Color(0.68, 0.22, 0.22, 1.0)
	_center_battle_pass.add_theme_stylebox_override("hover", style_pass_h)
	_center_battle_pass.pressed.connect(func(): _apply({"type": "pass_battle"}))
	prompt_btn_box.add_child(_center_battle_pass)

	var hand_holder := Control.new()
	hand_holder.custom_minimum_size = Vector2(0, 180)
	hand_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(hand_holder)

	_hand = HBoxContainer.new()
	_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand.add_theme_constant_override("separation", 8)
	_hand.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.mouse_entered.connect(func(): _on_don_hover_changed(false))
	hand_holder.add_child(_hand)

	# --- Right column: Combat Log (top right), Spacer, Controls & Buttons (bottom right) ---
	_rightbar = VBoxContainer.new()
	_rightbar.custom_minimum_size = Vector2(240, 0)
	_rightbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_rightbar)

	var log_panel := PanelContainer.new()
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.08, 0.10, 0.14, 0.82)
	log_style.border_color = Color(0.40, 0.45, 0.55, 0.5)
	log_style.set_border_width_all(1)
	log_style.set_corner_radius_all(8)
	log_style.content_margin_left = 8
	log_style.content_margin_right = 8
	log_style.content_margin_top = 8
	log_style.content_margin_bottom = 8
	log_panel.add_theme_stylebox_override("panel", log_style)
	_rightbar.add_child(log_panel)

	var log_box := VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 4)
	log_panel.add_child(log_box)

	var log_header := Label.new()
	log_header.text = "COMBAT LOG"
	log_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_header.add_theme_font_size_override("font_size", 14)
	log_header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	log_box.add_child(log_header)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.custom_minimum_size = Vector2(0, 260)
	_log_view.scroll_following = true
	_log_view.add_theme_font_size_override("normal_font_size", 11)
	log_box.add_child(_log_view)

	var right_spacer := Control.new()
	right_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rightbar.add_child(right_spacer)

	var ctrl_panel := PanelContainer.new()
	var ctrl_style := StyleBoxFlat.new()
	ctrl_style.bg_color = Color(0.08, 0.10, 0.14, 0.82)
	ctrl_style.border_color = Color(0.40, 0.45, 0.55, 0.5)
	ctrl_style.set_border_width_all(1)
	ctrl_style.set_corner_radius_all(8)
	ctrl_style.content_margin_left = 10
	ctrl_style.content_margin_right = 10
	ctrl_style.content_margin_top = 10
	ctrl_style.content_margin_bottom = 10
	_ctrl_panel = ctrl_panel
	_ctrl_panel.visible = false
	_rightbar.add_child(_ctrl_panel)

	var ctrl_box := VBoxContainer.new()
	ctrl_box.add_theme_constant_override("separation", 6)
	ctrl_panel.add_child(ctrl_box)

	_battle_panel = VBoxContainer.new()
	_battle_panel.add_theme_constant_override("separation", 6)
	_battle_panel.visible = false
	ctrl_box.add_child(_battle_panel)
	_battle_title = Label.new()
	_battle_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_title.add_theme_font_size_override("font_size", 18)
	_battle_panel.add_child(_battle_title)
	_battle_go = Button.new()
	_battle_go.custom_minimum_size = Vector2(0, 52)
	_battle_go.add_theme_font_size_override("font_size", 20)
	_battle_panel.add_child(_battle_go)
	_battle_pass = Button.new()
	_battle_pass.custom_minimum_size = Vector2(0, 52)
	_battle_pass.add_theme_font_size_override("font_size", 20)
	_battle_pass.pressed.connect(func(): _apply({"type": "pass_battle"}))
	_battle_panel.add_child(_battle_pass)
	_battle_go.pressed.connect(_on_battle_go)

	_back_style = StyleBoxFlat.new()
	_back_style.bg_color = Color(0.10, 0.16, 0.35, 0.95)
	_back_style.set_border_width_all(1)
	_back_style.border_color = Color(0.75, 0.75, 0.75, 0.8)
	_back_style.set_corner_radius_all(3)
	_arrow = Line2D.new()
	_arrow.width = 5.0
	_arrow.default_color = Color(1.0, 0.85, 0.25, 0.9)
	_arrow.visible = false
	add_child(_arrow)

	# Labels kept in memory for state binding without polluting the display
	_don_me = Label.new()
	_sub_me = Label.new()
	_don_opp = Label.new()
	_sub_opp = Label.new()
	_status = Label.new()

	_over_label = Label.new()
	_over_label.add_theme_font_size_override("font_size", 18)
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl_box.add_child(_over_label)
	_series_box = VBoxContainer.new()
	_series_box.visible = false
	_series_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_box.add_child(_series_box)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	if _playfield != null:
		if _playfield.has_signal("zone_clicked"):
			_playfield.zone_clicked.connect(_on_zone_clicked)
		if _playfield.has_signal("don_card_clicked"):
			_playfield.don_card_clicked.connect(_on_don_card_clicked)
		if _playfield.has_signal("end_turn_pressed"):
			_playfield.end_turn_pressed.connect(func(): _apply({"type": "end_turn"}))
		if _playfield.has_signal("surrender_pressed"):
			_playfield.surrender_pressed.connect(_on_surrender)

	_trigger_dialog = ConfirmationDialog.new()
	_trigger_dialog.ok_button_text = "Activate"
	_trigger_dialog.cancel_button_text = "Decline"
	_trigger_dialog.confirmed.connect(_on_trigger_yes)
	_trigger_dialog.canceled.connect(_on_trigger_no)
	add_child(_trigger_dialog)

	_mulligan_dialog = ConfirmationDialog.new()
	_mulligan_dialog.title = "Opening Hand — Mulligan Rule"
	_mulligan_dialog.dialog_text = "Review your 5 opening cards.\nWould you like to keep this hand, or return all 5 cards to your deck, shuffle, and draw 5 new cards? (One-time mulligan)"
	_mulligan_dialog.ok_button_text = "Keep Hand"
	_mulligan_dialog.cancel_button_text = "Mulligan (return 5, shuffle, draw 5)"
	_mulligan_dialog.confirmed.connect(_on_mulligan_keep)
	_mulligan_dialog.canceled.connect(_on_mulligan_redraw)
	add_child(_mulligan_dialog)

	_build_slot_dialog()
	_build_attack_dialog()
	_build_give_don_dialog()

func _build_attack_dialog() -> void:
	_attack_dialog = ConfirmationDialog.new()
	_attack_dialog.title = "Select Attack Target"
	_attack_dialog.ok_button_text = "Cancel"
	_attack_dialog.get_cancel_button().visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_attack_dialog.add_child(vbox)
	var prompt := Label.new()
	prompt.text = "Choose attack target:"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt)
	_attack_target_box = HBoxContainer.new()
	_attack_target_box.add_theme_constant_override("separation", 8)
	_attack_target_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_attack_target_box)
	add_child(_attack_dialog)

func _show_attack_target_picker(atk_uid: String, valid_characters: Array) -> void:
	_attack_pending_atk_uid = atk_uid
	for c in _attack_target_box.get_children():
		c.queue_free()
	var foe = _remote_ps()
	if foe.leader != null:
		var btn_lead := Button.new()
		btn_lead.text = "Leader\n%s (%d)" % [foe.leader.card_name(), engine.card_power(foe.leader)]
		btn_lead.custom_minimum_size = Vector2(110, 52)
		var lead_uid: String = foe.leader.uid
		btn_lead.pressed.connect(func():
			_attack_dialog.hide()
			_attack_with_animation(_attack_pending_atk_uid, lead_uid)
			_attack_pending_atk_uid = ""
		)
		_attack_target_box.add_child(btn_lead)
	for char_card in valid_characters:
		var btn_c := Button.new()
		btn_c.text = "Character\n%s (%d)" % [char_card.card_name(), engine.card_power(char_card)]
		btn_c.custom_minimum_size = Vector2(110, 52)
		var char_uid: String = char_card.uid
		btn_c.pressed.connect(func():
			_attack_dialog.hide()
			_attack_with_animation(_attack_pending_atk_uid, char_uid)
			_attack_pending_atk_uid = ""
		)
		_attack_target_box.add_child(btn_c)
	_attack_dialog.popup_centered()

func _build_give_don_dialog() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.visible = false
	wrap.z_index = 80
	_give_don_dialog = wrap
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	style.border_color = Color(1.0, 0.85, 0.3, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	wrap.add_child(panel)
	_give_don_box = VBoxContainer.new()
	_give_don_box.add_theme_constant_override("separation", 8)
	panel.add_child(_give_don_box)
	add_child(wrap)

func _show_give_don_dialog(pc: Dictionary) -> void:
	if _give_don_dialog == null or engine == null:
		return
	for c in _give_don_box.get_children():
		_give_don_box.remove_child(c)
		c.free()
	var maxn := int(pc.get("max", 0))
	var player := int(pc.get("player", 0))
	var ps = engine.players[player]
	var title := Label.new()
	title.text = "[On Play] Give rested DON!!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	_give_don_box.add_child(title)
	var prompt := Label.new()
	prompt.text = "Give up to %d rested DON!! to your Leader or 1 of your Characters." % maxn
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(500, 0)
	_give_don_box.add_child(prompt)
	var targets: Array = []
	if ps.leader != null:
		targets.append(ps.leader)
	for ch in ps.field:
		targets.append(ch)
	for t in targets:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l := Label.new()
		name_l.text = "%s (%s)" % [t.card_name(), "Leader" if t.is_leader() else "Character"]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		for n in range(1, maxn + 1):
			var btn := Button.new()
			btn.text = "Give %d" % n
			btn.custom_minimum_size = Vector2(80, 32)
			var uid: String = t.uid
			var amt: int = n
			btn.pressed.connect(func():
				_give_don_dialog.visible = false
				_apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": amt, "target_uid": uid})
			)
			row.add_child(btn)
		_give_don_box.add_child(row)
	var zero := Button.new()
	zero.text = "Give 0"
	zero.pressed.connect(func():
		_give_don_dialog.visible = false
		_apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 0, "target_uid": ""})
	)
	_give_don_box.add_child(zero)
	_give_don_dialog.visible = true

func _attack_with_animation(atk_uid: String, target_uid: String) -> void:
	var w := _widget_for(atk_uid)
	if w != null and w.has_method("set_rested_animated"):
		w.set_rested_animated(true, 0.22)
	var res := engine.apply({"type": engine.ACTION_ATTACK, "attacker": atk_uid, "target": target_uid})
	if res.ok:
		attacker_uid = ""
	_status.text = "" if res.ok else "REJECT: %s" % res.msg
	_dirty = true

func _build_slot_dialog() -> void:
	_slot_dialog = ConfirmationDialog.new()
	_slot_dialog.title = "Select Character Slot"
	_slot_dialog.ok_button_text = "Cancel"
	_slot_dialog.get_cancel_button().visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_slot_dialog.add_child(vbox)
	var prompt := Label.new()
	prompt.text = "Choose which slot to place this Character in:"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)
	for i in range(5):
		var btn := Button.new()
		btn.text = "Slot %d" % (i + 1)
		btn.custom_minimum_size = Vector2(95, 48)
		var slot_idx := i
		btn.pressed.connect(func(): _on_slot_button_pressed(slot_idx))
		hbox.add_child(btn)
		_slot_buttons.append(btn)
	add_child(_slot_dialog)

func _on_bg_pick(idx: int) -> void:
	var m := "ship"
	if idx == 1:
		m = "wood"
	elif idx == 2:
		m = "dark"
	MtTableBg.save_mode(m)
	if _tablebg != null:
		_tablebg.apply_mode(m)
	if _playfield != null:
		_playfield.set_table_mode(m)

func _sync_bg_pick() -> void:
	match MtTableBg.load_mode():
		"wood":
			_bg_pick.select(1)
		"dark":
			_bg_pick.select(2)
		_:
			_bg_pick.select(0)

func _build_player_bars(_root: Control) -> void:
	# Player HUDs live on the PlayField mats (above deck, right of characters).
	_bar_name.clear()
	_bar_life.clear()
	_bar_bar.clear()
	if _playfield != null and _playfield._bot_mat != null and _playfield._top_mat != null:
		_bar_name.append(_playfield._bot_mat.hud_name_label())
		_bar_name.append(_playfield._top_mat.hud_name_label())
		_bar_life.append(_playfield._bot_mat.hud_life_label())
		_bar_life.append(_playfield._top_mat.hud_life_label())
		_bar_bar.append(_playfield._bot_mat.hud_bar())
		_bar_bar.append(_playfield._top_mat.hud_bar())

func _avatars() -> void:
	if _playfield == null:
		return
	var mine: Texture2D = load(ProfileManager.avatar_path)
	var opp: Texture2D = load("res://assets/profiles/pfps/avatar_2.png")
	if _playfield._bot_mat != null:
		_playfield._bot_mat.set_avatar(mine)
	if _playfield._top_mat != null:
		_playfield._top_mat.set_avatar(opp)

func _populate_mats() -> void:
	_mat_paths = [""]
	_mat_pick.add_item("Default Mat", 0)
	var idx := 1
	var dir := DirAccess.open(MAT_CUSTOM_DIR)
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and (f.ends_with(".png") or f.ends_with(".jpg") or f.ends_with(".webp")):
				_mat_paths.append(MAT_CUSTOM_DIR.path_join(f))
				_mat_pick.add_item(f.get_basename(), idx)
				idx += 1
			f = dir.get_next()
		dir.list_dir_end()
	_apply_saved_mat()

func _apply_saved_mat() -> void:
	var saved := ""
	if FileAccess.file_exists(MAT_CFG):
		var file := FileAccess.open(MAT_CFG, FileAccess.READ)
		if file:
			var data = JSON.parse_string(file.get_as_text())
			if data is Dictionary:
				saved = String(data.get("p0", ""))
	var sel := 0
	for i in range(_mat_paths.size()):
		if String(_mat_paths[i]) == saved and not saved.is_empty():
			sel = i
	_mat_pick.select(sel)
	_mat_auto = String(_mat_paths[sel]).is_empty()
	_apply_mat_path(String(_mat_paths[sel]))

func _on_mat_pick(idx: int) -> void:
	var path := String(_mat_paths[idx]) if idx < _mat_paths.size() else ""
	_mat_auto = path.is_empty()
	_apply_mat_path(path)
	var file := FileAccess.open(MAT_CFG, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"p0": path}))

func _leader_colors(ps: MtPlayerState) -> Array:
	if ps == null or ps.leader == null:
		return []
	return ps.leader.colors()

func _apply_auto_skins() -> void:
	# Each half takes its leader's color mat (P2's half renders rotated);
	# a manual mat pick overrides P0 only.
	if not _mat_auto or engine == null or _playfield == null:
		return
	_playfield.set_player_mat(0, MtMatSkin.art_for(_leader_colors(_local_ps())))
	_playfield.set_player_mat(1, MtMatSkin.art_for(_leader_colors(_remote_ps())))

func _apply_mat_path(path: String) -> void:
	var social := get_node_or_null("/root/Social")
	if social != null:
		social.mat_path = path
	if _playfield == null:
		return
	if path.is_empty() or not ResourceLoader.exists(path):
		_playfield.set_player_mat(0, null)
		return
	_playfield.set_player_mat(0, load(path) as Texture2D)

func _populate_puzzles() -> void:
	_puzzle_entries = []
	_puzzle_pick.clear()
	var dir := DirAccess.open("res://data/puzzles")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".json"):
				var file := FileAccess.open("res://data/puzzles".path_join(f), FileAccess.READ)
				if file != null:
					var data = JSON.parse_string(file.get_as_text())
					if data is Array:
						for i in range((data as Array).size()):
							var p: Dictionary = (data as Array)[i]
							_puzzle_entries.append({"file": f, "idx": i,
								"title": String(p.get("title", f))})
							_puzzle_pick.add_item("%s: %s" % [f, String(p.get("title", "?"))],
								_puzzle_entries.size() - 1)
			f = dir.get_next()
		dir.list_dir_end()
	if _puzzle_entries.is_empty():
		_puzzle_pick.add_item("(no puzzles)", 0)

func _on_puzzle_load() -> void:
	if _puzzle_entries.is_empty():
		_status.text = "No puzzle pack found (run tests/puzzle_smoke.gd to generate)."
		return
	var e: Dictionary = _puzzle_entries[_puzzle_pick.selected]
	var file := FileAccess.open("res://data/puzzles".path_join(String(e.get("file", ""))), FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if not (data is Array):
		return
	_load_puzzle((data as Array)[int(e.get("idx", 0))])

func _load_puzzle(p: Dictionary) -> void:
	engine = MtMatch.new()
	engine.rng.seed = int(p.get("seed", 1))
	engine.auto_resolve_choices = false
	engine.start(p.get("deck_a", {}), p.get("deck_b", {}), int(p.get("first", 0)))
	for a in p.get("prefix", []):
		var res := engine.apply(a)
		if not res.get("ok", false):
			_status.text = "Puzzle prefix illegal: %s" % res.get("code", "?")
			return
	ai_levels.new_game()
	ai_auto.new_game()
	if _playfield != null:
		_playfield.bind_engine(engine)
	_apply_auto_skins()
	selected_uid = ""
	attacker_uid = ""
	_over_shown = false
	_shown_log = 0
	_safety = 0
	_puzzle = {"winner": int(p.get("winner", 0)), "turn": int(p.get("turn", 0)),
		"title": String(p.get("title", "puzzle"))}
	_puzzle_banner.text = "PUZZLE: %s — win this turn as P%d!" % [_puzzle.get("title", ""), _puzzle.get("winner", 0)]
	_started = true
	_dirty = true

func _check_puzzle() -> void:
	if _puzzle.is_empty() or engine == null:
		return
	if engine.over:
		if engine.winner == int(_puzzle.get("winner", 0)) and engine.turn == int(_puzzle.get("turn", 0)):
			_puzzle_banner.text = "PUZZLE SOLVED: %s" % _puzzle.get("title", "")
		else:
			_puzzle_banner.text = "Puzzle failed — Load Puzzle to retry."
		_puzzle = {}
	elif engine.turn > int(_puzzle.get("turn", 0)):
		_puzzle_banner.text = "Puzzle failed (turn passed) — Load Puzzle to retry."
		_puzzle = {}

func _make_action_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)

func _clear_placed() -> void:
	for w in _placed:
		if is_instance_valid(w):
			w.queue_free()
	_placed.clear()

func _card_sub(card: MtMatchCard) -> String:
	var txt := "%d" % engine.card_power(card)
	if card.rested:
		txt += " [REST]"
	if card.don_count() > 0:
		if engine.active == card.owner:
			txt += " +%dDON" % card.don_count()
		else:
			txt += " +%dDON (Own Turn)" % card.don_count()
	return txt

func _place_mat_cards(me: MtPlayerState, foe: MtPlayerState) -> void:
	_clear_placed()
	if _playfield != null:
		_playfield.set_bottom_seat(human_seat)
	_place_card(foe.index, "leader", foe.leader, "opp_leader")
	_place_card(me.index, "leader", me.leader, "my_leader")
	_place_card(foe.index, "stage", foe.stage, "opp_stage")
	_place_card(me.index, "stage", me.stage, "my_stage")
	var slots_foe: Array = _playfield.char_slots(foe.index)
	for i in range(foe.field.size()):
		if i < slots_foe.size():
			_place_card_in(slots_foe[i], foe.field[i], "opp_field")
	var slots_me: Array = _playfield.char_slots(me.index)
	var used_slots: Dictionary = {}
	for c in me.field:
		if _card_slot_map.has(c.uid):
			var s: int = _card_slot_map[c.uid]
			if s >= 0 and s < slots_me.size() and not used_slots.has(s):
				used_slots[s] = c
	var free_idx := 0
	for c in me.field:
		var has_slot := false
		for s in used_slots:
			if used_slots[s] == c:
				has_slot = true
				break
		if not has_slot:
			while free_idx < slots_me.size() and used_slots.has(free_idx):
				free_idx += 1
			if free_idx < slots_me.size():
				used_slots[free_idx] = c
				_card_slot_map[c.uid] = free_idx
				free_idx += 1
	for s in used_slots:
		_place_card_in(slots_me[s], used_slots[s], "my_field")

func _place_card(player: int, zone: String, card: MtMatchCard, role: String) -> void:
	if card == null:
		return
	_place_card_in(_playfield.get_zone(player, zone), card, role)

func _place_card_in(parent: Control, card: MtMatchCard, role: String) -> void:
	if parent == null or card == null:
		return
	var w := MtMatCard.new()
	var don_tex: Texture2D = null
	if _playfield != null and _playfield._bot_mat != null:
		don_tex = _playfield._bot_mat._don_art()
	w.setup(card.uid, role, card.card_name(), _card_sub(card),
		String(card.card.get("image_path", "")), card.rested,
		card.uid == selected_uid or card.uid == attacker_uid, card.card,
		card.don_count(), don_tex)
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.offset_left = 2.0
	w.offset_top = 2.0
	w.offset_right = -2.0
	w.offset_bottom = -2.0
	w.custom_minimum_size = Vector2.ZERO
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.size_flags_vertical = Control.SIZE_EXPAND_FILL
	w.clicked.connect(_on_matcard)
	w.hovered.connect(_on_mat_hover)
	w.drag_start.connect(_on_card_drag_start)
	w.drag_move.connect(_on_card_drag_move)
	w.drag_end.connect(_on_card_drag_end)
	w.context_requested.connect(_on_card_context_requested)
	parent.add_child(w)
	_placed.append(w)

func _rebuild_hand() -> void:
	for c in _hand.get_children():
		_hand.remove_child(c)
		c.queue_free()
	var me = _local_ps()
	for card in me.hand:
		var sub := "Cost %d" % engine.play_cost(card)
		if card.counter_value() > 0:
			sub += " ·+%d" % card.counter_value()
		var w := MtMatCard.new()
		w.setup(card.uid, "hand", card.card_name(), sub,
			String(card.card.get("image_path", "")), false, card.uid == selected_uid, card.card)
		w.custom_minimum_size = Vector2(105, 145)
		if _committed_don > 0 and engine.play_cost(card) == _committed_don:
			w.set_raised(true, true)
		w.clicked.connect(_on_matcard)
		w.hovered.connect(_on_mat_hover)
		w.drag_start.connect(_on_card_drag_start)
		w.drag_move.connect(_on_card_drag_move)
		w.drag_end.connect(_on_card_drag_end)
		w.context_requested.connect(_on_card_context_requested)
		_hand.add_child(w)
		_placed.append(w)
	_rebuild_opp_hand()

func _update_hand_elevation() -> void:
	for c in _hand.get_children():
		if c is MtMatCard:
			var card_match := _find_my_card(c.uid)
			var cost: int = engine.play_cost(card_match) if card_match != null else c.cost_value()
			if _committed_don > 0 and cost == _committed_don:
				c.set_raised(true, true)
			else:
				c.set_raised(false, false)

func _rebuild_opp_hand() -> void:
	for c in _opp_hand.get_children():
		c.queue_free()
	if engine == null:
		return
	var foe = _remote_ps()
	if spectate:
		for card in foe.hand:
			var w := MtMatCard.new()
			w.setup(card.uid, "opp_hand", card.card_name(), _card_sub(card),
				String(card.card.get("image_path", "")), card.rested, false, card.card)
			w.custom_minimum_size = Vector2(68, 92)
			w.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_opp_hand.add_child(w)
		return
	# Opponent hand is always face-down backs (YGO table look, hidden info).
	var s_art := MtMatCard.sleeve_art()
	for _card in foe.hand:
		var back := TextureRect.new()
		back.texture = s_art
		back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.custom_minimum_size = Vector2(68, 92)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_opp_hand.add_child(back)

func _on_mat_hover(uid: String) -> void:
	_inspector_hover = uid
	_update_inspector()

func _find_any_card(uid: String) -> MtMatchCard:
	if engine == null or uid.is_empty():
		return null
	for pi in [0, 1]:
		var ps = engine.players[pi]
		for zone_arr in [ps.hand, ps.field, ps.deck, ps.trash, ps.life]:
			for c in zone_arr:
				if (c as MtMatchCard).uid == uid:
					return c
		if ps.leader != null and ps.leader.uid == uid:
			return ps.leader
		if ps.stage != null and ps.stage.uid == uid:
			return ps.stage
	return null

func _update_inspector() -> void:
	var uid := selected_uid if not selected_uid.is_empty() else _inspector_hover
	var card := _find_any_card(uid)
	if card == null:
		_insp_art.texture = null
		_insp_name.text = "Select or hover a card"
		_insp_stats.text = ""
		_insp_text.text = ""
		return
	_insp_art.texture = MtMatCard.art_for(String(card.card.get("image_path", "")))
	_insp_name.text = "%s (%s)" % [card.card_name(), card.card_code()]
	var power_val: int = engine.card_power(card) if engine != null else card.base_power()
	_insp_stats.text = MtCardProfile.inspector_stats(card.card, power_val)
	if card.don_count() > 0 and (card.is_leader() or card.is_character()):
		_insp_stats.text += "\nGiven DON!!: %d" % card.don_count()
	var rules := MtCardProfile.inspector_rules(card.card)
	if not card.granted_keywords.is_empty():
		var gkw: Array = []
		for k in card.granted_keywords:
			gkw.append("[%s]" % k)
		rules = "Gained this turn: " + " ".join(gkw) + ("\n" if rules != "" else "") + rules
	_insp_text.text = rules

func _on_matcard(uid: String, role: String) -> void:
	if _auto:
		return
	if uid.is_empty():
		return
	selected_uid = uid
	if role == "my_leader" or role == "my_field":
		attacker_uid = uid
	elif role == "hand" or role == "my_stage":
		attacker_uid = ""
	_dirty = true

func _loaded() -> bool:
	if engine:
		return true
	return get_node_or_null("/root/CardDatabase") != null

func _start_game() -> void:
	var cdb := get_node_or_null("/root/CardDatabase")
	if cdb == null:
		return
	var deck := MtDeckLoader.load_deck_file(MtDeckLoader.default_deck_path(), cdb.get_card_data)
	if deck.get("main", []).is_empty():
		var main_codes: Array = []
		for code in ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
				"ST01-007", "ST01-008", "ST01-009", "ST01-010", "ST01-011", "ST01-012", "ST01-013",
				"ST01-015"]:
			for _i in range(4):
				main_codes.append(code)
		deck = MtDeckLoader.build_from_lists("ST01-001", main_codes, cdb.get_card_data)
	start_custom_match(deck, deck, 0, ai_policy)

func start_custom_match(deck_a: Dictionary, deck_b: Dictionary, first: int, ai_lv: int, continue_series: bool = false, seed_override: int = -1) -> void:
	# Pre-duel setup handoff: custom decks, first player, opponent level.
	if not continue_series:
		series_wins = [0, 0]
	watch = false
	_series_deck_a = deck_a
	_series_deck_b = deck_b
	_series_ai = ai_lv
	_replay_actions = []
	_match_seed = seed_override if seed_override >= 0 else randi()
	_started = true
	ai_policy = clampi(ai_lv, 0, 2)
	ai_levels.set_level(ai_policy)
	engine = MtMatch.new()
	engine.rng.seed = _match_seed
	engine.auto_resolve_choices = false
	engine.enable_mulligan = true
	engine.start(deck_a, deck_b, first)
	var social := get_node_or_null("/root/Social")
	if social != null:
		social.clear_match_chat()
	_common_post_start(continue_series)

func start_ai_duel(deck_a: Dictionary, deck_b: Dictionary, level_a: int, level_b: int, first: int) -> void:
	start_custom_match(deck_a, deck_b, first, level_b)
	watch = true
	_watch_delay = 0.55
	watch_pa = MtAiLevels.new(clampi(level_a, 0, 2))
	watch_pb = MtAiLevels.new(clampi(level_b, 0, 2))
	watch_pa.new_game()
	watch_pb.new_game()

func start_spectate(deck_a: Dictionary, deck_b: Dictionary, first: int, seed_value: int, actions: Array) -> void:
	spectate = true
	lan_mode = true
	start_custom_match(deck_a, deck_b, first, 1, false, seed_value)
	watch = false
	human_seat = 0
	for step in actions:
		if step is Dictionary:
			_lan_applying = true
			_apply_local(step, false)
			_lan_applying = false

func start_lan_match(deck_a: Dictionary, deck_b: Dictionary, first: int, seat: int, seed_value: int, continue_series: bool = false) -> void:
	lan_mode = true
	human_seat = seat & 1
	var net := get_node_or_null("/root/Lan")
	if net != null and not net.match_begin.is_connected(_on_series_begin):
		net.match_begin.connect(_on_series_begin)
		net.throws_revealed.connect(_on_series_reveal)
	start_custom_match(deck_a, deck_b, first, 1, continue_series, seed_value)

func start_replay(data: Dictionary) -> void:
	var cdb := get_node_or_null("/root/CardDatabase")
	if cdb == null:
		return
	replay_mode = true
	human_seat = 0
	lan_mode = false
	var da: Dictionary = data.get("deck_a", {})
	var db: Dictionary = data.get("deck_b", {})
	var deck_a := MtDeckLoader.build_from_lists(String(da.get("leader", "")), da.get("main", []), cdb.get_card_data)
	var deck_b := MtDeckLoader.build_from_lists(String(db.get("leader", "")), db.get("main", []), cdb.get_card_data)
	_replay_queue = (data.get("actions", []) as Array).duplicate()
	_replay_wait = 0.0
	_replay_paused = false
	_replay_pace = 0.45
	start_custom_match(deck_a, deck_b, int(data.get("first", 0)), 1, false, int(data.get("seed", 0)))
	_show_replay_controls()

func _common_post_start(keep_clock: bool = false) -> void:
	ai_levels.new_game()
	ai_auto.new_game()
	_puzzle = {}
	_puzzle_banner.text = ""
	_card_slot_map.clear()
	if _playfield != null:
		_playfield.bind_engine(engine)
	_apply_auto_skins()
	selected_uid = ""
	attacker_uid = ""
	_over_shown = false
	_shown_log = 0
	_safety = 0
	_started = true
	_dirty = true
	if _series_box != null:
		_series_box.visible = false
	if _playfield != null:
		_playfield.set_bottom_seat(human_seat)
	_avatars()
	if not keep_clock:
		_arm_clock()

func _arm_clock() -> void:
	_time_up = false
	_tourney_left = 0.0
	if _clock_label != null:
		_clock_label.visible = false
	if replay_mode:
		return
	var net := get_node_or_null("/root/Lan")
	var minutes := 0
	if net != null and (lan_mode or spectate):
		minutes = int(net.tourney_minutes)
	if minutes <= 0:
		return
	_tourney_left = float(minutes * 60)
	if _clock_label != null:
		_clock_label.visible = true
		_clock_label.text = "%d:00" % minutes

func _tick_clock(delta: float) -> void:
	if _tourney_left <= 0.0:
		return
	_tourney_left -= delta
	var left := maxi(0, int(_tourney_left))
	if _clock_label != null:
		_clock_label.text = "%d:%02d" % [left / 60, left % 60]
	if _tourney_left <= 0.0 and not spectate:
		_time_up = true
		if _status != null:
			_status.text = "Time."

func start_headless_auto() -> void:
	_auto = true

func _input(event: InputEvent) -> void:
	if not _drag_uid.is_empty():
		if event is InputEventMouseMotion:
			_on_card_drag_move(event.global_position)
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_on_card_drag_end(null, mb.global_position)
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _cancel_rule_call():
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and not event.echo:
		if replay_mode and event.keycode == KEY_SPACE:
			_on_replay_pause()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if engine != null and (_cancel_rule_call()):
				get_viewport().set_input_as_handled()
				return
			_on_back()
		elif event.keycode == KEY_SPACE:
			if engine != null and (_cancel_rule_call()):
				get_viewport().set_input_as_handled()
				return

func _process(delta: float) -> void:
	if not _loaded():
		return
	if not _started:
		_started = true
		if is_puzzle_mode:
			_on_puzzle_load()
		else:
			_start_game()
		return
	_tick_clock(delta)
	if _time_up and engine != null and not engine.is_over():
		if _status != null:
			_status.text = "Time."
		return
	if engine.is_over():
		if not _over_shown:
			_over_shown = true
			_on_match_over()
			_dirty = true
		if _dirty:
			_rebuild()
		_tick_replay(delta)
		return
	_handle_pending_choice()
	_check_puzzle()
	_anim_bars(delta)
	if _auto:
		_tick_ai()
	elif watch:
		_watch_cd += delta
		if _watch_cd >= _watch_delay:
			_watch_cd = 0.0
			_tick_ai()
	else:
		if _should_ai_act():
			_ai_timer += delta
			if _ai_timer >= AI_DELAY:
				_ai_timer = 0.0
				_tick_ai()
		_tick_replay(delta)
	if _dirty:
		_rebuild()

func _anim_bars(delta: float) -> void:
	# Animated life totals on the YGO bars (tween toward actual).
	if engine == null or _bar_life.size() < 2:
		return
	for side in [0, 1]:
		var ps = _local_ps() if side == 0 else _remote_ps()
		var target := float(ps.life.size())
		var cur: float = _shown_life[side]
		if cur != target:
			cur += clampf(target - cur, -delta * 4.0, delta * 4.0)
			_shown_life[side] = cur
		(_bar_life[side] as Label).text = "Life %d / %d" % [int(round(cur)), ps.max_life]
		(_bar_bar[side] as ProgressBar).max_value = maxi(1, ps.max_life)
		(_bar_bar[side] as ProgressBar).value = cur

func _update_bar_names(me, foe) -> void:
	if _bar_name.size() < 2:
		return
	var titles := [ProfileManager.username if ProfileManager else "YOU", "OPP" if lan_mode else ("AI (" + MtAiLevels.level_name(ai_policy) + ")")]
	if watch:
		titles = ["AI (" + MtAiLevels.level_name(watch_pa.level) + ")", "AI (" + MtAiLevels.level_name(watch_pb.level) + ")"]
	elif spectate:
		titles = ["P0", "P1"]
	for side in [0, 1]:
		var ps = me if side == 0 else foe
		var lname := ""
		if ps.leader != null:
			lname = ps.leader.card_name()
		(_bar_name[side] as Label).text = "%s — %s" % [titles[side], lname]

func _handle_pending_choice() -> void:
	if spectate:
		return
	var pc = engine.pending_choice
	if pc == null:
		if _give_don_dialog != null:
			_give_don_dialog.visible = false
		return
	var ptype := String(pc.get("type", ""))
	if ptype == "life_trigger":
		var pp := int(pc.get("player", 0))
		var ans := {"type": engine.ACTION_TRIGGER_YES, "player": pp,
			"card_uid": String(pc.get("card_uid", ""))}
		if _auto or watch or (pp != human_seat and not lan_mode):
			# Headless sims, spectated games, and the AI side always take it.
			_apply(ans)
			return
		if not _trigger_dialog.visible:
			var card := engine._find_card_by_uid(pp, String(pc.get("card_uid", "")))
			var cname := card.card_name() if card != null else "Life card"
			_trigger_dialog.dialog_text = "%s has a [Trigger]. Activate it?" % cname
			_trigger_dialog.popup_centered()
	elif ptype == "mulligan":
		var pp := int(pc.get("player", 0))
		if _auto or watch or (pp != human_seat and not lan_mode):
			var ai_mulligan: bool = _ai_should_mulligan(pp)
			_apply({"type": engine.ACTION_MULLIGAN if ai_mulligan else engine.ACTION_KEEP_HAND, "player": pp})
			return
		if not _mulligan_dialog.visible:
			_mulligan_dialog.popup_centered()
	elif ptype == "give_don":
		var pp := int(pc.get("player", 0))
		if _auto or watch or (pp != human_seat and not lan_mode):
			var acts: Array = engine.get_legal_actions()
			if not acts.is_empty():
				_apply(acts[0])
			return
		if _give_don_dialog != null and not _give_don_dialog.visible:
			_show_give_don_dialog(pc)

func _on_mulligan_keep() -> void:
	if engine != null and engine.pending_choice != null and String(engine.pending_choice.get("type", "")) == "mulligan":
		_apply({"type": engine.ACTION_KEEP_HAND, "player": 0})

func _on_mulligan_redraw() -> void:
	if engine != null and engine.pending_choice != null and String(engine.pending_choice.get("type", "")) == "mulligan":
		_apply({"type": engine.ACTION_MULLIGAN, "player": 0})

func _ai_should_mulligan(p_idx: int) -> bool:
	if engine == null or p_idx >= engine.players.size():
		return false
	var ps = engine.players[p_idx]
	var playable_low_cost := 0
	for c in ps.hand:
		if c.is_character() and c.cost_value() <= 3:
			playable_low_cost += 1
	return playable_low_cost == 0

func _on_trigger_yes() -> void:
	_answer_trigger(true)

func _on_trigger_no() -> void:
	_answer_trigger(false)

func _answer_trigger(yes: bool) -> void:
	var pc = engine.pending_choice
	if pc == null:
		return
	_apply({"type": engine.ACTION_TRIGGER_YES if yes else engine.ACTION_TRIGGER_NO,
		"player": int(pc.get("player", 0)), "card_uid": String(pc.get("card_uid", ""))})

func _local_ps() -> MtPlayerState:
	return engine.players[human_seat]

func _remote_ps() -> MtPlayerState:
	return engine.players[1 - human_seat]

func _should_ai_act() -> bool:
	if lan_mode or replay_mode or engine == null:
		return false
	if engine.pending_choice != null:
		return int(engine.pending_choice.get("player", -1)) != human_seat
	if engine.in_battle():
		return int(engine.battle.get("defender_owner", -1)) != human_seat
	return engine.get_active_player() != human_seat

func _on_ai_pick(idx: int) -> void:
	ai_policy = idx
	ai_levels.set_level(idx)

func _pick_ai_action() -> Dictionary:
	# Headless auto mode always uses New (fast epsilon-greedy).
	if _auto:
		return ai_auto.pick_action(engine, 1)
	return ai_levels.pick_action(engine, 1)

func _pick_ai_action_for(mover: int) -> Dictionary:
	if watch:
		if mover == 0:
			return watch_pa.pick_action(engine, 0)
		return watch_pb.pick_action(engine, 1)
	return _pick_ai_action()

func start_watch_duel(cfg: Dictionary, cdb: Node) -> void:
	# Spectate: both sides AI (per-side levels), slowed pace, open hands.
	watch = true
	_watch_delay = float(cfg.get("watch_delay", 0.8))
	_watch_cd = 0.0
	var deck_a := _watch_deck(cfg.get("deck_a", {}), cdb)
	var deck_b := _watch_deck(cfg.get("deck_b", {}), cdb)
	var ban := MtDeckLoader.load_banlist(String(cfg.get("banlist", "")))
	var fmt: Dictionary = cfg.get("format", {})
	if not fmt.is_empty():
		if String(fmt.get("banlist", "")) != "":
			ban = MtDeckLoader.load_banlist(String(fmt.get("banlist", "")))
	var blocks := MtDeckLoader.load_blocks() if not (fmt.get("allowed_blocks", []) as Array).is_empty() else {}
	for side in [deck_a, deck_b]:
		var errs := MtDeckLoader.validate_deck(side, ban, fmt, blocks)
		if not errs.is_empty():
			_status.text = "Illegal deck: %s" % "; ".join(errs)
			watch = false
			return
	engine = MtMatch.new()
	engine.rng.seed = int(cfg.get("seed", 1))
	engine.auto_resolve_choices = false
	engine.enable_mulligan = true
	engine.start(deck_a, deck_b, int(cfg.get("first", 0)))
	watch_pa = MtAiLevels.new(clampi(int(cfg.get("level_a", 1)), 0, 2))
	watch_pb = MtAiLevels.new(clampi(int(cfg.get("level_b", 1)), 0, 2))
	ai_levels.new_game()
	ai_auto.new_game()
	if _playfield != null:
		_playfield.bind_engine(engine)
	_apply_auto_skins()
	selected_uid = ""
	attacker_uid = ""
	_over_shown = false
	_shown_log = 0
	_safety = 0
	_puzzle = {}
	_puzzle_banner.text = ""
	_started = true
	_dirty = true

func _watch_deck(spec: Dictionary, cdb: Node) -> Dictionary:
	match String(spec.get("kind", "st01")):
		"meta":
			var idx := int(spec.get("index", 0))
			if FileAccess.file_exists("res://data/meta/decks.json"):
				var decks = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta/decks.json"))
				if decks is Array and idx >= 0 and idx < (decks as Array).size():
					var d: Dictionary = (decks as Array)[idx]
					var codes: Array = []
					for c in d.get("main", []):
						for i in range(int((c as Dictionary).get("count", 0))):
							codes.append(String((c as Dictionary).get("code", "")))
					return MtDeckLoader.build_from_lists(String(d.get("leader", "")), codes, cdb.get_card_data)
			return {}
		"file":
			return MtDeckLoader.load_deck_file(String(spec.get("path", "")), cdb.get_card_data)
		_:
			var main_codes: Array = []
			for i in range(100):
				main_codes.append("ST01-%03d" % [(i % 14) + 1])
				if main_codes.size() >= 50:
					break
			return MtDeckLoader.build_from_lists("ST01-001", main_codes, cdb.get_card_data)

func _tick_ai() -> void:
	var guard := 0
	while not engine.is_over() and (watch or _auto or _should_ai_act()) and guard < 60:
		var mover := engine.mover()
		var a := _pick_ai_action_for(mover)
		if a.is_empty():
			break
		var act_type := String(a.get("type", ""))
		if not _auto and not watch and act_type == engine.ACTION_ATTACK:
			var atk_uid := String(a.get("attacker", ""))
			var w := _widget_for(atk_uid)
			if w != null and w.has_method("set_rested_animated"):
				w.set_rested_animated(true, 0.22)
		elif not _auto and not watch and act_type == engine.ACTION_PLAY_EVENT:
			var card_uid := String(a.get("card_uid", ""))
			var c := engine._find_card_by_uid(mover, card_uid)
			if c != null:
				_show_event_in_zone(c.card_name(), c.cost_value(), c.card.duplicate(), mover)
		var res := engine.apply(a)
		if not res.ok:
			break
		guard += 1
	_dirty = true
	if not _auto and ai_policy > 0:
		_ai_info = "%s %dit %s" % [MtAiLevels.level_name(ai_policy),
			ai_levels._mcts.last_iterations, ai_levels._mcts.last_source]

func _apply(action: Dictionary) -> void:
	if watch or spectate or _time_up:
		return
	if engine == null or engine.is_over():
		return
	if lan_mode and not _lan_applying:
		var net := get_node_or_null("/root/Lan")
		if net != null:
			if net.is_host:
				_apply_local(action, true)
				if engine != null:
					net.broadcast_action(action)
			else:
				net.request_action(action)
			return
	_apply_local(action, not replay_mode)

func _apply_local(action: Dictionary, record: bool) -> void:
	var res := engine.apply(action)
	if res.ok:
		if record:
			_replay_actions.append(action.duplicate())
		selected_uid = ""
		attacker_uid = ""
		_status.text = ""
		_committed_don = 0
		if _playfield != null:
			_playfield.set_committed_don(human_seat, 0)
	else:
		_status.text = "REJECT: %s (%s)" % [res.msg, res.code]
	_dirty = true
	if res.ok:
		_handle_pending_choice()

var _lan_applying := false

func _on_lan_request(action: Dictionary) -> void:
	var net := get_node_or_null("/root/Lan")
	_lan_applying = true
	_apply_local(action, true)
	_lan_applying = false
	if net != null:
		net.broadcast_action(action)

func _on_lan_broadcast(action: Dictionary) -> void:
	_lan_applying = true
	_apply_local(action, false)
	_lan_applying = false

func _file_board_report() -> void:
	var social := get_node_or_null("/root/Social")
	if social == null or _report_kind == null:
		return
	var kind := _report_kind.get_item_text(_report_kind.selected).to_lower()
	var foe := "opponent"
	if engine != null and engine.players.size() > 1:
		var other = engine.players[1 - human_seat]
		if other.leader != null:
			foe = other.leader.card_name()
	MtMatCard.sleeve_art()
	social.sleeve_path = MtMatCard.sleeve_file
	var evidence := {
		"appearance": social.appearance(),
		"decks": {"a": _deck_codes(_series_deck_a), "b": _deck_codes(_series_deck_b)},
		"match_chat": _match_chat_copy(),
	}
	social.file_report(kind, foe, "Reported from the table.", evidence)
	_status.text = "Report saved."

func _show_replay_controls() -> void:
	if _replay_pause == null:
		return
	_replay_pause.visible = true
	_replay_pause.text = "Pause"
	_replay_step.visible = true
	_replay_speed.visible = true
	_replay_speed.text = "Faster"

func _on_replay_pause() -> void:
	_replay_paused = not _replay_paused
	if _replay_pause != null:
		_replay_pause.text = "Play" if _replay_paused else "Pause"

func _on_replay_step() -> void:
	_replay_paused = true
	if _replay_pause != null:
		_replay_pause.text = "Play"
	_replay_one()

func _on_replay_speed() -> void:
	if _replay_pace > 0.3:
		_replay_pace = 0.12
		_replay_speed.text = "Fast"
	elif _replay_pace > 0.05:
		_replay_pace = 0.0
		_replay_speed.text = "Instant"
	else:
		_replay_pace = 0.45
		_replay_speed.text = "Faster"

func _tick_replay(delta: float) -> void:
	if not replay_mode or _replay_paused or engine == null or engine.is_over() or _replay_queue.is_empty():
		return
	_replay_wait += delta
	if _replay_wait < _replay_pace:
		return
	_replay_wait = 0.0
	_replay_one()

func _replay_one() -> void:
	if not replay_mode or engine == null or engine.is_over() or _replay_queue.is_empty():
		return
	var step: Dictionary = _replay_queue.pop_front()
	_lan_applying = true
	_apply_local(step, false)
	_lan_applying = false

func _on_match_over() -> void:
	var w := engine.winner
	if w >= 0 and w < 2 and not replay_mode and not watch and not is_puzzle_mode:
		series_wins[w] = int(series_wins[w]) + 1
	var series := "Series %d-%d." % [int(series_wins[0]), int(series_wins[1])]
	_over_label.text = "GAME OVER - WINNER P%d (%s)  %s" % [w, engine.win_reason, series]
	_save_replay()
	_show_series_buttons()
	var need := _wins_needed()
	if int(series_wins[human_seat]) >= need:
		ProfileManager.register_win()
	elif int(series_wins[1 - human_seat]) >= need:
		ProfileManager.register_loss()

func _wins_needed() -> int:
	var best := 3
	if lan_mode:
		var net := get_node_or_null("/root/Lan")
		if net != null and int(net.tourney_best) > 0:
			best = int(net.tourney_best)
	var social := get_node_or_null("/root/Social")
	if social != null and social.has_method("wins_needed"):
		return int(social.wins_needed(best))
	return 2

func _deck_codes(deck: Dictionary) -> Dictionary:
	var main: Array = []
	for c in deck.get("main", []):
		if c is Dictionary:
			main.append(String((c as Dictionary).get("card_code", "")))
	var leader: Dictionary = deck.get("leader", {})
	return {"leader": String(leader.get("card_code", "")), "main": main}

func _save_replay() -> void:
	if replay_mode or _replay_actions.is_empty():
		return
	var path := "user://replays/replay_%d.json" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://replays"))
	var body := {
		"seed": _match_seed,
		"first": engine.first_player_idx,
		"winner": engine.winner,
		"reason": engine.win_reason,
		"deck_a": _deck_codes(_series_deck_a),
		"deck_b": _deck_codes(_series_deck_b),
		"actions": _replay_actions,
		"match_chat": _match_chat_copy(),
		"appearance": _appearance_copy(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(body))

func _match_chat_copy() -> Array:
	var social := get_node_or_null("/root/Social")
	if social == null:
		return []
	return (social.match_chat as Array).duplicate(true)

func _appearance_copy() -> Dictionary:
	var social := get_node_or_null("/root/Social")
	if social != null and social.has_method("appearance"):
		social.sleeve_path = MtMatCard.sleeve_file
		return social.appearance()
	return {}

func _show_series_buttons() -> void:
	if _series_box == null:
		return
	for ch in _series_box.get_children():
		ch.queue_free()
	var done := int(series_wins[0]) >= _wins_needed() or int(series_wins[1]) >= _wins_needed()
	if done or replay_mode or watch or is_puzzle_mode:
		_series_box.visible = false
		return
	if lan_mode:
		_show_lan_series()
		return
	_series_box.visible = true
	var note := Label.new()
	note.text = "Next game. Throw, then the winner chooses who goes first."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_series_box.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_series_box.add_child(row)
	for hand in ["Rock", "Paper", "Scissors"]:
		var b := Button.new()
		b.text = hand
		b.pressed.connect(_on_series_throw.bind(hand))
		row.add_child(b)

func _show_lan_series() -> void:
	_series_live = true
	_series_box.visible = true
	var note := Label.new()
	note.text = "Next game. Both players throw."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_series_box.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_series_box.add_child(row)
	for hand in ["Rock", "Paper", "Scissors"]:
		var b := Button.new()
		b.text = hand
		b.pressed.connect(_on_lan_series_throw.bind(hand))
		row.add_child(b)

func _on_lan_series_throw(hand: String) -> void:
	var net := get_node_or_null("/root/Lan")
	if net != null:
		net.send_throw(hand)
	_over_label.text = "You threw %s." % hand

func _on_series_reveal(you: String, opp: String, winner_seat: int) -> void:
	if not _series_live or _series_box == null:
		return
	for ch in _series_box.get_children():
		ch.queue_free()
	if winner_seat < 0 or you == opp:
		_show_lan_series()
		_over_label.text = "Tie (%s vs %s). Throw again. Series %d-%d." % [you, opp, series_wins[0], series_wins[1]]
		return
	if winner_seat == human_seat:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_series_box.add_child(row)
		var first := Button.new()
		first.text = "Go first"
		first.pressed.connect(_on_lan_series_first.bind(human_seat))
		row.add_child(first)
		var second := Button.new()
		second.text = "Go second"
		second.pressed.connect(_on_lan_series_first.bind(1 - human_seat))
		row.add_child(second)
		_over_label.text = "You threw %s, opponent %s. You choose." % [you, opp]
		return
	_over_label.text = "You threw %s, opponent %s. Opponent is choosing." % [you, opp]

func _on_lan_series_first(first: int) -> void:
	var net := get_node_or_null("/root/Lan")
	if net != null:
		net.send_first(first)

func _on_series_begin(_deck_a: Dictionary, _deck_b: Dictionary, first: int, seed_value: int) -> void:
	if not _series_live:
		return
	_series_live = false
	if _series_box != null:
		_series_box.visible = false
	start_lan_match(_series_deck_a, _series_deck_b, first, human_seat, seed_value, true)

func _on_series_throw(hand: String) -> void:
	var opp: String = ["Rock", "Paper", "Scissors"][randi() % 3]
	var winner := MtPreDuel.rps_winner(hand, opp)
	for ch in _series_box.get_children():
		ch.queue_free()
	if winner < 0:
		_show_series_buttons()
		_over_label.text = "Tie (%s vs %s). Throw again. Series %d-%d." % [hand, opp, series_wins[0], series_wins[1]]
		return
	if winner == 0:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_series_box.add_child(row)
		var first := Button.new()
		first.text = "Go first"
		first.pressed.connect(_start_next_game.bind(human_seat))
		row.add_child(first)
		var second := Button.new()
		second.text = "Go second"
		second.pressed.connect(_start_next_game.bind(1 - human_seat))
		row.add_child(second)
		_over_label.text = "You threw %s, opponent %s. You choose." % [hand, opp]
		return
	_over_label.text = "You threw %s, opponent %s. Opponent goes second." % [hand, opp]
	_start_next_game(human_seat)

func _start_next_game(first: int) -> void:
	_series_box.visible = false
	start_custom_match(_series_deck_a, _series_deck_b, first, _series_ai, true)

func _on_attach_don() -> void:
	_apply({"type": engine.ACTION_ATTACH_DON, "card_uid": selected_uid})

func _on_play() -> void:
	if selected_uid.is_empty():
		_status.text = "Select a card from your hand first."
		return
	var card := _find_my_card(selected_uid)
	if card == null:
		_status.text = "Selected card is no longer in your hand."
		return
	var action_type := engine.ACTION_PLAY_EVENT if card.is_event() else engine.ACTION_PLAY
	_apply({"type": action_type, "card_uid": selected_uid})

func _on_activate() -> void:
	if engine != null and engine.pending_choice != null and String(engine.pending_choice.get("type", "")) == "give_don":
		_show_give_don_dialog(engine.pending_choice)
		return
	var card := _find_my_card(selected_uid)
	if card != null:
		var fx: Dictionary = engine.fx(card)
		if fx.get("activate_main", []).is_empty() and not fx.get("on_play", []).is_empty():
			_status.text = "%s has an [On Play] effect, resolved when it is played." % card.card_name()
			return
	_apply({"type": engine.ACTION_ACTIVATE, "card_uid": selected_uid})

func _on_counter() -> void:
	_apply({"type": engine.ACTION_COUNTER, "card_uid": selected_uid})

func _on_block() -> void:
	if selected_uid.is_empty():
		_status.text = "Select one of your [Blocker] Characters first."
		return
	_apply({"type": engine.ACTION_BLOCK, "blocker": selected_uid})

func _find_my_card(uid: String) -> MtMatchCard:
	var me = _local_ps()
	for c in me.hand:
		if c.uid == uid:
			return c
	for c in me.field:
		if c.uid == uid:
			return c
	if me.leader != null and me.leader.uid == uid:
		return me.leader
	return null

func _on_card_drag_start(card: MtMatCard, global_pos: Vector2) -> void:
	if _auto or watch or spectate or engine == null or engine.is_over():
		return
	if card.role != "hand" and card.role != "my_field":
		return
	_start_custom_drag(card.uid, card.role, MtMatCard.art_for(card.image_path()), global_pos)

func _start_custom_drag(uid: String, role: String, tex: Texture2D, global_pos: Vector2) -> void:
	_drag_uid = uid
	_drag_role = role
	if _drag_ghost != null:
		_drag_ghost.queue_free()
	_drag_ghost = MtMatCard.new()
	_drag_ghost.setup(uid, "drag", "", "", "", false, false, {})
	if _drag_ghost._art != null:
		_drag_ghost._art.texture = tex
	_drag_ghost.custom_minimum_size = Vector2(90, 126)
	_drag_ghost.size = Vector2(90, 126)
	_drag_ghost.modulate = Color(1.0, 1.0, 1.0, 0.88)
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 250
	add_child(_drag_ghost)
	_drag_ghost.global_position = global_pos - Vector2(45, 63)

func _on_don_card_clicked(player_index: int, _don_index: int, is_active: bool, is_committed: bool) -> void:
	if _auto or watch or engine == null or engine.is_over() or player_index != human_seat:
		return
	if is_active:
		var me = _local_ps()
		var avail: int = me.get_available_don()
		if _committed_don < avail:
			_committed_don += 1
			if _playfield != null:
				_playfield.set_committed_don(human_seat, _committed_don)
			_update_hand_elevation()
	elif is_committed:
		if _committed_don > 0:
			_committed_don -= 1
			if _playfield != null:
				_playfield.set_committed_don(human_seat, _committed_don)
			_update_hand_elevation()

func _on_mat_drag_started(player: int, zone: String, global_pos: Vector2) -> void:
	if _auto or engine == null or engine.is_over() or player != human_seat:
		return
	match zone:
		"deck":
			var me = _local_ps()
			if me.deck.is_empty():
				return
			_start_custom_drag("deck", "deck", MtMatCard.sleeve_art(), global_pos)
		"cost":
			var me = _local_ps()
			if me.get_available_don() <= 0:
				return
			var don_tex: Texture2D = null
			if _playfield != null and _playfield._bot_mat != null:
				don_tex = _playfield._bot_mat._don_art()
			_start_custom_drag("don", "don", don_tex if don_tex != null else MtMatCard.don_sleeve_art(), global_pos)
		"don_deck":
			var me = _local_ps()
			if me.don_in_deck <= 0:
				return
			_start_custom_drag("don_deck", "don_deck", MtMatCard.don_sleeve_art(), global_pos)
		"life":
			var me = _local_ps()
			if me.life.is_empty():
				return
			_start_custom_drag("life", "life", MtMatCard.sleeve_art(), global_pos)

func _on_mat_drag_moved(global_pos: Vector2) -> void:
	_on_card_drag_move(global_pos)

func _on_mat_drag_ended(player: int, _zone: String, global_pos: Vector2) -> void:
	if player == human_seat:
		_on_card_drag_end(null, global_pos)

func _on_card_drag_move(global_pos: Vector2) -> void:
	if _drag_ghost != null:
		_drag_ghost.global_position = global_pos - Vector2(45, 63)

func _on_card_drag_end(_card: MtMatCard, global_pos: Vector2) -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null
	if _drag_uid.is_empty():
		return
	var uid := _drag_uid
	var role := _drag_role
	_drag_uid = ""
	_drag_role = ""
	_handle_card_drop(uid, role, global_pos)

func _handle_card_drop(uid: String, role: String, global_pos: Vector2) -> void:
	if engine == null:
		return
	var me = _local_ps()
	var foe = _remote_ps()
	
	if role == "deck":
		# Official rule: cards can only be drawn at turn start (Draw Phase) or via card effects
		_status.text = "Cards are only drawn at turn start or via card effects."
		return

	elif role == "don":
		var target_card: MtMatchCard = null

		# 1. Check Leader (leader zone with grow, leader card widget with grow, or center distance)
		if me.leader != null:
			var leader_zone: Control = _playfield.get_zone(human_seat, "leader") if _playfield != null else null
			if leader_zone != null and leader_zone.get_global_rect().grow(45.0).has_point(global_pos):
				target_card = me.leader
			else:
				var lead_w := _widget_for(me.leader.uid)
				if lead_w != null:
					var lw_center: Vector2 = lead_w.get_global_transform() * (lead_w.size / 2.0)
					if lead_w.get_global_rect().grow(45.0).has_point(global_pos) or global_pos.distance_to(lw_center) <= 95.0:
						target_card = me.leader

		# 2. Check Characters on field (widgets, slots, or closest character in character area)
		if target_card == null and not me.field.is_empty():
			var closest_char: MtMatchCard = null
			var min_dist := 999999.0

			# Check all placed field card widgets
			for w in _placed:
				if is_instance_valid(w) and w is MtMatCard and (w as MtMatCard).role == "my_field":
					var w_center: Vector2 = w.get_global_transform() * (w.size / 2.0)
					var dist: float = global_pos.distance_to(w_center)
					if (w.get_global_rect().grow(35.0).has_point(global_pos) or dist <= 90.0) and dist < min_dist:
						for c in me.field:
							if c.uid == (w as MtMatCard).uid:
								closest_char = c
								min_dist = dist
								break

			if closest_char != null:
				target_card = closest_char

			# Check character slots if no widget matched directly
			if target_card == null and _playfield != null:
				var slots_me: Array = _playfield.char_slots(0)
				for i in range(slots_me.size()):
					var slot: Control = slots_me[i]
					if slot != null and slot.get_global_rect().grow(30.0).has_point(global_pos):
						for c in me.field:
							if _card_slot_map.get(c.uid, -1) == i or (not _card_slot_map.has(c.uid) and me.field.find(c) == i):
								target_card = c
								break
						if target_card != null:
							break

			# Fallback: if dropped anywhere in character area, snap to closest character
			if target_card == null and _playfield != null:
				var char_zone: Control = _playfield.get_zone(human_seat, "character")
				if char_zone != null and char_zone.get_global_rect().grow(25.0).has_point(global_pos):
					for w in _placed:
						if is_instance_valid(w) and w is MtMatCard and (w as MtMatCard).role == "my_field":
							var w_center: Vector2 = w.get_global_transform() * (w.size / 2.0)
							var dist: float = global_pos.distance_to(w_center)
							if dist < min_dist:
								for c in me.field:
									if c.uid == (w as MtMatCard).uid:
										closest_char = c
										min_dist = dist
										break
					if closest_char != null:
						target_card = closest_char

		if target_card != null:
			var res := engine.apply({"type": engine.ACTION_ATTACH_DON, "card_uid": target_card.uid})
			if res.ok:
				if _committed_don > 0:
					_committed_don -= 1
					if _playfield != null:
						_playfield.set_committed_don(human_seat, _committed_don)
					_update_hand_elevation()
				_status.text = ""
			else:
				_status.text = "REJECT: %s" % res.msg
			_dirty = true
			return

	elif role == "don_deck":
		# Official rule: DON is granted during DON!! Phase or via card effects
		_status.text = "DON!! is granted during the DON!! Phase or via card effects."
		return

	elif role == "life":
		# Official rule: Life cards are drawn upon taking damage or via card effects
		_status.text = "Life cards are drawn upon taking damage or via card effects."
		return

	elif role == "hand":
		var card := _find_my_card(uid)
		if card == null:
			return
		
		var bot_mat_rect := _playfield._bot_mat.get_global_rect() if (_playfield != null and _playfield._bot_mat != null) else Rect2()
		var leader_zone: Control = _playfield.get_zone(human_seat, "leader") if _playfield != null else null
		var lead_rect := leader_zone.get_global_rect() if leader_zone != null else Rect2()
		var is_left_of_leader := (lead_rect.size.x > 0 and global_pos.x < lead_rect.position.x and global_pos.x > lead_rect.position.x - 260.0 and global_pos.y >= lead_rect.position.y - 60.0 and global_pos.y <= lead_rect.end.y + 60.0)
		var event_zone: Control = _playfield.get_zone(human_seat, "event") if _playfield != null else null
		var dropped_on_event := (event_zone != null and event_zone.get_global_rect().has_point(global_pos))

		if card.is_event():
			# Dropped on event zone, left of leader, or anywhere on player's field
			if dropped_on_event or is_left_of_leader or bot_mat_rect.has_point(global_pos):
				_on_play_event_with_anim(uid)
				return

		elif card.is_stage():
			var stage_zone: Control = _playfield.get_zone(human_seat, "stage") if _playfield != null else null
			if (stage_zone != null and stage_zone.get_global_rect().has_point(global_pos)) or bot_mat_rect.has_point(global_pos):
				_on_play_card_uid(uid)
				return

		elif card.is_character():
			# 1. Dropped on a specific Character Slot (0..4)
			var slots_me: Array = _playfield.char_slots(0) if _playfield != null else []
			for i in range(slots_me.size()):
				var slot: Control = slots_me[i]
				if slot.get_global_rect().has_point(global_pos):
					_play_card_to_slot(uid, i)
					return
			
			# 2. Dropped on Character zone, Leader, or anywhere on player's field
			var char_zone: Control = _playfield.get_zone(human_seat, "character") if _playfield != null else null
			if (char_zone != null and char_zone.get_global_rect().has_point(global_pos)) or (leader_zone != null and leader_zone.get_global_rect().has_point(global_pos)) or bot_mat_rect.has_point(global_pos):
				var first_empty := -1
				for i in range(5):
					var occ := false
					for c in me.field:
						if _card_slot_map.get(c.uid, -1) == i:
							occ = true
							break
					if not occ:
						first_empty = i
						break
				if first_empty >= 0:
					_play_card_to_slot(uid, first_empty)
				else:
					_show_slot_picker(uid)
				return

	elif role == "my_field":
		# Attacking opponent!
		var opp_leader_zone: Control = _playfield.get_zone(1 - human_seat, "leader")
		if opp_leader_zone != null and opp_leader_zone.get_global_rect().has_point(global_pos):
			if foe.leader != null:
				_attack_with_animation(uid, foe.leader.uid)
				return
		
		var slots_foe: Array = _playfield.char_slots(1)
		for i in range(mini(foe.field.size(), slots_foe.size())):
			var slot: Control = slots_foe[i]
			if slot.get_global_rect().has_point(global_pos):
				var target_card: MtMatchCard = foe.field[i]
				_attack_with_animation(uid, target_card.uid)
				return

		# Dropped generally on opponent Character zone or mat:
		var opp_char_zone: Control = _playfield.get_zone(1 - human_seat, "character")
		var opp_mat: Control = _playfield._top_mat
		if (opp_char_zone != null and opp_char_zone.get_global_rect().has_point(global_pos)) or (opp_mat != null and opp_mat.get_global_rect().has_point(global_pos)):
			var atk_card := _find_my_card(uid)
			var valid_targets: Array = []
			for c in foe.field:
				if c.rested or engine._can_attack_active(atk_card):
					valid_targets.append(c)
			if valid_targets.is_empty():
				if foe.leader != null:
					_attack_with_animation(uid, foe.leader.uid)
			else:
				_show_attack_target_picker(uid, valid_targets)
			return

func _show_slot_picker(card_uid: String) -> void:
	_slot_pending_uid = card_uid
	if engine == null or engine.players.is_empty():
		return
	var me = _local_ps()
	for i in range(_slot_buttons.size()):
		var btn: Button = _slot_buttons[i]
		var occ_name := ""
		for c in me.field:
			if _card_slot_map.get(c.uid, -1) == i:
				occ_name = c.card_name()
				break
		if occ_name != "":
			btn.text = "Slot %d\n(%s)" % [i + 1, occ_name.substr(0, 8)]
		else:
			btn.text = "Slot %d\n[Empty]" % (i + 1)
	_slot_dialog.popup_centered()

func _on_slot_button_pressed(slot_idx: int) -> void:
	_slot_dialog.hide()
	if _slot_pending_uid.is_empty():
		return
	_play_card_to_slot(_slot_pending_uid, slot_idx)
	_slot_pending_uid = ""

func _play_card_to_slot(card_uid: String, slot_idx: int) -> void:
	var card := _find_my_card(card_uid)
	if card == null:
		return
	_card_slot_map[card_uid] = slot_idx
	var action_type := engine.ACTION_PLAY_EVENT if card.is_event() else engine.ACTION_PLAY
	var res := engine.apply({"type": action_type, "card_uid": card_uid})
	if res.ok:
		_committed_don = 0
		if _playfield != null:
			_playfield.set_committed_don(human_seat, 0)
	_status.text = "" if res.ok else "REJECT: %s" % res.msg
	_dirty = true

func _on_play_card_uid(card_uid: String) -> void:
	var card := _find_my_card(card_uid)
	if card == null:
		return
	if card.is_event():
		_on_play_event_with_anim(card_uid)
		return
	var res := engine.apply({"type": engine.ACTION_PLAY, "card_uid": card_uid})
	if res.ok:
		_committed_don = 0
		if _playfield != null:
			_playfield.set_committed_don(human_seat, 0)
	_status.text = "" if res.ok else "REJECT: %s" % res.msg
	_dirty = true

func _on_play_event_with_anim(card_uid: String) -> void:
	var card := _find_my_card(card_uid)
	if card == null:
		return
	var card_info := card.card.duplicate()
	var card_name_str := card.card_name()
	var cost_val := engine.play_cost(card)
	var res := engine.apply({"type": engine.ACTION_PLAY_EVENT, "card_uid": card_uid})
	if res.ok:
		_committed_don = 0
		if _playfield != null:
			_playfield.set_committed_don(human_seat, 0)
		selected_uid = ""
		_status.text = "Activated Event: %s" % card_name_str
		_show_event_in_zone(card_name_str, cost_val, card_info)
	else:
		_status.text = "REJECT: %s" % res.msg
	_dirty = true

func _show_event_in_zone(p_name: String, p_cost: int, p_dict: Dictionary, player: int = 0) -> void:
	var event_zone := _playfield.get_zone(player, "event") if _playfield != null else null
	if event_zone == null:
		return
	for c in event_zone.get_children():
		if c is MtMatCard:
			c.queue_free()
	var w := MtMatCard.new()
	w.setup("event_anim", "event", p_name, "Cost %d" % p_cost,
		String(p_dict.get("image_path", "")), false, false, p_dict)
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.pivot_offset = Vector2(45, 63)

	# Realistic throw-down casual angle (-14 deg to +14 deg, avoiding perfectly 0)
	var angle := randf_range(-14.0, 14.0)
	if absf(angle) < 4.0:
		angle = 6.0 if angle >= 0.0 else -6.0

	# Start slightly enlarged and hovering, then slap down onto felt
	w.scale = Vector2(1.28, 1.28)
	w.rotation_degrees = angle * 0.4
	w.modulate = Color(1.25, 1.25, 1.15, 0.7)
	event_zone.add_child(w)

	var tween := create_tween()
	# Throw down slap
	tween.set_parallel(true)
	tween.tween_property(w, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(w, "rotation_degrees", angle, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(w, "modulate", Color(1.05, 1.05, 1.0, 1.0), 0.16)
	# Hold on table felt
	tween.chain().tween_interval(1.1)
	# Fade out & drift slightly toward trash zone
	tween.chain().set_parallel(true)
	tween.tween_property(w, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(w, "position:x", w.position.x + 30.0, 0.35)
	tween.chain().tween_callback(w.queue_free)

func _rebuild() -> void:
	if engine == null:
		return
	var me = _local_ps()
	var foe = _remote_ps()

	var who := "AI"
	if watch:
		var side_lv := watch_pa.level if engine.get_active_player() == 0 else watch_pb.level
		who = "AI " + MtAiLevels.level_name(side_lv)
	elif engine.get_active_player() == human_seat:
		who = "YOU"
	elif lan_mode:
		who = "OPP"
	_phase_label.text = "Turn %d - P%d (%s)  %s" % [
		engine.turn, engine.get_active_player(), who,
		"BATTLE" if engine.in_battle() else ""]
	if _ai_info != "":
		_phase_label.text += "  [%s]" % _ai_info
	if _playfield != null:
		_phase_label.text += "  Mat T%d/B%d %dx%d" % [
			_playfield._top_mat.zone_total() if _playfield._top_mat != null and _playfield._top_mat.has_method("zone_total") else -1,
			_playfield._bot_mat.zone_total() if _playfield._bot_mat != null and _playfield._bot_mat.has_method("zone_total") else -1,
			int(_playfield.size.x), int(_playfield.size.y)]
	_update_bar_names(me, foe)

	_place_mat_cards(me, foe)
	_rebuild_hand()
	_update_battle_chrome()
	_update_battle_panel()
	_update_choice_panel()
	if _resolve_banner != null:
		_resolve_banner.visible = false
		_resolve_banner.text = ""
	if _ctrl_panel != null:
		_ctrl_panel.visible = _battle_panel.visible or not _over_label.text.is_empty()
	_update_inspector()
	_sweep_updater()

	if me.stage:
		_don_me.text = "Stage: %s" % me.stage.card_name()
	else:
		_don_me.text = ""
	var me_prefix := ""
	if me.stage:
		me_prefix = "Stage: %s   " % me.stage.card_name()
	_don_opp.text = "DON: %d/%d active, %d rested   Life: %d/%d   Attached %d" % [
		foe.don_active, foe.don_deck_size, foe.don_rested, foe.life.size(), foe.max_life, foe.get_attached_don_total()]
	_don_me.text = me_prefix + "DON: %d/%d active, %d rested   Life: %d/%d   Attached %d" % [
		me.don_active, me.don_deck_size, me.don_rested, me.life.size(), me.max_life, me.get_attached_don_total()]
	_sub_opp.text = "Hand %d   Deck %d   Trash %d" % [foe.hand.size(), foe.deck.size(), foe.trash.size()]
	_sub_me.text = "Hand %d   Deck %d   Trash %d" % [me.hand.size(), me.deck.size(), me.trash.size()]
	if _playfield != null:
		_playfield.refresh()

	var sel_txt := "Select a card"
	var sel_card = _find_my_card(selected_uid)
	if sel_card:
		sel_txt = "Selected: %s (%d)" % [sel_card.card_name(), engine.card_power(sel_card)]
		if not attacker_uid.is_empty():
			sel_txt += "   [ATTACKER - click an opponent card]"
	_status.text = sel_txt

	if _shown_log < engine.log_lines.size():
		var start := maxi(0, engine.log_lines.size() - 30)
		var text := "[center][color=gray]…[/color][/center]\n"
		for i in range(start, engine.log_lines.size()):
			text += "[center]" + engine.log_lines[i] + "[/center]\n"
		_log_view.text = text
		_shown_log = engine.log_lines.size()
	_dirty = false

func _on_battle_go() -> void:
	# Big contextual button: Block! during the blocker window, Counter!
	# during counter windows, using the currently selected card.
	if engine == null or not engine.in_battle():
		return
	if String(engine.battle.get("step", "")) == "block":
		_on_block()
	else:
		_on_counter()

func _update_battle_panel() -> void:
	# YGO-style: big step panel for the human defender only.
	if engine == null or not engine.in_battle() or _auto or watch:
		_battle_panel.visible = false
		if _center_battle_prompt != null:
			_center_battle_prompt.visible = false
		return
	if int(engine.battle.get("defender_owner", -1)) != human_seat:
		_battle_panel.visible = false
		if _center_battle_prompt != null:
			_center_battle_prompt.visible = false
		return
	var step := String(engine.battle.get("step", "resolve"))
	_battle_panel.visible = true
	if _center_battle_prompt != null:
		_center_battle_prompt.visible = true
	var b := engine.battle
	var atk: MtMatchCard = b.get("attacker", null)
	var dfn: MtMatchCard = b.get("defender", null)
	var a_name := atk.card_name() if atk != null else "Attacker"
	var d_name := dfn.card_name() if dfn != null else "Defender"
	var a_pow := engine.card_power(atk) if atk != null else 0
	var d_pow := (engine.card_power(dfn) if dfn != null else 0) + int(b.get("counter_bonus", 0))

	if step == "block":
		_battle_title.text = "Blocker Step"
		_battle_go.text = "Block!"
		_battle_pass.text = "No Blocker"
		var is_legal_block: bool = bool(engine._legal({"type": engine.ACTION_BLOCK, "blocker": selected_uid}).get("ok", false))
		_battle_go.disabled = not is_legal_block

		if _center_battle_title != null:
			_center_battle_title.text = "Block Step"
			_center_battle_sub.text = "%s (%d) is attacking %s (%d). You may rest a Character with [Blocker] to make it the new target." % [a_name, a_pow, d_name, d_pow]
			var sel := _find_my_card(selected_uid)
			if is_legal_block and sel != null:
				_center_battle_go.text = "Block with %s" % sel.card_name()
			else:
				_center_battle_go.text = "Declare Blocker"
			_center_battle_go.disabled = not is_legal_block
			_center_battle_pass.text = "Do not Block"
	else:
		_battle_title.text = "Counter Step"
		_battle_go.text = "Counter!"
		var sel := _find_my_card(selected_uid)
		var can_counter: bool = sel != null and (sel.counter_value() > 0 or (sel.is_event() and engine.has_counter_effect(sel)))
		_battle_go.disabled = not can_counter

		var cb: int = int(b.get("counter_bonus", 0))
		var is_char: bool = dfn != null and dfn.is_character()

		# Pass button: change text based on whether counters have been played
		if cb > 0:
			if d_pow > a_pow:
				_battle_pass.text = "Done (attack fails)"
			else:
				_battle_pass.text = "Done Countering"
		else:
			if is_char:
				_battle_pass.text = "Do not Counter"
			else:
				_battle_pass.text = "Do not Counter"

		if _center_battle_title != null:
			_center_battle_title.text = "Counter Step"
			if cb > 0:
				_center_battle_sub.text = "%s (%d) vs %s (%d + %d Counter = %d)" % [a_name, a_pow, d_name, d_pow - cb, cb, d_pow]
			else:
				_center_battle_sub.text = "%s (%d) vs %s (%d). You may use a Counter from your hand." % [a_name, a_pow, d_name, d_pow]
			if can_counter and sel != null:
				if sel.counter_value() > 0:
					_center_battle_go.text = "Counter: %s (+%d)" % [sel.card_name(), sel.counter_value()]
				else:
					_center_battle_go.text = "Activate [Counter]: %s" % sel.card_name()
			else:
				_center_battle_go.text = "Use Counter"
			_center_battle_go.disabled = not can_counter

			if cb > 0:
				if d_pow > a_pow:
					_center_battle_pass.text = "Done Countering (attack fails)"
				elif is_char:
					_center_battle_pass.text = "Done Countering (%s will be K.O.'d)" % d_name
				else:
					_center_battle_pass.text = "Done Countering (Leader takes damage)"
			else:
				if is_char:
					_center_battle_pass.text = "Do not Counter"
				else:
					_center_battle_pass.text = "Do not Counter"

func _sweep_updater() -> void:
	# The updater panel has appeared over live boards through unknown flow;
	# sweep it on every rebuild (cheap, runs only on dirty frames).
	for n in get_tree().root.find_children("UpdaterPanel", "PanelContainer", true, false):
		if (n as Control).visible:
			(n as Control).visible = false

func _clear_choice_opts() -> void:
	if _choice_opts == null:
		return
	for ch in _choice_opts.get_children():
		ch.queue_free()

func _update_choice_panel() -> void:
	_clear_choice_opts()
	if engine == null or _auto or watch:
		return
	if engine.pending_choice == null or int(engine.pending_choice.get("player", -1)) != human_seat:
		if _center_battle_go != null:
			_center_battle_go.visible = true
		if _center_battle_pass != null:
			_center_battle_pass.visible = true
		return
	var ptype := String(engine.pending_choice.get("type", ""))
	if ptype == "mulligan" or ptype == "life_trigger":
		return
	if _center_battle_prompt != null:
		_center_battle_prompt.visible = true
	if _battle_panel != null:
		_battle_panel.visible = false
	if _center_battle_go != null:
		_center_battle_go.visible = false
	if _center_battle_pass != null:
		_center_battle_pass.visible = false
	if _center_battle_title != null:
		if ptype == "modal":
			_center_battle_title.text = "Choose one"
			_center_battle_sub.text = "Pick an option, or continue with neither."
			var options: Array = engine.pending_choice.get("options", [])
			for oi in range(options.size()):
				var b := Button.new()
				b.text = "Option %d" % (oi + 1)
				var acts = options[oi]
				if acts is Array and not acts.is_empty() and acts[0] is Array:
					b.text = "Option %d: %s" % [oi + 1, String(acts[0][0]).replace("_", " ")]
				b.custom_minimum_size = Vector2(280, 36)
				var idx := oi
				b.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": idx}))
				_choice_opts.add_child(b)
			var skip := Button.new()
			skip.text = "Skip / continue with neither"
			skip.pressed.connect(func(): _cancel_rule_call())
			_choice_opts.add_child(skip)
		elif ptype == "look_order":
			var pool: Array = engine.pending_choice.get("all_uids", engine.pending_choice.get("candidates", []))
			var key := "%s|%s" % [String(engine.pending_choice.get("kind", "")), ",".join(pool)]
			if key != _look_key:
				_look_key = key
				_look_build = []
			_center_battle_title.text = "Place in order"
			_center_battle_sub.text = "Click remaining cards to add them (first = top). Click a placed card to pull it back."
			var placed := HBoxContainer.new()
			placed.alignment = BoxContainer.ALIGNMENT_CENTER
			placed.add_theme_constant_override("separation", 6)
			if _look_build.is_empty():
				var empty := Label.new()
				empty.text = "(empty — top of the pile)"
				placed.add_child(empty)
			for i in range(_look_build.size()):
				var uid := String(_look_build[i])
				var pb := Button.new()
				pb.text = "%d. %s" % [i + 1, _look_name(uid)]
				var drop_i := i
				pb.pressed.connect(func():
					if drop_i >= 0 and drop_i < _look_build.size():
						_look_build.remove_at(drop_i)
						_dirty = true
				)
				placed.add_child(pb)
			_choice_opts.add_child(placed)
			var rest := HBoxContainer.new()
			rest.alignment = BoxContainer.ALIGNMENT_CENTER
			rest.add_theme_constant_override("separation", 6)
			for uid2 in pool:
				var u := String(uid2)
				if _look_build.has(u):
					continue
				var rb := Button.new()
				rb.text = _look_name(u)
				var add_u := u
				rb.pressed.connect(func():
					if not _look_build.has(add_u):
						_look_build.append(add_u)
						_dirty = true
				)
				rest.add_child(rb)
			_choice_opts.add_child(rest)
			var conf := Button.new()
			conf.text = "Confirm this order"
			conf.pressed.connect(func(): _confirm_look_order(pool))
			_choice_opts.add_child(conf)
			var topb := Button.new()
			topb.text = "Confirm and place on top of deck"
			topb.pressed.connect(func(): _confirm_look_order(pool, "top"))
			_choice_opts.add_child(topb)
			var botb := Button.new()
			botb.text = "Confirm and place on the bottom"
			botb.pressed.connect(func(): _confirm_look_order(pool, "bottom"))
			_choice_opts.add_child(botb)
		elif ptype == "start_turn":
			_center_battle_title.text = "Start of your turn"
			_center_battle_sub.text = "You may activate this effect now."
			var go := Button.new()
			go.text = "Activate"
			go.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 1}))
			_choice_opts.add_child(go)
			var no := Button.new()
			no.text = "Skip"
			no.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 0, "skip": true}))
			_choice_opts.add_child(no)
		elif ptype == "pay_optional":
			_center_battle_title.text = "Pay the cost?"
			_center_battle_sub.text = "You may pay this cost. Declining skips the effect."
			var pay := Button.new()
			pay.text = "Pay"
			pay.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 1}))
			_choice_opts.add_child(pay)
			var decline := Button.new()
			decline.text = "Decline"
			decline.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 0, "skip": true}))
			_choice_opts.add_child(decline)
		elif ptype == "life_edge":
			_center_battle_title.text = "Top or bottom"
			_center_battle_sub.text = "Choose which end of the Life pile."
			var topb := Button.new()
			topb.text = "Top"
			topb.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "edge": "top"}))
			_choice_opts.add_child(topb)
			var botb := Button.new()
			botb.text = "Bottom"
			botb.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "edge": "bottom"}))
			_choice_opts.add_child(botb)
		elif ptype == "pick":
			var need := int(engine.pending_choice.get("max", 1))
			var have: Array = engine.pending_choice.get("picked", [])
			var up_to := bool(engine.pending_choice.get("up_to", false))
			_center_battle_title.text = "Choose cards"
			_center_battle_sub.text = "Right-click legal cards. %d of %d chosen.%s" % [
				have.size(), need, " You may take fewer." if up_to else ""]
			var done := Button.new()
			done.text = "Confirm / take fewer" if up_to else "Confirm"
			done.pressed.connect(func(): _apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 0}))
			_choice_opts.add_child(done)
		else:
			_center_battle_title.text = "Pending choice"
			_center_battle_sub.text = "Right-click a legal card, or skip."
			var sk := Button.new()
			sk.text = "Skip / continue"
			sk.pressed.connect(func(): _cancel_rule_call())
			_choice_opts.add_child(sk)

func _look_name(uid: String) -> String:
	var c := _find_any_card(uid)
	return c.card_name() if c != null else uid

func _confirm_look_order(pool: Array, rest_edge: String = "") -> void:
	var uids: Array = _look_build.duplicate()
	for u in pool:
		var us := String(u)
		if not uids.has(us):
			uids.append(us)
	var act := {"type": engine.ACTION_CHOOSE_EFFECT, "n": uids.size(), "uids": uids, "skip": false}
	if rest_edge != "":
		act["rest"] = rest_edge
	_look_build = []
	_look_key = ""
	_apply(act)

func _widget_for(uid: String) -> Control:
	for w in _placed:
		if is_instance_valid(w) and (w as MtMatCard).uid == uid:
			return w
	return null

func _update_battle_chrome() -> void:
	# YGO-style battle banner + attack arrow between the mat cards.
	if not engine.in_battle():
		_battle_banner.visible = false
		_arrow.visible = false
		return
	var b = engine.battle
	var atk: MtMatchCard = b.get("attacker", null)
	var dfn: MtMatchCard = b.get("defender", null)
	if atk == null or dfn == null:
		_battle_banner.visible = false
		_arrow.visible = false
		return
	var step := String(engine.battle.get("step", "resolve"))
	var d_power := engine.card_power(dfn) + int(engine.battle.get("counter_bonus", 0))
	_battle_banner.text = "%s: %s (%d) → %s (%d)" % [
		step.capitalize(), atk.card_name(), engine.card_power(atk),
		dfn.card_name(), d_power]
	_battle_banner.visible = true
	var wa := _widget_for(atk.uid)
	var wd := _widget_for(dfn.uid)
	if wa == null or wd == null:
		_arrow.visible = false
		return
	var center_a: Vector2 = wa.get_global_transform() * (wa.size / 2.0)
	var center_d: Vector2 = wd.get_global_transform() * (wd.size / 2.0)
	_arrow.points = PackedVector2Array([
		_arrow.to_local(center_a),
		_arrow.to_local(center_d)
	])
	_arrow.visible = true

func _show_resolve_banner(_msg: String, _color: Color) -> void:
	if _resolve_banner != null:
		_resolve_banner.visible = false
		_resolve_banner.text = ""

func _on_back() -> void:
	var parent := get_parent()
	if parent and parent.has_method("switch_scene"):
		parent.switch_scene(BACK_SCENE)
	else:
		queue_free()

func _on_surrender() -> void:
	if engine == null or engine.is_over():
		return
	engine.over = true
	engine.winner = 1
	engine.win_reason = "Surrendered"
	_append_log("[color=salmon]You surrendered.[/color]")
	_dirty = true

# --- Context Menu & Simulator Actions ---

func _append_log(msg: String) -> void:
	if engine != null:
		engine.log_lines.append(msg)
		_dirty = true

func _cancel_rule_call() -> bool:
	if engine == null or engine.is_over():
		return false
	if engine.pending_choice != null and int(engine.pending_choice.get("player", -1)) == human_seat:
		var ptype := String(engine.pending_choice.get("type", ""))
		if ptype == "mulligan" or ptype == "life_trigger":
			return false
		_apply({"type": engine.ACTION_CANCEL_CHOICE})
		return true
	if engine.in_battle() and int(engine.battle.get("defender_owner", -1)) == human_seat:
		_apply({"type": engine.ACTION_CANCEL_CHOICE})
		return true
	return false

func _pending_uids() -> Array:
	if engine == null or engine.pending_choice == null:
		return []
	return engine.pending_choice.get("candidates", [])

func _on_card_context_requested(card_widget: MtMatCard, global_pos: Vector2) -> void:
	if engine == null or engine.is_over():
		return
	var card := _find_any_card(card_widget.uid)
	if card == null:
		return
	_ctx_target_card = card
	_ctx_target_role = card_widget.role
	_ctx_zone = ""
	_context_menu.clear()

	var pc = engine.pending_choice
	if pc != null and int(pc.get("player", -1)) == human_seat:
		var ptype := String(pc.get("type", ""))
		if ptype != "mulligan" and ptype != "life_trigger":
			var cands: Array = pc.get("candidates", [])
			if ptype == "pick" or ptype == "look_order":
				if cands.has(card.uid) or cands.has(String(card.uid)):
					_context_menu.add_item("Choose this card", CtxAction.CHOOSE_THIS)
			elif ptype == "give_don" or ptype == "replace_ko" or ptype == "opp_may":
				if ptype == "give_don" and (card_widget.role == "my_field" or card_widget.role == "my_leader"):
					_context_menu.add_item("Give DON!! here", CtxAction.CHOOSE_THIS)
				elif ptype != "give_don":
					_context_menu.add_item("Take this option", CtxAction.CHOOSE_THIS)
			_context_menu.add_item("Skip / continue without this", CtxAction.SKIP_OPTION)
			if _context_menu.item_count > 0:
				_context_menu.position = Vector2i(global_pos)
				_context_menu.popup()
			return

	if engine.in_battle() and int(engine.battle.get("defender_owner", -1)) == human_seat:
		var step := String(engine.battle.get("step", ""))
		if step == "block" and (card_widget.role == "my_field"):
			_context_menu.add_item("Declare as Blocker", CtxAction.BLOCK_THIS)
		elif step == "counter" or step == "counter2":
			if card_widget.role == "hand":
				_context_menu.add_item("Play as Counter", CtxAction.COUNTER_THIS)
		_context_menu.add_item("Pass this window", CtxAction.SKIP_OPTION)
		if _context_menu.item_count > 0:
			_context_menu.position = Vector2i(global_pos)
			_context_menu.popup()
		return

	if card_widget.role == "hand":
		var play_label := "Play / Cast Event" if card.is_event() else "Play to Field"
		_context_menu.add_item(play_label, CtxAction.HAND_PLAY)
	elif card_widget.role == "opp_leader" or card_widget.role == "opp_field":
		if not attacker_uid.is_empty() and engine.phase == MtMatch.Phase.MAIN and not engine.in_battle():
			_context_menu.add_item("Attack this card", CtxAction.FIELD_ATTACK_TARGET)
	elif card_widget.role == "my_field" or card_widget.role == "my_leader":
		if not card.rested and engine.phase == MtMatch.Phase.MAIN and not engine.in_battle():
			_context_menu.add_item("Attack Leader", CtxAction.FIELD_ATTACK_LEADER)
			var foe = _remote_ps()
			var has_char_targets := false
			for c in foe.field:
				if c.rested or engine._can_attack_active(card):
					has_char_targets = true
					break
			if has_char_targets:
				_context_menu.add_item("Attack Character", CtxAction.FIELD_ATTACK_TARGET)
		var me = _local_ps()
		if me.get_available_don() > 0:
			_context_menu.add_item("Give 1 Active DON!!", CtxAction.FIELD_ATTACH_DON)
		var fx: Dictionary = engine.fx(card)
		if not fx.get("activate_main", []).is_empty():
			_context_menu.add_item("Activate [Activate: Main]", CtxAction.FIELD_ACTIVATE)

	if _context_menu.item_count > 0:
		_context_menu.position = Vector2i(global_pos)
		_context_menu.popup()

func _on_zone_clicked(player_index: int, zone: String, button_index: int, global_pos: Vector2) -> void:
	if engine == null or engine.is_over() or player_index != human_seat:
		return

	if button_index == MOUSE_BUTTON_RIGHT:
		_context_menu.clear()
		var pc = engine.pending_choice
		if pc != null and int(pc.get("player", -1)) == human_seat and String(pc.get("type", "")) == "modal":
			var options: Array = pc.get("options", [])
			for oi in range(mini(options.size(), 4)):
				_context_menu.add_item("Choose option %d" % (oi + 1), CtxAction.CHOOSE_OPT0 + oi)
			_context_menu.add_item("Skip / continue with neither", CtxAction.SKIP_OPTION)
			_context_menu.position = Vector2i(global_pos)
			_context_menu.popup()
			return
		if _cancel_rule_call():
			return

	if button_index == MOUSE_BUTTON_LEFT:
		return

	if button_index != MOUSE_BUTTON_RIGHT:
		return
	_ctx_target_card = null
	_ctx_target_role = ""
	_ctx_zone = zone
	_ctx_player_idx = player_index
	_context_menu.clear()

	match zone:
		"trash":
			_context_menu.add_item("View Trash in Combat Log", CtxAction.TRASH_VIEW)

	if _context_menu.item_count > 0:
		_context_menu.position = Vector2i(global_pos)
		_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	if engine == null:
		return
	var me = _local_ps()
	match id:
		CtxAction.HAND_PLAY:
			if _ctx_target_card != null:
				selected_uid = _ctx_target_card.uid
				_on_play()
		CtxAction.HAND_TRASH:
			if _ctx_target_card != null:
				engine._move_to_trash(me, _ctx_target_card)
				_append_log("Trashed %s from hand." % _ctx_target_card.card_name())
		CtxAction.HAND_ADD_LIFE:
			if _ctx_target_card != null:
				me.hand.erase(_ctx_target_card)
				_ctx_target_card.zone = MtMatchCard.ZONE_LIFE
				me.life.append(_ctx_target_card)
				_append_log("Added %s to Life face-down." % _ctx_target_card.card_name())
		CtxAction.FIELD_REST_STAND:
			if _ctx_target_card != null:
				_ctx_target_card.rested = not _ctx_target_card.rested
				_append_log("%s %s." % [_ctx_target_card.card_name(), "rested" if _ctx_target_card.rested else "stood up"])
		CtxAction.FIELD_ATTACH_DON:
			if _ctx_target_card != null:
				_apply({"type": engine.ACTION_ATTACH_DON, "card_uid": _ctx_target_card.uid})
		CtxAction.FIELD_DETACH_DON:
			if _ctx_target_card != null and _ctx_target_card.attached_don.size() > 0:
				_ctx_target_card.attached_don.pop_back()
				_append_log("Detached 1 DON from %s." % _ctx_target_card.card_name())
		CtxAction.FIELD_ATTACK_LEADER:
			if _ctx_target_card != null:
				var foe = _remote_ps()
				if foe.leader != null:
					_attack_with_animation(_ctx_target_card.uid, foe.leader.uid)
		CtxAction.FIELD_ATTACK_TARGET:
			if _ctx_target_card != null:
				if _ctx_target_role == "opp_field" or _ctx_target_role == "opp_leader":
					if not attacker_uid.is_empty():
						_attack_with_animation(attacker_uid, _ctx_target_card.uid)
				else:
					var foe = _remote_ps()
					var valid: Array = []
					for c in foe.field:
						if c.rested or engine._can_attack_active(_ctx_target_card):
							valid.append(c)
					if not valid.is_empty():
						_show_attack_target_picker(_ctx_target_card.uid, valid)
					elif foe.leader != null:
						_attack_with_animation(_ctx_target_card.uid, foe.leader.uid)
		CtxAction.CHOOSE_THIS:
			if _ctx_target_card != null:
				var pc = engine.pending_choice
				if pc != null:
					var ptype := String(pc.get("type", ""))
					if ptype == "give_don":
						_apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": int(pc.get("max", 1)),
							"target_uid": _ctx_target_card.uid})
					elif ptype == "replace_ko" or ptype == "opp_may":
						_apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 1})
					elif ptype == "look_order":
						var uid := _ctx_target_card.uid
						if _look_build.has(uid):
							_look_build.erase(uid)
						else:
							_look_build.append(uid)
						_dirty = true
					else:
						_apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": 1,
							"target_uid": _ctx_target_card.uid, "uids": [_ctx_target_card.uid]})
		CtxAction.COUNTER_THIS:
			if _ctx_target_card != null:
				_apply({"type": engine.ACTION_COUNTER, "card_uid": _ctx_target_card.uid})
		CtxAction.BLOCK_THIS:
			if _ctx_target_card != null:
				_apply({"type": engine.ACTION_BLOCK, "blocker": _ctx_target_card.uid})
		CtxAction.SKIP_OPTION:
			_cancel_rule_call()
		CtxAction.CHOOSE_OPT0, CtxAction.CHOOSE_OPT1, CtxAction.CHOOSE_OPT2, CtxAction.CHOOSE_OPT3:
			_apply({"type": engine.ACTION_CHOOSE_EFFECT, "n": id - CtxAction.CHOOSE_OPT0})
		CtxAction.FIELD_ACTIVATE:
			if _ctx_target_card != null:
				selected_uid = _ctx_target_card.uid
				_on_activate()
		CtxAction.FIELD_RETURN_HAND:
			if _ctx_target_card != null:
				var owner_ps = engine.players[_ctx_target_card.owner]
				engine._finalize_move(_ctx_target_card)
				_ctx_target_card.zone = MtMatchCard.ZONE_HAND
				_ctx_target_card.rested = false
				owner_ps.hand.append(_ctx_target_card)
				_append_log("Returned %s to hand." % _ctx_target_card.card_name())
		CtxAction.FIELD_TRASH:
			if _ctx_target_card != null:
				var owner_ps = engine.players[_ctx_target_card.owner]
				engine._move_to_trash(owner_ps, _ctx_target_card)
				_append_log("Sent %s to trash." % _ctx_target_card.card_name())
		CtxAction.DECK_DRAW_1:
			var c = engine.draw_card(me)
			if c != null:
				_append_log("Drew 1 card: %s." % c.card_name())
		CtxAction.DECK_DRAW_2:
			var _c1 = engine.draw_card(me)
			var _c2 = engine.draw_card(me)
			_append_log("Drew 2 cards.")
		CtxAction.DECK_MILL:
			if not me.deck.is_empty():
				var c = me.deck.pop_front()
				engine._move_to_trash(me, c)
				_append_log("Milled %s to trash." % c.card_name())
		CtxAction.DECK_LOOK_TOP:
			var top_names: Array = []
			for i in range(mini(3, me.deck.size())):
				top_names.append((me.deck[i] as MtMatchCard).card_name())
			_append_log("Top %d cards: %s" % [top_names.size(), ", ".join(top_names) if not top_names.is_empty() else "None"])
		CtxAction.DECK_SHUFFLE:
			me.deck.shuffle()
			_append_log("Deck shuffled.")
		CtxAction.DON_GIVE_ACTIVE:
			if me.don_in_deck > 0:
				me.don_in_deck -= 1
				me.don_active += 1
				_append_log("Gave 1 active DON!! (Total: %d)" % me.don_active)
		CtxAction.DON_GIVE_2_ACTIVE:
			var to_add = mini(2, me.don_in_deck)
			me.don_in_deck -= to_add
			me.don_active += to_add
			_append_log("Gave %d active DON!! (Total: %d)" % [to_add, me.don_active])
		CtxAction.DON_GIVE_RESTED:
			if me.don_in_deck > 0:
				me.don_in_deck -= 1
				me.don_active += 1
				me.don_rested += 1
				_append_log("Gave 1 rested DON!! (Total: %d, Rested: %d)" % [me.don_active, me.don_rested])
		CtxAction.LIFE_TAKE_TO_HAND:
			if not me.life.is_empty():
				var c: MtMatchCard = me.life.pop_back()
				c.zone = MtMatchCard.ZONE_HAND
				me.hand.append(c)
				_append_log("Took life card to hand: %s" % c.card_name())
		CtxAction.LIFE_TRASH:
			if not me.life.is_empty():
				var c: MtMatchCard = me.life.pop_back()
				engine._move_to_trash(me, c)
				_append_log("Sent life card %s to trash." % c.card_name())
		CtxAction.LIFE_ADD_FROM_DECK:
			if not me.deck.is_empty():
				var c: MtMatchCard = me.deck.pop_front()
				c.zone = MtMatchCard.ZONE_LIFE
				me.life.append(c)
				_append_log("Added top of deck to Life (face-down).")
		CtxAction.TRASH_RECOVER_TOP:
			if not me.trash.is_empty():
				var c: MtMatchCard = me.trash.pop_back()
				c.zone = MtMatchCard.ZONE_HAND
				c.rested = false
				me.hand.append(c)
				_append_log("Recovered %s from trash to hand." % c.card_name())
		CtxAction.TRASH_VIEW:
			var names: Array = []
			for c in me.trash:
				names.append((c as MtMatchCard).card_name())
			_append_log("Trash (%d cards): %s" % [names.size(), ", ".join(names) if not names.is_empty() else "Empty"])

	_dirty = true
