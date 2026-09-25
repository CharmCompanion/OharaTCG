extends SceneTree

# tests/turn_surrender_smoke.gd -- Test End Turn and Surrender button functionality

var _frame := 0
var _board: Node
var _fail := ""

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var script = load("res://scripts/ui/TestBoard.gd")
		_board = script.new()
		root.add_child(_board)
		return false

	if _frame == 5:
		# Check PlayField and bot mat
		var pf = _board.get_node_or_null("PlayField")
		if pf == null:
			printerr("FAIL: PlayField null")
			quit(1)
			return true
		var bot_mat = pf.get_node_or_null("BottomMat")
		if bot_mat == null:
			printerr("FAIL: BottomMat null")
			quit(1)
			return true

		# Check buttons exist in HUD
		var hud = bot_mat.get_node_or_null("PlayerHUD")
		if hud == null or not hud.visible:
			printerr("FAIL: PlayerHUD not visible on BottomMat")
			quit(1)
			return true

		var end_btn = hud.find_child("EndTurnButton", true, false)
		var surr_btn = hud.find_child("SurrenderButton", true, false)
		if end_btn == null:
			printerr("FAIL: EndTurnButton not found")
			quit(1)
			return true
		if surr_btn == null:
			printerr("FAIL: SurrenderButton not found")
			quit(1)
			return true

		print("PASS: EndTurnButton and SurrenderButton found in PlayerHUD")

		# Test Surrender
		surr_btn.emit_signal("pressed")
		return false

	if _frame == 7:
		var engine = _board.engine
		if engine == null or not engine.is_over() or engine.winner != 1:
			printerr("FAIL: Surrender did not end match with winner 1")
			quit(1)
			return true
		print("PASS: Surrender button successfully surrendered the match to P1")
		print("TURN SURRENDER SMOKE: OK (0 failures)")
		quit(0)
		return true

	return false
