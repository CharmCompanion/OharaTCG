# Admins read open reports and ban or dismiss. The lobby keeps the record.
extends Control

var _list: VBoxContainer
var _note: Label
var _who: LineEdit

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -360
	box.offset_top = -260
	box.offset_right = 360
	box.offset_bottom = 260
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "Review"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	var row := HBoxContainer.new()
	box.add_child(row)
	_who = LineEdit.new()
	_who.placeholder_text = "Account to make admin"
	_who.custom_minimum_size = Vector2(220, 0)
	row.add_child(_who)
	var add := Button.new()
	add.text = "Add admin"
	add.pressed.connect(_on_add)
	row.add_child(add)
	_list = VBoxContainer.new()
	box.add_child(_list)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back)
	box.add_child(back)
	var accounts := get_node_or_null("/root/Accounts")
	if accounts != null and not accounts.queue_changed.is_connected(_paint):
		accounts.queue_changed.connect(_paint)
		accounts.session.connect(_on_session)
		accounts.ask_queue()
	_paint()

func _paint() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var accounts := get_node_or_null("/root/Accounts")
	if accounts == null:
		return
	if accounts.queue.is_empty():
		var empty := Label.new()
		empty.text = "No open reports."
		_list.add_child(empty)
		return
	for row in accounts.queue:
		if not row is Dictionary:
			continue
		_list.add_child(_one(accounts, row))

func _one(accounts: Node, row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "%s · %s · %s · %s" % [row.get("kind", ""), row.get("target", ""), row.get("reporter", ""), row.get("note", "")]
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(lab)
	var id := String(row.get("id", ""))
	var ban := Button.new()
	ban.text = "Ban"
	ban.pressed.connect(accounts.decide.bind(id, true))
	line.add_child(ban)
	var no := Button.new()
	no.text = "Dismiss"
	no.pressed.connect(accounts.decide.bind(id, false))
	line.add_child(no)
	return line

func _on_add() -> void:
	var accounts := get_node_or_null("/root/Accounts")
	if accounts == null or _who == null:
		return
	var note: String = accounts.add_admin(_who.text)
	if note != "":
		_note.text = note

func _on_session(ok: bool, note: String) -> void:
	_note.text = note
	if ok:
		_who.text = ""

func _on_back() -> void:
	var ui = get_parent()
	if ui and ui.has_method("switch_scene"):
		ui.switch_scene("res://scenes/ui/PostLogin.tscn")
