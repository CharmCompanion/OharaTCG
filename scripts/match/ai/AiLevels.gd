# res://scripts/match/ai/AiLevels.gd
# Difficulty levels with one unified interface: pick_action(engine, viewer).
#   EASY (0): deck-aware policy, 22% random blunders. Fast.
#   MEDIUM (1): MCTS light (80 iters / 150 ms). Rollouts use the same policy.
#   PRO (2): MCTS deep (600 iters / 600 ms) + book, priors, and eval weights.
# Meta priors come from data/meta/card_weights.json (tournament deck data);
# missing file = zero weights (pure search). Same class_name convention.

class_name MtAiLevels

extends RefCounted

const NEW := 0
const ADV := 1
const PRO := 2

const WEIGHTS_PATH := "res://data/meta/card_weights.json"
const BOOK_PATH := "res://data/ai/book.json"
const PRIORS_PATH := "res://data/ai/move_priors.json"
const EVAL_PATH := "res://data/ai/eval_weights.json"

var level := ADV
var _dummy := MtDummyAI.new()
var _mcts := MtMctsAi.new()

static func names_line_up(leader: String, note: String) -> bool:
	var a := leader.to_lower()
	var b := note.to_lower()
	if a == "" or b.length() < 3:
		return false
	if a.contains(b) or b.contains(a):
		return true
	# Article nicknames that are not a piece of the printed leader name.
	var nick := {
		"doffy": "doflamingo",
		"croc": "crocodile",
		"boa": "hancock",
		"aokiji": "kuzan",
		"akainu": "sakazuki",
		"kizaru": "borsalino",
		"big mom": "linlin",
	}
	for key in nick:
		if b.contains(key) and a.contains(String(nick[key])):
			return true
	return false

static func prefer_first(my_name: String, opp_name: String) -> int:
	# 1 = go first, 0 = go second, -1 = no report. Reports are matchup
	# writeups, used only when both leader names line up.
	var data := load_json("res://data/ai/matchup_notes.json")
	var me := my_name.to_lower()
	var opp := opp_name.to_lower()
	if me == "" or opp == "":
		return -1
	for n in data.get("notes", []):
		if not (n is Dictionary):
			continue
		var s := String(n.get("self", "")).to_lower()
		var o := String(n.get("opp", "")).to_lower()
		if s.length() < 3 or o.length() < 3:
			continue
		if names_line_up(me, s) and names_line_up(opp, o):
			var seat := String(n.get("seat", ""))
			if seat == "first":
				return 1
			if seat == "second":
				return 0
	return -1

static func level_name(lv: int) -> String:
	match lv:
		NEW:
			return "Easy"
		ADV:
			return "Medium"
		_:
			return "Pro"

static func load_weights() -> Dictionary:
	if not FileAccess.file_exists(WEIGHTS_PATH):
		return {}
	var file := FileAccess.open(WEIGHTS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		return data.get("weights", {})
	return {}

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}

func _init(p_level: int = ADV) -> void:
	set_level(p_level)

func set_level(p_level: int) -> void:
	level = clampi(p_level, NEW, PRO)
	_dummy.epsilon = 0.22 if level == NEW else 0.0
	# Both search tiers share all learned data; depth is the dial.
	var meta := MtAiLevels.load_weights()
	_dummy.card_weights = meta
	_mcts.move_priors = MtAiLevels.load_json(PRIORS_PATH).get("priors", {})
	_mcts.eval_weights = MtAiLevels.load_json(EVAL_PATH).get("weights", {})
	_mcts.book = MtAiLevels.load_json(BOOK_PATH).get("entries", {})
	_mcts.card_weights = meta
	if level == ADV:
		_mcts.iterations = 80
		_mcts.time_budget_ms = 150
	elif level == PRO:
		_mcts.iterations = 600
		_mcts.time_budget_ms = 600

func pick_action(engine: Object, viewer: int = 1) -> Dictionary:
	if level == NEW:
		return _dummy.pick_action(engine)
	return _mcts.pick_action(engine, viewer)

func new_game() -> void:
	_mcts.new_game()
