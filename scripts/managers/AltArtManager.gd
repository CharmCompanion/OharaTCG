extends Node

var dragging := false
var drag_start_x := 0.0
var hovered_card: Control = null
var alt_index_map: Dictionary = {}  # Acts as both alt_cache and active lookup

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			dragging = true
			drag_start_x = event.position.x
			hovered_card = get_card_under_mouse()
		else:
			dragging = false
			hovered_card = null

	elif event is InputEventMouseMotion and dragging and hovered_card:
		var delta_x: float = event.position.x - drag_start_x
		if abs(delta_x) > 30:
			if delta_x > 0:
				hovered_card.call_deferred("next_alt")
			else:
				hovered_card.call_deferred("prev_alt")
			dragging = false
			hovered_card = null

func get_card_under_mouse() -> Control:
	var viewport := get_viewport()
	var pos := viewport.get_mouse_position()
	var result: Control = viewport.gui_pick(pos)
	if result and result.has_method("next_alt"):
		return result
	return null

func get_alt_index(card_code: String) -> int:
	return alt_index_map.get(card_code, 0)

func set_alt_index(card_code: String, index: int) -> void:
	alt_index_map[card_code] = index
