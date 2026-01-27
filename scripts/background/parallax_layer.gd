extends ParallaxLayer

@export var scroll_speed := 8.0  # Adjust as needed

func _process(delta):
	motion_offset.x += scroll_speed * delta
