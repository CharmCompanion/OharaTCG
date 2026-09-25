# res://scripts/ui/PreDuel.gd
# Pre-duel, YGOPro Percy style: lock decks, both sides throw rock-paper-scissors,
# the winner chooses to go first or second, then the board opens.
# Human always plays P0; P1 is AI. Code-built Control, no .tscn.

extends Control
class_name MtPreDuel

const BACK_SCENE := "res://scenes/ui/PostLogin.tscn"
const _HANDS := ["Rock", "Paper", "Scissors"]

var _lv: OptionButton
var _lv_you: OptionButton
var _deck_a: OptionButton
var _deck_b: OptionButton
var _fmt: OptionButton
var _sum_a: Label
var _sum_b: Label
var _decks: Array = []
var _fmts: Array = []
var _throw_btns: Array = []
var _choice_row: HBoxContainer
var _start: Button
var _again: Button
var _join_ip: LineEdit
var _rooms_box: VBoxContainer
var _room_kind: OptionButton
var _room_access: OptionButton
var _invite_code: LineEdit
var _tour_box: VBoxContainer
var _tour_minutes: LineEdit
var _tour_best: OptionButton
var _tour_format: OptionButton
var _tour_rules: LineEdit
var _tour_code: Label
var _tour_entrant: LineEdit
var _tour_winner: LineEdit
var _tour_bracket: Label
var _invite_name: LineEdit
var _room_sig := ""
var _rps_label: Label
var _status: Label
var _phase := "throw"
var _you_throw := ""
var _opp_throw := ""
var _first_player := -1
var _my_seat := 0
var _lan := false
var chat_ui: Control = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	_build()
	load_chat_ui()

func load_chat_ui() -> void:
	if OS.get_name() == "Android" or chat_ui:
		return
	var chat_scene = load("res://scenes/ui/ChatUI.tscn")
	if chat_scene is PackedScene:
		chat_ui = chat_scene.instantiate()
		chat_ui.mouse_filter = Control.MOUSE_FILTER_PASS
		chat_ui.z_index = 100
		add_child(chat_ui)

func _cdb() -> Node:
	return get_node_or_null("/root/CardDatabase")

func _deck_choices() -> Array:
	var out := [{"label": "ST01 Starter", "spec": {"kind": "st01"}}]
	if FileAccess.file_exists("res://data/meta/decks.json"):
		var decks = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta/decks.json"))
		if decks is Array:
			for i in range((decks as Array).size()):
				var d: Dictionary = (decks as Array)[i]
				out.append({"label": "Meta: %s (%s)" % [String(d.get("leader", "?")), String(d.get("player", "?"))],
					"spec": {"kind": "meta", "index": i}})
	for path in MtDeckLoader.available_deck_paths():
		out.append({"label": "File: %s" % path.get_file(), "spec": {"kind": "file", "path": path}})
	return out

func _fmt_choices() -> Array:
	var out := [{"label": "Open / Casual", "fmt": {}}]
	for f in MtDeckLoader.list_formats():
		var fd: Dictionary = f
		if String(fd.get("id", "")) == "open":
			continue
		out.append({"label": "%s" % String(fd.get("id", "?")), "fmt": fd})
	return out

