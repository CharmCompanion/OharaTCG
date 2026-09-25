# res://scripts/ui/MatCard.gd
# Lightweight clickable and draggable card widget for mat zones + hand.
# Clean, borderless edge-to-edge art. Details show in top-left Inspector on hover.
# Supports attached DON stack, -90 deg rotation for rested state, hover focus growth,
# and right-click context menu signal.

extends PanelContainer
class_name MtMatCard

signal clicked(uid: String, role: String)
signal hovered(uid: String)
signal drag_start(card: MtMatCard, global_pos: Vector2)
signal drag_move(global_pos: Vector2)
signal drag_end(card: MtMatCard, global_pos: Vector2)
signal context_requested(card: MtMatCard, global_pos: Vector2)

const BASE_ART := "res://assets/cards/Base/BaseCard.png"
const REGULAR_BACK := "res://assets/cards/Backs/CardBackRegular.png"
const DON_BACK := "res://assets/cards/Backs/CardBackDon.png"
const HOLO_SHADER := preload("res://shaders/holo_card.gdshader")

static var sleeve_file := ""
static var _art_cache := {}

var uid := ""
var role := ""
var is_rested := false
var don_count := 0

var _art: TextureRect
var _holo: TextureRect
var _name_l: Label
var _sub_l: Label
var _dict := {}
var _don_layer: Control
var _don_art_tex: Texture2D = null

var _style_normal: StyleBoxFlat
var _style_sel: StyleBoxFlat

var _drag_pressing := false
var _drag_started := false
var _drag_start_pos := Vector2.ZERO
var _hover_tween: Tween = null

static func art_for(p_image_path: String) -> Texture2D:
	var path := p_image_path.strip_edges()
	if path.is_empty():
		path = BASE_ART
	if _art_cache.has(path):
		return _art_cache[path]
	var tex: Texture2D = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var db = tree.root.get_node_or_null("CardDatabase")
		if db != null:
			tex = db.get_cached_texture(path)
	if tex == null and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and path != BASE_ART:
		return art_for(BASE_ART)
	_art_cache[path] = tex
	return tex

static func sleeve_art() -> Texture2D:
	if _art_cache.has("__sleeve__"):
		return _art_cache["__sleeve__"]
	var tex: Texture2D = null
	if DirAccess.dir_exists_absolute("res://assets/sleeves"):
		var dir := DirAccess.open("res://assets/sleeves")
		if dir != null:
			dir.list_dir_begin()
			var fn := dir.get_next()
			while fn != "":
				if fn.ends_with(".png") or fn.ends_with(".jpg"):
					var path := "res://assets/sleeves/" + fn
					if ResourceLoader.exists(path):
						tex = load(path) as Texture2D
						if tex != null:
							sleeve_file = path
							break
				fn = dir.get_next()
	if tex == null and ResourceLoader.exists(REGULAR_BACK):
		tex = load(REGULAR_BACK) as Texture2D
		sleeve_file = REGULAR_BACK
	if tex == null:
		tex = load(BASE_ART) as Texture2D
	_art_cache["__sleeve__"] = tex
	return tex

static func don_sleeve_art() -> Texture2D:
	if _art_cache.has("__don_sleeve__"):
		return _art_cache["__don_sleeve__"]
	var tex: Texture2D = null
	if ResourceLoader.exists(DON_BACK):
		tex = load(DON_BACK) as Texture2D
	if tex == null:
		tex = load(BASE_ART) as Texture2D
	_art_cache["__don_sleeve__"] = tex
	return tex

func _ready() -> void:
	if not _dict.is_empty() and _art != null:
		_apply_holo(_art.texture, _dict)
	resized.connect(_on_resized)
	_on_resized()
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

func _on_resized() -> void:
	if size.x > 0 and size.y > 0:
		pivot_offset = size / 2.0
	elif custom_minimum_size.x > 0 and custom_minimum_size.y > 0:
		pivot_offset = custom_minimum_size / 2.0
	else:
		pivot_offset = Vector2(45, 63)

