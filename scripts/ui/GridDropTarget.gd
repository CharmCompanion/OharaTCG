extends GridContainer
# no class_name to avoid collisions with any existing global class

@export_enum("search","main","don") var role: String = "search"
var decks: Node = null

func _ready() -> void:
	add_to_group("drop_targets")
	mouse_filter = Control.MOUSE_FILTER_PASS
	if decks == null:
		decks = get_tree().get_first_node_in_group("decks_host")

func can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY: return false
	if String(data.get("type","")) != "card_drag": return false
	if role == "don":
		var card: Dictionary = data.get("payload", {})
		return String(card.get("type","")) == "DON!!"
	return true

func drop_data(pos: Vector2, data: Variant) -> void:
	if decks == null: return
	var card: Dictionary = data.get("payload", {})
	match role:
		"main":
			decks.call_deferred("_add_card_to_main", card)
		"don":
			var idx := _slot_index_from_pos(pos)
			decks.call_deferred("_set_don_card_at", idx, card)
		_:
			pass

func _slot_index_from_pos(local_pos: Vector2) -> int:
	var cols: int = max(1, columns)
	var w: float = max(1.0, size.x)
	var cell_w: float = w / float(cols)
	var idx := int(floor(clamp(local_pos.x, 0.0, w - 1.0) / cell_w))
	return clamp(idx, 0, cols - 1)
