# tests/watch_duel.gd -- spectated AI-vs-AI duel on the real board.
# Same --duel-config JSON as tests/duel_room.gd, plus optional "watch_delay".
# Windowed (no --headless): the Godot window stays open on the final board
# so you can watch hands, cards, and active play. Headless: plays through
# and quits with a DUEL RESULT line (used as a smoke test).
extends SceneTree

var _frame := 0
var _started := false
var _board: Node
var _done := false

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
		_begin(cdb)
		return false
	if _board != null and _board.engine != null and _board.engine.is_over() and not _done:
		_done = true
		var e = _board.engine
		print("DUEL RESULT winner=%d turns=%d reason=%s" % [e.winner, e.turn, e.win_reason])
		if DisplayServer.get_name() == "headless":
			quit(0)
			return true
	return false

func _cfg() -> Dictionary:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--duel-config="):
			var path := String(a).trim_prefix("--duel-config=")
			if FileAccess.file_exists(path):
				var data = JSON.parse_string(FileAccess.get_file_as_string(path))
				if data is Dictionary:
					return data
	return {}

func _begin(cdb: Node) -> void:
	var cfg := _cfg()
	if cfg.is_empty():
		print("DUEL ERROR no-config")
		quit(2)
		return
	var script = load("res://scripts/ui/TestBoard.gd")
	_board = script.new()
	root.add_child(_board)
	_board.start_watch_duel(cfg, cdb)
	if not _board.watch:
		print("DUEL ERROR illegal-deck: %s" % _board._status.text)
		quit(2)