func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(460, 0)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.offset_left = -250
	box.offset_top = -420
	box.offset_right = 250
	box.offset_bottom = 520
	add_child(box)
	var title := Label.new()
	title.text = "PRE-DUEL SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_decks = _deck_choices()
	_fmts = _fmt_choices()
	_deck_a = _row_combo(box, "Your deck (P0):", _labels(_decks))
	_sum_a = _summary_label(box)
	_lv_you = _row_combo(box, "Your AI (watch):", ["Easy", "Medium", "Pro"])
	_lv = _row_combo(box, "Opponent AI (P1):", ["Easy", "Medium", "Pro"])
	(_lv as OptionButton).select(1)
	_deck_b = _row_combo(box, "Opponent deck:", _labels(_decks))
	_sum_b = _summary_label(box)
	_fmt = _row_combo(box, "Format:", _labels(_fmts))
	var rule := Label.new()
	rule.text = "Both sides throw. The winner chooses who goes first."
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rule)
	var throw_row := HBoxContainer.new()
	throw_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(throw_row)
	for t in _HANDS:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(110, 40)
		b.pressed.connect(_on_throw.bind(t))
		throw_row.add_child(b)
		_throw_btns.append(b)
	_rps_label = Label.new()
	_rps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_rps_label)
	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_choice_row)
	var go_first := Button.new()
	go_first.text = "Go first"
	go_first.custom_minimum_size = Vector2(140, 40)
	go_first.pressed.connect(_choose_seat.bind(true))
	_choice_row.add_child(go_first)
	var go_second := Button.new()
	go_second.text = "Go second"
	go_second.custom_minimum_size = Vector2(140, 40)
	go_second.pressed.connect(_choose_seat.bind(false))
	_choice_row.add_child(go_second)
	_start = Button.new()
	_start.text = "Start duel"
	_start.custom_minimum_size = Vector2(0, 48)
	_start.add_theme_font_size_override("font_size", 22)
	_start.pressed.connect(_on_start)
	box.add_child(_start)
	var watch_b := Button.new()
	watch_b.text = "Watch AI vs AI"
	watch_b.tooltip_text = "P0 plays Your AI. P1 plays Opponent AI. Each keeps the deck selected above."
	watch_b.pressed.connect(_on_watch)
	box.add_child(watch_b)
	_again = Button.new()
	_again.text = "Throw again"
	_again.pressed.connect(_reset_toss)
	box.add_child(_again)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var back := Button.new()
	back.text = "< Back"
	back.pressed.connect(_on_back)
	box.add_child(back)
	var net_row := HBoxContainer.new()
	net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(net_row)
	var host_b := Button.new()
	host_b.text = "Host LAN"
	host_b.pressed.connect(_on_host)
	net_row.add_child(host_b)
	var join_b := Button.new()
	join_b.text = "Join"
	join_b.pressed.connect(_on_join)
	net_row.add_child(join_b)
	var mate_join := Button.new()
	mate_join.text = "Join as partner"
	mate_join.pressed.connect(_on_join_mate)
	net_row.add_child(mate_join)
	_join_ip = LineEdit.new()
	_join_ip.placeholder_text = "127.0.0.1"
	_join_ip.custom_minimum_size = Vector2(140, 0)
	net_row.add_child(_join_ip)
	var policy_row := HBoxContainer.new()
	policy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(policy_row)
	_room_kind = OptionButton.new()
	_room_kind.add_item("Public", 0)
	_room_kind.add_item("Private", 1)
	_room_kind.add_item("Tournament", 2)
	_room_kind.add_item("Tag", 3)
	_room_kind.item_selected.connect(_on_room_kind)
	policy_row.add_child(_room_kind)
	_room_access = OptionButton.new()
	_room_access.add_item("Friends", 0)
	_room_access.add_item("Crew", 1)
	_room_access.add_item("No one", 2)
	_room_access.visible = false
	policy_row.add_child(_room_access)
	_invite_code = LineEdit.new()
	_invite_code.placeholder_text = "Invite code"
	_invite_code.custom_minimum_size = Vector2(110, 0)
	policy_row.add_child(_invite_code)
	_tour_box = VBoxContainer.new()
	_tour_box.visible = false
	box.add_child(_tour_box)
	var tour_row := HBoxContainer.new()
	tour_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tour_box.add_child(tour_row)
	_tour_minutes = LineEdit.new()
	_tour_minutes.placeholder_text = "Minutes"
	_tour_minutes.text = "50"
	_tour_minutes.custom_minimum_size = Vector2(70, 0)
	tour_row.add_child(_tour_minutes)
	_tour_best = OptionButton.new()
	_tour_best.add_item("Best of 1", 1)
	_tour_best.add_item("Best of 3", 3)
	_tour_best.add_item("Best of 5", 5)
	_tour_best.select(1)
	tour_row.add_child(_tour_best)
	_tour_format = OptionButton.new()
	_tour_format.add_item("Swiss")
	_tour_format.add_item("Round robin")
	_tour_format.add_item("Single elimination")
	_tour_format.add_item("Double elimination")
	_tour_format.add_item("Swiss then top 4")
	tour_row.add_child(_tour_format)
	_tour_rules = LineEdit.new()
	_tour_rules.placeholder_text = "Rules"
	_tour_rules.custom_minimum_size = Vector2(180, 0)
	tour_row.add_child(_tour_rules)
	var save_tour := Button.new()
	save_tour.text = "Save tournament"
	save_tour.pressed.connect(_on_save_tournament)
	_tour_box.add_child(save_tour)
	_tour_code = Label.new()
	_tour_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tour_code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tour_box.add_child(_tour_code)
	var enter_row := HBoxContainer.new()
	enter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tour_box.add_child(enter_row)
	_tour_entrant = LineEdit.new()
	_tour_entrant.placeholder_text = "Entrant"
	_tour_entrant.custom_minimum_size = Vector2(120, 0)
	enter_row.add_child(_tour_entrant)
	var add_ent := Button.new()
	add_ent.text = "Add"
	add_ent.pressed.connect(_on_add_entrant)
	enter_row.add_child(add_ent)
	var cin := Button.new()
	cin.text = "Check in"
	cin.pressed.connect(_on_check_in)
	enter_row.add_child(cin)
	var gen := Button.new()
	gen.text = "Generate bracket"
	gen.pressed.connect(_on_generate_bracket)
	enter_row.add_child(gen)
	var next_r := Button.new()
	next_r.text = "Next Swiss round"
	next_r.pressed.connect(_on_next_swiss)
	enter_row.add_child(next_r)
	var win_row := HBoxContainer.new()
	win_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tour_box.add_child(win_row)
	_tour_winner = LineEdit.new()
	_tour_winner.placeholder_text = "Winner"
	_tour_winner.custom_minimum_size = Vector2(120, 0)
	win_row.add_child(_tour_winner)
	var rec := Button.new()
	rec.text = "Record win"
	rec.pressed.connect(_on_record_win)
	win_row.add_child(rec)
	_tour_bracket = Label.new()
	_tour_bracket.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tour_bracket.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tour_box.add_child(_tour_bracket)
	var invite_row := HBoxContainer.new()
	invite_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(invite_row)
	_invite_name = LineEdit.new()
	_invite_name.placeholder_text = "Player name"
	_invite_name.custom_minimum_size = Vector2(140, 0)
	invite_row.add_child(_invite_name)
	var duel_inv := Button.new()
	duel_inv.text = "Duel invite"
	duel_inv.pressed.connect(_on_duel_invite)
	invite_row.add_child(duel_inv)
	var tour_inv := Button.new()
	tour_inv.text = "Tournament invite"
	tour_inv.pressed.connect(_on_tour_invite)
	invite_row.add_child(tour_inv)
	box.add_child(load("res://scripts/ui/InviteBox.gd").new())
	if OS.get_name() != "Android":
		var lobby_row := HBoxContainer.new()
		lobby_row.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(lobby_row)
		var server_lab := Label.new()
		var accounts := get_node_or_null("/root/Accounts")
		var host := ""
		if accounts != null:
			host = String(accounts.host())
		server_lab.text = "Server: %s" % host if host != "" else "Server address is not set."
		lobby_row.add_child(server_lab)
		var host_on := Button.new()
		host_on.text = "Host online"
		host_on.pressed.connect(_on_host_online)
		lobby_row.add_child(host_on)
		var refresh_b := Button.new()
		refresh_b.text = "Refresh"
		refresh_b.pressed.connect(_on_refresh_rooms)
		lobby_row.add_child(refresh_b)
		var rooms_title := Label.new()
		rooms_title.text = "Rooms"
		rooms_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(rooms_title)
		_rooms_box = VBoxContainer.new()
		box.add_child(_rooms_box)
	_deck_a.item_selected.connect(_on_setup_changed)
	_deck_b.item_selected.connect(_on_setup_changed)
	_fmt.item_selected.connect(_on_setup_changed)
	_reset_toss()
	var net := get_node_or_null("/root/Lan")
	if net != null:
		if not net.joined.is_connected(_lan_joined):
			net.joined.connect(_lan_joined)
			net.peer_ready.connect(_lan_peer)
			net.throws_revealed.connect(_lan_revealed)
			net.match_begin.connect(_lan_start)
			net.spectate_ready.connect(_on_spectate)
			net.room_opened.connect(_on_room_opened)
			net.room_full.connect(_on_room_full)
			net.room_denied.connect(_on_room_denied)
			net.rooms_updated.connect(_rebuild_rooms)
			net.seated.connect(_on_seated)
			net.mates_changed.connect(_on_mates)
		net.listen_rooms()
		_rebuild_rooms()
	var social := get_node_or_null("/root/Social")
	if social != null and not social.social_changed.is_connected(_on_social):
		social.social_changed.connect(_on_social)
	_on_social()

