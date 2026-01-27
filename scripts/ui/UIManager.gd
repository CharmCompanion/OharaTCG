extends Control

const HOVER_SOUND_PATH := "res://assets/audio/ui_hover.ogg"
const CLICK_SOUND_PATH := "res://assets/audio/ui_click.ogg"

var current_scene: Node = null
var current_scene_path: String = ""

func _ready() -> void:
	switch_scene("res://scenes/ui/Login.tscn")

func switch_scene(scene_path: String) -> void:
	var previous_path := current_scene.scene_file_path if current_scene else ""
	for child in get_children():
		child.queue_free()

	var scene_res = load(scene_path)
	if scene_res is PackedScene:
		var new_ui = scene_res.instantiate()
		add_child(new_ui)
		current_scene = new_ui
		current_scene_path = scene_path

		if new_ui.has_method("set_previous_scene"):
			new_ui.set_previous_scene(previous_path)
	else:
		push_error("UIManager.switch_scene: failed to load PackedScene: %s" % scene_path)

func switch_scene_with_instance(instance: Node) -> void:
	var previous_path := current_scene_path
	if previous_path == "" and current_scene:
		previous_path = current_scene.scene_file_path
	for child in get_children():
		child.queue_free()

	add_child(instance)
	current_scene = instance
	current_scene_path = instance.scene_file_path
	if instance.has_method("set_previous_scene"):
		instance.set_previous_scene(previous_path)

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

# ✅ Automatically attach sounds to any button
func attach_sounds_to(button: Button) -> void:
	if not button.is_in_group("ui_buttons"):
		button.add_to_group("ui_buttons")

	button.mouse_entered.connect(play_hover_sound)
	button.pressed.connect(play_click_sound)
