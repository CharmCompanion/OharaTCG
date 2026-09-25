extends Node

func animate_card_in(card: Control) -> void:
	var tween = card.get_node_or_null("Tween")
	if tween:
		card.modulate.a = 0.0
		tween.tween_property(card, "modulate:a", 1.0, 0.3)
