extends SceneTree

# Phase 1 verification: runs scripted matches through the mt engine.
# Usage: godot --headless --path <project> --script res://tests/match_smoke.gd
#   --  run a few full games between AI policies, assert invariants.
#   --coverage  parse every card's effect text and print coverage stats.

var _frame := 0
var _started := false
var _mode := "games"
var _games_done := 0
var _gpd: int = 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--coverage"):
		_mode = "coverage"
	if args.has("--games"):
		_mode = "games"

func _process(_delta: float) -> bool:
	_frame += 1
	var cdb = root.get_node_or_null("CardDatabase")
	if not cdb or not cdb.is_data_loaded:
		if _frame > 900:
			printerr("TEST FAIL: CardDatabase never loaded")
			quit(1)
			return true
		return false

	if _mode == "coverage":
		if not _started:
			_started = true
			run_coverage(cdb)
			quit(0)
		return false

	if not _started:
		_started = true
		_gpd = Time.get_ticks_msec()
		var seeds := [0x2545F491, 0xDEADBEEF, 0x12345678, 0x80A91C22, 0x99C0FFEE]
		var wins := [0, 0]
		for seed in seeds:
			var won: Array = run_one_game(cdb, seed)
			if won.size() == 2:
				wins[won[0]] += 1
		print("SEED SUMMARY: %s" % str(wins))
		return false

	# A full game is synchronous; just quit after run.
	if _started:
		quit(0)
	return false

# ---- Deck building ----
func build_deck(cdb: Node) -> Dictionary:
	var chars := ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
		"ST01-007", "ST01-008", "ST01-009", "ST01-010", "ST01-011", "ST01-012", "ST01-013"]
	var evs := ["ST01-015"]
	var main: Array = []
	for code in chars:
		var d = cdb.get_card_data(code)
		if not d.is_empty():
			for i in range(4):
				main.append(d)
	for code in evs:
		# fill remaining 2 slots (8 nothing left) - trim later
		var d = cdb.get_card_data(code)
		if not d.is_empty():
			main.append(d)
			main.append(d)
	var final: Array = []
	for i in range(min(50, main.size())):
		final.append(main[i])
	var leader = cdb.get_card_data("ST01-001")
	return {"leader": leader, "main": final}

# ---- Gameplay policy (greedy, deterministic-ish) ----
var _rnd := RandomNumberGenerator.new()
var _policy_tracker: Dictionary = {}

func pick_action(engine: Object, side: int) -> Dictionary:
	var actions = engine.get_legal_actions()
	if actions.is_empty():
		return {}
	var battle_acts: Array = []
	var plays: Array = []
	var attaches: Array = []
	var activations: Array = []
	var attacks: Array = []
	var ends: Array = []
	for a in actions:
		match a.type:
			engine.ACTION_COUNTER, engine.ACTION_BLOCK, engine.ACTION_PASS_BATTLE:
				battle_acts.append(a)
			engine.ACTION_PLAY:
				plays.append(a)
			engine.ACTION_PLAY_EVENT:
				plays.append(a)
			engine.ACTION_ATTACH_DON:
				attaches.append(a)
			engine.ACTION_ACTIVATE:
				activations.append(a)
			engine.ACTION_ATTACK:
				attacks.append(a)
			engine.ACTION_END_TURN:
				ends.append(a)
	if not battle_acts.is_empty():
		# Prefer counters to win, else pass
		for a in battle_acts:
			if a.type == engine.ACTION_COUNTER:
				return a
		for a in battle_acts:
			if a.type != engine.ACTION_PASS_BATTLE:
				return a
		return {"type": engine.ACTION_PASS_BATTLE}
	if not attacks.is_empty():
		return attacks[_rnd.randi_range(0, attacks.size() - 1)]
	if not attaches.is_empty():
		return attaches[0]
	if not plays.is_empty():
		# prefer characters, highest cost first
		var best = plays[0]
		for a in plays:
			if a.type == engine.ACTION_PLAY_EVENT:
				continue
			if a.type == engine.ACTION_PLAY:
				best = a
				break
		return best
	if not activations.is_empty():
		return activations[0]
	if not ends.is_empty():
		return ends[0]
	return actions[0]

