class_name ChatUI
extends Control

var toggle_button: Button
var panel: PanelContainer
var vbox: VBoxContainer
var tab_bar: TabBar
var chat_log: RichTextLabel
var chat_input: LineEdit

var player_name: String = "Player"
var current_channel: String = "general"
var chat_visible: bool = true  # Start expanded

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	build_ui()
	setup_chat_logic()
	update_chat_visibility()
	if not ChatManager.message_received.is_connected(_on_remote_chat):
		ChatManager.message_received.connect(_on_remote_chat)

func build_ui() -> void:
	# Chat Panel base
	panel = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.35
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_bottom = -16
	panel.offset_top = -260
	panel.custom_minimum_size = Vector2(400, 240)
	add_child(panel)

	# VBox inside panel
	vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Horizontal container for tab bar and toggle button
	var tab_row = HBoxContainer.new()
	tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tab_row)

	# Toggle Button inside the tab row, left of the tab bar
	toggle_button = Button.new()
	toggle_button.text = "[−]"
	toggle_button.custom_minimum_size = Vector2(24, 24)
	toggle_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tab_row.add_child(toggle_button)

	# Tab Bar
	tab_bar = TabBar.new()
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_bar)

	# Chat Log
	chat_log = RichTextLabel.new()
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_log.scroll_following = true
	chat_log.scroll_active = true
	vbox.add_child(chat_log)

	# Input
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Type a message..."
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(chat_input)
	var report_b := Button.new()
	report_b.text = "Report this chat"
	report_b.pressed.connect(_on_report_chat)
	vbox.add_child(report_b)

func setup_chat_logic() -> void:
	toggle_button.pressed.connect(_on_toggle_pressed)
	chat_input.text_submitted.connect(_on_chat_submitted)
	tab_bar.tab_changed.connect(_on_tab_changed)

	tab_bar.clear_tabs()
	tab_bar.add_tab("General")
	tab_bar.add_tab("Friends")
	tab_bar.add_tab("Crew")
	tab_bar.add_tab("Match")

	set_chat_channel("general")

func _on_toggle_pressed() -> void:
	chat_visible = !chat_visible
	update_chat_visibility()

func update_chat_visibility() -> void:
	if chat_visible:
		panel.custom_minimum_size = Vector2(400, 240)
		panel.offset_top = -260
		chat_log.visible = true
		chat_input.visible = true
		tab_bar.visible = true
	else:
		panel.custom_minimum_size = Vector2(48, 32)
		panel.offset_top = -48
		chat_log.visible = false
		chat_input.visible = false
		tab_bar.visible = false

	toggle_button.text = "[−]" if chat_visible else "[+]"

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return

	if text.begins_with("/"):
		handle_command(text)
	else:
		var message = "[%s][%s]: %s" % [current_channel, player_name, text]
		ChatManager.post_message(current_channel, message)

	chat_input.clear()
	chat_input.grab_focus()

func _on_remote_chat(channel: String, message: String) -> void:
	if channel == current_channel:
		display_message(message)

func _on_tab_changed(tab_index: int) -> void:
	var tab_name = tab_bar.get_tab_title(tab_index).to_lower()
	set_chat_channel(tab_name)

func set_chat_channel(channel: String) -> void:
	current_channel = channel
	chat_log.clear()
	chat_log.append_text("[Switched to #%s channel]\n" % channel)
	if ChatManager.channels.has(channel):
		for msg in ChatManager.channels[channel]:
			display_message(msg)

func display_message(msg: String) -> void:
	chat_log.append_text(msg + "\n")

func _on_report_chat() -> void:
	var social := get_node_or_null("/root/Social")
	if social == null:
		return
	var line := ""
	if current_channel == "match" and social.match_chat.size() > 0:
		line = String((social.match_chat.back() as Dictionary).get("text", ""))
	elif ChatManager.channels.has(current_channel) and ChatManager.channels[current_channel].size() > 0:
		line = String(ChatManager.channels[current_channel].back())
	social.file_report("chat", player_name, "Reported a chat line.", {
		"channel": current_channel, "line": line,
	})
	display_message("Report saved.")

func handle_command(cmd: String) -> void:
	var parts = cmd.strip_edges().split(" ", false)
	match parts[0]:
		"/clear":
			chat_log.clear()
		"/shrug":
			_on_chat_submitted("¯\\_(ツ)_/¯")
		"/help":
			display_message("Available commands: /clear, /shrug, /help, /whisper <name> <msg>")
		"/whisper":
			if parts.size() >= 3:
				var target = parts[1]
				var msg_text = " ".join(parts.slice(2))
				var line := "[whisper → %s][%s]: %s" % [target, player_name, msg_text]
				ChatManager.post_message("friends", line)
			else:
				display_message("Usage: /whisper <name> <message>")
		_:
			display_message("Unknown command: %s" % cmd)
