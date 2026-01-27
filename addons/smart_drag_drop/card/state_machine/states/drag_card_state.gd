extends CardState


func _enter():
	card.index = card.get_index()
	var parent_grid = card.get_parent()
	card.start_parent = parent_grid
	var count: int = int(card.card_data.get("count", 1))
	var zone: String = card.card_data.get("zone", "")
	var drag_full_stack := Input.is_key_pressed(KEY_SHIFT)

	# If this is a stack in the main deck (2+ copies), leave a stack behind
	# and drag a single-copy card instead.
	if zone == "main" and count > 1 and parent_grid and not drag_full_stack:
		var stack_data := card.card_data.duplicate(true)
		stack_data["count"] = count - 1
		var stack_cards := DeckManager.create_card(stack_data, card.home_field, false)
		if stack_cards.size() > 0:
			var stack_card: Card = stack_cards[0]
			stack_card.custom_minimum_size = Vector2(75, 125)
			parent_grid.add_child(stack_card)
			parent_grid.move_child(stack_card, card.index)
		# This dragged card now represents a single copy.
		card.card_data["count"] = 1
		if card.count_label:
			card.count_label.visible = false
			card.count_label.text = ""

	var container = card.home_field
	if container:
		card.reparent(container)


func on_input(event: InputEvent):
	var mouse_motion := event is InputEventMouseMotion
	var confirm = event.is_action_released("mouse_left")
	
	if mouse_motion:
		card.global_position = card.get_global_mouse_position() - card.pivot_offset
	
	if confirm:
		transitioned.emit("Release")
