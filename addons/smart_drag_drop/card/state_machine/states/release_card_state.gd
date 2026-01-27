extends CardState

func _enter():
	# Let the DeckField decide what grid this card should
	# belong to based on drop areas and overlapping cards.
	if card.home_field and card.home_field.has_method("card_reposition"):
		card.home_field.card_reposition(card)
	else:
		# Fallback to original position if something is misconfigured.
		if card.home_field and card.home_field.has_method("return_card_starting_position"):
			card.home_field.return_card_starting_position(card)

	transitioned.emit("idle")
