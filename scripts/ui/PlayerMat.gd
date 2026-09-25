# res://scripts/ui/PlayerMat.gd
# ONE player's half of the table (backed by scenes/PlayerMat.tscn).
# This is the customizable "play mat": set_art() skins this half, and the
# Custom folder res://assets/mats/Custom/ is where player mats live.
#
# Half layout, outer edge -> center line (no logo plaque):
#   Row A: DON!! deck | COST AREA (wide) | TRASH
#   Row B: LEADER CARD | STAGE CARD | DECK
#   Row C: LIFE (sideways fanned card backs + tick strip) | CHARACTER AREA (5 slots)

extends Control
class_name MtPlayerMat

signal zone_clicked(zone_name: String, button_index: int, global_pos: Vector2)
signal don_hover_changed(hovered: bool)
signal end_turn_pressed()
signal surrender_pressed()
signal mat_drag_started(zone_name: String, global_pos: Vector2)
signal mat_drag_moved(global_pos: Vector2)
signal mat_drag_ended(zone_name: String, global_pos: Vector2)
signal don_card_clicked(player_index: int, don_index: int, is_active: bool, is_committed: bool)

@export var player_index := 0

const ZONES := ["don_deck", "cost", "trash", "deck", "leader", "stage", "character", "life", "event"]
const CHAR_SLOTS := 5
const MAX_TICKS := 6

const ZONE_TITLES := {
	"don_deck": "DON!!",
	"cost": "DON AREA",
	"trash": "TRASH",
	"deck": "DECK",
	"leader": "LEADER CARD",
	"stage": "STAGE CARD",
	"character": "CHARACTER AREA",
	"life": "LIFE",
	"event": "",
}

# Half-local rects as fractions (x0, y0, x1, y1); y=0 is the center divider, y=1 is the outer edge.
# 1920x540 reference half-mat: card is 90x126 (ratio 1:1.4).
# 3 rows (each 126px tall = 0.233):
#   Row 1: y=[0.018, 0.251] -> CHARACTER AREA (centered at 0.500), LIFE (snug rotated card backs)
#   Row 2: y=[0.296, 0.529] -> EVENT (left of leader), LEADER (centered at 0.500), STAGE (left of deck), DECK
#   Row 3: y=[0.574, 0.807] -> DON DECK, DON AREA (centered at 0.500), TRASH (under deck)
# Gap between fields: 0.018 + 0.018 = 0.036 (less than DON-to-Stage gap 0.045).
const ZONE_RECTS := {
	"character": [0.340, 0.018, 0.660, 0.251],
	"life": [0.268, 0.060, 0.320, 0.420],
	"event": [0.405, 0.296, 0.452, 0.529],
	"leader": [0.4765, 0.296, 0.5235, 0.529],
	"stage": [0.605, 0.296, 0.652, 0.529],
	"deck": [0.672, 0.296, 0.719, 0.529],
	"don_deck": [0.273, 0.574, 0.320, 0.807],
	"cost": [0.340, 0.574, 0.660, 0.807],
	"trash": [0.672, 0.574, 0.719, 0.807],
}
const TICKS_RECT := [0.268, 0.430, 0.320, 0.450]
const HUD_RECT := [0.672, 0.018, 0.719, 0.251]

var _art: TextureRect
var _zones := {}
var _panels := {}
var _counts := {}
var _ticks: Array = []
var _slots: Array = []
var _fan: Control
var _don_fan: Control
var _deck_pile: Control
var _don_deck_pile: Control
var _trash_art: TextureRect
var _don_art_path := ""
var _drag_zone := ""
var _drag_start_pos := Vector2.ZERO
var _is_pressing := false
var _is_dragging := false

var _hud_root: Control
var _hud_name: Label
var _hud_life: Label
var _hud_bar: ProgressBar
var _hud_avatar: TextureRect

var _style_normal: StyleBoxFlat
var _style_hi: StyleBoxFlat
var _style_slot: StyleBoxFlat
var _style_back: StyleBoxFlat
var _style_don_committed: StyleBoxFlat

var committed_don: int = 0
var _last_ps: MtPlayerState = null

