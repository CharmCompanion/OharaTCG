# tests/placement_and_events_smoke.gd -- Test card placement, events in left-of-leader zone, click-to-place, and login button centering
extends SceneTree

var _frame := 0
var _board: MtTestBoard = null
var _deck: Dictionary = {}
var _cdb: Node = null

func _process(_delta: float) -> bool:
	_frame += 1
	if _cdb == null:
		_cdb = root.get_node_or_null("CardDatabase")
	if not _cdb or not _cdb.is_data_loaded:
		if _frame > 900:
			printerr("TEST FAIL: CardDatabase never loaded")
			quit(1)
			return true
		return false

	if _board == null:
		print("--- Running Card Placement & Event Zone Smoke Test ---")
		
		# 1. Verify Login Screen Button Centering
		var login_scene: PackedScene = load("res://scenes/ui/Login.tscn")
		assert(login_scene != null, "Login.tscn exists")
		var login_node = login_scene.instantiate()
		root.add_child(login_node)
		var btn_rows := login_node.find_children("", "HBoxContainer", true, false)
		assert(not btn_rows.is_empty(), "Button row found in Login")
		var row: HBoxContainer = btn_rows[0]
		assert(row.alignment == BoxContainer.ALIGNMENT_CENTER, "Login button row must be centered (ALIGNMENT_CENTER)")
		assert(login_node.find_child("Login") != null or row.get_child_count() >= 2, "Login buttons exist")
		login_node.queue_free()
		print("PASS: Login screen bottom buttons properly centered with separation")

		# Build deck with characters and events
		var main_codes: Array = []
		for code in ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
				"ST01-007", "ST01-008", "ST01-009", "ST01-010", "ST01-011", "ST01-012", "ST01-013",
				"ST01-015"]:
			for _i in range(3):
				main_codes.append(code)
		# Add Event cards (Diable Jambe ST01-016)
		for _i in range(11):
			main_codes.append("ST01-016")
		_deck = MtDeckLoader.build_from_lists("ST01-001", main_codes, _cdb.get_card_data)

		_board = MtTestBoard.new()
		_board.size = Vector2(1920, 1080)
		root.add_child(_board)
		_board.start_custom_match(_deck, _deck, 0, 1)
		return false

	# Wait for layout
	if _frame % 4 != 0:
		return false

	var tb_engine := _board.engine
	var tb_me = tb_engine.players[0]
	tb_engine.phase = tb_engine.Phase.MAIN
	tb_me.don_active = 10
	tb_me.don_rested = 0

	while tb_me.hand.filter(func(c): return c.is_character()).size() < 3 and not tb_me.deck.is_empty():
		for dc in tb_me.deck:
			if dc.is_character():
				tb_me.deck.erase(dc)
				tb_me.hand.append(dc)
				break

	if tb_me.hand.filter(func(c): return c.is_event()).is_empty():
		for dc in tb_me.deck:
			if dc.is_event():
				tb_me.deck.erase(dc)
				tb_me.hand.append(dc)
				break

	# 2. Verify mouse_filters on containers to ensure clicks fall through
	assert(_board._hand.mouse_filter == Control.MOUSE_FILTER_IGNORE, "_hand must be MOUSE_FILTER_IGNORE so cards receive clicks")
	assert(_board._opp_hand.mouse_filter == Control.MOUSE_FILTER_IGNORE, "_opp_hand must be MOUSE_FILTER_IGNORE")
	print("PASS: UI containers set to MOUSE_FILTER_IGNORE allowing clicks to pass through to field")

	# 3. Verify Event Zone exists next to Leader
	var event_zone: Control = _board._playfield.get_zone(0, "event")
	assert(event_zone != null, "Event zone must exist on PlayerMat")
	var lead_zone: Control = _board._playfield.get_zone(0, "leader")
	assert(lead_zone != null, "Leader zone exists")
	assert(event_zone.get_global_rect().position.x < lead_zone.get_global_rect().position.x, "Event zone must be located to the LEFT of Leader")
	print("PASS: Event zone verified in the empty space to the left of Leader")

	# 4. Test Drag-to-Place Character into specific slot 2
	var test_char_card: MtMatchCard = null
	for c in tb_me.hand:
		if c.is_character():
			test_char_card = c
			break
	assert(test_char_card != null, "Found character in hand")
	var slot2: Control = _board._playfield.char_slots(0)[2]
	var slot2_center := slot2.get_global_rect().get_center()
	var char_uid := test_char_card.uid
	_board._handle_card_drop(char_uid, "hand", slot2_center)
	assert(test_char_card in tb_me.field, "Character must be placed on field")
	assert(_board._card_slot_map.get(char_uid, -1) == 2, "Character must be assigned to slot 2")
	print("PASS: Drag-to-place Character directly into specific slot 2 succeeded")

	# 5. Test Drag-to-Place Character on field generally (auto-places in first empty slot 0)
	var test_char2: MtMatchCard = null
	for c in tb_me.hand:
		if c.is_character():
			test_char2 = c
			break
	assert(test_char2 != null, "Found 2nd character in hand")
	var char2_uid := test_char2.uid
	var field_center := _board._playfield._bot_mat.get_global_rect().get_center()
	_board._handle_card_drop(char2_uid, "hand", field_center)
	assert(test_char2 in tb_me.field, "2nd Character must be placed on field")
	assert(_board._card_slot_map.get(char2_uid, -1) == 0, "Character dropped generally must auto-place in first empty slot 0")
	print("PASS: Drag-to-place Character on field generally auto-placed in slot 0")

	# 6. Test Click-to-Place Character into slot 3
	var test_char3: MtMatchCard = null
	for c in tb_me.hand:
		if c.is_character():
			test_char3 = c
			break
	assert(test_char3 != null, "Found 3rd character in hand")
	var char3_uid := test_char3.uid
	_board.selected_uid = char3_uid
	# Simulate clicking slot 3
	_board._on_zone_clicked(0, "slot_3", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	assert(test_char3 in tb_me.field, "3rd Character must be placed via click-to-place")
	assert(_board._card_slot_map.get(char3_uid, -1) == 3, "3rd Character must be assigned to slot 3")
	print("PASS: Click-to-place Character (select in hand -> click slot 3) succeeded")

	# 7. Test Drag-to-Play Event Card into the space left of Leader
	var event_card_dict := {
		"name": "Diable Jambe", "card_code": "ST01-016", "type": "Event",
		"cost": 1, "power": 0, "counter": 0, "color": "Red",
		"effect": "[Main] Give leader unblockable."
	}
	var event_card: MtMatchCard = tb_engine._mk(event_card_dict, 0, MtMatchCard.ZONE_HAND)
	tb_me.hand.append(event_card)
	var ev_center := event_zone.get_global_rect().get_center()
	var init_trash_size: int = tb_me.trash.size()
	_board._handle_card_drop(event_card.uid, "hand", ev_center)
	assert(not (event_card in tb_me.hand), "Event card must be played from hand")
	assert(event_card in tb_me.trash, "Event card must resolve and move to trash")
	assert(tb_me.trash.size() == init_trash_size + 1, "Trash size increased by 1")
	print("PASS: Drag Event card into empty space left of Leader successfully activated and moved to trash")

	# 8. Test Click-to-Play Event Card (select in hand -> click event zone)
	var event_card2: MtMatchCard = tb_engine._mk(event_card_dict, 0, MtMatchCard.ZONE_HAND)
	tb_me.hand.append(event_card2)
	_board.selected_uid = event_card2.uid
	var init_trash2: int = tb_me.trash.size()
	_board._on_zone_clicked(0, "event", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	assert(not (event_card2 in tb_me.hand), "Event card 2 must be played from hand")
	assert(event_card2 in tb_me.trash, "Event card 2 must resolve to trash")
	assert(tb_me.trash.size() == init_trash2 + 1, "Trash size increased by 1")
	print("PASS: Click-to-play Event card (select in hand -> click event zone) succeeded")

	_board.queue_free()
	print("ALL PLACEMENT AND EVENT TESTS PASSED! (0 failures)")
	quit(0)
	return true
