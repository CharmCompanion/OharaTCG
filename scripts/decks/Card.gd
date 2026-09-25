extends Control

signal request_add_to_main(card: Dictionary)
signal request_remove_from_main(card: Dictionary)

var card_data: Dictionary = {}
var context: String = "search"
var _variant_index: int = 0

@onready var name_lbl: Label = $NameLabel
@onready var image_btn: TextureButton = $CardImage
@onready var overlay: ColorRect = $ColorRect
@onready var state_lbl: Label = $Label
@onready var holo_layer: TextureRect = $Holo

const HOLO_SHADER := preload("res://shaders/holo_card.gdshader")

func _ready():
	mouse_filter = MOUSE_FILTER_PASS
	_image_btn_filter_mode()

func _image_btn_filter_mode():
	if image_btn:
		image_btn.mouse_filter = MOUSE_FILTER_IGNORE

func set_card_data(data: Dictionary, new_context: String = "search"):
	card_data = data
	context = new_context
	_variant_index = int(data.get("variant_index", 0))
	_update_view()

func _update_view():
	if not is_inside_tree() or card_data.is_empty():
		return

	var card_name: String = card_data.get("name", card_data.get("card_name", ""))
	name_lbl.text = card_name

	var image_path: String = card_data.get("image_path", "")
	var texture = CardDatabase.get_cached_texture(image_path)
	if texture:
		image_btn.texture_normal = texture
		name_lbl.visible = false
	else:
		image_btn.texture_normal = null
		name_lbl.visible = true

	_update_holo()
	_update_state_label()

func _update_state_label():
	state_lbl.visible = false
	state_lbl.text = context

func _update_holo():
	if not holo_layer: return

	var enabled = _collect_view_holo()
	holo_layer.visible = enabled
	if not enabled:
		return

	var texture = image_btn.texture_normal
	if not texture:
		holo_layer.visible = false
		return
	holo_layer.texture = texture

	var mat: ShaderMaterial = holo_layer.material

	var grade := String(card_data.get("foil_grade", ""))
	var parallel := 0.0
	var prize := 0.0
	match grade:
		"prize":
			prize = 1.0
			parallel = 1.0
		"parallel":
			parallel = 1.0

	mat.set_shader_parameter("u_source", texture)
	mat.set_shader_parameter("u_strength", 1.0)
	mat.set_shader_parameter("u_parallel", parallel)
	mat.set_shader_parameter("u_prize", prize)

func _collect_view_holo() -> bool:
	# Manual override (Ctrl+click toggles it per card_code in the editor)
	if CollectionManager.is_foiled(card_data.get("card_code", "")):
		return true

	var grade := String(card_data.get("foil_grade", ""))
	if grade == "prize" or grade == "parallel":
		return true

	var rarity := String(card_data.get("rarity", ""))
	return rarity in ["SecretRare", "TreasureRare", "SuperRare"]

func set_foil_enabled(enabled: bool):
	var code: String = card_data.get("card_code", "")
	if code.is_empty(): return
	CollectionManager.set_foiled(code, enabled)
	_update_holo()

func _set_variant(index: int):
	if card_data.is_empty(): return
	var code: String = card_data.get("card_code", "")
	var variants := CardDatabase.get_variants(code)
	if variants.size() <= 1: return
	_variant_index = wrapi(index, 0, variants.size())
	card_data = variants[_variant_index]
	_update_view()

func next_alt():
	if card_data.is_empty(): return
	_set_variant(_variant_index + 1)

func prev_alt():
	if card_data.is_empty(): return
	_set_variant(_variant_index - 1)

# --- Input handlers (wired in card.tscn) ---
func _on_gui_input(ev: InputEvent):
	if ev is InputEventMouseButton and ev.pressed:
		if ev.ctrl_pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			set_foil_enabled(not CollectionManager.is_foiled(card_data.get("card_code", "")))
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			emit_signal("request_add_to_main", card_data)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			emit_signal("request_remove_from_main", card_data)

func _on_mouse_entered():
	pass

func _on_mouse_exited():
	pass
