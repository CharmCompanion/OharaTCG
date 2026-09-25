extends SceneTree

# tests/menu_navigation_smoke.gd -- Test Main Menu (PostLogin) buttons and Duel/Puzzle header visibility

var _frame := 0
var _post_login: Control

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var scene: PackedScene = load("res://scenes/ui/PostLogin.tscn")
		_post_login = scene.instantiate()
		root.add_child(_post_login)
		return false

	if _frame == 4:
		var menu_box = _post_login.get_node_or_null("MenuVBox")
		if menu_box == null:
			printerr("FAIL: MenuVBox not found in PostLogin")
			quit(1)
			return true

		var play_btn = menu_box.get_node_or_null("PlayButton")
		var deck_btn = menu_box.get_node_or_null("DeckBuilderButton")
		var puzzle_btn = menu_box.get_node_or_null("PuzzleButton")
		var profile_btn = menu_box.get_node_or_null("ProfileButton")
		var quit_btn = menu_box.get_node_or_null("QuitButton")

		assert(play_btn != null, "PlayButton must exist")
		assert(deck_btn != null, "DeckBuilderButton must exist")
		assert(puzzle_btn != null, "PuzzleButton must exist")
		assert(profile_btn != null, "ProfileButton must exist")
		assert(quit_btn != null, "QuitButton must exist")
		print("PASS: All 5 Main Menu buttons exist in MenuVBox!")

		# Verify TestBoard duel mode header is hidden
		var duel_board = load("res://scripts/ui/TestBoard.gd").new()
		duel_board.is_puzzle_mode = false
		root.add_child(duel_board)
		var duel_header = duel_board._header
		assert(duel_header != null and not duel_header.visible, "Duel mode top bar must be HIDDEN")
		var duel_banner = duel_board._puzzle_banner
		assert(duel_banner != null and not duel_banner.visible, "Duel mode puzzle banner must be HIDDEN")
		print("PASS: Duel mode top bar and banner are HIDDEN!")
		duel_board.queue_free()

		# Verify TestBoard puzzle mode header is visible
		var puzzle_board = load("res://scripts/ui/TestBoard.gd").new()
		puzzle_board.is_puzzle_mode = true
		root.add_child(puzzle_board)
		var puzzle_header = puzzle_board._header
		assert(puzzle_header != null and puzzle_header.visible, "Puzzle mode top bar must be VISIBLE")
		var puzzle_banner = puzzle_board._puzzle_banner
		assert(puzzle_banner != null and puzzle_banner.visible, "Puzzle mode puzzle banner must be VISIBLE")
		print("PASS: Puzzle mode top bar and banner are VISIBLE!")
		puzzle_board.queue_free()

		_post_login.queue_free()
		print("MENU NAVIGATION SMOKE: OK (0 failures)")
		quit(0)
		return true

	return false
