class_name Field
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
	var grid = card.get_parent()
	grid.move_child(card, card.index)

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
		return

	if cards_areas.size() == 1:
		index = cards_areas[0].get_parent().get_index()
	elif cards_areas.size() > 1:
		index = min(cards_areas[0].get_parent().get_index(), cards_areas[1].get_parent().get_index()) + 1
	else:
		index = target_grid.get_child_count()

	card.reparent(target_grid)
	target_grid.move_child(card, index)
