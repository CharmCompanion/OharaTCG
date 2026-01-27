extends ColorRect

var phases = [
	{"color": Color(0, 0, 0, 0), "duration": 40.0},       # Day (no tint)
	{"color": Color(1.0, 0.5, 0.4, 0.35), "duration": 25.0}, # Dusk (rosy peach-orange sunset)
	{"color": Color(0, 0, 0.2, 0.4), "duration": 35.0},   # Night (blue tint)
	{"color": Color(0, 0, 0, 0.6), "duration": 30.0},     # Midnight (dark overlay)
	{"color": Color(1, 0.8, 0.6, 0.2), "duration": 20.0}, # Dawn (light orange tint)
]

var current_phase := 0

func _ready():
	start_cycle()

func start_cycle():
	var tween = create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	var phase = phases[current_phase]
	tween.tween_property(self, "color", phase.color, phase.duration)
	tween.finished.connect(advance_phase)

func advance_phase():
	current_phase = (current_phase + 1) % phases.size()
	start_cycle()
