extends Node

func can_drop_data(position: Vector2, data) -> bool:
	return true

func drop_data(position: Vector2, data):
	if data and data.has_method("release_to_zone"):
		data.release_to_zone(self)