func set_committed_don(count: int) -> void:
	committed_don = count
	if _last_ps != null:
		_refresh_don(_last_ps)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_styles()
	_art = TextureRect.new()
	add_child(_art)
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.modulate = Color(1, 1, 1, 0.55)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	if player_index == 1:
		# Far-half perspective: foreshortened art + dimmer light, rendered
		# table-rotated with the rest of the half by PlayField.
		_art.scale = Vector2(0.96, 0.97)
		_art.resized.connect(_on_art_resized)
		_on_art_resized()
	for zone in ZONES:
		_build_zone(zone)
	_build_ticks()
	_build_hud()

func _on_art_resized() -> void:
	if _art != null:
		_art.pivot_offset = _art.size / 2.0

# --- Public API ---

func hud_name_label() -> Label:
	return _hud_name

func hud_life_label() -> Label:
	return _hud_life

func hud_bar() -> ProgressBar:
	return _hud_bar

func set_avatar(tex: Texture2D) -> void:
	if _hud_avatar == null:
		return
	_hud_avatar.texture = tex
	_hud_avatar.visible = tex != null

func set_art(tex: Texture2D) -> void:
	_art.texture = tex
	_art.visible = tex != null

# Color mat from a leader's colors (first color wins); file art in
# mats/Custom/<color>.png overrides the procedural felt automatically.
func set_leader_skin(colors: Array) -> void:
	set_art(MtMatSkin.art_for(colors))

func refresh(ps: MtPlayerState) -> void:
	_last_ps = ps
	_set_count("life", "%d/%d" % [ps.life.size(), ps.max_life])
	var free_count := maxi(0, ps.don_active - ps.get_attached_don_total() - ps.don_rested - committed_don)
	var rested_count := ps.don_rested + committed_don
	_set_count("cost", "%d+%dR/%d" % [free_count, rested_count, ps.don_deck_size])
	_set_count("don_deck", "%d" % ps.don_in_deck)
	_set_count("deck", "%d" % ps.deck.size())
	_set_count("trash", "%d" % ps.trash.size())
	_set_count("character", "%d/%d" % [ps.field.size(), CHAR_SLOTS])
	_refresh_ticks(ps.life.size(), ps.max_life)
	_refresh_fan(ps.life.size())
	_refresh_don(ps)
	_refresh_piles(ps)

func set_zone_highlight(zone: String, on: bool) -> void:
	var panel: Panel = _panels.get(zone, null)
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _style_hi if on else _style_normal)

func get_zone(zone: String) -> Control:
	return _zones.get(zone, null)

func char_slots() -> Array:
	return _slots

func zone_total() -> int:
	return _zones.size()

func zone_count(zone: String) -> String:
	var label: Label = _counts.get(zone, null)
	return label.text if label != null else ""

func visible_ticks() -> int:
	var n := 0
	for t in _ticks:
		if (t as ColorRect).visible:
			n += 1
	return n

# --- Construction ---

func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.18, 0.20, 0.24, 0.35)
	_style_normal.set_border_width_all(1)
	_style_normal.border_color = Color(0.85, 0.85, 0.90, 0.4)
	_style_normal.set_corner_radius_all(6)
	_style_hi = _style_normal.duplicate()
	_style_hi.border_color = Color(1.0, 0.85, 0.25, 1.0)
	_style_hi.set_border_width_all(3)
	_style_slot = StyleBoxFlat.new()
	_style_slot.bg_color = Color(0.20, 0.22, 0.28, 0.25)
	_style_slot.set_border_width_all(1)
	_style_slot.border_color = Color(0.80, 0.85, 0.90, 0.3)
	_style_slot.set_corner_radius_all(4)
	_style_back = StyleBoxFlat.new()
	_style_back.bg_color = Color(0.10, 0.16, 0.35, 0.95)
	_style_back.set_border_width_all(1)
	_style_back.border_color = Color(0.92, 0.92, 0.92, 0.9)
	_style_back.set_corner_radius_all(3)
	_style_don_committed = StyleBoxFlat.new()
	_style_don_committed.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_style_don_committed.border_color = Color(1.0, 0.88, 0.25, 0.95)
	_style_don_committed.set_border_width_all(2)
	_style_don_committed.set_corner_radius_all(3)

