extends Control

const HOVER_SOUND_PATH := "res://assets/audio/ui_hover.ogg"
const CLICK_SOUND_PATH := "res://assets/audio/ui_click.ogg"

var current_scene: Node = null

func _ready() -> void:
	resized.connect(_on_resized)
	switch_scene("res://scenes/ui/Login.tscn")

func _on_resized() -> void:
	for child in get_children():
		if child is Control:
			child.set_anchors_preset(Control.PRESET_FULL_RECT)
			child.grow_horizontal = Control.GROW_DIRECTION_BOTH
			child.grow_vertical = Control.GROW_DIRECTION_BOTH
			child.offset_left = 0
			child.offset_top = 0
			child.offset_right = 0
			child.offset_bottom = 0

func switch_scene(scene_path: String) -> void:
	var previous_path := ""
	if current_scene != null:
		previous_path = current_scene.scene_file_path
	for child in get_children():
		child.queue_free()

	var scene_res = load(scene_path)
	if scene_res is PackedScene:
		var new_ui = scene_res.instantiate()
		add_child(new_ui)
		current_scene = new_ui
		if new_ui is Control:
			new_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
			new_ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
			new_ui.grow_vertical = Control.GROW_DIRECTION_BOTH
			new_ui.offset_left = 0
			new_ui.offset_top = 0
			new_ui.offset_right = 0
			new_ui.offset_bottom = 0

		if new_ui.has_method("set_previous_scene"):
			new_ui.set_previous_scene(previous_path)

func switch_scene_with_instance(instance: Node) -> void:
	for child in get_children():
		child.queue_free()

	add_child(instance)
	current_scene = instance
	if instance is Control:
		instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		instance.grow_horizontal = Control.GROW_DIRECTION_BOTH
		instance.grow_vertical = Control.GROW_DIRECTION_BOTH
		instance.offset_left = 0
		instance.offset_top = 0
		instance.offset_right = 0
		instance.offset_bottom = 0

func play_hover_sound() -> void:
	_play_ui_sound(HOVER_SOUND_PATH)

func play_click_sound() -> void:
	_play_ui_sound(CLICK_SOUND_PATH)

func _play_ui_sound(path: String) -> void:
	if ResourceLoader.exists(path):
		var sound = AudioStreamPlayer.new()
		sound.stream = load(path)
		get_tree().root.add_child(sound)
		sound.play()
		sound.finished.connect(Callable(sound, "queue_free"))

# Automatically attach sounds to any button
func attach_sounds_to(button: Button) -> void:
	if not button.is_in_group("ui_buttons"):
		button.add_to_group("ui_buttons")

	button.mouse_entered.connect(play_hover_sound)
	button.pressed.connect(play_click_sound)
