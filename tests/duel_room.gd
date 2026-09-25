# tests/duel_room.gd -- headless AI-vs-AI duel runner for tools/duel_room.py.
# Reads JSON config from the --duel-config=<path> user arg:
#   {"seed": int, "deck_a": {...}, "deck_b": {...}, "level_a": 0-2,
#    "level_b": 0-2, "first": 0|1, "banlist": ""|"res://..."}
# Deck spec: {"kind": "st01"} | {"kind": "meta", "index": i}
#          | {"kind": "file", "path": "res://..."}.
# Prints the full MATCH play-by-play (engine not quiet) plus a final
# DUEL RESULT line (or DUEL ERROR). One game per invocation.
extends SceneTree

var _frame := 0
var _started := false

func _process(_delta: float) -> bool:
	_frame += 1
	var cdb = root.get_node_or_null("CardDatabase")
	if not cdb or not cdb.is_data_loaded:
		if _frame > 900:
			print("DUEL ERROR no-database")
			quit(2)
			return true
		return false
	if not _started:
		_started = true
		_run(cdb)
	return false

func _cfg_path() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--duel-config="):
			return String(a).trim_prefix("--duel-config=")
	return ""

func _run(cdb: Node) -> void:
	var cfg = _load_cfg()
	if cfg.is_empty():
		print("DUEL ERROR no-config")
		quit(2)
		return
	var deck_a := _resolve_deck(cdb, cfg.get("deck_a", {}))
	var deck_b := _resolve_deck(cdb, cfg.get("deck_b", {}))
	if deck_a.is_empty() or deck_b.is_empty():
		print("DUEL ERROR bad-deck")
		quit(2)
		return
	var ban := MtDeckLoader.load_banlist(String(cfg.get("banlist", "")))
	var fmt: Dictionary = cfg.get("format", {})
	if not fmt.is_empty():
		if String(fmt.get("banlist", "")) != "":
			ban = MtDeckLoader.load_banlist(String(fmt.get("banlist", "")))
	var blocks := MtDeckLoader.load_blocks() if not (fmt.get("allowed_blocks", []) as Array).is_empty() else {}
	for side in [deck_a, deck_b]:
		var errs := MtDeckLoader.validate_deck(side, ban, fmt, blocks)
		if not errs.is_empty():
			print("DUEL ERROR illegal-deck: %s" % "; ".join(errs))
			quit(2)
			return
	var mt := MtMatch.new()
	mt.rng.seed = int(cfg.get("seed", 1))
	mt.auto_resolve_choices = true
	mt.start(deck_a, deck_b, int(cfg.get("first", 0)))
	var pa := MtAiLevels.new(clampi(int(cfg.get("level_a", 1)), 0, 2))
	var pb := MtAiLevels.new(clampi(int(cfg.get("level_b", 1)), 0, 2))
	var steps := 0
	var bad := 0
	while not mt.over and mt.turn <= 60 and steps < 8000:
		var mover := mt.mover()
		var a := {}
		if mover == 0:
			a = (pa as MtAiLevels).pick_action(mt, 0)
		else:
			a = (pb as MtAiLevels).pick_action(mt, 1)
		if (a as Dictionary).is_empty():
			break
		var res := mt.apply(a)
		if not res.get("ok", false):
			bad += 1
			if bad > 2:
				break
			continue
		steps += 1
	if mt.over:
		print("DUEL RESULT winner=%d turns=%d steps=%d reason=%s" % [
			mt.winner, mt.turn, steps, mt.win_reason])
		quit(0)
	else:
		print("DUEL RESULT winner=-1 turns=%d steps=%d reason=unfinished" % [mt.turn, steps])
		quit(3)

func _load_cfg() -> Dictionary:
	var path := _cfg_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _resolve_deck(cdb: Node, spec: Dictionary) -> Dictionary:
	match String(spec.get("kind", "st01")):
		"meta":
			return _meta_deck(cdb, int(spec.get("index", 0)))
		"file":
			var d := MtDeckLoader.load_deck_file(String(spec.get("path", "")), cdb.get_card_data)
			if (d.get("main", []) as Array).is_empty():
				return {}
			return d
		_:
			return _st01(cdb)

func _st01(cdb: Node) -> Dictionary:
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

func _meta_deck(cdb: Node, idx: int) -> Dictionary:
	if not FileAccess.file_exists("res://data/meta/decks.json"):
		return {}
	var decks = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta/decks.json"))
	if not (decks is Array) or idx < 0 or idx >= (decks as Array).size():
		return {}
	var d: Dictionary = (decks as Array)[idx]
	var codes: Array = []
	for c in d.get("main", []):
		for i in range(int((c as Dictionary).get("count", 0))):
			codes.append(String((c as Dictionary).get("code", "")))
	return MtDeckLoader.build_from_lists(String(d.get("leader", "")), codes, cdb.get_card_data)
