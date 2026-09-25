# tests/drag_and_attack_rules_smoke.gd -- Test OPTCG attack targeting, blocker sequence, and drag-and-drop actions
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
		var main_codes: Array = []
		for code in ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
				"ST01-007", "ST01-008", "ST01-009", "ST01-010", "ST01-011", "ST01-012", "ST01-013",
				"ST01-015"]:
			for _i in range(4):
				main_codes.append(code)
		_deck = MtDeckLoader.build_from_lists("ST01-001", main_codes, _cdb.get_card_data)

		# 1. OPTCG Attack Targeting Rules Verification in engine
		print("--- Running Attack Targeting Rules Verification ---")
		var engine := MtMatch.new()
		engine.auto_resolve_choices = true
		engine.start(_deck, _deck, 0)
		engine.turn = 3
		engine.active = 0
		engine.phase = engine.Phase.MAIN
		var me = engine.players[0]
		var foe = engine.players[1]
		me.don_active = 10
		me.don_rested = 0

		var zoro_dict := {"name": "Roronoa Zoro", "card_code": "ST01-013", "type": "Character", "cost": 3, "power": 5000, "counter": 1000, "color": "Red"}
		var zoro: MtMatchCard = engine._mk(zoro_dict, 0, MtMatchCard.ZONE_FIELD)
		me.field.append(zoro)

		var active_char_dict := {"name": "Nami Active", "card_code": "ST01-007", "type": "Character", "cost": 1, "power": 1000, "counter": 1000, "color": "Red"}
		var active_char: MtMatchCard = engine._mk(active_char_dict, 1, MtMatchCard.ZONE_FIELD)
		active_char.rested = false
		foe.field.append(active_char)

		var rested_char_dict := {"name": "Chopper Rested", "card_code": "ST01-006", "type": "Character", "cost": 1, "power": 1000, "counter": 0, "color": "Red"}
		var rested_char: MtMatchCard = engine._mk(rested_char_dict, 1, MtMatchCard.ZONE_FIELD)
		rested_char.rested = true
		foe.field.append(rested_char)

		# Check attacking active character (MUST BE REJECTED)
		var res_active := engine.apply({"type": engine.ACTION_ATTACK, "attacker": zoro.uid, "target": active_char.uid})
		assert(not res_active.ok, "Attacking an active Character without effect must be REJECTED")
		assert("rested" in res_active.msg.to_lower() or "active" in res_active.msg.to_lower(), "Reject message should cite rested/active requirement")
		print("PASS: Attacking active Character correctly rejected (%s)" % res_active.msg)

		# Check attacking opponent Leader (MUST SUCCEED)
		assert(foe.leader != null, "Foe leader must exist")
		var res_leader := engine.apply({"type": engine.ACTION_ATTACK, "attacker": zoro.uid, "target": foe.leader.uid})
		assert(res_leader.ok, "Attacking opponent Leader must be LEGAL")
		assert(zoro.rested == true, "Attacking card must become rested (-90 deg)")
		assert(engine.in_battle(), "Match should enter battle")
		print("PASS: Attacking opponent Leader legal and rested attacker")

		# Resolve battle
		engine.apply({"type": engine.ACTION_PASS_BATTLE})
		assert(not engine.in_battle(), "Battle resolved")

		# Stand Zoro to attack again
		zoro.rested = false
		zoro.attacked_count = 0

		# Check attacking rested character (MUST SUCCEED)
		var res_rested := engine.apply({"type": engine.ACTION_ATTACK, "attacker": zoro.uid, "target": rested_char.uid})
		assert(res_rested.ok, "Attacking rested Character must be LEGAL")
		assert(zoro.rested == true, "Attacking card must become rested")
		print("PASS: Attacking rested Character legal")
		engine.apply({"type": engine.ACTION_PASS_BATTLE})

		# Setup Board for Drag & Drop
		_board = MtTestBoard.new()
		_board.size = Vector2(1920, 1080)
		root.add_child(_board)
		_board.start_custom_match(_deck, _deck, 0, 1)
		if _board.engine.pending_choice != null and _board.engine.pending_choice.get("type", "") == "mulligan":
			_board._on_mulligan_keep()
		if _board.engine.pending_choice != null and _board.engine.pending_choice.get("type", "") == "mulligan":
			_board.engine.apply({"type": _board.engine.ACTION_KEEP_HAND, "player": 1})
		_board._rebuild()
		return false

	# Wait a couple frames for UI containers to lay out
	if _frame % 4 != 0:
		return false

	print("--- Testing TestBoard Drag and Drop Actions ---")
	var tb_engine := _board.engine
	var tb_me = tb_engine.players[0]
	var tb_foe = tb_engine.players[1]
	tb_engine.turn = 3
	tb_engine.phase = tb_engine.Phase.MAIN
	tb_me.don_active = 5
	tb_me.don_rested = 0

	# A. Test Drag Deck to Hand -> Disallowed by official rules (must be rejected)
	var init_hand_size: int = tb_me.hand.size()
	var hand_center: Vector2 = _board._hand.get_global_rect().get_center()
	_board._handle_card_drop("deck", "deck", hand_center)
	assert(tb_me.hand.size() == init_hand_size, "Manual dragging deck to hand must be rejected under official rules")
	print("PASS: Drag Deck to Hand rejected under official rules (hand size preserved: %d)" % tb_me.hand.size())

	# B. Test Drag DON to Leader -> Attach DON
	var init_lead_don: int = tb_me.leader.don_count()
	var lead_zone: Control = _board._playfield.get_zone(0, "leader")
	var lead_center: Vector2 = lead_zone.get_global_rect().get_center()
	_board._handle_card_drop("don", "don", lead_center)
	assert(tb_me.leader.don_count() == init_lead_don + 1, "Dragging DON to Leader must attach 1 DON")
	print("PASS: Drag DON to Leader attached 1 DON (leader DON: %d)" % tb_me.leader.don_count())

	# C. Test Drag DON to Character -> Attach DON
	var zoro_dict := {"name": "Roronoa Zoro", "card_code": "ST01-013", "type": "Character", "cost": 3, "power": 5000, "counter": 1000, "color": "Red"}
	var test_char: MtMatchCard = tb_engine._mk(zoro_dict, 0, MtMatchCard.ZONE_FIELD)
	tb_me.field.append(test_char)
	_board._card_slot_map[test_char.uid] = 0
	var slot0: Control = _board._playfield.char_slots(0)[0]
	var slot0_center: Vector2 = slot0.get_global_rect().get_center()
	var init_char_don: int = test_char.don_count()
	_board._handle_card_drop("don", "don", slot0_center)
	assert(test_char.don_count() == init_char_don + 1, "Dragging DON to Character slot must attach 1 DON")
	print("PASS: Drag DON to Character attached 1 DON (character DON: %d)" % test_char.don_count())

	# D. Test Drag DON Deck to Cost Area -> Disallowed by official rules (must be rejected)
	var init_active_don: int = tb_me.don_active
	var cost_zone: Control = _board._playfield.get_zone(0, "cost")
	var cost_center: Vector2 = cost_zone.get_global_rect().get_center()
	_board._handle_card_drop("don_deck", "don_deck", cost_center)
	assert(tb_me.don_active == init_active_don, "Manual dragging DON deck to cost area must be rejected under official rules")
	print("PASS: Drag DON Deck to Cost area rejected under official rules (active DON preserved: %d)" % tb_me.don_active)

	# E. Test Drag Life to Hand -> Disallowed by official rules (must be rejected)
	var init_life_size: int = tb_me.life.size()
	_board._handle_card_drop("life", "life", hand_center)
	assert(tb_me.life.size() == init_life_size, "Manual dragging Life to Hand must be rejected under official rules")
	print("PASS: Drag Life to Hand rejected under official rules (life preserved: %d)" % tb_me.life.size())

	# F. Test Drag Character to Opponent Leader -> Attack
	assert(test_char != null, "Character exists")
	test_char.rested = false
	var opp_lead_zone: Control = _board._playfield.get_zone(1, "leader")
	var opp_lead_center: Vector2 = opp_lead_zone.get_global_rect().get_center()
	_board._handle_card_drop(test_char.uid, "my_field", opp_lead_center)
	assert(test_char.rested == true, "Character must become rested upon attacking")
	assert(tb_engine.in_battle(), "Match must be in battle with opponent Leader")
	print("PASS: Drag Attacker to Opponent Leader successfully attacks and rests Character")

	tb_engine.apply({"type": tb_engine.ACTION_PASS_BATTLE})

	# G. Leader attacks via right-click on the target (left-click only selects).
	assert(tb_me.leader != null, "Leader exists")
	if tb_engine.pending_choice != null and String(tb_engine.pending_choice.get("type", "")) == "life_trigger":
		tb_engine.apply({"type": tb_engine.ACTION_TRIGGER_NO, "player": int(tb_engine.pending_choice.get("player", 1)),
			"card_uid": String(tb_engine.pending_choice.get("card_uid", ""))})
	tb_me.leader.rested = false
	_board.selected_uid = tb_me.leader.uid
	_board.attacker_uid = tb_me.leader.uid
	tb_engine.phase = MtMatch.Phase.MAIN
	var dummy_opp := MtMatCard.new()
	dummy_opp.uid = tb_foe.leader.uid
	dummy_opp.role = "opp_leader"
	_board._on_card_context_requested(dummy_opp, Vector2(10, 10))
	var has_atk := false
	for i in range(_board._context_menu.item_count):
		if _board._context_menu.get_item_id(i) == _board.CtxAction.FIELD_ATTACK_TARGET:
			has_atk = true
	assert(has_atk, "Right-click opponent Leader offers Attack")
	_board._on_context_menu_id_pressed(_board.CtxAction.FIELD_ATTACK_TARGET)
	dummy_opp.queue_free()
	assert(tb_me.leader.rested == true, "Leader must become rested upon attacking via right-click")
	assert(tb_engine.in_battle(), "Match must be in battle when Leader attacks via right-click")
	print("PASS: Leader attacks opponent Leader via right-click")

	_board.queue_free()
	print("ALL DRAG AND ATTACK RULES TESTS PASSED! (0 failures)")
	quit(0)
	return true
