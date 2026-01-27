extends CardState

func _enter():
	if card.count_label:
		var zone: String = card.card_data.get("zone", "")
		var count: int = int(card.card_data.get("count", 1))
		if zone == "main" and count > 1:
			card.count_label.visible = true
			card.count_label.text = "x%d" % count
		else:
			card.count_label.visible = false
			card.count_label.text = ""
	card.pivot_offset = Vector2.ZERO

func on_mouse_entered():
	transitioned.emit("hover")
