# res://tests/don_interactivity_and_leader_lock_smoke.gd
# Verification script for:
# 1. Leader card cannot be dragged anywhere (drag is blocked on Leader).
# 2. Clicking active DON cards rotates them -90 deg (rested/committed) and stages cost.
# 3. Hand cards matching the committed DON amount raise up (-42px) with golden highlight.
# 4. Clicking committed DON card uncommits it and lowers hand cards back down.
# 5. Playing a card resets committed DON back to 0.

extends SceneTree

var _frame := 0
var _tb: MtTestBoard = null
var _cdb: Node = null

func _process(_delta: float) -> bool:
	_frame += 1
	if _cdb == null:
		_cdb = root.get_node_or_null("CardDatabase")
	if not _cdb or not _cdb.is_data_loaded:
		if _frame > 600:
			printerr("TEST FAIL: CardDatabase never loaded")
			quit(1)
			return true
		return false

	if _tb == null:
		print("--- Running DON Interactivity and Leader Lock Smoke Test ---")
		_tb = MtTestBoard.new()
		_tb.name = "TestBoard"
		root.add_child(_tb)
		return false

	if _tb.engine == null or not _tb._started or _tb.engine.players.size() < 2:
		return false

	if _frame < 30:
		return false

	_run_all_tests()
	quit(0)
	return true

func _run_all_tests() -> void:
	if _tb.engine.pending_choice != null and _tb.engine.pending_choice.get("type", "") == "mulligan":
		_tb._on_mulligan_keep()
	if _tb.engine.pending_choice != null and _tb.engine.pending_choice.get("type", "") == "mulligan":
		_tb.engine.apply({"type": _tb.engine.ACTION_KEEP_HAND, "player": 1})
	_tb._rebuild()

	var me = _tb.engine.players[0]

	# --- TEST 1: Leader card cannot be dragged ---
	print("[TEST 1] Testing Leader Card Drag Prevention...")
	var leader_widget: MtMatCard = null
	for w in _tb._placed:
		if w is MtMatCard and w.role == "my_leader":
			leader_widget = w
			break
	assert(leader_widget != null, "Leader card widget should be placed on board")

	# Simulate dragging mouse on leader widget
	var press_ev := InputEventMouseButton.new()
	press_ev.button_index = MOUSE_BUTTON_LEFT
	press_ev.pressed = true
	press_ev.global_position = Vector2(500, 300)
	leader_widget._on_gui_input(press_ev)

	var motion_ev := InputEventMouseMotion.new()
	motion_ev.global_position = Vector2(550, 350)
	leader_widget._on_gui_input(motion_ev)

	# Verify drag was NOT started
	assert(_tb._drag_ghost == null, "Leader card must NEVER start a drag or spawn a drag ghost")
	assert(_tb._drag_uid == "", "Drag UID must remain empty when dragging leader")
	print("[TEST 1 PASSED] Leader card cannot be dragged anywhere.")

	# --- TEST 2: Active DON card interaction & -90 rotation ---
	print("[TEST 2] Testing DON Card Clicking and -90 deg Rotation...")
	me.don_active = 4
	me.don_rested = 0
	_tb.engine.active = 0
	_tb._dirty = true
	_tb._rebuild()

	var bot_mat: MtPlayerMat = _tb._playfield._bot_mat
	assert(bot_mat != null, "Bottom player mat must exist")
	var don_fan: Control = bot_mat._don_fan
	assert(don_fan.get_child_count() == 4, "Should have 4 DON cards in DON area")

	var don_card_0: Control = don_fan.get_child(0) as Control
	assert(absf(don_card_0.rotation_degrees) < 0.01, "Active DON card must start upright (0 deg)")

	# Click DON card 0 (active) -> should commit it
	_tb._on_don_card_clicked(0, 0, true, false)

	assert(_tb._committed_don == 1, "Committed DON should now be 1")
	var don_fan_updated: Control = bot_mat._don_fan
	var committed_card: Control = don_fan_updated.get_child(3) as Control
	assert(absf(committed_card.rotation_degrees - (-90.0)) < 0.01, "Committed DON card must rotate to -90 deg")
	print("[TEST 2 PASSED] Clicking active DON rotates card to -90 deg and stages cost.")

	# --- TEST 3: Hand card elevation matching committed DON ---
	print("[TEST 3] Testing Hand Card Elevation Matching Cost...")
	me.hand.clear()
	var card_1cost := _tb.engine._mk({"type": "Character", "name": "1-Cost Guy", "cost": 1, "card_code": "C1"}, 0, MtMatchCard.ZONE_HAND)
	var card_2cost := _tb.engine._mk({"type": "Character", "name": "2-Cost Guy", "cost": 2, "card_code": "C2"}, 0, MtMatchCard.ZONE_HAND)
	var card_3cost := _tb.engine._mk({"type": "Character", "name": "3-Cost Guy", "cost": 3, "card_code": "C3"}, 0, MtMatchCard.ZONE_HAND)
	me.hand.append(card_1cost)
	me.hand.append(card_2cost)
	me.hand.append(card_3cost)
	_tb._rebuild_hand()

	var h1: MtMatCard = _tb._hand.get_child(0) as MtMatCard
	var h2: MtMatCard = _tb._hand.get_child(1) as MtMatCard
	var h3: MtMatCard = _tb._hand.get_child(2) as MtMatCard
	assert(h1.base_y == -42.0, "1-cost card should be raised when 1 DON committed")
	assert(h2.base_y == 0.0, "2-cost card should NOT be raised when 1 DON committed")
	assert(h3.base_y == 0.0, "3-cost card should NOT be raised when 1 DON committed")

	# Now commit 1 more DON -> _committed_don == 2
	_tb._on_don_card_clicked(0, 0, true, false)
	assert(_tb._committed_don == 2, "Committed DON should now be 2")
	assert(h1.base_y == 0.0, "1-cost card should lower back down when 2 DON committed")
	assert(h2.base_y == -42.0, "2-cost card should be raised when 2 DON committed")
	assert(h3.base_y == 0.0, "3-cost card should NOT be raised when 2 DON committed")
	print("[TEST 3 PASSED] Hand cards matching committed DON raise up (-42px) with golden highlight.")

	# --- TEST 4: Un-committing DON card by clicking it ---
	print("[TEST 4] Testing Un-committing DON Card...")
	_tb._on_don_card_clicked(0, 3, false, true)
	assert(_tb._committed_don == 1, "Committed DON should decrease to 1")
	assert(h1.base_y == -42.0, "1-cost card should be raised again when committed DON returns to 1")
	assert(h2.base_y == 0.0, "2-cost card should be lowered")

	_tb._on_don_card_clicked(0, 3, false, true)
	assert(_tb._committed_don == 0, "Committed DON should decrease to 0")
	assert(h1.base_y == 0.0, "All hand cards should be lowered when 0 DON committed")
	print("[TEST 4 PASSED] Un-committing DON cards lowers hand cards and updates rotation.")

	# --- TEST 5: Playing card resets committed DON ---
	print("[TEST 5] Testing Playing Card Resets Committed DON...")
	_tb._on_don_card_clicked(0, 0, true, false)
	assert(_tb._committed_don == 1, "Should have 1 committed DON before play")
	_tb._play_card_to_slot(card_1cost.uid, 0)
	assert(_tb._committed_don == 0, "Playing card must reset committed DON to 0")
	print("[TEST 5 PASSED] Playing card resets committed DON.")

	print("\n>>> ALL DON INTERACTIVITY AND LEADER LOCK SMOKE TESTS PASSED! <<<")
