class_name Card
extends Control

@onready var card_image: TextureButton = $CardImage
@onready var count_label: Label = $CountLabel
@onready var state_machine: CardStateMachine = $CardStateMachine
@onready var drop_point_detector: Area2D = $DropPointDetector
@onready var card_detector: Area2D = $CardsDetector

const SEARCH_CARD_SIZE := Vector2(75, 125)

var home_field
var card_data: Dictionary = {}
var alt_textures: Array[Texture2D] = []
var current_alt_index := 0
var index: int = 0
var start_parent: Node = null

func _ready():
	_apply_fixed_size(SEARCH_CARD_SIZE)
	update_texture()
	# Ensure count label starts hidden until setup applies zone/count rules.
	if count_label:
		count_label.visible = false
		count_label.text = ""
	state_machine.start("idle") # changed from _start()

func setup(data: Dictionary, field: Node):
	card_data = data.duplicate(true)
	home_field = field
	# Ensure textures or container layouts can't inflate card size.
	_apply_fixed_size(SEARCH_CARD_SIZE)

	var card_code := card_data.get("card_code", "")
	current_alt_index = AltArtManager.get_alt_index(card_code)

	DeckManager.assign_card_image_path(card_data)
	alt_textures.clear()

	var base_path := card_data.get("image_path", "")
	var base_tex = ResourceLoader.load(base_path, "Texture2D")
	if base_tex == null:
		base_tex = ResourceLoader.load(DeckManager.BASE_IMAGE_PATH, "Texture2D")
		card_data["image_path"] = DeckManager.BASE_IMAGE_PATH
	if base_tex:
		alt_textures.append(base_tex)

	var set_code := card_data.get("set_code", "")
	var i := 1
	while true:
		var alt_path := "res://assets/cards/Alts/%s/%s_alt%d.png" % [set_code, card_code, i]
		if ResourceLoader.exists(alt_path):
			var alt_tex = ResourceLoader.load(alt_path, "Texture2D")
			if alt_tex is Texture2D:
				alt_textures.append(alt_tex)
			i += 1
		else:
			break

	update_texture()

	# Only show count if not in search zone
	if count_label:
		var zone = card_data.get("zone", "")
		var count: int = int(card_data.get("count", 1))
		if zone == "main" and count > 1:
			count_label.visible = true
			count_label.text = "x%d" % count
		else:
			count_label.visible = false
			count_label.text = ""

func _apply_fixed_size(target_size: Vector2) -> void:
	custom_minimum_size = target_size

	if card_image:
		card_image.custom_minimum_size = target_size
		# Godot versions differ; only set if the property exists.
		for prop in card_image.get_property_list():
			if prop.get("name") == "ignore_texture_size":
				card_image.set("ignore_texture_size", true)
				break

func update_texture():
	if not card_image:
		return

	if alt_textures.size() == 0:
		var fallback_tex = ResourceLoader.load(DeckManager.BASE_IMAGE_PATH, "Texture2D")
		if fallback_tex:
			card_image.texture_normal = fallback_tex
		return

	if alt_textures.size() > current_alt_index:
		var tex: Texture2D = alt_textures[current_alt_index]
		card_image.texture_normal = tex

func get_card_data() -> Dictionary:
	var data = card_data.duplicate(true)
	data["alt_index"] = current_alt_index
	return data

func _input(event: InputEvent) -> void:
	if state_machine and state_machine.has_method("on_input"):
		state_machine.on_input(event)

func _on_gui_input(event: InputEvent) -> void:
	if state_machine and state_machine.has_method("on_gui_input"):
		state_machine.on_gui_input(event)

func _on_mouse_entered() -> void:
	if state_machine and state_machine.has_method("on_mouse_entered"):
		state_machine.on_mouse_entered()

func _on_mouse_exited() -> void:
	if state_machine and state_machine.has_method("on_mouse_exited"):
		state_machine.on_mouse_exited()


func _on_card_image_gui_input(event: InputEvent) -> void:
	_on_gui_input(event)


func _on_card_image_mouse_entered() -> void:
	_on_mouse_entered()


func _on_card_image_mouse_exited() -> void:
	_on_mouse_exited()
