extends Control

var username_field: LineEdit
var password_field: LineEdit
var login_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var user_label = Label.new()
	user_label.text = "Username:"
	vbox.add_child(user_label)

	username_field = LineEdit.new()
	vbox.add_child(username_field)

	var pass_label = Label.new()
	pass_label.text = "Password:"
	vbox.add_child(pass_label)

	password_field = LineEdit.new()
	password_field.secret = true
	vbox.add_child(password_field)

	var button_row = HBoxContainer.new()
	vbox.add_child(button_row)

	login_button = Button.new()
	login_button.text = "Login"
	login_button.pressed.connect(_on_login_pressed)
	button_row.add_child(login_button)
	_connect_button_sounds(login_button)

	var settings_btn = Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_on_settings_pressed)
	button_row.add_child(settings_btn)
	_connect_button_sounds(settings_btn)

func _connect_button_sounds(button: Button) -> void:
	var ui_manager = get_tree().root.get_node("Main/UIContainer")
	if ui_manager and ui_manager.has_method("attach_sounds_to"):
		ui_manager.attach_sounds_to(button)

func _on_login_pressed() -> void:
	login_button.disabled = true
	var ui_manager = get_parent()
	if ui_manager.has_method("switch_scene"):
		ui_manager.switch_scene("res://scenes/ui/PostLogin.tscn")
	else:
		push_error("ui_manager missing 'switch_scene' method?")

func _on_settings_pressed() -> void:
	var ui_manager = get_parent()
	if ui_manager and ui_manager.has_method("switch_scene"):
		var settings_scene = load("res://scenes/ui/Settings.tscn")
		if settings_scene is PackedScene:
			var settings_instance = settings_scene.instantiate()
			if settings_instance.has_method("set_previous_scene"):
				settings_instance.set_previous_scene(get_scene_file_path())
			ui_manager.switch_scene_with_instance(settings_instance)
