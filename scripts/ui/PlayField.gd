# res://scripts/ui/PlayField.gd (backed by scenes/PlayField.tscn)
# The whole table: two PlayerMat halves + center divider + shared-mat art.
#
# Mat art rule: the board is ONE field. If neither side has a mat, only the
# dark backing shows. One side set (or both set to the SAME art) -> that art
# covers the whole board. Each side with its OWN mat -> split: top half shows
# P1's art, bottom half shows P0's art.

extends Control
class_name MtPlayField

signal zone_clicked(player_index: int, zone_name: String, button_index: int, global_pos: Vector2)
signal don_hover_changed(hovered: bool)
signal end_turn_pressed()
signal surrender_pressed()
signal mat_drag_started(player_index: int, zone_name: String, global_pos: Vector2)
signal mat_drag_moved(global_pos: Vector2)
signal mat_drag_ended(player_index: int, zone_name: String, global_pos: Vector2)
signal don_card_clicked(player_index: int, don_index: int, is_active: bool, is_committed: bool)

var engine: MtMatch = null

var _mat_top: Texture2D = null
var _mat_bottom: Texture2D = null

var _art_full: TextureRect
var _top_mat: MtPlayerMat
var _bot_mat: MtPlayerMat
var _divider: ColorRect
var _felt: ColorRect

func set_table_mode(m: String) -> void:
	# Ship/wood modes: translucent felt lets the table show through the
	# mat gaps; dark mode stays fully opaque.
	if _felt != null:
		match m:
			"ship":
				_felt.color = Color(0.04, 0.05, 0.08, 0.35)
			"wood":
				_felt.color = Color(0.10, 0.06, 0.03, 0.30)
			_:
				_felt.color = Color(0.05, 0.04, 0.035, 0.45)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Table felt FIRST: the field must never be transparent, even if a node
	# below is missing (fail loud, never silent).
	var felt := ColorRect.new()
	felt.color = Color(0.09, 0.075, 0.06, 1.0)
	felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(felt)
	_felt = felt
	_art_full = get_node_or_null("ArtFull") as TextureRect
	_top_mat = get_node_or_null("TopMat")
	_bot_mat = get_node_or_null("BottomMat")
	_divider = get_node_or_null("Divider") as ColorRect
	if _art_full == null or _top_mat == null or _bot_mat == null or _divider == null:
		printerr("PlayField: scene nodes missing (ArtFull/TopMat/BottomMat/Divider). Reimport the project.")
		return
	_art_full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_full.stretch_mode = TextureRect.STRETCH_SCALE
	_art_full.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_full.modulate = Color(1, 1, 1, 0.55)
	_art_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_full.visible = false
	_top_mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bot_mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_mat.resized.connect(_on_top_resized)
	_on_top_resized()
	if _bot_mat.has_signal("zone_clicked"):
		_bot_mat.zone_clicked.connect(func(z, btn, gpos): zone_clicked.emit(_seat_on(true), z, btn, gpos))
	if _top_mat.has_signal("zone_clicked"):
		_top_mat.zone_clicked.connect(func(z, btn, gpos): zone_clicked.emit(_seat_on(false), z, btn, gpos))
	if _bot_mat.has_signal("don_hover_changed"):
		_bot_mat.don_hover_changed.connect(func(h): don_hover_changed.emit(h))
	if _bot_mat.has_signal("end_turn_pressed"):
		_bot_mat.end_turn_pressed.connect(func(): end_turn_pressed.emit())
	if _bot_mat.has_signal("surrender_pressed"):
		_bot_mat.surrender_pressed.connect(func(): surrender_pressed.emit())
	if _bot_mat.has_signal("mat_drag_started"):
		_bot_mat.mat_drag_started.connect(func(z, pos): mat_drag_started.emit(_seat_on(true), z, pos))
	if _bot_mat.has_signal("mat_drag_moved"):
		_bot_mat.mat_drag_moved.connect(func(pos): mat_drag_moved.emit(pos))
	if _bot_mat.has_signal("mat_drag_ended"):
		_bot_mat.mat_drag_ended.connect(func(z, pos): mat_drag_ended.emit(_seat_on(true), z, pos))
	if _bot_mat.has_signal("don_card_clicked"):
		_bot_mat.don_card_clicked.connect(func(_p, idx, act, com): don_card_clicked.emit(_seat_on(true), idx, act, com))
	if _top_mat.has_signal("don_card_clicked"):
		_top_mat.don_card_clicked.connect(func(_p, idx, act, com): don_card_clicked.emit(_seat_on(false), idx, act, com))
	_divider.color = Color(0.92, 0.92, 0.92, 0.5)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.visible = false
	_apply_mats()
	resized.connect(_on_field_resized)
	_sync_halves()

func _on_field_resized() -> void:
	_sync_halves()

func _sync_halves() -> void:
	if size == Vector2.ZERO:
		return
	if _top_mat != null:
		_top_mat.pivot_offset = _top_mat.size / 2.0

func _on_top_resized() -> void:
	_top_mat.pivot_offset = _top_mat.size / 2.0

# --- Mat art ---

func set_shared_mat(tex: Texture2D) -> void:
	_mat_top = tex
	_mat_bottom = tex
	_apply_mats()

func set_player_mat(player: int, tex: Texture2D) -> void:
	if player == 0:
		_mat_bottom = tex
	else:
		_mat_top = tex
	_apply_mats()

func clear_mats() -> void:
	_mat_top = null
	_mat_bottom = null
	_apply_mats()

func split_state() -> String:
	if _mat_top != null and _mat_bottom != null and _mat_top != _mat_bottom:
		return "split"
	if _mat_top != null or _mat_bottom != null:
		return "shared"
	return "none"

func _apply_mats() -> void:
	if _art_full == null:
		return
	var split := split_state() == "split"
	_art_full.visible = split_state() == "shared"
	if _art_full.visible:
		_art_full.texture = _mat_top if _mat_top != null else _mat_bottom
	_top_mat.set_art(_mat_top if split else null)
	_bot_mat.set_art(_mat_bottom if split else null)

# --- Engine binding ---

var bottom_seat := 0

func set_bottom_seat(seat: int) -> void:
	bottom_seat = seat & 1

func _seat_on(bottom: bool) -> int:
	return bottom_seat if bottom else 1 - bottom_seat

func bind_engine(m: MtMatch) -> void:
	engine = m
	refresh()

func refresh() -> void:
	if engine == null or engine.players.size() < 2:
		return
	_bot_mat.refresh(engine.players[bottom_seat])
	_top_mat.refresh(engine.players[1 - bottom_seat])

func set_committed_don(player: int, count: int) -> void:
	_mat_for(player).set_committed_don(count)

func set_zone_highlight(player: int, zone: String, on: bool) -> void:
	_mat_for(player).set_zone_highlight(zone, on)

func get_zone(player: int, zone: String) -> Control:
	return _mat_for(player).get_zone(zone)

func char_slots(player: int) -> Array:
	return _mat_for(player).char_slots()

func zone_total() -> int:
	return _bot_mat.zone_total()

func zone_count(player: int, zone: String) -> String:
	return _mat_for(player).zone_count(zone)

func visible_ticks(player: int) -> int:
	return _mat_for(player).visible_ticks()

func top_rotated() -> bool:
	return absf(_top_mat.rotation_degrees - 180.0) < 0.01

func _mat_for(player: int) -> MtPlayerMat:
	return _bot_mat if player == bottom_seat else _top_mat