# ---- Single game ----
func run_one_game(cdb: Node, seed: int) -> Array:
	_rnd.seed = seed
	var deck_a := build_deck(cdb)
	var deck_b := build_deck(cdb)
	var mt = MtMatch.new()
	mt.rng.seed = seed
	mt.start(deck_a, deck_b, 0)

	var steps := 0
	var actions_streak := 0
	var last_action: Dictionary = {}
	while not mt.over and mt.turn < 60:
		if steps > 2000 and steps % 500 == 0:
			print("DIAG turn=%d phase=%d acts=%d last=%s" % [mt.turn, mt.phase, mt.get_legal_actions().size(), str(last_action)])
		var a := pick_action(mt, mt.active)
		if a.is_empty():
			break
		last_action = a
		var res := mt.apply(a)
		if not res.ok:
			printerr("TEST: ILLEGAL action applied: %s -> %s (%s)" % [a, res.msg, res.code])
			mt.log_lines.append("TEST ILLEGAL: %s" % str(a))
			actions_streak += 1
			if actions_streak > 3:
				break
			continue
		actions_streak = 0
		steps += 1
		if steps > 4000:
			break

	_games_done += 1
	var verdict := "WINNER P%d (%s) in %d turns / %d steps" % [mt.winner, mt.win_reason, mt.turn, steps] if mt.over else "NO RESULT (turns out)"
	print("GAME %d: %s" % [_games_done, verdict])
	var result: Array = []
	if mt.over:
		result = [mt.winner, mt.win_reason]

	# Invariants
	var p0 = mt.players[0]
	var p1 = mt.players[1]
	if p0.deck.size() + p1.deck.size() < 40:
		printerr("TEST FAIL: deck sizes implausible")
		quit(1)
	if p0.don_active > 10 or p1.don_active > 10:
		printerr("TEST FAIL: don_active > 10")
		quit(1)

	print("DON: P0 active=%d rested=%d | P1 active=%d rested=%d" % [p0.don_active, p0.don_rested, p1.don_active, p1.don_rested])
	print("Elapsed: %d ms" % (Time.get_ticks_msec() - _gpd))
	return result

# ---- Coverage scan of all card texts ----
func run_coverage(cdb: Node) -> void:
	var all = cdb.get_all_card_data_as_array()
	var fx_parser = MtEffectParser
	var stats := {
		"total": 0, "keywords": 0, "on_play": 0, "activate_main": 0, "trigger_parsed": 0,
		"draw": 0, "add_don": 0, "ko": 0, "play_self": 0, "no_block": 0, "power": 0,
		"life": 0, "on_end": 0, "rules": 0,
	}
	var seen := {}
	for d in all:
		var code := String(d.get("card_code", ""))
		if seen.has(code):
			continue
		seen[code] = true
		stats.total += 1
		var f = fx_parser.parse(d)
		if not f.keywords.is_empty():
			stats.keywords += 1
		if not f.on_play.is_empty():
			stats.on_play += 1
		if not f.activate_main.is_empty():
			stats.activate_main += 1
		if not f.triggers.is_empty() or f.play_self_on_trigger or f.get("rerun_main_on_trigger", false):
			stats.trigger_parsed += 1
		for key in ["on_play", "triggers", "on_attack", "on_ko", "activate_main", "on_main", "on_end"]:
			for tok in f.get(key, []):
				for act in (tok.get("actions", []) if tok is Dictionary else []):
					match act[0]:
						fx_parser.TOK_DRAW:
							stats.draw += 1
						fx_parser.TOK_ADD_DON:
							stats.add_don += 1
						fx_parser.TOK_ATTACH_DON:
							stats.add_don += 1
						fx_parser.TOK_KO:
							stats.ko += 1
						fx_parser.TOK_POWER:
							stats.power += 1
						fx_parser.TOK_LIFE_TO_HAND, fx_parser.TOK_DECK_TO_LIFE, fx_parser.TOK_HAND_TO_LIFE, fx_parser.TOK_TRASH_LIFE, fx_parser.TOK_FACE_LIFE, fx_parser.TOK_CHAR_TO_LIFE, fx_parser.TOK_LOOK_LIFE, fx_parser.TOK_TRASH_FACEUP:
							stats.life += 1
		if not f.get("on_end", []).is_empty():
			stats.on_end += 1
		if not f.get("rules", {}).is_empty():
			stats.rules += 1
		if f.play_self_on_trigger:
			stats.play_self += 1
		if f.no_block_with_don > 0:
			stats.no_block += 1
	print("COVERAGE (base cards=%d):" % stats.total)
	for k in ["keywords", "on_play", "activate_main", "trigger_parsed", "draw", "add_don", "ko", "power", "play_self", "no_block", "life", "on_end", "rules"]:
		print("  %-15s %d (%.1f%%)" % [k, stats[k], 100.0 * stats[k] / stats.total])