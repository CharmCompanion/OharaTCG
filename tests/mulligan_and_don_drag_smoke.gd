# res://tests/mulligan_and_don_drag_smoke.gd
# Headless smoke test for Mulligan rule, DON attachment, and legal rules enforcement.

extends SceneTree

func _init() -> void:
	print("[MULLIGAN & DON DRAG SMOKE] Starting tests...")
	_test_mulligan_flow()
	_test_mulligan_compat()
	_test_don_drag_logic()
	print("[MULLIGAN & DON DRAG SMOKE] ALL TESTS PASSED!")
	quit(0)

func _make_test_deck() -> Dictionary:
	var leader := {
		"card_code": "ST01-001",
		"name": "Monkey D. Luffy",
		"type": "Leader",
		"color": "Red",
		"power": 5000,
		"life": 5
	}
	var main: Array[Dictionary] = []
	for i in range(50):
		main.append({
			"card_code": "ST01-%03d" % ((i % 15) + 2),
			"name": "Card %d" % i,
			"type": "Character",
			"color": "Red",
			"cost": 1 + (i % 5),
			"power": 3000 + (i % 4) * 1000,
			"counter": 1000
		})
	return {"leader": leader, "main": main}

func _test_mulligan_flow() -> void:
	print("--- Testing Mulligan Interactive Flow ---")
	var deck_a := _make_test_deck()
	var deck_b := _make_test_deck()

	var m := MtMatch.new()
	m.rng.seed = 12345
	m.enable_mulligan = true
	m.auto_resolve_choices = false
	m.start(deck_a, deck_b, 0)

	assert(m.pending_choice != null, "Pending choice should exist at start when mulligan enabled")
	assert(m.pending_choice.type == "mulligan", "Pending choice should be mulligan")
	assert(m.pending_choice.player == 0, "First player (0) should have mulligan choice first")

	var legals := m.get_legal_actions()
	assert(legals.size() == 2, "Should only have keep_hand and mulligan actions")
	print("Legal actions at mulligan: ", legals)

	var orig_hand_uids: Array = []
	for c in m.players[0].hand:
		orig_hand_uids.append(c.uid)
	assert(orig_hand_uids.size() == 5, "Opening hand should be 5 cards")

	# P0 chooses Mulligan (redraw)
	var res0 := m.apply({"type": m.ACTION_MULLIGAN, "player": 0})
	assert(res0.ok, "Mulligan apply should succeed: " + str(res0))
	assert(m.mulligan_done[0] == true, "P0 mulligan_done should be true")
	assert(m.players[0].hand.size() == 5, "P0 hand should still have 5 cards after mulligan")

	# Now P1 should have mulligan choice
	assert(m.pending_choice != null, "P1 should now have pending mulligan choice")
	assert(m.pending_choice.type == "mulligan", "P1 choice should be mulligan")
	assert(m.pending_choice.player == 1, "P1 should be the player choosing")

	# P1 chooses Keep Hand
	var res1 := m.apply({"type": m.ACTION_KEEP_HAND, "player": 1})
	assert(res1.ok, "Keep hand apply should succeed: " + str(res1))
	assert(m.mulligan_done[1] == true, "P1 mulligan_done should be true")

	# Both mulligans done -> Turn 1 begins!
	assert(m.pending_choice == null, "No choice should pend after both mulligans done")
	assert(m.turn == 1, "Turn should be 1")
	assert(m.phase == m.Phase.MAIN, "Should have transitioned through DON/DRAW to MAIN")
	print("Mulligan flow verified successfully.")

func _test_mulligan_compat() -> void:
	print("--- Testing Backward Compatibility (auto_resolve_choices = true) ---")
	var deck_a := _make_test_deck()
	var deck_b := _make_test_deck()

	var m := MtMatch.new()
	m.rng.seed = 42
	# Default: auto_resolve_choices is true, enable_mulligan is false
	m.start(deck_a, deck_b, 0)

	assert(m.pending_choice == null, "No pending choice in legacy/auto mode")
	assert(m.turn == 1, "Turn should be 1")
	assert(m.phase == m.Phase.MAIN, "Should be in MAIN phase")
	print("Backward compatibility verified successfully.")

func _test_don_drag_logic() -> void:
	print("--- Testing DON Attachment and Rules ---")
	var deck_a := _make_test_deck()
	var deck_b := _make_test_deck()

	var m := MtMatch.new()
	m.rng.seed = 999
	m.start(deck_a, deck_b, 0)

	# Give plenty of active DON to P0
	m.players[0].don_active = 10
	assert(m.players[0].get_available_don() == 10, "P0 should have 10 available DON")

	# Attach DON to Leader
	var res_lead := m.apply({"type": m.ACTION_ATTACH_DON, "card_uid": m.players[0].leader.uid})
	assert(res_lead.ok, "Should attach DON to leader: " + str(res_lead))
	assert(m.players[0].leader.don_count() == 1, "Leader should have 1 DON attached")
	assert(m.card_power(m.players[0].leader) == 6000, "Leader power with 1 DON during own turn should be 6000 (5000 + 1000)")

	# Play a Character to field (cost <= available DON)
	var char_card: MtMatchCard = null
	for c in m.players[0].hand:
		if c.cost_value() <= m.players[0].get_available_don():
			char_card = c
			break
	assert(char_card != null, "Should find a playable card in hand")
	var res_play := m.apply({"type": m.ACTION_PLAY, "card_uid": char_card.uid})
	assert(res_play.ok, "Playing character should succeed: " + str(res_play))
	assert(char_card in m.players[0].field, "Character should be on field")

	# Attach DON to Character
	var res_char := m.apply({"type": m.ACTION_ATTACH_DON, "card_uid": char_card.uid})
	assert(res_char.ok, "Should attach DON to character: " + str(res_char))
	assert(char_card.don_count() == 1, "Character should have 1 DON attached")

	print("DON attachment verified successfully.")
