# tests/puzzle_smoke.gd -- lethal ("win this turn") puzzle pipeline.
# Plays Pro-vs-New, mines the winner's run-up, verifies a forced same-turn
# win, and writes data/puzzles/pack1.json. Slow offline test by design.
extends SceneTree

const PACK_PATH := "res://data/puzzles/pack1.json"
const SEEDS := [31337, 777001, 90210]
const REC_ITERS := 40
const VER_ITERS := 80
const VER_SEEDS := 2

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
		print("PUZZLE SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _run(cdb: Node) -> void:
	var deck := _deck(cdb)
	var made: Array = []
	for seed in SEEDS:
		var rec := _record(deck, seed)
		if rec.is_empty():
			continue
		var cands := MtPuzzles.mine(rec["log"], 0, 12)
		# Newest first: closest to the winning blow verifies fastest.
		cands.reverse()
		for c in cands.slice(0, 3):
			var idx := int((c as Dictionary).get("index", 0))
			var prefix := (rec["log"] as Array).slice(0, idx + 1)
			var acts := []
			for e in prefix:
				acts.append((e as Dictionary).get("action", {}))
			if MtPuzzles.verify(seed, deck, deck, 0, acts, 0,
					int((c as Dictionary).get("turn", 0)), VER_ITERS, VER_SEEDS):
				var par: int = (rec["log"] as Array).size() - idx - 1
				made.append(MtPuzzles.emit_puzzle(
					"Win this turn (mate in %d)" % maxi(par, 1),
					seed, deck, deck, 0, acts, 0,
					int((c as Dictionary).get("turn", 0)), maxi(par, 1)))
				break
		if not made.is_empty():
			break
	_check("puzzle mined+verified", not made.is_empty(), made.size())
	if made.is_empty():
		return
	# Replay determinism: same seed+prefix reproduces the position.
	var p: Dictionary = made[0]
	var r1: MtMatch = MtPuzzles.replay(int(p["seed"]), p["deck_a"], p["deck_b"], int(p["first"]), p["prefix"])
	var r2: MtMatch = MtPuzzles.replay(int(p["seed"]), p["deck_a"], p["deck_b"], int(p["first"]), p["prefix"])
	_check("replay works", r1 != null and r2 != null, "null?")
	if r1 != null and r2 != null:
		_check("replay deterministic", _sig(r1) == _sig(r2), _sig(r1))
		_check("puzzle side to move", r1.get_active_player() == 0 or int(r1.battle.get("defender_owner", 0)) == 0, "mover")
	DirAccess.make_dir_recursive_absolute("res://data/puzzles")
	var file := FileAccess.open(PACK_PATH, FileAccess.WRITE)
	if file == null:
		_check("pack writable", false, PACK_PATH)
	else:
		file.store_string(JSON.stringify(_sanitize(made), "\t"))
		file.flush()
		file.close()
		_check("pack written", true, PACK_PATH)
	_run_board_load(made[0])

# Card texts can carry raw control chars (tabs, 0x07 bullets) that
# JSON.stringify emits verbatim but JSON.parse_string rejects (Python's json
# tolerates them; Godot's does not). Scrub every sub-32 code in strings.
func _sanitize(v):
	if v is String:
		var s := ""
		for i in range((v as String).length()):
			var code := (v as String).unicode_at(i)
			if code < 32:
				s += " "
			else:
				s += (v as String)[i]
		return s
	if v is Array:
		var out := []
		for e in v:
			out.append(_sanitize(e))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _sanitize(v[k])
		return d
	return v

func _run_board_load(p: Dictionary) -> void:
	var script = load("res://scripts/ui/TestBoard.gd")
	var b = script.new()
	root.add_child(b)
	b._load_puzzle(p)
	_check("board puzzle loads", b.engine != null and b.engine.turn == int(p.get("turn", 0)), b.engine.turn if b.engine != null else "null")
	_check("board banner set", (b._puzzle_banner.text as String).begins_with("PUZZLE"), b._puzzle_banner.text)
	b._rebuild()
	_check("board puzzle cards", b.find_children("MatCard", "MtMatCard", true, false).size() >= 3, "cards")
	b.queue_free()

func _sig(mt: MtMatch) -> String:
	var p0: MtPlayerState = mt.players[0]
	var p1: MtPlayerState = mt.players[1]
	return "%d/%d/%d/%d/%d/%d/%d/%d" % [mt.turn, mt.active, p0.life.size(),
		p0.hand.size(), p0.field.size(), p1.life.size(), p1.hand.size(), p1.field.size()]

func _record(deck: Dictionary, seed: int) -> Dictionary:
	var mt := MtMatch.new()
	mt.rng.seed = seed
	mt.auto_resolve_choices = true
	mt.start(deck, deck, 0)
	var pro := MtMctsAi.new()
	pro.iterations = REC_ITERS
	pro.time_budget_ms = 30000
	pro.rng.seed = seed + 1
	var dummy := MtDummyAI.new()
	var log: Array = []
	var steps := 0
	var bad := 0
	while not mt.over and mt.turn <= 30 and steps < 1500:
		var mover := mt.get_active_player() if not mt.in_battle() else int(mt.battle.get("defender_owner", 0))
		var a := {}
		if mover == 0:
			a = pro.pick_action(mt, 0)
		else:
			a = dummy.pick_action(mt)
		if (a as Dictionary).is_empty():
			return {}
		var res := mt.apply(a)
		if not res.get("ok", false):
			bad += 1
			if bad > 2:
				return {}
			continue
		log.append({"action": a, "mover": mover, "turn": mt.turn, "over": mt.over})
		steps += 1
	if mt.over and mt.winner == 0:
		return {"log": log}
	return {}

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

func _check(label: String, cond: bool, got) -> void:
	if not cond:
		_fail += 1
		print("FAIL %-24s got=%s" % [label, str(got)])