func _labels(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(String((it as Dictionary).get("label", "?")))
	return out

func _summary_label(parent: Control) -> Label:
	var lab := Label.new()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_font_size_override("font_size", 13)
	parent.add_child(lab)
	return lab

func _row_combo(parent: Control, text: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lab := Label.new()
	lab.text = text
	lab.custom_minimum_size = Vector2(150, 0)
	row.add_child(lab)
	var cb := OptionButton.new()
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		cb.add_item(String(it))
	row.add_child(cb)
	return cb

static func rps_winner(a: String, b: String) -> int:
	# -1 tie, 0 if a wins, 1 if b wins.
	if a == b:
		return -1
	if (a == "Rock" and b == "Scissors") or (a == "Scissors" and b == "Paper") or (a == "Paper" and b == "Rock"):
		return 0
	return 1

func _on_setup_changed(_idx: int) -> void:
	_reset_toss()

func _reset_toss() -> void:
	_phase = "throw"
	_you_throw = ""
	_opp_throw = ""
	_first_player = -1
	_rps_label.text = "Pick rock, paper, or scissors."
	_choice_row.visible = false
	_start.visible = false
	_again.visible = false
	_status.text = ""
	for b in _throw_btns:
		(b as Button).disabled = false
		(b as Button).modulate = Color.WHITE
	_refresh_summaries()

func _set_throws_enabled(on: bool) -> void:
	for b in _throw_btns:
		(b as Button).disabled = not on

func _paint_throw(you: String) -> void:
	for b in _throw_btns:
		var btn := b as Button
		btn.modulate = Color(1.0, 0.85, 0.35) if btn.text == you else Color(0.55, 0.55, 0.55)

func _on_throw(t: String) -> void:
	if _phase != "throw":
		return
	if _lan:
		var err := _deck_error()
		if err != "":
			_status.text = err
			return
		var net := get_node_or_null("/root/Lan")
		if net == null:
			return
		_you_throw = t
		_paint_throw(t)
		_set_throws_enabled(false)
		_rps_label.text = "You: %s\nWaiting for the other throw." % t
		net.send_throw(t)
		return
	play_throw(t, _HANDS[randi() % 3])

func play_throw(you: String, opp: String) -> void:
	if _phase != "throw":
		return
	var err := _deck_error()
	if err != "":
		_status.text = err
		return
	_status.text = ""
	_you_throw = you
	_opp_throw = opp
	_paint_throw(you)
	var winner := rps_winner(you, opp)
	if winner < 0:
		_rps_label.text = "You: %s    Opponent: %s\nTie. Throw again." % [you, opp]
		for b in _throw_btns:
			(b as Button).disabled = false
			(b as Button).modulate = Color.WHITE
		return
	_set_throws_enabled(false)
	_again.visible = true
	if winner == 0:
		_phase = "choose"
		_rps_label.text = "You: %s    Opponent: %s\nYou win the toss. Go first or second?" % [you, opp]
		_choice_row.visible = true
		return
	# Second seat draws and can attack on turn 1. A matchup report can
	# override that when it says this leader should go first.
	_phase = "ready"
	var human_name := _leader_name(_deck_a)
	var ai_name := _leader_name(_deck_b)
	var want_first := MtAiLevels.prefer_first(ai_name, human_name) == 1
	_first_player = 1 if want_first else 0
	_rps_label.text = "You: %s    Opponent: %s\nOpponent wins and chooses to go %s." % [
		you, opp, "first" if want_first else "second"]
	_start.visible = true

func _choose_seat(i_go_first: bool) -> void:
	if _phase != "choose":
		return
	var first := _my_seat if i_go_first else 1 - _my_seat
	if _lan:
		var net := get_node_or_null("/root/Lan")
		if net != null:
			_rps_label.text = "Starting the duel."
			net.send_first(first)
		return
	_first_player = first
	_launch()

func _on_start() -> void:
	if _phase != "ready" or _first_player < 0:
		return
	_launch()

func _leader_name(pick: OptionButton) -> String:
	if pick == null or pick.selected < 0 or pick.selected >= _decks.size():
		return ""
	var deck := _resolve_deck((_decks[pick.selected] as Dictionary).get("spec", {}))
	var leader: Dictionary = deck.get("leader", {})
	return String(leader.get("name", ""))

func _resolve_deck(spec: Dictionary) -> Dictionary:
	var cdb := _cdb()
	match String(spec.get("kind", "st01")):
		"meta":
			var idx := int(spec.get("index", 0))
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
			var starter := "res://data/decks/ST01-StrawHats.json"
			if FileAccess.file_exists(starter):
				return MtDeckLoader.load_deck_file(starter, cdb.get_card_data)
			var main_codes: Array = []
			for code in ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
					"ST01-007", "ST01-008", "ST01-009", "ST01-010"]:
				for _i in range(4):
					main_codes.append(code)
			for code in ["ST01-011", "ST01-012", "ST01-013", "ST01-014", "ST01-015", "ST01-016", "ST01-017"]:
				for _i in range(2):
					main_codes.append(code)
			return MtDeckLoader.build_from_lists("ST01-001", main_codes, cdb.get_card_data)

func _rules() -> Array:
	var fmt: Dictionary = {}
	if _fmt != null and _fmt.selected >= 0 and _fmt.selected < _fmts.size():
		fmt = (_fmts[_fmt.selected] as Dictionary).get("fmt", {})
	var ban := MtDeckLoader.load_banlist(String(fmt.get("banlist", "")))
	var blocks := MtDeckLoader.load_blocks() if not (fmt.get("allowed_blocks", []) as Array).is_empty() else {}
	return [fmt, ban, blocks]

func _deck_error() -> String:
	var cdb := _cdb()
	if cdb == null:
		return "Card data is still loading."
	var rules := _rules()
	var sides := [
		["Your deck", _resolve_deck((_decks[_deck_a.selected] as Dictionary).get("spec", {}))],
		["Opponent deck", _resolve_deck((_decks[_deck_b.selected] as Dictionary).get("spec", {}))],
	]
	for side in sides:
		var errs := MtDeckLoader.validate_deck(side[1], rules[1], rules[0], rules[2])
		if not errs.is_empty():
			return "%s: %s" % [side[0], "; ".join(errs)]
	return ""

func _refresh_summaries() -> void:
	if _sum_a == null or _deck_a == null:
		return
	var cdb := _cdb()
	if cdb == null:
		return
	var rules := _rules()
	_paint_summary(_sum_a, _resolve_deck((_decks[_deck_a.selected] as Dictionary).get("spec", {})), rules)
	_paint_summary(_sum_b, _resolve_deck((_decks[_deck_b.selected] as Dictionary).get("spec", {})), rules)

func _paint_summary(lab: Label, deck: Dictionary, rules: Array) -> void:
	var leader: Dictionary = deck.get("leader", {})
	var name := String(leader.get("name", leader.get("card_name", "No leader")))
	var color := String(leader.get("color", ""))
	var n := (deck.get("main", []) as Array).size()
	var errs := MtDeckLoader.validate_deck(deck, rules[1], rules[0], rules[2])
	if errs.is_empty():
		lab.text = "%s · %s · %d cards · Legal" % [name, color, n]
		lab.add_theme_color_override("font_color", Color(0.65, 0.9, 0.65))
	else:
		lab.text = "%s · %s · %d cards · %s" % [name, color, n, errs[0]]
		lab.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))

