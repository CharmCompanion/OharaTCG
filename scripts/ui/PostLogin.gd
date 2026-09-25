extends Control

var chat_ui: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Single menu: the TSCN buttons only (Play/DeckBuilder/Puzzle/Profile/Quit).
	_wire_button("MenuVBox/PlayButton", _on_play_pressed)
	_wire_button("MenuVBox/DeckBuilderButton", _on_deck_builder_button_pressed)
	_wire_button("MenuVBox/PuzzleButton", _on_puzzle_pressed)
	_wire_button("MenuVBox/ProfileButton", _on_profile_pressed)
	_wire_button("MenuVBox/SettingsButton", _on_settings_pressed)
	_wire_button("MenuVBox/ShopButton", _on_shop_pressed)
	_wire_button("MenuVBox/ReplaysButton", _on_replays_pressed)
	_wire_button("MenuVBox/QuitButton", _on_quit_button_pressed)
	var review := Button.new()
	review.text = "Review"
	review.visible = ProfileManager.role == "admin" and OS.get_name() != "Android"
	review.pressed.connect(_on_review_pressed)
	var menu := get_node("MenuVBox")
	var quit := menu.get_node("QuitButton")
	menu.add_child(review)
	menu.move_child(review, quit.get_index())
	# NOTE: the Content Updater was removed from this menu entirely
	# (it kept resurfacing). Devs run tools/fetch_meta.py directly.
	load_chat_ui()

func _wire_button(path: String, cb: Callable) -> void:
	var b := get_node_or_null(path)
	if b != null and not (b as Button).pressed.is_connected(cb):
		(b as Button).pressed.connect(cb)

func load_chat_ui() -> void:
	if OS.get_name() == "Android" or chat_ui:
		return
	var chat_scene = load("res://scenes/ui/ChatUI.tscn")
	if chat_scene is PackedScene:
		chat_ui = chat_scene.instantiate()
		chat_ui.mouse_filter = Control.MOUSE_FILTER_PASS
		chat_ui.z_index = 100
		add_child(chat_ui)

# --- Button Logic ---

func _on_duel_pressed() -> void:
	if not DataManager.is_data_loaded:
		print("Card data is not loaded yet. Please wait.")
		return
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var board = load("res://scripts/ui/TestBoard.gd").new()
		ui_manager.switch_scene_with_instance(board)

func _on_decks_pressed() -> void:
	# Corrected to use the new DataManager singleton
	if not DataManager.is_data_loaded:
		print("Card data is not loaded yet. Please wait.")
		return

	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene"):
		var decks_scene = load("res://scenes/ui/DeckEdit.tscn")
		if decks_scene is PackedScene:
			var decks_instance = decks_scene.instantiate()
			if decks_instance.has_method("set_previous_scene"):
				decks_instance.set_previous_scene(get_scene_file_path())
			ui_manager.switch_scene_with_instance(decks_instance)

func _on_shop_pressed() -> void:
	if not DataManager.is_data_loaded:
		print("Card data is not loaded yet. Please wait.")
		return
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		ui_manager.switch_scene_with_instance(load("res://scripts/ui/Shop.gd").new())

func _on_replays_pressed() -> void:
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		ui_manager.switch_scene_with_instance(load("res://scripts/ui/Replays.gd").new())

func _on_profile_pressed() -> void:
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene"):
		ui_manager.switch_scene("res://scenes/Profile.tscn")

func _on_settings_pressed() -> void:
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene"):
		var settings_scene = load("res://scenes/ui/Settings.tscn")
		if settings_scene is PackedScene:
			var settings_instance = settings_scene.instantiate()
			if settings_instance.has_method("set_previous_scene"):
				settings_instance.set_previous_scene(get_scene_file_path())
			ui_manager.switch_scene_with_instance(settings_instance)

# --- TSCN-wired menu buttons (single wiring; see PostLogin.tscn) ---

func _on_deck_builder_button_pressed() -> void:
	_on_decks_pressed()

func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _on_play_pressed() -> void:
	# Pre-duel setup screen: who duels, which decks, format, who goes first.
	if not DataManager.is_data_loaded:
		print("Card data is not loaded yet. Please wait.")
		return
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var pre = load("res://scripts/ui/PreDuel.gd").new()
		ui_manager.switch_scene_with_instance(pre)

func _on_puzzle_pressed() -> void:
	if not DataManager.is_data_loaded:
		print("Card data is not loaded yet. Please wait.")
		return
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var board = load("res://scripts/ui/TestBoard.gd").new()
		board.is_puzzle_mode = true
		ui_manager.switch_scene_with_instance(board)

func _on_review_pressed() -> void:
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		ui_manager.switch_scene_with_instance(load("res://scripts/ui/Review.gd").new())
