extends Control

@onready var resolution_dropdown: OptionButton = $Panel/VBoxContainer/ResolutionRow/OptionButton
@onready var fullscreen_check: CheckBox = $Panel/VBoxContainer/FullscreenRow/CheckBox
@onready var ui_scale_slider: HSlider = $Panel/VBoxContainer/UIScaleRow/HSlider
@onready var master_volume: HSlider = $Panel/VBoxContainer/VolumeSection/MasterRow/HSlider
@onready var music_volume: HSlider = $Panel/VBoxContainer/VolumeSection/MusicRow/HSlider
@onready var sfx_volume: HSlider = $Panel/VBoxContainer/VolumeSection/SFXRow/HSlider
@onready var buttons_container: HBoxContainer = $Panel/VBoxContainer/Buttons

var previous_scene_path: String = ""

func _ready():
	var panel = $Panel
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.set_anchors_preset(Control.PRESET_CENTER)

	for slider in [ui_scale_slider, master_volume, music_volume, sfx_volume]:
		slider.custom_minimum_size = Vector2(300, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER

	ui_scale_slider.value_changed.connect(_on_setting_changed)
	master_volume.value_changed.connect(_on_setting_changed)
	music_volume.value_changed.connect(_on_setting_changed)
	sfx_volume.value_changed.connect(_on_setting_changed)
	fullscreen_check.toggled.connect(_on_setting_changed)
	resolution_dropdown.item_selected.connect(_on_setting_changed)

	_connect_button_sounds($Panel/VBoxContainer/Buttons/Back)
	_connect_button_sounds($Panel/VBoxContainer/Buttons/Reset)

	load_settings()
	populate_resolutions()

func _connect_button_sounds(button: Button) -> void:
	var ui_manager = get_tree().root.get_node("Main/UIContainer")
	if ui_manager and ui_manager.has_method("attach_sounds_to"):
		ui_manager.attach_sounds_to(button)

func populate_resolutions():
	resolution_dropdown.clear()
	resolution_dropdown.add_item("1280x720")
	resolution_dropdown.add_item("1600x900")
	resolution_dropdown.add_item("1920x1080")
	resolution_dropdown.add_item("2560x1440")
	resolution_dropdown.select(2)

func load_settings():
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	ui_scale_slider.value = ProjectSettings.get_setting("gui/theme/custom_constant/ui_scale", 1.0)
	if AudioServer.get_bus_count() > 2:
		master_volume.value = 1.0
		music_volume.value = 1.0
		sfx_volume.value = 1.0

func _on_setting_changed(_value = null):
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen_check.button_pressed else DisplayServer.WINDOW_MODE_WINDOWED
	)

	match resolution_dropdown.get_selected_id():
		0: DisplayServer.window_set_size(Vector2i(1280, 720))
		1: DisplayServer.window_set_size(Vector2i(1600, 900))
		2: DisplayServer.window_set_size(Vector2i(1920, 1080))
		3: DisplayServer.window_set_size(Vector2i(2560, 1440))

	ProjectSettings.set_setting("gui/theme/custom_constant/ui_scale", ui_scale_slider.value)
	ProjectSettings.save()

	if AudioServer.get_bus_count() > 2:
		AudioServer.set_bus_volume_db(0, linear_to_db(master_volume.value))
		AudioServer.set_bus_volume_db(1, linear_to_db(music_volume.value))
		AudioServer.set_bus_volume_db(2, linear_to_db(sfx_volume.value))

func _on_reset_pressed():
	load_settings()

func _on_back_pressed():
	if previous_scene_path != "":
		var ui_manager = get_parent()
		if ui_manager and ui_manager.has_method("switch_scene"):
			ui_manager.switch_scene(previous_scene_path)

func set_previous_scene(path: String):
	previous_scene_path = path