func setup(p_uid: String, p_role: String, title: String, sub: String,
		p_image_path: String, rested: bool = false, selected: bool = false,
		p_card_dict: Dictionary = {}, p_don_count: int = 0, p_don_art: Texture2D = null) -> void:
	uid = p_uid
	role = p_role
	_dict = p_card_dict
	is_rested = rested
	don_count = p_don_count
	_don_art_tex = p_don_art
	_build()
	if size.x > 0 and size.y > 0:
		pivot_offset = size / 2.0
	elif custom_minimum_size.x > 0 and custom_minimum_size.y > 0:
		pivot_offset = custom_minimum_size / 2.0
	else:
		pivot_offset = Vector2(45, 63)
	var tex := MtMatCard.art_for(p_image_path)
	_art.texture = tex
	var t := title
	if t.length() > 14:
		t = t.substr(0, 13) + "…"
	_name_l.text = t
	var s := sub
	if not String(p_card_dict.get("trigger", "")).is_empty():
		s += " ·TRG"
	_sub_l.text = s
	_apply_holo(tex, p_card_dict)
	
	# Rested cards turn -90 degrees (landscape orientation like Life cards)
	if rested:
		rotation_degrees = -90.0
		modulate = Color(0.92, 0.92, 0.96, 1.0)
	else:
		rotation_degrees = 0.0
		modulate = Color(1.0, 1.0, 1.0, 1.0)
	
	if don_count > 0:
		_refresh_attached_don()
	elif _don_layer != null:
		for c in _don_layer.get_children():
			c.queue_free()
	
	set_selected(selected)
	name = "MatCard"

func title_text() -> String:
	return _name_l.text if _name_l != null else ""

func image_path() -> String:
	return String(_dict.get("image_path", ""))

func card_dict() -> Dictionary:
	return _dict

func _refresh_attached_don() -> void:
	if _don_layer == null:
		return
	for c in _don_layer.get_children():
		c.queue_free()
	var tex := _don_art_tex if _don_art_tex != null else don_sleeve_art()
	for i in range(don_count):
		var d := TextureRect.new()
		d.texture = tex
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		d.show_behind_parent = true
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.set_anchors_preset(Control.PRESET_FULL_RECT)
		var offset_x := float(i + 1) * 8.0
		d.offset_left = offset_x
		d.offset_right = offset_x
		d.offset_top = 0.0
		d.offset_bottom = 0.0
		_don_layer.add_child(d)

func _apply_holo(tex: Texture2D, p_card_dict: Dictionary) -> void:
	if p_card_dict.is_empty() or tex == null:
		return
	var code := String(p_card_dict.get("card_code", ""))
	var enabled := false
	if is_inside_tree():
		var cm := get_node_or_null("/root/CollectionManager")
		if cm != null and code != "" and bool(cm.call("is_foiled", code)):
			enabled = true
	var grade := String(p_card_dict.get("foil_grade", ""))
	if grade == "prize" or grade == "parallel":
		enabled = true
	var rarity := String(p_card_dict.get("rarity", ""))
	if rarity in ["SecretRare", "TreasureRare", "SuperRare", "Rare", "Special"]:
		enabled = true
	if not enabled:
		return

	# Holographic style:
	# 0 = Super Rare Rainbow Wave
	# 1 = Secret Rare / Starlight Streaks
	# 2 = Cosmo / Galaxy Glitter
	# 3 = Liquid Gold / Caustic Relief (Special / Leader / Prize)
	var style := 0
	if p_card_dict.has("holo_style"):
		style = int(p_card_dict.get("holo_style", 0))
	elif rarity == "SecretRare":
		style = 1
	elif rarity == "TreasureRare":
		style = 2
	elif rarity == "Special" or grade == "prize" or String(p_card_dict.get("card_type", "")) == "Leader":
		style = 3
	elif grade == "parallel":
		style = 1

	var mat := ShaderMaterial.new()
	mat.shader = HOLO_SHADER
	mat.set_shader_parameter("u_source", tex)
	mat.set_shader_parameter("u_style", style)
	mat.set_shader_parameter("u_strength", 0.55 if (grade == "prize" or rarity == "SecretRare") else 0.42)
	mat.set_shader_parameter("u_parallel", 1.0 if (grade == "parallel" or grade == "prize" or rarity == "SecretRare") else 0.0)
	mat.set_shader_parameter("u_prize", 1.0 if (grade == "prize" or style == 3) else 0.0)
	mat.set_shader_parameter("u_speed", 0.6)
	_holo.material = mat
	_holo.texture = tex
	_holo.visible = true

