# tests/phase3_smoke.gd -- Phase 3: life-trigger choice point, life hooks, mat cards.
extends SceneTree

var _frame := 0
var _started := false
var _fail := 0
var _board: Node
var _setup_frame := 0
var _checked := false

func _process(_delta: float) -> bool:
	_frame += 1
	var cdb = root.get_node_or_null("CardDatabase")
	if not cdb or not cdb.is_data_loaded:
		if _frame > 900:
			printerr("TEST FAIL: CardDatabase never loaded")
			quit(1)
			return true
		return false
	if not _started:
		_started = true
		_setup(cdb)
		_setup_frame = _frame
		return false
	if not _checked and _frame >= _setup_frame + 6:
		_checked = true
		_run_board_checks()
		print("PHASE3 SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _setup(cdb: Node) -> void:
	_test_choice(cdb)
	_test_hooks(cdb)
	_test_life_tokens(cdb)
	_test_matcard()
	var script = load("res://scripts/ui/TestBoard.gd")
	_board = script.new()
	root.add_child(_board)

func _test_matcard() -> void:
	var w := MtMatCard.new()
	w.setup("u1", "hand", "Some Name Here Plus", "Cost 2", "", false, false,
		{"trigger": "Play this card.", "foil_grade": "parallel", "rarity": "", "card_code": "T-001"})
	_check("trg marker", w._sub_l.text.contains("TRG"), w._sub_l.text)
	_check("holo on parallel", w._holo.visible, w._holo.visible)
	var w2 := MtMatCard.new()
	w2.setup("u2", "hand", "Plain", "Cost 1", "", false, false, {"rarity": "Common"})
	_check("holo off common", not w2._holo.visible, w2._holo.visible)
	w.queue_free()
	w2.queue_free()

func _deck(cdb: Node, leader_code: String, main_prefix: String) -> Dictionary:
	var leader: Dictionary = cdb.get_card_data(leader_code)
	var main: Array = []
	var slots := 0
	for i in range(100):
		var d: Dictionary = cdb.get_card_data("%s-%03d" % [main_prefix, (i % 14) + 1])
		if not d.is_empty():
			main.append(d)
			slots += 1
			if slots >= 50:
				break
	return {"leader": leader, "main": main}

func _find_trigger_card(cdb: Node) -> Dictionary:
	var fallback := {}
	for d in cdb.get_all_card_data_as_array():
		var dd: Dictionary = d
		if String(dd.get("trigger", "")).is_empty():
			continue
		if String(dd.get("type", "")) == "Character" and String(dd.get("trigger", "")).contains("Play this card"):
			return dd
		if fallback.is_empty():
			fallback = dd
	return fallback

func _test_choice(cdb: Node) -> void:
	var tcard := _find_trigger_card(cdb)
	_check("found trigger card", not tcard.is_empty(), tcard.get("card_code", "?"))
	if tcard.is_empty():
		return
	# Manual-resolve mode: damage with a trigger card pends a choice.
	var mt := MtMatch.new()
	mt.auto_resolve_choices = false
	mt.start(_deck(cdb, "ST01-001", "ST01"), _deck(cdb, "ST01-001", "ST01"), 0)
	var p1: MtPlayerState = mt.players[1]
	var tm := mt._mk(tcard, 1, MtMatchCard.ZONE_LIFE)
	tm.face_down = true
	p1.life = [tm]
	mt._deal_leader_damage(p1, null)
	_check("choice pends", mt.pending_choice != null, mt.pending_choice)
	_check("choice player", mt.pending_choice != null and int(mt.pending_choice.get("player", -1)) == 1, mt.pending_choice)
	var acts := mt.get_legal_actions()
	var types: Array = []
	for a in acts:
		types.append(String(a.get("type", "")))
	_check("yes and no offered", types.has("trigger_yes") and types.has("trigger_no"), types)
	# Wrong player is rejected.
	var bad := mt.apply({"type": "trigger_yes", "player": 0, "card_uid": tm.uid})
	_check("wrong player rejected", not bad.get("ok", true), bad.get("code", ""))
	# Decline: card stays in hand, choice clears.
	var no := mt.apply({"type": "trigger_no", "player": 1, "card_uid": tm.uid})
	_check("decline ok", no.get("ok", false), no)
	_check("choice cleared", mt.pending_choice == null, mt.pending_choice)
	_check("card kept in hand", p1.hand.has(tm), p1.hand.size())
	# Accept: resolves without error; card ends on field/hand/stage somewhere.
	p1.hand.erase(tm)
	tm.zone = MtMatchCard.ZONE_LIFE
	tm.face_down = true
	p1.life = [tm]
	mt._deal_leader_damage(p1, null)
	var yes := mt.apply({"type": "trigger_yes", "player": 1, "card_uid": tm.uid})
	_check("accept ok", yes.get("ok", false), yes)
	_check("accept clears", mt.pending_choice == null, mt.pending_choice)
	var placed: bool = p1.field.has(tm) or p1.hand.has(tm) or p1.stage == tm
	_check("trigger resolved somewhere", placed, "%d/%d" % [p1.field.size(), p1.hand.size()])
	# Auto mode (default): resolves immediately, nothing pends.
	var mt2 := MtMatch.new()
	mt2.start(_deck(cdb, "ST01-001", "ST01"), _deck(cdb, "ST01-001", "ST01"), 0)
	var q1: MtPlayerState = mt2.players[1]
	var tm2 := mt2._mk(tcard, 1, MtMatchCard.ZONE_LIFE)
	tm2.face_down = true
	q1.life = [tm2]
	mt2._deal_leader_damage(q1, null)
	_check("auto resolves (no pend)", mt2.pending_choice == null, mt2.pending_choice)

func _test_hooks(cdb: Node) -> void:
	var mt := MtMatch.new()
	mt.start(_deck(cdb, "ST01-001", "ST01"), _deck(cdb, "ST01-001", "ST01"), 0)
	var p0: MtPlayerState = mt.players[0]
	var life0 := p0.life.size()
	var deck0 := p0.deck.size()
	_check("deck_to_life down", mt.deck_to_life(p0, 1, true) == 1 and p0.life.size() == life0 + 1, p0.life.size())
	_check("deck_to_life up", mt.deck_to_life(p0, 1, false) == 1, p0.life.size())
	var top: MtMatchCard = p0.life.back()
	_check("face-up honored", top.face_down == false, top.face_down)
	_check("set face down", mt.life_set_face(p0, p0.life.size() - 1, true) and top.face_down, top.face_down)
	_check("bad index rejected", not mt.life_set_face(p0, 99, true), "idx99")
	var first_uid: String = (p0.life[0] as MtMatchCard).uid
	_check("reorder reverses", mt.life_reorder(p0, _reversed_idx(p0.life.size())), "order")
	_check("reorder moved", (p0.life.back() as MtMatchCard).uid == first_uid, (p0.life.back() as MtMatchCard).uid)
	_check("bad reorder rejected", not mt.life_reorder(p0, [0]), "short")
	var trash0 := p0.trash.size()
	_check("life_to_trash", mt.life_to_trash(p0, 1) == 1 and p0.trash.size() == trash0 + 1, p0.trash.size())
	_check("deck shrank by 2", p0.deck.size() == deck0 - 2, p0.deck.size())

func _reversed_idx(n: int) -> Array:
	var o := []
	for i in range(n - 1, -1, -1):
		o.append(i)
	return o

func _test_life_tokens(cdb: Node) -> void:
	# Parser: sample phrasings harvested from real card texts.
	var f1 := MtEffectParser.parse({"effect": "[On Play] You may add 1 card from the top or bottom of your Life cards to your hand: draw 1 card."})
	_check("life_to_hand parsed", _has_tok(f1, "on_play", "life_to_hand"), f1.get("on_play", []))
	var a1: Array = _find_tok(f1, "on_play", "life_to_hand")
	_check("edge either", a1.size() > 1 and a1[1].get("edge", "") == "either", a1)
	var mt_cost := MtMatch.new()
	mt_cost.start(_deck(cdb, "ST01-001", "ST01"), _deck(cdb, "ST01-001", "ST01"), 0)
	var cp: MtPlayerState = mt_cost.players[0]
	var ch0 := cp.hand.size()
	var cl0 := cp.life.size()
	var cost_acts: Array = []
	if not (f1.get("on_play", []) as Array).is_empty():
		cost_acts = ((f1["on_play"] as Array)[0] as Dictionary).get("actions", [])
	mt_cost._resolve_actions(cp.leader, cost_acts, {})
	_check("life cost then draw", cp.life.size() == cl0 - 1 and cp.hand.size() == ch0 + 2, "%d/%d" % [cp.life.size(), cp.hand.size()])
	var f2 := MtEffectParser.parse({"effect": "[On Play] Add up to 1 card from the top of your deck to the top of your Life cards."})
	_check("deck_to_life parsed", _has_tok(f2, "on_play", "deck_to_life"), "on_play")
	var f3 := MtEffectParser.parse({"effect": "[On Play] Trash 1 card from the top of your opponent's Life cards."})
	var a3: Array = _find_tok(f3, "on_play", "trash_life")
	_check("trash_life opp", not a3.is_empty() and a3[1].get("player", "") == "opp", a3)
	var f4 := MtEffectParser.parse({"effect": "[On Play] You may turn 1 card from the top of your Life cards face-down: draw 1 card."})
	var a4: Array = _find_tok(f4, "on_play", "face_life")
	_check("face_life down", not a4.is_empty() and bool(a4[1].get("down", false)), a4)
	var f5 := MtEffectParser.parse({"effect": "[On Play] If you have 2 or less Life cards, add up to 1 card from your hand to the top of your Life cards."})
	var a5: Array = _find_tok(f5, "on_play", "hand_to_life")
	_check("hand_to_life cond", not a5.is_empty() and int(a5[1].get("cond", {}).get("life_lte", 0)) == 2, a5)
	var f6 := MtEffectParser.parse({"effect": "Your face-up Life cards are placed at the bottom of your deck instead of being added to your hand, according to the rules."})
	_check("divert rule parsed", bool(f6.get("rules", {}).get("faceup_life_to_deck", false)), f6.get("rules", {}))
	var f7 := MtEffectParser.parse({"effect": "[End of Your Turn] Trash all your face-up Life cards."})
	_check("on_end parsed", _has_tok(f7, "on_end", "trash_faceup"), "on_end")
	var f8 := MtEffectParser.parse({"effect": "[On Play] Add up to 1 of your opponent's Characters with a cost of 3 or less to the top of your opponent's Life cards face-up."})
	var a8: Array = _find_tok(f8, "on_play", "char_to_life")
	_check("char_to_life parsed", not a8.is_empty() and a8[1].get("face", "") == "up" and int(a8[1].get("max_cost", 0)) == 3, a8)

	# Resolution through _resolve_actions with a life_lte gate.
	var mt := MtMatch.new()
	mt.start(_deck(cdb, "ST01-001", "ST01"), _deck(cdb, "ST01-001", "ST01"), 0)
	var p0: MtPlayerState = mt.players[0]
	var hand0 := p0.hand.size()
	var life0 := p0.life.size()
	var gated: Array = (f5["on_play"] as Array)[0].get("actions", [])
	mt._resolve_actions(p0.leader, gated, {})
	_check("cond blocks at 5 life", p0.hand.size() == hand0 and p0.life.size() == life0, "%d/%d" % [p0.hand.size(), p0.life.size()])
	# Drop to 2 life: gate opens, first hand card moves to life face-down.
	while p0.life.size() > 2:
		p0.life.pop_back()
	mt._resolve_actions(p0.leader, gated, {})
	_check("cond opens at 2 life", p0.hand.size() == hand0 - 1 and p0.life.size() == 3, "%d/%d" % [p0.hand.size(), p0.life.size()])
	_check("moved face-down", (p0.life.back() as MtMatchCard).face_down, "face")

	# Divert rule end-to-end with the real leader text.
	var divert := _find_divert_leader(cdb)
	_check("divert leader in DB", not divert.is_empty(), divert.get("card_code", "?"))
	if not divert.is_empty():
		var mt2 := MtMatch.new()
		var d := {"leader": divert, "main": (_deck(cdb, "ST01-001", "ST01") as Dictionary).get("main", [])}
		mt2.start(d, _deck(cdb, "ST01-001", "ST01"), 0)
		var q0: MtPlayerState = mt2.players[0]
		var up := mt2._mk(cdb.get_card_data("ST01-002"), 0, MtMatchCard.ZONE_LIFE)
		up.face_down = false
		var h0 := q0.hand.size()
		q0.life = [up]
		mt2._deal_leader_damage(q0, null)
		_check("face-up diverted to deck", q0.deck.back() == up and q0.hand.size() == h0, "%d/%d" % [q0.deck.size(), q0.hand.size()])
		_check("divert skips trigger", mt2.pending_choice == null, mt2.pending_choice)

	# trash_faceup helper.
	var mt3 := MtMatch.new()
	mt3.start(_deck(cdb, "ST01-001", "ST01"), _deck(cdb, "ST01-001", "ST01"), 0)
	var r0: MtPlayerState = mt3.players[0]
	(r0.life[0] as MtMatchCard).face_down = false
	var t0 := r0.trash.size()
	_check("trash_faceup moves 1", mt3.life_trash_faceup(r0) == 1 and r0.trash.size() == t0 + 1, r0.trash.size())

func _has_tok(f: Dictionary, section: String, kind: String) -> bool:
	return not _find_tok(f, section, kind).is_empty()

func _find_tok(f: Dictionary, section: String, kind: String) -> Array:
	for tok in f.get(section, []):
		var found := _find_in_acts((tok as Dictionary).get("actions", []), kind)
		if not found.is_empty():
			return found
	return []

func _find_in_acts(actions: Array, kind: String) -> Array:
	for act in actions:
		if not (act is Array) or (act as Array).is_empty():
			continue
		if String((act as Array)[0]) == kind:
			return act
		if String((act as Array)[0]) == "pay_cost" and (act as Array).size() > 1 and (act as Array)[1] is Dictionary:
			var inner := _find_in_acts(((act as Array)[1] as Dictionary).get("actions", []), kind)
			if not inner.is_empty():
				return inner
	return []

func _find_divert_leader(cdb: Node) -> Dictionary:
	for d in cdb.get_all_card_data_as_array():
		var dd: Dictionary = d
		if String(dd.get("type", "")) == "Leader" and String(dd.get("effect", "")).contains("instead of being added to your hand"):
			return dd
	return {}

func _run_board_checks() -> void:
	if _board == null or _board.engine == null:
		_check("board engine up", false, "null")
		return
	var cards := _board.find_children("MatCard", "MtMatCard", true, false)
	_check("mat cards placed (>=3)", cards.size() >= 3, cards.size())
	var lead_zone: Control = _board._playfield.get_zone(0, "leader")
	var nlead := 0
	for c in lead_zone.find_children("MatCard", "MtMatCard", false, false):
		nlead += 1
	_check("P0 leader on mat", nlead == 1, nlead)
	_check("dialog wired", _board._trigger_dialog != null, "null?")
	_run_preduel_checks()

func _run_preduel_checks() -> void:
	var pre = load("res://scripts/ui/PreDuel.gd").new()
	root.add_child(pre)
	_check("preduel decks listed", (pre._deck_choices() as Array).size() >= 1, "decks")
	_check("preduel formats listed", (pre._fmt_choices() as Array).size() >= 8, "fmts")
	var st01: Dictionary = pre._resolve_deck({"kind": "st01"})
	_check("preduel st01 50", (st01.get("main", []) as Array).size() == 50, (st01.get("main", []) as Array).size())
	_check("rock beats scissors", pre.rps_winner("Rock", "Scissors") == 0, pre.rps_winner("Rock", "Scissors"))
	_check("paper beats rock", pre.rps_winner("Paper", "Rock") == 0, pre.rps_winner("Paper", "Rock"))
	_check("scissors beat paper", pre.rps_winner("Scissors", "Paper") == 0, pre.rps_winner("Scissors", "Paper"))
	_check("rps tie", pre.rps_winner("Paper", "Paper") == -1, pre.rps_winner("Paper", "Paper"))
	pre.play_throw("Rock", "Scissors")
	_check("win opens seat choice", pre._phase == "choose", "%s %s" % [pre._phase, pre._status.text])
	pre._reset_toss()
	pre.play_throw("Rock", "Paper")
	_check("loss lets opponent pick", pre._phase == "ready" and pre._first_player == 0, "%s %s" % [pre._phase, pre._status.text])
	pre._reset_toss()
	pre.play_throw("Scissors", "Scissors")
	_check("tie stays on throw", pre._phase == "throw", "%s %s" % [pre._phase, pre._rps_label.text])
	pre.queue_free()

func _check(label: String, cond: bool, got) -> void:
	if not cond:
		_fail += 1
		print("FAIL %-26s got=%s" % [label, str(got)])
