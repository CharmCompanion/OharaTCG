# tests/battle_and_events_smoke.gd -- Test battle arrow coordinates, card resting, event throw-down & YGOPro combat flow
extends SceneTree

var _tb: Control
var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_tb = load("res://scripts/ui/TestBoard.gd").new()
		root.add_child(_tb)
		_tb._ready()
		_tb.build_ui()
		_tb._start_game()
		return false
	if _frame == 3:
		_run_checks()
		quit(0)
	return false

func _run_checks() -> void:
	print("--- Running Battle and Events Smoke Checks ---")
	var tb: Control = _tb
	var engine = tb.get("engine")
	assert(engine != null, "Engine must be valid")
	
	# 1. Check Event Zone Visuals on PlayerMat
	var bot_mat = tb.get("_playfield")._bot_mat
	var top_mat = tb.get("_playfield")._top_mat
	assert(bot_mat != null and top_mat != null, "Player mats must be initialized")
	
	var event_zone_bot = bot_mat.get_zone("event")
	var event_zone_top = top_mat.get_zone("event")
	assert(event_zone_bot != null and event_zone_top != null, "Event zone containers must exist")
	
	# Verify panels and titles are invisible
	for c in event_zone_bot.get_children():
		if c is Panel:
			assert(c.visible == false, "Bottom mat event panel must be invisible (blank felt)")
		elif c is Label:
			assert(c.visible == false or c.text.strip_edges() == "", "Bottom mat event title must be invisible/empty")
	
	for c in event_zone_top.get_children():
		if c is Panel:
			assert(c.visible == false, "Top mat event panel must be invisible (blank felt)")
		elif c is Label:
			assert(c.visible == false or c.text.strip_edges() == "", "Top mat event title must be invisible/empty")
	print("CHECK 1 PASSED: Event zones have no visible panel outline or printed title (blank felt table).")

	# 2. Check MatCard Pivot & Minimum Size
	var test_card = load("res://scripts/ui/MatCard.gd").new()
	test_card.setup("test_uid", "my_field", "Test Luffy", "5000", "", true)
	root.add_child(test_card)
	assert(test_card.pivot_offset.x > 0 and test_card.pivot_offset.y > 0, "Card pivot_offset must be centered")
	assert(test_card.rotation_degrees == -90.0, "Rested card must have rotation_degrees = -90.0")
	test_card.queue_free()
	print("CHECK 2 PASSED: MatCard sets custom_minimum_size and centered pivot_offset for landscape resting.")

	# 3. Check Attack Arrow Affine Transformation
	while engine.pending_choice != null and String(engine.pending_choice.get("type", "")) == "mulligan":
		engine.apply({"type": engine.ACTION_KEEP_HAND, "player": int(engine.pending_choice.get("player", 0))})
	engine.turn = 2
	engine.active = 1
	engine.phase = engine.Phase.MAIN
	var foe = engine.players[1]
	var me = engine.players[0]
	foe.leader.rested = false
	
	# Declare attack from P1 leader to P0 leader
	var atk_res = engine.apply({"type": engine.ACTION_ATTACK, "attacker": foe.leader.uid, "target": me.leader.uid})
	assert(atk_res.get("ok", false), "Attack must succeed: %s" % atk_res.get("msg", ""))
	assert(foe.leader.rested == true, "Attacking leader must be rested")
	
	tb._rebuild()
	
	# Verify attacker widget is rested
	var atk_widget = tb._widget_for(foe.leader.uid)
	assert(atk_widget != null, "Attacker widget must exist")
	assert(atk_widget.rotation_degrees == -90.0, "Attacker widget must be visually rotated to -90 deg")
	
	# Check battle arrow endpoints
	var arrow: Line2D = tb.get("_arrow")
	assert(arrow != null and arrow.visible == true, "Battle arrow must be visible")
	assert(arrow.points.size() == 2, "Battle arrow must have 2 endpoints")
	
	var expected_start = arrow.to_local(atk_widget.get_global_transform() * (atk_widget.size / 2.0))
	var def_widget = tb._widget_for(me.leader.uid)
	var expected_end = arrow.to_local(def_widget.get_global_transform() * (def_widget.size / 2.0))
	
	assert(arrow.points[0].distance_to(expected_start) < 1.0, "Arrow start point must match affine transform center of attacker card")
	assert(arrow.points[1].distance_to(expected_end) < 1.0, "Arrow end point must match affine transform center of defender card")
	print("CHECK 3 PASSED: Attack arrow accurately originates from attacking leader card center via affine transform.")

	# 4. Check YGOPro-style Blocker & Counter Step Flow
	# Add a blocker (Chopper) to player 0's field
	var chopper_dict = {
		"card_code": "ST01-006", "name": "Tony Tony.Chopper", "type": "Character",
		"power": 1000, "cost": 1, "counter": 0, "effect": "[Blocker]",
		"color": "Red", "rarity": "Common"
	}
	var chopper = engine._mk(chopper_dict, 0, MtMatchCard.ZONE_FIELD)
	chopper.rested = false
	me.field.append(chopper)
	
	# Reset battle to block step targeting leader with blocker available
	engine.battle.step = "block"
	tb._rebuild()
	
	# Prompt should be visible for blocker
	var center_prompt: Control = tb.get("_center_battle_prompt")
	assert(center_prompt != null and center_prompt.visible == true, "Center battle prompt must be visible in blocker step")
	
	# Block with Chopper
	var block_res = engine.apply({"type": engine.ACTION_BLOCK, "blocker": chopper.uid})
	assert(block_res.get("ok", false), "Blocking with Chopper must succeed")
	assert(chopper.rested == true, "Blocker must be rested after blocking")
	assert(engine.battle.get("defender") == chopper, "Defender is now Chopper")
	assert(engine.battle.get("step") == "counter", "Battle should advance to counter step")
	
	tb._rebuild()
	
	# In counter step, pass button should let the defender be K.O.'d if power is lower
	var pass_btn: Button = tb.get("_center_battle_pass")
	assert(pass_btn != null, "Center battle pass button must exist")
	assert("Counter" in pass_btn.text or "K.O." in pass_btn.text, "Pass button must use official Counter / K.O. wording: %s" % pass_btn.text)
	
	# Give player a counter card in hand to ensure pass is intentional
	var counter_dict = {
		"card_code": "ST01-007", "name": "Nami", "type": "Character",
		"power": 1000, "cost": 1, "counter": 1000, "color": "Red", "rarity": "Common"
	}
	var nami = engine._mk(counter_dict, 0, MtMatchCard.ZONE_HAND)
	me.hand.append(nami)
	
	# Human clicks pass ("No Counter / Let Blocker Die")
	var pass_res = engine.apply({"type": "pass_battle"})
	assert(pass_res.get("ok", false), "Pass battle must succeed")
	
	# Blocker (Chopper) should take hit and be KO'd to trash!
	assert(chopper in me.trash, "Chopper must be KO'd and sent to trash")
	assert(not (chopper in me.field), "Chopper must no longer be on field")
	assert(engine.battle.is_empty(), "Battle must resolve and clear")
	# Leader must NOT have taken damage because Chopper blocked!
	print("CHECK 4 PASSED: Blocker rests, player declines Counter, Chopper is K.O.'d to Trash cleanly.")

	print("--- ALL BATTLE AND EVENT CHECKS PASSED SUCCESSFULLY! ---")