func set_selected(on: bool) -> void:
	add_theme_stylebox_override("panel", _style_sel if on else _style_normal)

func _build() -> void:
	if _art != null:
		return
	if custom_minimum_size == Vector2.ZERO and role != "my_field" and role != "opp_field" \
			and role != "my_leader" and role != "opp_leader" and role != "my_stage" and role != "opp_stage":
		custom_minimum_size = Vector2(90, 126)
	pivot_offset = custom_minimum_size / 2.0
	# Clean borderless style by default
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_style_normal.set_border_width_all(0)
	_style_normal.set_corner_radius_all(3)

	# Golden highlight border when selected
	_style_sel = StyleBoxFlat.new()
	_style_sel.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_style_sel.border_color = Color(1.0, 0.85, 0.25, 1.0)
	_style_sel.set_border_width_all(3)
	_style_sel.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", _style_normal)

	_don_layer = Control.new()
	_don_layer.name = "DonLayer"
	_don_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_don_layer.show_behind_parent = true
	_don_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_don_layer)
	move_child(_don_layer, 0)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_art = TextureRect.new()
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_art)

	_holo = TextureRect.new()
	_holo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_holo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_holo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holo.visible = false
	_art.add_child(_holo)

	# Kept for inspector/data access, hidden from visual card face for clean look
	_name_l = Label.new()
	_name_l.visible = false
	box.add_child(_name_l)
	_sub_l = Label.new()
	_sub_l.visible = false
	box.add_child(_sub_l)

	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

func cost_value() -> int:
	return int(_dict.get("cost", 0))

var base_y: float = 0.0

func set_raised(raised: bool, highlight: bool = false) -> void:
	base_y = -42.0 if raised else 0.0
	z_index = 20 if raised else 0
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "position:y", base_y, 0.18)
	if highlight:
		set_selected(true)
	else:
		set_selected(false)

func set_rested_animated(rested: bool, duration: float = 0.22) -> void:
	is_rested = rested
	pivot_offset = size / 2.0
	var target_rot := -90.0 if rested else 0.0
	var target_mod := Color(0.95, 0.95, 0.98, 1.0) if rested else Color(1.0, 1.0, 1.0, 1.0)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees", target_rot, duration)
	tw.tween_property(self, "modulate", target_mod, duration)

func _on_mouse_entered() -> void:
	hovered.emit(uid)
	if role == "hand":
		pivot_offset = size / 2.0
		z_index = 50
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hover_tween.tween_property(self, "position:y", base_y - 35.0, 0.15)
		_hover_tween.tween_property(self, "scale", Vector2(1.35, 1.35), 0.15)

func _on_mouse_exited() -> void:
	if role == "hand":
		z_index = 20 if base_y < -1.0 else 0
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hover_tween.tween_property(self, "position:y", base_y, 0.15)
		_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.15)
	if _holo != null and _holo.visible and _holo.material is ShaderMaterial:
		(_holo.material as ShaderMaterial).set_shader_parameter("u_mouse", Vector2(-1.0, -1.0))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_pressing = true
				_drag_started = false
				_drag_start_pos = mb.global_position
				accept_event()
			else:
				if _drag_started:
					_drag_started = false
					_drag_pressing = false
					drag_end.emit(self, mb.global_position)
					accept_event()
				elif _drag_pressing:
					_drag_pressing = false
					clicked.emit(uid, role)
					accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			context_requested.emit(self, mb.global_position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _holo != null and _holo.visible and _holo.material is ShaderMaterial and size.x > 0.0 and size.y > 0.0:
			var local_uv := mm.position / size
			(_holo.material as ShaderMaterial).set_shader_parameter("u_mouse", local_uv)
		if _drag_pressing:
			if role == "my_leader" or role == "opp_leader":
				# Leader cannot be dragged anywhere!
				pass
			else:
				if not _drag_started and mm.global_position.distance_to(_drag_start_pos) > 8.0:
					_drag_started = true
					drag_start.emit(self, mm.global_position)
				if _drag_started:
					drag_move.emit(mm.global_position)

