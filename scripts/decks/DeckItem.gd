extends Button

signal deck_selected(deck_data: Dictionary)

var current_deck_data: Dictionary = {}

var deck_color_a: String = ""
var deck_color_b: String = ""
var _is_new_tile := false

const COLOR_MAP := {
	"red": Color(0.9, 0.25, 0.25),
	"green": Color(0.2, 0.8, 0.4),
	"blue": Color(0.2, 0.5, 0.9),
	"yellow": Color(0.95, 0.85, 0.3),
	"purple": Color(0.7, 0.4, 0.9),
	"black": Color(0.2, 0.2, 0.2),
	"gray": Color(0.65, 0.65, 0.68),
	"white": Color(0.9, 0.9, 0.95),
}

@onready var _background_panel: Panel = get_node_or_null("Background")
var _bg_stylebox: StyleBoxFlat = null


func _ready() -> void:
	# Ensure the tile itself captures mouse input.
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not pressed.is_connected(Callable(self, "_on_pressed")):
		pressed.connect(Callable(self, "_on_pressed"))

	# Apply a rounded panel background behind the content.
	# (Done in script to avoid .tscn sub_resource parsing issues.)
	if _background_panel:
		_bg_stylebox = StyleBoxFlat.new()
		_bg_stylebox.corner_radius_top_left = 18
		_bg_stylebox.corner_radius_top_right = 18
		_bg_stylebox.corner_radius_bottom_left = 18
		_bg_stylebox.corner_radius_bottom_right = 18
		_bg_stylebox.shadow_color = Color(0, 0, 0, 0.35)
		_bg_stylebox.shadow_size = 10
		_bg_stylebox.shadow_offset = Vector2(3, 3)
		_apply_background(false)


func _apply_background(is_new: bool) -> void:
	if _background_panel == null or _bg_stylebox == null:
		return
	# New Deck tile should be grey (not the same dark panel as normal decks).
	_bg_stylebox.bg_color = Color(0.14, 0.14, 0.14, 1.0) if is_new else Color(0.06, 0.06, 0.06, 1.0)
	_background_panel.add_theme_stylebox_override("panel", _bg_stylebox)

func setup(data: Dictionary, is_new_button: bool = false) -> void:
	current_deck_data = data
	_is_new_tile = is_new_button
	_apply_background(_is_new_tile)

	if is_new_button:
		%DeckName.text = "Create New Deck"
		%LeaderImage.texture = null
		%CardCount.text = ""
		%Legality.text = ""
		deck_color_a = "gray"
		deck_color_b = "gray"
		if has_node("Outline"):
			$Outline.queue_redraw()
		return

	%DeckName.text = str(data.get("display_name", data.get("name", "Unnamed Deck")))

	var tex: Texture2D = data.get("leader_texture", null)
	if tex == null:
		var fallback_path := str(data.get("leader_image_path", "res://icon.svg"))
		if ResourceLoader.exists(fallback_path):
			tex = load(fallback_path)
	%LeaderImage.texture = tex

	var count := int(data.get("main_total", data.get("card_count", 0)))
	%CardCount.text = str(count) + "/51"

	var is_legal := bool(data.get("is_legal", true))
	%Legality.text = "Legal" if is_legal else "Invalid"
	%Legality.add_theme_color_override("font_color", Color.GREEN if is_legal else Color.RED)

	var raw_colors = data.get("colors", [])
	var parsed: Array = []
	if typeof(raw_colors) == TYPE_ARRAY:
		for c in raw_colors:
			var s = str(c).strip_edges().to_lower()
			if s != "":
				parsed.append(s)
	elif typeof(raw_colors) == TYPE_STRING:
		var s2 = str(raw_colors).strip_edges().to_lower()
		if s2 != "":
			parsed.append(s2)

	if parsed.size() == 0:
		deck_color_a = "red"
		deck_color_b = deck_color_a
	elif parsed.size() == 1:
		deck_color_a = parsed[0]
		deck_color_b = deck_color_a
	else:
		deck_color_a = parsed[0]
		deck_color_b = parsed[1]

	# Outline is drawn by the Outline child.
	if has_node("Outline"):
		$Outline.queue_redraw()


func _on_pressed() -> void:
	deck_selected.emit(current_deck_data)


func _gui_input(event: InputEvent) -> void:
	# Make the whole tile clickable even if a child Control steals focus.
	if disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		deck_selected.emit(current_deck_data)

func _get_color(color_name: String, fallback: Color) -> Color:
	var key = color_name.to_lower()
	if COLOR_MAP.has(key):
		return COLOR_MAP[key]
	return fallback

func get_outline_colors() -> Array:
	var col_a = _get_color(deck_color_a, Color(0.8, 0.2, 0.2))
	var col_b = _get_color(deck_color_b, Color(0.2, 0.4, 0.9))
	return [col_a, col_b]