func _build_zone(zone: String) -> void:
	var r: Array = ZONE_RECTS[zone]
	var root := Control.new()
	_place_frac(self, root, r)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _style_normal)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var title := Label.new()
	title.text = ZONE_TITLES[zone]
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16 if zone == "character" or zone == "cost" else 12)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.35))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.5))
	title.add_theme_constant_override("outline_size", 4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	if zone == "event":
		panel.visible = false
		title.visible = false

	var count := Label.new()
	count.text = ""
	count.anchor_left = 0.0
	count.anchor_top = 1.0
	count.anchor_right = 1.0
	count.anchor_bottom = 1.0
	count.offset_top = -18.0
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 4)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.visible = false
	root.add_child(count)

	if zone == "life":
		# Sideways fanned card backs sit on top of panel and title.
		_fan = Control.new()
		_fan.name = "Fan"
		_fan.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_fan)
	if zone == "cost":
		# Active DON!! fanned across the cost area (dimmed once rested).
		_don_fan = Control.new()
		_don_fan.name = "DonFan"
		_don_fan.set_anchors_preset(Control.PRESET_FULL_RECT)
		_don_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_don_fan)
		root.mouse_filter = Control.MOUSE_FILTER_PASS
		root.mouse_entered.connect(func(): don_hover_changed.emit(true))
		root.mouse_exited.connect(func(): don_hover_changed.emit(false))
	if zone == "deck":
		# Stacked sleeve backs while cards remain.
		_deck_pile = Control.new()
		_deck_pile.name = "DeckPile"
		_deck_pile.set_anchors_preset(Control.PRESET_FULL_RECT)
		_deck_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_deck_pile)
		var s_art := MtMatCard.sleeve_art()
		for i in range(3):
			var trect := TextureRect.new()
			trect.texture = s_art
			trect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			trect.set_anchors_preset(Control.PRESET_FULL_RECT)
			trect.offset_left = i * 3.0
			trect.offset_top = -i * 3.0
			trect.offset_right = i * 3.0
			trect.offset_bottom = -i * 3.0
			trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_deck_pile.add_child(trect)
	if zone == "don_deck":
		# Stacked DON sleeve backs.
		_don_deck_pile = Control.new()
		_don_deck_pile.name = "DonDeckPile"
		_don_deck_pile.set_anchors_preset(Control.PRESET_FULL_RECT)
		_don_deck_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_don_deck_pile)
		var don_back := MtMatCard.don_sleeve_art()
		for i in range(3):
			var trect := TextureRect.new()
			trect.texture = don_back
			trect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			trect.set_anchors_preset(Control.PRESET_FULL_RECT)
			trect.offset_left = i * 3.0
			trect.offset_top = -i * 3.0
			trect.offset_right = i * 3.0
			trect.offset_bottom = -i * 3.0
			trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_don_deck_pile.add_child(trect)
	if zone == "trash":
		# Top of trash shown as mini art.
		_trash_art = TextureRect.new()
		_trash_art.name = "TrashTop"
		_trash_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_trash_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		_trash_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_trash_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_trash_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_trash_art.visible = false
		root.add_child(_trash_art)
	_zones[zone] = root
	_panels[zone] = panel
	_counts[zone] = count
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed:
				zone_clicked.emit(zone, mb.button_index, mb.global_position)
			if mb.button_index == MOUSE_BUTTON_LEFT and player_index == 0 and zone in ["deck", "don_deck", "life", "cost"]:
				if mb.pressed:
					_is_pressing = true
					_is_dragging = false
					_drag_zone = zone
					_drag_start_pos = mb.global_position
				else:
					if _is_dragging:
						_is_dragging = false
						_is_pressing = false
						mat_drag_ended.emit(_drag_zone, mb.global_position)
						_drag_zone = ""
					else:
						_is_pressing = false
						_drag_zone = ""
		elif ev is InputEventMouseMotion and player_index == 0 and _is_pressing:
			var mm := ev as InputEventMouseMotion
			if not _is_dragging and mm.global_position.distance_to(_drag_start_pos) > 8.0:
				_is_dragging = true
				mat_drag_started.emit(_drag_zone, mm.global_position)
			if _is_dragging:
				mat_drag_moved.emit(mm.global_position)
	)
	if zone == "character":
		_build_slots(root)

