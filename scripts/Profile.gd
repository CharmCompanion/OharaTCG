extends Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	# Avatar button
	_create_button("Avatar", Callable(self, "_on_avatar_pressed"), vbox)

	# Decks button
	_create_button("Decks", Callable(self, "_on_decks_pressed"), vbox)

func _create_button(text: String, callback: Callable, parent: Node) -> void:
	var btn = Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(callback)

	# Optional: Add UI sound hookup
	var ui = get_tree().root.get_node("Main/UIContainer")
	if ui and ui.has_method("attach_sounds_to"):
		ui.attach_sounds_to(btn)

	parent.add_child(btn)

func _on_avatar_pressed() -> void:
	print("Avatar button pressed!")

func _on_decks_pressed() -> void:
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene"):
		var sel_scene = load("res://scenes/ui/DeckSelection.tscn")
		if sel_scene is PackedScene:
			var sel_instance = sel_scene.instantiate()
			if sel_instance.has_method("set_previous_scene"):
				sel_instance.set_previous_scene(get_scene_file_path())
			ui_manager.switch_scene_with_instance(sel_instance)
