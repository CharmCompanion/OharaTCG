extends Control

var chat_ui: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	build_ui()
	load_chat_ui()

func build_ui() -> void:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(outer_vbox)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 185)
	outer_vbox.add_child(spacer)

	var vbox = VBoxContainer.new()
	vbox.name = "PostLoginVBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 10)
	outer_vbox.add_child(vbox)

	# Buttons
	create_button("Duel", Callable(self, "_on_duel_pressed"), vbox)
	create_button("Decks", Callable(self, "_on_decks_pressed"), vbox)
	create_button("Shop", Callable(self, "_on_shop_pressed"), vbox)
	create_button("Profile", Callable(self, "_on_profile_pressed"), vbox)
	create_button("Settings", Callable(self, "_on_settings_pressed"), vbox)


func create_button(text: String, callback: Callable, parent: Node) -> void:
	var btn = Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(callback)
	parent.add_child(btn)

	_connect_button_sounds(btn)

func _connect_button_sounds(button: Button) -> void:
	var ui_manager = get_tree().root.get_node("Main/UIContainer")
	if ui_manager and ui_manager.has_method("attach_sounds_to"):
		ui_manager.attach_sounds_to(button)

func load_chat_ui() -> void:
	if chat_ui: return
	var chat_scene = load("res://scenes/ui/ChatUI.tscn")
	if chat_scene is PackedScene:
		chat_ui = chat_scene.instantiate()
		chat_ui.mouse_filter = Control.MOUSE_FILTER_PASS
		chat_ui.z_index = 100
		add_child(chat_ui)

# Button Logic
func _on_duel_pressed() -> void:
	print("Duel button pressed!")

func _on_decks_pressed() -> void:
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene"):
		var sel_scene = load("res://scenes/DeckSelection.tscn")
		if sel_scene is PackedScene:
			var sel_instance = sel_scene.instantiate()
			if sel_instance.has_method("set_previous_scene"):
				sel_instance.set_previous_scene(get_scene_file_path())
			ui_manager.switch_scene_with_instance(sel_instance)

func _on_shop_pressed() -> void:
	print("Shop button pressed!")

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
