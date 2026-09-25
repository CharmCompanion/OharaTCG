extends Control

var username_field: LineEdit
var password_field: LineEdit
var login_button: Button
var _note: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	_build_ui()

func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.offset_left = -240
	vbox.offset_top = -320
	vbox.offset_right = 240
	vbox.offset_bottom = 320
	vbox.custom_minimum_size = Vector2(480, 0)
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var logo = TextureRect.new()
	logo.texture = load("res://assets/OharaTCG.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 160)
	vbox.add_child(logo)

	var user_label = Label.new()
	user_label.text = "Username:"
	vbox.add_child(user_label)

	username_field = LineEdit.new()
	vbox.add_child(username_field)

	var phone := OS.get_name() == "Android"
	if not phone:
		var pass_label = Label.new()
		pass_label.text = "Password:"
		vbox.add_child(pass_label)
		password_field = LineEdit.new()
		password_field.secret = true
		vbox.add_child(password_field)
		var server_label = Label.new()
		server_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var accounts := get_node_or_null("/root/Accounts")
		var host := ""
		if accounts != null:
			host = accounts.host()
		server_label.text = "Server: %s" % host if host != "" else "Server address is not set."
		vbox.add_child(server_label)
	else:
		var folder := Label.new()
		folder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		folder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		folder.text = "Copy assets/cards into Downloads/OharaTCG/cards"
		vbox.add_child(folder)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_note)

	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)

	login_button = Button.new()
	login_button.text = "Play" if OS.get_name() == "Android" else "Login"
	login_button.custom_minimum_size = Vector2(140, 38)
	login_button.pressed.connect(_on_login_pressed)
	button_row.add_child(login_button)
	_connect_button_sounds(login_button)

	var settings_btn = Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(140, 38)
	settings_btn.pressed.connect(_on_settings_pressed)
	button_row.add_child(settings_btn)
	_connect_button_sounds(settings_btn)

func _connect_button_sounds(button: Button) -> void:
	var ui_manager = get_tree().root.get_node("Main/UIContainer")
	if ui_manager and ui_manager.has_method("attach_sounds_to"):
		ui_manager.attach_sounds_to(button)

func _on_login_pressed() -> void:
	var user := username_field.text.strip_edges()
	if user == "":
		_note.text = "Enter a username."
		return
	if OS.get_name() == "Android":
		ProfileManager.set_username(user)
		ProfileManager.touch_login()
		_enter()
		return
	var pw := ""
	if password_field != null:
		pw = password_field.text
	if pw == "":
		_note.text = "Enter a username and a password."
		return
	var accounts := get_node_or_null("/root/Accounts")
	if accounts == null:
		return
	var host := String(accounts.host())
	if host == "":
		_note.text = "The server address is not set."
		return
	var digest := pw.sha256_text()
	var wait: String = accounts.begin_remote(String(accounts.dial()), user, digest)
	if wait != "":
		_note.text = wait
		return
	_note.text = "Checking the account server..."
	login_button.disabled = true
	if not accounts.session.is_connected(_on_session):
		accounts.session.connect(_on_session)

func _on_session(ok: bool, note: String) -> void:
	login_button.disabled = false
	if not ok:
		_note.text = note
		return
	_enter()

func _enter() -> void:
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
