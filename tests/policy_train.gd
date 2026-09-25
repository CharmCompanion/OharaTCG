# tests/policy_train.gd -- self-play with the deck-aware policy, then
# tools/train_eval.py rebuilds the book, priors, and eval weights.
extends SceneTree

const LOG_PATH := "res://data/ai/games.jsonl"
const SEEDS := [7101, 7102, 7103, 7104, 7105, 7106, 7107, 7108]

var _frame := 0
var _started := false

func _process(_delta: float) -> bool:
	_frame += 1
	var cdb = root.get_node_or_null("CardDatabase")
	if not cdb or not cdb.is_data_loaded:
		if _frame > 900:
			printerr("TRAIN FAIL: CardDatabase never loaded")
			quit(1)
			return true
		return false
	if not _started:
		_started = true
		_run(cdb)
		quit(0)
	return false

func _run(cdb: Node) -> void:
	var decks := _decks(cdb)
	var saved := 0
	for i in range(SEEDS.size()):
		var seed: int = SEEDS[i]
		var p0 := MtAiLevels.new(MtAiLevels.NEW)
		var p1 := MtAiLevels.new(MtAiLevels.NEW)
		p0._dummy.epsilon = 0.0
		p1._dummy.epsilon = 0.0
		var rec := MtGameLog.play(p0, p1, decks[i % decks.size()], decks[(i + 1) % decks.size()], seed)
		var winner := int(rec.get("winner", -1))
		if winner < 0:
			print("skip seed %d" % seed)
			continue
		if MtGameLog.append_jsonl(LOG_PATH, rec):
			saved += 1
			print("saved seed %d winner P%d turns %d" % [seed, winner, int(rec.get("turns", 0))])
	print("POLICY TRAIN: saved %d" % saved)

func _decks(cdb: Node) -> Array:
	var out: Array = []
	var starter := MtDeckLoader.load_deck_file("res://data/decks/ST01-StrawHats.json", cdb.get_card_data)
	if not (starter.get("main", []) as Array).is_empty():
		out.append(starter)
	if FileAccess.file_exists("res://data/meta/decks.json"):
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta/decks.json"))
		if raw is Array:
			var n := 0
			for d in raw:
				if n >= 2:
					break
				var codes: Array = []
				for c in (d as Dictionary).get("main", []):
					for _i in range(int((c as Dictionary).get("count", 0))):
						codes.append(String((c as Dictionary).get("code", "")))
				var built := MtDeckLoader.build_from_lists(String((d as Dictionary).get("leader", "")), codes, cdb.get_card_data)
				if (built.get("main", []) as Array).size() == 50:
					out.append(built)
					n += 1
	if out.is_empty():
		out.append(starter)
	return out
