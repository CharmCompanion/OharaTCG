# res://scripts/managers/DeckManager.gd
extends Node

# This scene is used to create the card visuals in the deck editor.
var card_scene: PackedScene = preload("res://scenes/cards/card.tscn")

# Property for compatibility
var is_data_loaded: bool:
	get:
		var cdb = get_node_or_null("/root/CardDatabase")
		return cdb.is_data_loaded if cdb != null else false

# --- Public API ---

# Pass-through functions to get data from the CardDatabase singleton
func get_card_data(card_id: String) -> Dictionary:
	return CardDatabase.get_card_data(card_id)

func get_all_card_data_as_array() -> Array:
	return CardDatabase.get_all_card_data_as_array()

func get_cached_texture(path: String) -> Texture2D:
	return CardDatabase.get_cached_texture(path)

# This function creates the card visuals specifically for the deck editor UI
func create_card_view(card_data: Dictionary, context: String = "") -> Control:
	if not card_scene:
		push_error("DeckManager: card_scene is not loaded! Check the path.")
		return null
		
	var card_view: Control = card_scene.instantiate()
	card_view.set_card_data(card_data)
	card_view.context = context
	return card_view