func _build_hud() -> void:
	_hud_root = Control.new()
	_hud_root.name = "PlayerHUD"
	_hud_root.visible = (player_index == 0)
	_place_frac(self, _hud_root, HUD_RECT)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_hud_root.add_child(vbox)

	_hud_name = Label.new()
	_hud_life = Label.new()
	_hud_bar = ProgressBar.new()
	_hud_avatar = TextureRect.new()
	_hud_avatar.custom_minimum_size = Vector2(48, 48)
	_hud_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hud_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 6)
	hud_row.add_child(_hud_avatar)
	var hud_col := VBoxContainer.new()
	hud_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_col.add_child(_hud_name)
	hud_col.add_child(_hud_life)
	hud_col.add_child(_hud_bar)
	hud_row.add_child(hud_col)
	vbox.add_child(hud_row)
	_hud_root.visible = true

	if player_index == 0:
		var end_btn := Button.new()
		end_btn.name = "EndTurnButton"
		end_btn.text = "End Turn"
		end_btn.custom_minimum_size = Vector2(84, 30)
		end_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		end_btn.focus_mode = Control.FOCUS_NONE
		end_btn.add_theme_font_size_override("font_size", 13)
		var style_end := StyleBoxFlat.new()
		style_end.bg_color = Color(0.20, 0.45, 0.85, 0.90)
		style_end.set_border_width_all(1)
		style_end.border_color = Color(0.6, 0.8, 1.0, 0.8)
		style_end.set_corner_radius_all(4)
		end_btn.add_theme_stylebox_override("normal", style_end)
		var style_end_h := style_end.duplicate()
		style_end_h.bg_color = Color(0.28, 0.55, 0.95, 1.0)
		end_btn.add_theme_stylebox_override("hover", style_end_h)
		end_btn.pressed.connect(func(): end_turn_pressed.emit())
		vbox.add_child(end_btn)

		var surr_btn := Button.new()
		surr_btn.name = "SurrenderButton"
		surr_btn.text = "Surrender"
		surr_btn.custom_minimum_size = Vector2(84, 24)
		surr_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		surr_btn.focus_mode = Control.FOCUS_NONE
		surr_btn.add_theme_font_size_override("font_size", 11)
		var style_surr := StyleBoxFlat.new()
		style_surr.bg_color = Color(0.35, 0.15, 0.15, 0.75)
		style_surr.set_border_width_all(1)
		style_surr.border_color = Color(0.7, 0.3, 0.3, 0.6)
		style_surr.set_corner_radius_all(4)
		surr_btn.add_theme_stylebox_override("normal", style_surr)
		var style_surr_h := style_surr.duplicate()
		style_surr_h.bg_color = Color(0.55, 0.20, 0.20, 0.9)
		surr_btn.add_theme_stylebox_override("hover", style_surr_h)
		surr_btn.pressed.connect(func(): surrender_pressed.emit())
		vbox.add_child(surr_btn)
	else:
		_hud_root.rotation = PI
		_hud_root.resized.connect(func():
			if _hud_root != null:
				_hud_root.pivot_offset = _hud_root.size / 2.0
		)
		_hud_root.pivot_offset = _hud_root.size / 2.0

func _build_slots(char_root: Control) -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	box.offset_left = 2.0
	box.offset_top = 2.0
	box.offset_right = -2.0
	box.offset_bottom = -2.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	char_root.add_child(box)
	char_root.clip_contents = true
	for i in range(CHAR_SLOTS):
		var slot := Panel.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.add_theme_stylebox_override("panel", _style_slot)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.clip_contents = true
		var slot_idx := i
		slot.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.pressed:
					zone_clicked.emit("slot_%d" % slot_idx, mb.button_index, mb.global_position)
		)
		# Fit a 63:88 card inside the slot so the Character Area holds the card.
		var host := AspectRatioContainer.new()
		host.ratio = 63.0 / 88.0
		host.stretch_mode = AspectRatioContainer.STRETCH_FIT
		host.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
		host.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(host)
		box.add_child(slot)
		_slots.append(host)

func _build_ticks() -> void:
	var ticks := HBoxContainer.new()
	_place_frac(self, ticks, TICKS_RECT)
	ticks.add_theme_constant_override("separation", 3)
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(MAX_TICKS):
		var tick := ColorRect.new()
		tick.custom_minimum_size = Vector2(4, 4)
		tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tick.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tick.color = Color(0.25, 0.25, 0.27, 0.9)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ticks.add_child(tick)
		_ticks.append(tick)

func _place_frac(parent: Control, c: Control, r: Array) -> void:
	parent.add_child(c)
	c.anchor_left = float(r[0])
	c.anchor_top = float(r[1])
	c.anchor_right = float(r[2])
	c.anchor_bottom = float(r[3])
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _set_count(zone: String, text: String) -> void:
	var label: Label = _counts.get(zone, null)
	if label != null:
		label.text = text

