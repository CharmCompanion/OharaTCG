extends SceneTree

# Headless end-to-end board smoke: instantiates the TestBoard UI, forces the
# AI to drive BOTH sides, waits for a completed game, and asserts sanity.
# Usage: godot --headless --path <project> --script res://tests/testboard_smoke.gd

var _frame := 0
var _board: Node
var _fail := ""

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var script = load("res://scripts/ui/TestBoard.gd")
		_board = script.new()
		root.add_child(_board)
		_board.start_headless_auto()
		return false
	if _frame < 10:
		return false

	if _frame > 6000:
		_fail = "board did not finish a game within 6000 frames"
		printerr("TEST FAIL: " + _fail)
		quit(1)
		return true

	var engine = null if _board == null else _board.engine
	if engine == null:
		return false
	if engine.is_over():
		if engine.winner != 0 and engine.winner != 1:
			_fail = "invalid winner %s" % str(engine.winner)
		elif engine.turn < 2:
			_fail = "game ended too early (turn %d)" % engine.turn
		if _fail == "":
			print("TESTBOARD OK: game ended - winner P%d (%s) after %d turns, phase=%s, battle_clear=%s" % [
				engine.winner, engine.win_reason, engine.turn,
				engine.get_phase(), not engine.in_battle()])
		else:
			printerr("TEST FAIL: " + _fail)
		quit(0 if _fail == "" else 1)
		return true
	return false