func _launch() -> void:
	if _first_player < 0:
		return
	var err := _deck_error()
	if err != "":
		_status.text = err
		return
	var deck_a := _resolve_deck((_decks[_deck_a.selected] as Dictionary).get("spec", {}))
	var deck_b := _resolve_deck((_decks[_deck_b.selected] as Dictionary).get("spec", {}))
	var won := rps_winner(_you_throw, _opp_throw) == 0
	var seat := "you go first." if _first_player == 0 else "you go second."
	var note := "Rock-paper-scissors: You %s, opponent %s. %s and %s" % [
		_you_throw, _opp_throw, "You win" if won else "Opponent wins", seat]
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var board = load("res://scripts/ui/TestBoard.gd").new()
		ui_manager.switch_scene_with_instance(board)
		board.start_custom_match(deck_a, deck_b, _first_player, (_lv as OptionButton).get_selected_id())
		board._append_log(note)

func _on_watch() -> void:
	var err := _deck_error()
	if err != "":
		_status.text = err
		return
	var deck_a := _resolve_deck((_decks[_deck_a.selected] as Dictionary).get("spec", {}))
	var deck_b := _resolve_deck((_decks[_deck_b.selected] as Dictionary).get("spec", {}))
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var board = load("res://scripts/ui/TestBoard.gd").new()
		ui_manager.switch_scene_with_instance(board)
		board.start_ai_duel(deck_a, deck_b, _lv_you.get_selected_id(), _lv.get_selected_id(), randi() % 2)

