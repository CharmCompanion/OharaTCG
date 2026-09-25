# res://scripts/ui/TableBg.gd
# Table surface behind the mat. Modes (player-switchable, persisted):
#   "ship" — the player's parallax ship + clouds art (Ocean pack), drifting
#            layers at different speeds + bobbing ship.
#   "wood" — warm procedural wood-felt gradient.
#   "dark" — plain dark felt.
# Layer pics are full-HD; ship is Ocean_1/Body.png (single frame on purpose:
# tail frames only composite if transparent, so they stay opt-in).

extends Control
class_name MtTableBg

const CFG := "user://playfield.cfg"
const OCEAN := "res://assets/backgrounds/Ocean and Clouds"

var mode := "ship"
var _layers: Array = []
var _t := 0.0
var _ship: TextureRect
var _ship_base_y := 0.0
var _ship_init := false

static func load_mode() -> String:
	if FileAccess.file_exists(CFG):
		var f := FileAccess.open(CFG, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				return String((d as Dictionary).get("bg", "ship"))
	return "ship"

static func save_mode(m: String) -> void:
	var d := {}
	if FileAccess.file_exists(CFG):
		var f := FileAccess.open(CFG, FileAccess.READ)
		if f != null:
			var old = JSON.parse_string(f.get_as_text())
			if old is Dictionary:
				d = old
	d["bg"] = m
	var w := FileAccess.open(CFG, FileAccess.WRITE)
	if w != null:
		w.store_string(JSON.stringify(d))

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_mode(MtTableBg.load_mode())

func apply_mode(m: String) -> void:
	mode = m
	for c in get_children():
		c.queue_free()
	_layers.clear()
	_ship = null
	if mode == "wood":
		var wood := ColorRect.new()
		wood.color = Color(0.32, 0.20, 0.11, 1.0)
		wood.set_anchors_preset(Control.PRESET_FULL_RECT)
		wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(wood)
		var sheen := ColorRect.new()
		sheen.color = Color(0.55, 0.38, 0.22, 0.25)
		sheen.anchor_left = 0.0
		sheen.anchor_top = 0.0
		sheen.anchor_right = 1.0
		sheen.anchor_bottom = 0.35
		sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sheen)
		return
	if mode == "dark":
		var dark := ColorRect.new()
		dark.color = Color(0.07, 0.06, 0.055, 1.0)
		dark.set_anchors_preset(Control.PRESET_FULL_RECT)
		dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dark)
		return
	# Ship + clouds parallax. Far layers drift slow, near layers fast.
	var defs := [
		["Ocean_8/6.png", 6.0, 1.0],
		["Ocean_6/5.png", 10.0, 1.0],
		["Ocean_4/5.png", 16.0, 1.0],
		["Ocean_2/5.png", 26.0, 0.95],
	]
	for d in defs:
		var tex := _tex(OCEAN.path_join(d[0]))
		if tex == null:
			continue
		_layers.append({"tex": tex, "speed": d[1], "x": 0.0,
			"a": _layer(), "b": _layer()})
		_set_tex(_layers.back()["a"], tex)
		_set_tex(_layers.back()["b"], tex)
	var ship_tex := _tex(OCEAN.path_join("Ocean_1/Body.png"))
	if ship_tex != null:
		_ship = TextureRect.new()
		_ship.texture = ship_tex
		_ship.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_ship.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_ship.custom_minimum_size = Vector2(420, 200)
		_ship.anchor_left = 0.5
		_ship.anchor_top = 0.42
		_ship.anchor_right = 0.5
		_ship.anchor_bottom = 0.42
		_ship.offset_left = -210.0
		_ship.offset_top = -100.0
		_ship.offset_right = 210.0
		_ship.offset_bottom = 100.0
		_ship.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ship.modulate = Color(1, 1, 1, 0.9)
		add_child(_ship)
		_ship_base_y = 0.0

func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t

func _set_tex(t: TextureRect, tex: Texture2D) -> void:
	t.texture = tex

func _process(delta: float) -> void:
	if mode != "ship" or _layers.is_empty():
		return
	_t += delta
	var w := size.x
	if w <= 0.0:
		return
	for l in _layers:
		l["x"] = fmod(float(l["x"]) + float(l["speed"]) * delta, w)
		var a: TextureRect = l["a"]
		var b: TextureRect = l["b"]
		a.position.x = -float(l["x"])
		b.position.x = -float(l["x"]) + w
		a.size.x = w
		b.size.x = w
	if _ship != null:
		if not _ship_init:
			_ship_init = true
			_ship_base_y = _ship.position.y
		_ship.position.y = _ship_base_y + sin(_t * 0.8) * 7.0