func _refresh_ticks(life: int, max_life: int) -> void:
	for i in range(_ticks.size()):
		var tick: ColorRect = _ticks[i]
		if i < max_life:
			tick.visible = true
			tick.color = Color(0.95, 0.85, 0.35, 0.95) if i < life else Color(0.25, 0.25, 0.27, 0.9)
		else:
			tick.visible = false

func _refresh_fan(n: int) -> void:
	for c in _fan.get_children():
		c.queue_free()
	if n <= 0:
		return
	# Life cards are rotated 90 degrees (landscape orientation: width > height).
	# The life zone is 1 rotated card wide (~126px), so cards span full width (anchor_left=0, anchor_right=1).
	# Standard card ratio is ~1:1.4. In landscape, height is ~90px out of ~276px total zone height (~0.326).
	# Cards stack vertically downwards with even overlapping offsets so each earlier card shows its edge.
	var card_h_f := 0.326
	var step_y := 0.0 if n <= 1 else (1.0 - card_h_f) / float(n - 1)
	var s_art := MtMatCard.sleeve_art()
	for i in range(n):
		var holder := Control.new()
		holder.anchor_left = 0.0
		holder.anchor_right = 1.0
		holder.anchor_top = float(i) * step_y
		holder.anchor_bottom = float(i) * step_y + card_h_f
		holder.offset_left = 0.0
		holder.offset_right = 0.0
		holder.offset_top = 0.0
		holder.offset_bottom = 0.0
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fan.add_child(holder)

		var trect := TextureRect.new()
		trect.set_anchors_preset(Control.PRESET_TOP_LEFT)
		trect.texture = s_art
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(trect)

		var update_trect := func():
			var cw := holder.size.x
			var ch := holder.size.y
			if cw > 1.0 and ch > 1.0:
				trect.size = Vector2(ch, cw)
				trect.pivot_offset = Vector2(ch / 2.0, cw / 2.0)
				trect.position = Vector2((cw - ch) / 2.0, (ch - cw) / 2.0)
				trect.rotation_degrees = -90.0
		holder.resized.connect(update_trect)
		update_trect.call()

func _don_art() -> Texture2D:
	if _don_art_path != "":
		return MtMatCard.art_for(_don_art_path)
	if is_inside_tree():
		var cdb := get_node_or_null("/root/CardDatabase")
		if cdb != null:
			var don: Dictionary = cdb.call("get_don_card")
			var p: String = String(don.get("image_override", don.get("image_path", "")))
			if p != "":
				_don_art_path = p
	if _don_art_path == "":
		_don_art_path = "res://assets/cards/Don/Don.png"
	return MtMatCard.art_for(_don_art_path)

static func get_don_groups(count: int) -> Array:
	match count:
		1: return [1]
		2: return [2]
		3: return [3]
		4: return [2, 2]
		5: return [5]
		6: return [3, 3]
		7: return [5, 2]
		8: return [5, 3]
		9: return [3, 3, 3]
		10: return [5, 5]
		_:
			var groups := []
			var rem := count
			while rem >= 5:
				groups.append(5)
				rem -= 5
			if rem == 4:
				groups.append(2)
				groups.append(2)
			elif rem > 0:
				groups.append(rem)
			return groups

