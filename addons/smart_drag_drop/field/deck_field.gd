extends MarginContainer

@onready var card_drop_area_right: Area2D = $CardDropAreaRight
@onready var card_drop_area_left: Area2D = $CardDropAreaLeft
@onready var card_drop_area_bottom: Area2D = $CardDropAreaBottom

@onready var search_grid: GridContainer = $CardDropAreaLeft/SearchGrid
@onready var main_grid: GridContainer = $CardDropAreaRight/MainDeckGrid
@onready var don_grid: GridContainer = $CardDropAreaBottom/DonDeckGrid

func _ready():
	for grid in [search_grid, main_grid, don_grid]:
		if grid == null:
			continue
		for child in grid.get_children():
			if child is Card:
				child.home_field = self

func return_card_starting_position(card: Card):
	var grid: Node = card.start_parent if card.start_parent else card.get_parent()
	if grid == null:
		return

	# Ensure the card is actually a child of the original grid again
	# before trying to move it back to its stored index.
	if card.get_parent() != grid:
		card.reparent(grid)

	if grid.has_method("move_child"):
		var child_count := grid.get_child_count()
		var idx := card.index
		if idx < 0:
			idx = 0
		elif idx >= child_count:
			idx = child_count - 1
		grid.move_child(card, idx)

func set_new_card(card: Card):
	card_reposition(card)

func card_reposition(card: Card):
	var field_areas = card.drop_point_detector.get_overlapping_areas()
	var cards_areas = card.card_detector.get_overlapping_areas()
	var target_grid = null
	var index = 0

	if field_areas.has(card_drop_area_left):
		target_grid = search_grid
	elif field_areas.has(card_drop_area_right):
		target_grid = main_grid
	elif field_areas.has(card_drop_area_bottom):
		target_grid = don_grid
	else:
		# Fallback: if we didn't hit a drop area but we are over
		# another card, infer the grid from that card's parent.
		if cards_areas.size() > 0:
			var other_card_node = cards_areas[0].get_parent()
			if other_card_node is Card:
				var parent_grid = other_card_node.get_parent()
				if parent_grid and parent_grid.has_method("add_child"):
					target_grid = parent_grid
		if target_grid == null:
			return_card_starting_position(card)
			return

	var card_type = str(card.card_data.get("type", ""))
	var is_don = card_type.to_upper().contains("DON") or str(card.card_data.get("card_code", "")).begins_with("DON")

	# Prevent DON!! cards from entering the main deck.
	if target_grid == main_grid and is_don:
		return_card_starting_position(card)
		return

	# If dropping into the main deck, try to merge into an existing stack
	# (same card_code) instead of keeping separate entries.
	# This also fixes the "split a stack and can't stack it back" case.
	if target_grid == main_grid:
		var card_code = card.card_data.get("card_code", "")
		if card_code != "":
			for child in main_grid.get_children():
				if child is Card and child != card:
					var existing_code = child.card_data.get("card_code", "")
					if existing_code == card_code:
						var existing_count: int = int(child.card_data.get("count", 1))
						var incoming_count: int = int(card.card_data.get("count", 1))
						var new_count: int = existing_count + incoming_count
						child.card_data["count"] = new_count
						if child.count_label:
							if new_count > 1:
								child.count_label.visible = true
								child.count_label.text = "x%d" % new_count
							else:
								child.count_label.visible = false
								child.count_label.text = ""
						# This dropped card is now merged into the stack.
						card.queue_free()
						return

	if cards_areas.size() == 1:
		index = cards_areas[0].get_parent().get_index()
	elif cards_areas.size() > 1:
		index = min(cards_areas[0].get_parent().get_index(), cards_areas[1].get_parent().get_index()) + 1
	else:
		index = target_grid.get_child_count()

	# Update zone and texture based on destination grid
	if target_grid == search_grid:
		card.card_data["zone"] = "search"
		card.custom_minimum_size = Vector2(75, 125)
		if card.card_image:
			card.card_image.custom_minimum_size = Vector2(75, 125)
	elif target_grid == main_grid:
		card.card_data["zone"] = "main"
		card.custom_minimum_size = Vector2(75, 125)
		if card.card_image:
			card.card_image.custom_minimum_size = Vector2(75, 125)
	elif target_grid == don_grid:
		card.card_data["zone"] = "don"
		card.custom_minimum_size = Vector2(75, 125)
		if card.card_image:
			card.card_image.custom_minimum_size = Vector2(75, 125)

	DeckManager.assign_card_image_path(card.card_data)
	card.update_texture()

	card.start_parent = target_grid
	card.reparent(target_grid)
	target_grid.move_child(card, index)