func _on_host() -> void:
	var err := _deck_error()
	if err != "":
		_status.text = err
		return
	if not _apply_room_policy():
		return
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return
	var code: int = net.host_game()
	if code != OK:
		_status.text = "Could not host (%d)." % code
		return
	_lan = true
	_my_seat = 0
	net.local_deck = _code_deck(_decks[_deck_a.selected])
	_set_throws_enabled(false)
	_status.text = "Hosting on port 7777. Waiting for an opponent%s." % (" and both partners" if _is_tag() else "")

func _on_host_online() -> void:
	var err := _deck_error()
	if err != "":
		_status.text = err
		return
	var net := get_node_or_null("/root/Lan")
	var accounts := get_node_or_null("/root/Accounts")
	if net == null or accounts == null:
		return
	if not _apply_room_policy():
		return
	var host := String(accounts.host())
	if host == "":
		_status.text = "The server address is not set."
		return
	var code: int = net.reach_lobby(String(accounts.dial()), true)
	if code != OK:
		_status.text = "Could not reach the server (%d)." % code
		return
	_status.text = "Opening a room on %s." % host

func _on_refresh_rooms() -> void:
	var net := get_node_or_null("/root/Lan")
	var accounts := get_node_or_null("/root/Accounts")
	if net == null or accounts == null:
		return
	net.listen_rooms()
	var host := String(accounts.host())
	if host == "":
		_status.text = "The server address is not set."
		_rebuild_rooms()
		return
	var code: int = net.reach_lobby(String(accounts.dial()), false)
	if code != OK:
		_status.text = "Could not reach the server (%d)." % code
		return
	_status.text = "Asking %s for rooms." % host

