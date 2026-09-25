# res://scripts/managers/DataManager.gd
# Compatibility shim delegating to CardDatabase
extends Node

var is_data_loaded: bool:
	get:
		return CardDatabase.is_data_loaded

func _ready():
	print("DataManager: Operating as compatibility shim for CardDatabase.")

func get_card_data(card_id: String) -> Dictionary:
	return CardDatabase.get_card_data(card_id)

func get_all_card_data_as_array() -> Array:
	return CardDatabase.get_all_card_data_as_array()

func get_cached_texture(path: String) -> Texture2D:
	return CardDatabase.get_cached_texture(path)

func get_card_image_path(card_data) -> String:
	if card_data is Dictionary:
		return card_data.get("image_path", "res://assets/cards/Base/BaseCard.png")
	return "res://assets/cards/Base/BaseCard.png"

func create_card_view(card_data: Dictionary, context: String = "") -> Control:
	var dm = get_node_or_null("/root/DeckManager")
	if dm and dm.has_method("create_card_view"):
		return dm.create_card_view(card_data, context)
	return null
