extends CanvasLayer

var label: Label

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(200, 80)
	add_child(panel)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)
	panel.visible = false

func show_hover(text: String, at_screen: Vector2) -> void:
	var panel := get_child(0) as Panel
	label.text = text
	panel.global_position = at_screen + Vector2(12, 12)
	panel.visible = true

func hide_hover() -> void:
	var panel := get_child(0) as Panel
	panel.visible = false