func _on_room_opened() -> void:
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return
	_lan = true
	_my_seat = 0
	net.local_deck = _code_deck(_decks[_deck_a.selected])
	_set_throws_enabled(false)
	_status.text = "Room is open. Waiting for an opponent%s." % (" and both partners" if _is_tag() else "")

func _on_room_full() -> void:
	_status.text = "That room already has two players."

func _on_room_denied(reason: String) -> void:
	_lan = false
	_status.text = reason

func _is_tag() -> bool:
	return _room_kind != null and _room_kind.selected == 3

func _on_seated(seat: int) -> void:
	_lan = true
	_my_seat = seat
	_set_throws_enabled(false)
	_status.text = "You are the partner on side %d." % (seat + 1)

func _on_mates(count: int) -> void:
	if _phase == "throw":
		return
	_status.text = "Tag partners %d/2." % count

func _on_check_in() -> void:
	var social := get_node_or_null("/root/Social")
	if social == null:
		return
	var who := _tour_entrant.text.strip_edges() if _tour_entrant != null else ""
	if who == "":
		who = ProfileManager.username
	social.check_in(who)
	if _tour_entrant != null:
		_tour_entrant.text = ""

func _on_room_kind(_idx: int) -> void:
	var private_room := _room_kind != null and _room_kind.selected == 1
	var tourney := _room_kind != null and _room_kind.selected == 2
	if _room_access != null:
		_room_access.visible = private_room
	if _tour_box != null:
		_tour_box.visible = tourney

func _format_key() -> String:
	var keys := ["swiss", "round_robin", "single", "double", "swiss_cut"]
	if _tour_format == null:
		return "swiss"
	return keys[clampi(_tour_format.selected, 0, keys.size() - 1)]

func _on_social() -> void:
	var social := get_node_or_null("/root/Social")
	if social == null:
		return
	if _tour_bracket != null:
		_tour_bracket.text = social.bracket_text()
	if String(social.notice) == "":
		return
	if _invite_code != null and String(social.tournament.get("code", "")) != "":
		_invite_code.text = String(social.tournament.get("code", ""))
	_status.text = String(social.notice)
	social.notice = ""

func _on_add_entrant() -> void:
	var social := get_node_or_null("/root/Social")
	if social != null and _tour_entrant != null:
		social.add_entrant(_tour_entrant.text)
		_tour_entrant.text = ""

func _on_generate_bracket() -> void:
	var social := get_node_or_null("/root/Social")
	if social == null:
		return
	if social.generate_bracket().is_empty():
		_status.text = "Add at least one other entrant, then generate."

func _on_next_swiss() -> void:
	var social := get_node_or_null("/root/Social")
	if social != null:
		social.next_swiss_round()

func _on_record_win() -> void:
	var social := get_node_or_null("/root/Social")
	if social != null and _tour_winner != null:
		social.record_win(_tour_winner.text)
		_tour_winner.text = ""

