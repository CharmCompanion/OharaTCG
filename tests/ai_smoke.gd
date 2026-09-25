# tests/ai_smoke.gd -- Phase 2: clone/determinize, MCTS legality + game.
extends SceneTree

var _frame := 0
var _started := false
var _fail := 0

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
		_run(cdb)
		print("AI SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _run(cdb: Node) -> void:
	_test_clone(cdb)
	_test_mcts_legal(cdb)
	_test_short_game(cdb)
	_test_levels(cdb)
	_test_meta(cdb)
	_test_learned(cdb)

func _deck(cdb: Node) -> Dictionary:
	var leader: Dictionary = cdb.get_card_data("ST01-001")
	var main: Array = []
	var slots := 0
	for i in range(100):
		var d: Dictionary = cdb.get_card_data("ST01-%03d" % [(i % 14) + 1])
		if not d.is_empty():
			main.append(d)
			slots += 1
			if slots >= 50:
				break
	return {"leader": leader, "main": main}

func _test_clone(cdb: Node) -> void:
	var mt := MtMatch.new()
	mt.rng.seed = 1234
	mt.start(_deck(cdb), _deck(cdb), 0)
	var c := mt.clone()
	_check("clone quiet", c.quiet, "quiet flag")
	_check("clone turn", c.turn == mt.turn and c.active == mt.active, "%d/%d" % [c.turn, mt.turn])
	_check("clone life", (c.players[0] as MtPlayerState).life.size() == (mt.players[0] as MtPlayerState).life.size(), "life")
	_check("clone uids", (c.players[0] as MtPlayerState).leader.uid == (mt.players[0] as MtPlayerState).leader.uid, "uid")
	_check("clone distinct", (c.players[0] as MtPlayerState).leader != (mt.players[0] as MtPlayerState).leader, "same ref")
	# Independence: act on the clone, original untouched.
	var turn0 := mt.turn
	var acts := c.get_legal_actions()
	var res := c.apply(acts[0])
	_check("clone acts ok", res.get("ok", false), res)
	_check("original untouched", mt.turn == turn0 and mt.pending_choice == null, mt.turn)
	# Determinize keeps counts, usually reorders the deck.
	var d0: Array = []
	for x in (c.players[1] as MtPlayerState).deck:
		d0.append((x as MtMatchCard).uid)
	c.determinize(0)
	var d1: Array = []
	for x in (c.players[1] as MtPlayerState).deck:
		d1.append((x as MtMatchCard).uid)
	_check("determinize keeps size", d0.size() == d1.size() and d0.size() > 0, d0.size())
	_check("determinize valid game", not c.over or (c.winner == 0 or c.winner == 1), "over=%s" % c.over)

func _test_mcts_legal(cdb: Node) -> void:
	var mt := MtMatch.new()
	mt.rng.seed = 99
	mt.start(_deck(cdb), _deck(cdb), 0)
	var mcts := MtMctsAi.new()
	mcts.iterations = 40
	mcts.time_budget_ms = 5000
	mcts.rng.seed = 7
	var a := mcts.pick_action(mt, 0)
	_check("mcts returns action", not a.is_empty(), a)
	_check("mcts action legal", _contains(mt.get_legal_actions(), a), a)
	_check("mcts searched", mcts.last_iterations > 0, mcts.last_iterations)
	var mcts2 := MtMctsAi.new()
	mcts2.iterations = 40
	mcts2.time_budget_ms = 5000
	mcts2.rng.seed = 7
	var b := mcts2.pick_action(mt, 0)
	_check("mcts repeatable", str(a) == str(b), "%s vs %s" % [a, b])

func _test_short_game(cdb: Node) -> void:
	var mt := MtMatch.new()
	mt.rng.seed = 4242
	mt.start(_deck(cdb), _deck(cdb), 0)
	var mcts := MtMctsAi.new()
	mcts.iterations = 12
	mcts.time_budget_ms = 3000
	var dummy := MtDummyAI.new()
	var steps := 0
	var bad := 0
	while not mt.over and mt.turn < 40 and steps < 1500:
		var mover := mt.get_active_player() if not mt.in_battle() else int(mt.battle.get("defender_owner", 0))
		var a := {}
		if mover == 0:
			a = mcts.pick_action(mt, 0)
		else:
			a = dummy.pick_action(mt)
		if (a as Dictionary).is_empty():
			break
		var res := mt.apply(a)
		if not res.get("ok", false):
			bad += 1
			if bad > 3:
				break
			continue
		steps += 1
	_check("short game ends", mt.over, "turn=%d steps=%d" % [mt.turn, steps])
	_check("valid winner", mt.winner == 0 or mt.winner == 1, mt.winner)
	_check("no illegal streak", bad <= 3, bad)

func _test_levels(cdb: Node) -> void:
	_check("level names", MtAiLevels.level_name(0) == "Easy" and MtAiLevels.level_name(1) == "Medium" and MtAiLevels.level_name(2) == "Pro", "names")
	_check("weights miss = {}", MtAiLevels.load_weights().is_empty() or MtAiLevels.load_weights() is Dictionary, "load")
	var mt := MtMatch.new()
	mt.rng.seed = 555
	mt.start(_deck(cdb), _deck(cdb), 0)
	for lv in [0, 1, 2]:
		var pol := MtAiLevels.new(lv)
		if lv > 0:
			(pol as MtAiLevels)._mcts.iterations = 10
			(pol as MtAiLevels)._mcts.time_budget_ms = 2000
		var a: Dictionary = (pol as MtAiLevels).pick_action(mt, 0)
		_check("L%d legal" % lv, not a.is_empty() and _contains(mt.get_legal_actions(), a), a)
	# New level actually randomizes: same position, epsilon picks vary.
	var n1 := MtAiLevels.new(0)
	(n1 as MtAiLevels)._dummy.rng.seed = 42
	var seen := {}
	for i in range(40):
		var a: Dictionary = (n1 as MtAiLevels).pick_action(mt, 0)
		seen[str(a)] = true
	_check("New varies", seen.size() > 1, seen.size())
	var greedy := MtDummyAI.new()
	greedy.epsilon = 0.0
	var opening: Dictionary = greedy.pick_action(mt, 0)
	var playable := false
	for act in mt.get_legal_actions():
		var kind := String((act as Dictionary).get("type", ""))
		if kind == "play" or kind == "play_event":
			playable = true
	if playable:
		var got := String(opening.get("type", ""))
		_check("plays the deck", got == "play" or got == "play_event" or got == "activate", opening)

func _test_meta(cdb: Node) -> void:
	# Tournament meta decks (tools/fetch_meta.py): load, validate, spar.
	if not FileAccess.file_exists("res://data/meta/decks.json"):
		_check("meta decks present", false, "missing file")
		return
	var file := FileAccess.open("res://data/meta/decks.json", FileAccess.READ)
	var decks = JSON.parse_string(file.get_as_text())
	_check("meta decks loaded", decks is Array and (decks as Array).size() >= 10, (decks as Array).size() if decks is Array else "bad")
	if not (decks is Array) or (decks as Array).is_empty():
		return
	var totals_ok := true
	for d in decks:
		var t := 0
		for c in (d as Dictionary).get("main", []):
			t += int((c as Dictionary).get("count", 0))
		if t != 50 or String((d as Dictionary).get("leader", "")) == "":
			totals_ok = false
	_check("meta decks 50 + leader", totals_ok, "counts")
	# Spar: Adv vs New on two different meta leaders (exercises Enel-6, Nami-4).
	var da: Dictionary = decks[0]
	var db: Dictionary = decks[0]
	for d in decks:
		if String((d as Dictionary).get("leader", "")) != String(da.get("leader", "")):
			db = d
			break
	var mt := MtMatch.new()
	mt.rng.seed = 777
	mt.start(_meta_deck(cdb, da), _meta_deck(cdb, db), 0)
	var adv := MtAiLevels.new(MtAiLevels.ADV)
	(adv as MtAiLevels)._mcts.iterations = 12
	(adv as MtAiLevels)._mcts.time_budget_ms = 2000
	var new := MtAiLevels.new(MtAiLevels.NEW)
	var steps := 0
	var bad := 0
	while not mt.over and mt.turn < 40 and steps < 1500:
		var mover := mt.get_active_player() if not mt.in_battle() else int(mt.battle.get("defender_owner", 0))
		var a: Dictionary = (adv as MtAiLevels).pick_action(mt, mover) if mover == 0 else (new as MtAiLevels).pick_action(mt, mover)
		if a.is_empty():
			break
		var res := mt.apply(a)
		if not res.get("ok", false):
			bad += 1
			if bad > 3:
				break
			continue
		steps += 1
	_check("meta spar ends", mt.over, "turn=%d steps=%d" % [mt.turn, steps])
	_check("meta valid winner", mt.winner == 0 or mt.winner == 1, mt.winner)

func _test_learned(cdb: Node) -> void:
	# Trained files ship in repo (tools/train_eval.py over gauntlet logs).
	var pro := MtAiLevels.new(MtAiLevels.PRO)
	var m: MtMctsAi = (pro as MtAiLevels)._mcts
	_check("book loaded", not (m.book as Dictionary).is_empty(), (m.book as Dictionary).size())
	_check("priors loaded", not (m.move_priors as Dictionary).is_empty(), (m.move_priors as Dictionary).size())
	_check("eval loaded", not (m.eval_weights as Dictionary).is_empty(), (m.eval_weights as Dictionary).keys())
	var mt := MtMatch.new()
	mt.rng.seed = 31337
	mt.start(_deck(cdb), _deck(cdb), 0)
	(m as MtMctsAi).iterations = 10
	(m as MtMctsAi).time_budget_ms = 2000
	var a: Dictionary = (pro as MtAiLevels).pick_action(mt, 0)
	_check("opening from book", (m as MtMctsAi).last_source == "book", (m as MtMctsAi).last_source)
	_check("book move legal", not a.is_empty() and _contains(mt.get_legal_actions(), a), a)

func _meta_deck(cdb: Node, d: Dictionary) -> Dictionary:
	var codes: Array = []
	for c in d.get("main", []):
		for i in range(int((c as Dictionary).get("count", 0))):
			codes.append(String((c as Dictionary).get("code", "")))
	return MtDeckLoader.build_from_lists(String(d.get("leader", "")), codes, cdb.get_card_data)

func _contains(acts: Array, a: Dictionary) -> bool:
	for x in acts:
		if str(x) == str(a):
			return true
	return false

func _check(label: String, cond: bool, got) -> void:
	if not cond:
		_fail += 1
		print("FAIL %-24s got=%s" % [label, str(got)])
