# tests/gauntlet_smoke.gd -- level ordering (Pro > New) + self-play log harvest.
# Slow offline test by design. Writes data/ai/games.jsonl entries used by
# tools/train_eval.py. Learned files are NOT required (depth-only ordering).
extends SceneTree

const LOG_PATH := "res://data/ai/games.jsonl"
const SEEDS := [101, 202, 303]

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
		print("GAUNTLET SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _run(cdb: Node) -> void:
	var deck := _deck(cdb)
	var pro_wins := 0
	var played := 0
	for seed in SEEDS:
		var pro := MtAiLevels.new(MtAiLevels.PRO)
		(pro as MtAiLevels)._mcts.iterations = 50
		(pro as MtAiLevels)._mcts.time_budget_ms = 3000
		(pro as MtAiLevels)._mcts.card_weights = {}
		(pro as MtAiLevels)._mcts.book = {}
		(pro as MtAiLevels)._mcts.eval_weights = {}
		(pro as MtAiLevels)._mcts.move_priors = {}
		var new := MtAiLevels.new(MtAiLevels.NEW)
		var rec := MtGameLog.play(pro, new, deck, deck, seed)
		_check("pro-new completes %d" % seed, int(rec.get("winner", -1)) == 0 or int(rec.get("winner", -1)) == 1, rec.get("winner", -1))
		if int(rec.get("winner", -1)) < 0:
			continue
		played += 1
		if int(rec.get("winner", -1)) == 0:
			pro_wins += 1
		_check("log saved %d" % seed, MtGameLog.append_jsonl(LOG_PATH, rec), "append")
	_check("pro dominates new", pro_wins >= 2 and played == 3, "%d/%d" % [pro_wins, played])
	# Cheap volume for the trainer: Dummy mirror games (fast, no search).
	for seed in [11, 22]:
		var d0 := MtDummyAI.new()
		var d1 := MtDummyAI.new()
		var rec := MtGameLog.play(d0, d1, deck, deck, seed)
		if int(rec.get("winner", -1)) >= 0:
			MtGameLog.append_jsonl(LOG_PATH, rec)
	_check("harvest done", true, LOG_PATH)

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