func _on_duel_invite() -> void:
	var social := get_node_or_null("/root/Social")
	if social != null and _invite_name != null:
		social.invite_duel(_invite_name.text)

func _on_tour_invite() -> void:
	var social := get_node_or_null("/root/Social")
	if social == null or _invite_name == null:
		return
	if String(social.tournament.get("code", "")) == "":
		_status.text = "Save the tournament first. That creates the invite code."
		return
	social.invite_tournament(_invite_name.text)

func _on_save_tournament() -> void:
	var social := get_node_or_null("/root/Social")
	if social == null or _tour_minutes == null:
		return
	var code: String = social.save_tournament(int(_tour_minutes.text), _tour_best.get_selected_id(), _tour_rules.text, _format_key())
	DisplayServer.clipboard_set(code)
	if _tour_code != null:
		_tour_code.text = "Invite code %s (copied). %d min, best of %d, %s." % [code, int(social.tournament.get("minutes", 50)), int(social.tournament.get("best_of", 1)), social.tournament.get("format", "swiss")]
	_status.text = "Tournament saved. Share the code. It is not listed on the room."

func _apply_room_policy() -> bool:
	var social := get_node_or_null("/root/Social")
	if social == null or _room_kind == null:
		return true
	var kind := "public"
	if _room_kind.selected == 1:
		kind = "private"
	elif _room_kind.selected == 2:
		kind = "tournament"
	elif _room_kind.selected == 3:
		kind = "tag"
	var net := get_node_or_null("/root/Lan")
	if net != null:
		net.tag = kind == "tag"
	if kind == "tournament":
		if String(social.tournament.get("code", "")) == "":
			_status.text = "Save the tournament first. That creates the invite code."
			return false
		social.set_room("tournament", "invite")
		return true
	var access := "anyone"
	if kind == "private" and _room_access != null:
		access = ["friends", "crew", "none"][_room_access.selected]
	social.set_room(kind, access)
	return true

func _use_invite() -> void:
	var net := get_node_or_null("/root/Lan")
	if net != null and _invite_code != null:
		net.set_invite(_invite_code.text)

func _rebuild_rooms() -> void:
	if _rooms_box == null:
		return
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return
	var rooms: Array = net.lan_rooms()
	var bits: Array = []
	for row in rooms:
		var d: Dictionary = row
		bits.append("%s|%s|%s|%s|%s" % [d.get("kind", ""), d.get("ip", ""), d.get("id", 0), d.get("players", 0), d.get("live", false)])
	var sig := "|".join(bits)
	if sig == _room_sig and _rooms_box.get_child_count() > 0:
		return
	_room_sig = sig
	for c in _rooms_box.get_children():
		c.queue_free()
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "No rooms yet. Host on this network, or refresh a lobby."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rooms_box.add_child(empty)
		return
	for row in rooms:
		var d: Dictionary = row
		var line := HBoxContainer.new()
		_rooms_box.add_child(line)
		var lab := Label.new()
		var where := "LAN" if String(d.get("kind", "")) == "lan" else "Lobby"
		var state := "in game" if bool(d.get("live", false)) else "waiting"
		var cap := 4 if String(d.get("mode", "")) == "tag" else 2
		lab.text = "%s · %s · %s · %d/%d · %s" % [d.get("name", "Room"), d.get("mode", "public"), where, int(d.get("players", 1)), cap, state]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(lab)
		var join_b := Button.new()
		join_b.text = "Join"
		join_b.pressed.connect(_join_room.bind(d, false, false))
		line.add_child(join_b)
		if String(d.get("mode", "")) == "tag":
			var mate_b := Button.new()
			mate_b.text = "Partner"
			mate_b.pressed.connect(_join_room.bind(d, false, true))
			line.add_child(mate_b)
		var watch_b := Button.new()
		watch_b.text = "Watch"
		watch_b.pressed.connect(_join_room.bind(d, true, false))
		line.add_child(watch_b)