func _refresh_don(ps: MtPlayerState) -> void:
	for c in _don_fan.get_children():
		_don_fan.remove_child(c)
		c.queue_free()
	var attached := ps.get_attached_don_total()
	var don_in_area := mini(maxi(0, ps.don_active - attached), 10)
	if don_in_area <= 0:
		return
	var tex := _don_art()
	var total_rested := clampi(ps.don_rested + committed_don, 0, don_in_area)
	var free_n := don_in_area - total_rested
	var groups := get_don_groups(don_in_area)

	# DON cards are 1 card size (vertical, ~84x116 px).
	# Cost area reference size is 490px wide by 126px tall.
	# Inside a group, cards stack with ~24px (~quarter inch) overlap step.
	# Between groups, there is a clear group separation gap (~28px).
	var area_w: float = _don_fan.size.x if _don_fan.size.x > 10.0 else 490.0
	var area_h: float = _don_fan.size.y if _don_fan.size.y > 10.0 else 126.0
	var card_w := 84.0
	var card_h := 116.0
	var step_x := 24.0
	var group_gap := 28.0

	var cur_x := 10.0
	var card_y := (area_h - card_h) / 2.0
	var card_idx := 0

	for g_size in groups:
		for j in range(g_size):
			var is_active := (card_idx < free_n)
			var is_committed := (card_idx >= free_n and card_idx < free_n + committed_don)

			var holder := Control.new()
			holder.name = "DonCard_%d" % card_idx
			holder.custom_minimum_size = Vector2(card_w, card_h)
			holder.pivot_offset = Vector2(card_w / 2.0, card_h / 2.0)
			holder.mouse_filter = Control.MOUSE_FILTER_STOP if player_index == 0 else Control.MOUSE_FILTER_IGNORE

			var cx := cur_x + float(j) * step_x
			holder.anchor_left = cx / area_w
			holder.anchor_right = (cx + card_w) / area_w
			holder.anchor_top = card_y / area_h
			holder.anchor_bottom = (card_y + card_h) / area_h
			holder.offset_left = 0.0
			holder.offset_right = 0.0
			holder.offset_top = 0.0
			holder.offset_bottom = 0.0

			holder.resized.connect(func():
				holder.pivot_offset = holder.size / 2.0
			)

			var trect := TextureRect.new()
			trect.texture = tex
			trect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			trect.set_anchors_preset(Control.PRESET_FULL_RECT)
			trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(trect)

			if is_committed:
				var border := Panel.new()
				border.set_anchors_preset(Control.PRESET_FULL_RECT)
				border.mouse_filter = Control.MOUSE_FILTER_IGNORE
				border.add_theme_stylebox_override("panel", _style_don_committed)
				holder.add_child(border)

			if is_active:
				holder.rotation_degrees = 0.0
				holder.modulate = Color.WHITE
				if player_index == 0:
					holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			elif is_committed:
				holder.rotation_degrees = -90.0
				holder.modulate = Color(1.15, 1.10, 0.85, 1.0)
				if player_index == 0:
					holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			else:
				holder.rotation_degrees = -90.0
				holder.modulate = Color(0.70, 0.70, 0.75, 1.0)
				if player_index == 0:
					holder.mouse_default_cursor_shape = Control.CURSOR_ARROW

			if player_index == 0:
				var this_idx := card_idx
				var this_act := is_active
				var this_com := is_committed
				var drag_press := false
				var drag_started := false
				var drag_start_pos := Vector2.ZERO

				holder.mouse_entered.connect(func():
					if this_act:
						var tw := holder.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						tw.tween_property(holder, "scale", Vector2(1.08, 1.08), 0.12)
				)
				holder.mouse_exited.connect(func():
					if this_act:
						var tw := holder.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						tw.tween_property(holder, "scale", Vector2.ONE, 0.12)
				)

				holder.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton:
						var mb := ev as InputEventMouseButton
						if mb.button_index == MOUSE_BUTTON_LEFT:
							if mb.pressed:
								drag_press = true
								drag_started = false
								drag_start_pos = mb.global_position
							else:
								if drag_started:
									drag_started = false
									drag_press = false
									mat_drag_ended.emit("cost", mb.global_position)
								elif drag_press:
									drag_press = false
									don_card_clicked.emit(player_index, this_idx, this_act, this_com)
					elif ev is InputEventMouseMotion and drag_press:
						var mm := ev as InputEventMouseMotion
						if not drag_started and mm.global_position.distance_to(drag_start_pos) > 8.0:
							if this_act or this_com:
								drag_started = true
								mat_drag_started.emit("cost", mm.global_position)
						if drag_started:
							mat_drag_moved.emit(mm.global_position)
				)

			_don_fan.add_child(holder)
			card_idx += 1
		cur_x += card_w + float(g_size - 1) * step_x + group_gap

func _refresh_piles(ps: MtPlayerState) -> void:
	_deck_pile.visible = not ps.deck.is_empty()
	if _don_deck_pile != null:
		_don_deck_pile.visible = ps.don_in_deck > 0
	if ps.trash.is_empty():
		_trash_art.visible = false
	else:
		var top: MtMatchCard = ps.trash.back()
		_trash_art.texture = MtMatCard.art_for(String(top.card.get("image_path", "")))
		_trash_art.visible = true
