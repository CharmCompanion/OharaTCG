extends Sprite2D

@export var bob_distance := 1.75
@export var bob_duration := 2

var start_y := 0.0
var going_down := true

func _ready():
	start_y = position.y
	bob()

func bob():
	var target_y: float = start_y + bob_distance if going_down else start_y - bob_distance
	if !going_down:
		target_y = start_y - bob_distance
	else:
		target_y = start_y + bob_distance

	going_down = !going_down

	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", target_y, bob_duration)
	tween.finished.connect(bob)