func _join_room(row: Dictionary, as_watch: bool, as_mate: bool = false) -> void:
	var err := _deck_error()
	if err != "" and not as_watch and not as_mate:
		_status.text = err
		return
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return
	_use_invite()
	_lan = true
	_my_seat = 1
	_set_throws_enabled(false)
	if String(row.get("kind", "")) == "lan":
		var code: int = net.join_game(String(row.get("ip", "")), as_watch, int(row.get("port", 7777)), as_mate)
		if code != OK:
			_status.text = "Could not join (%d)." % code
			return
		_status.text = "Connecting as a partner." if as_mate else "Connecting..."
		return
	if int(row.get("id", 0)) == 0:
		net.hello_direct(as_watch, as_mate)
		_status.text = "Connecting as a partner." if as_mate else "Connecting..."
		return
	net.enter_room(int(row.get("id", 0)), as_watch, as_mate)
	_status.text = "Entering as a partner." if as_mate else "Entering the room."

func _on_spectate(deck_a: Dictionary, deck_b: Dictionary, first: int, seed_value: int, actions: Array) -> void:
	var cdb := _cdb()
	if cdb == null:
		return
	var full_a := MtDeckLoader.build_from_lists(String(deck_a.get("leader", "")), deck_a.get("main", []), cdb.get_card_data)
	var full_b := MtDeckLoader.build_from_lists(String(deck_b.get("leader", "")), deck_b.get("main", []), cdb.get_card_data)
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var board = load("res://scripts/ui/TestBoard.gd").new()
		ui_manager.switch_scene_with_instance(board)
		board.start_spectate(full_a, full_b, first, seed_value, actions)

func _on_join_mate() -> void:
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return
	_use_invite()
	var ip := _join_ip.text.strip_edges() if _join_ip != null else ""
	var code: int = net.join_game(ip, false, -1, true)
	if code != OK:
		_status.text = "Could not join (%d)." % code
		return
	_lan = true
	_set_throws_enabled(false)
	_status.text = "Connecting as a partner."

func _on_join() -> void:
	var err := _deck_error()
	if err != "":
		_status.text = err
		return
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return
	_use_invite()
	var ip := _join_ip.text.strip_edges() if _join_ip != null else ""
	var code: int = net.join_game(ip)
	if code != OK:
		_status.text = "Could not join (%d)." % code
		return
	_lan = true
	_my_seat = 1
	_set_throws_enabled(false)
	_status.text = "Connecting..."

func _lan_joined() -> void:
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return
	net.send_deck(_code_deck(_decks[_deck_a.selected]), ProfileManager.username)

func _lan_peer() -> void:
	_phase = "throw"
	_set_throws_enabled(true)
	_status.text = ""
	_rps_label.text = "Opponent connected. Pick rock, paper, or scissors."

func _lan_revealed(you: String, opp: String, winner_seat: int) -> void:
	_you_throw = you
	_opp_throw = opp
	_paint_throw(you)
	if winner_seat < 0 or you == "" or you == opp:
		_phase = "throw"
		_set_throws_enabled(true)
		_choice_row.visible = false
		_rps_label.text = "You: %s    Opponent: %s\nTie. Throw again." % [you, opp]
		return
	_set_throws_enabled(false)
	if winner_seat == _my_seat:
		_phase = "choose"
		_choice_row.visible = true
		_rps_label.text = "You: %s    Opponent: %s\nYou win the toss. Go first or second?" % [you, opp]
		return
	_phase = "ready"
	_choice_row.visible = false
	_rps_label.text = "You: %s    Opponent: %s\nOpponent won the toss and is choosing." % [you, opp]

func _lan_start(deck_a: Dictionary, deck_b: Dictionary, first: int, seed_value: int) -> void:
	var cdb := _cdb()
	if cdb == null:
		return
	var full_a := MtDeckLoader.build_from_lists(String(deck_a.get("leader", "")), deck_a.get("main", []), cdb.get_card_data)
	var full_b := MtDeckLoader.build_from_lists(String(deck_b.get("leader", "")), deck_b.get("main", []), cdb.get_card_data)
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var board = load("res://scripts/ui/TestBoard.gd").new()
		ui_manager.switch_scene_with_instance(board)
		board.start_lan_match(full_a, full_b, first, _my_seat, seed_value)

func _code_deck(entry: Dictionary) -> Dictionary:
	var deck := _resolve_deck(entry.get("spec", {}))
	var main: Array = []
	for c in deck.get("main", []):
		if c is Dictionary:
			main.append(String((c as Dictionary).get("card_code", "")))
	var leader: Dictionary = deck.get("leader", {})
	return {"leader": String(leader.get("card_code", "")), "main": main}

func _on_back() -> void:
	var parent := get_parent()
	if parent and parent.has_method("switch_scene"):
		parent.switch_scene(BACK_SCENE)
	else:
		queue_free()
