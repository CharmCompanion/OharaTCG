# Lists saved duels and plays them back on the board.
extends Control

const BACK_SCENE := "res://scenes/ui/PostLogin.tscn"
const DIR := "user://replays"

var _box: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80
	root.offset_top = 40
	root.offset_right = -80
	root.offset_bottom = -40
	add_child(root)
	var title := Label.new()
	title.text = "REPLAYS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	_box = VBoxContainer.new()
	root.add_child(_box)
	var back := Button.new()
	back.text = "< Back"
	back.pressed.connect(_on_back)
	root.add_child(back)
	_fill()

func _fill() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var names: Array = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			names.append(f)
		f = dir.get_next()
	names.sort()
	names.reverse()
	if names.is_empty():
		var empty := Label.new()
		empty.text = "No saved duels yet. Finish a game and it will show up here."
		_box.add_child(empty)
		return
	for name in names:
		var b := Button.new()
		b.text = String(name)
		b.pressed.connect(_open.bind(String(name)))
		_box.add_child(b)

func _open(name: String) -> void:
	var raw := FileAccess.get_file_as_string(DIR.path_join(name))
	var data = JSON.parse_string(raw)
	if not data is Dictionary:
		return
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene_with_instance"):
		var board = load("res://scripts/ui/TestBoard.gd").new()
		ui_manager.switch_scene_with_instance(board)
		board.start_replay(data)

func _on_back() -> void:
	var parent := get_parent()
	if parent and parent.has_method("switch_scene"):
		parent.switch_scene(BACK_SCENE)
	else:
		queue_free()
