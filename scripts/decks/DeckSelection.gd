extends Control

@onready var deck_item_scene: PackedScene = preload("res://scenes/ui/DeckItem.tscn")
@onready var deck_grid: GridContainer = %DeckGrid
@onready var deck_tabs: TabBar = %DeckTabs
@onready var back_button: Button = $MainLayout/TopBar/Back

var previous_scene_path: String = ""
const FALLBACK_PREVIOUS_SCENE := "res://scenes/ui/PostLogin.tscn"

const TAB_STARTER := 0
const TAB_META := 1
const TAB_CUSTOM := 2

func _ready() -> void:
	deck_tabs.tab_changed.connect(_on_tab_changed)
	back_button.pressed.connect(_on_back_pressed)
	_connect_button_sounds(back_button)
	_refresh_grid()

func set_previous_scene(path: String) -> void:
	previous_scene_path = path
	if previous_scene_path == "":
		previous_scene_path = FALLBACK_PREVIOUS_SCENE

func _get_ui_manager() -> Node:
	var ui_manager := get_parent()
	if ui_manager and ui_manager.has_method("switch_scene"):
		return ui_manager
	var root := get_tree().root
	if root:
		var from_root := root.get_node_or_null("Main/UIContainer")
		if from_root and from_root.has_method("switch_scene"):
			return from_root
	return null

func _connect_button_sounds(button: Button) -> void:
	var root := get_tree().root
	if root == null:
		return
	var ui_manager = root.get_node_or_null("Main/UIContainer")
	if ui_manager and ui_manager.has_method("attach_sounds_to"):
		ui_manager.attach_sounds_to(button)

func _on_back_pressed() -> void:
	var ui_manager := _get_ui_manager()
	var target := previous_scene_path if previous_scene_path != "" else FALLBACK_PREVIOUS_SCENE
	if ui_manager:
		ui_manager.switch_scene(target)
	else:
		# Allow running DeckSelection as a standalone scene (no Main/UIContainer).
		get_tree().change_scene_to_file(target)

func _on_tab_changed(_tab_index: int) -> void:
	_refresh_grid()

func _refresh_grid() -> void:
	for child in deck_grid.get_children():
		child.queue_free()

	var decks := _collect_decks(deck_tabs.current_tab)
	for d in decks:
		_create_deck_button(d, false)

	# Always show a "New Deck" tile as the last item.
	_create_deck_button({}, true)

func _create_deck_button(data: Dictionary, is_new: bool) -> void:
	var item: Button = deck_item_scene.instantiate()
	deck_grid.add_child(item)
	# Store data on the node so we can always handle clicks via `pressed`.
	item.set_meta("deck_data", data)
	item.set_meta("is_new", is_new)
	if item.has_method("setup"):
		item.call("setup", data, is_new)
	# Robust click wiring: use built-in pressed signal.
	if not item.pressed.is_connected(Callable(self, "_on_tile_pressed")):
		item.pressed.connect(Callable(self, "_on_tile_pressed").bind(item))
	# Also support the custom signal if present.
	if item.has_signal("deck_selected") and not item.is_connected("deck_selected", Callable(self, "_on_deck_clicked")):
		item.connect("deck_selected", Callable(self, "_on_deck_clicked").bind(is_new))


func _on_tile_pressed(item: Node) -> void:
	var is_new := bool(item.get_meta("is_new", false))
	var deck_data := item.get_meta("deck_data", {})
	if typeof(deck_data) != TYPE_DICTIONARY:
		deck_data = {}
	_on_deck_clicked(deck_data, is_new)

func _on_deck_clicked(deck_data: Dictionary, is_new: bool) -> void:
	if is_new:
		_open_deck_editor("", true)
		return
	var deck_id := str(deck_data.get("deck_id", ""))
	_open_deck_editor(deck_id, false)

func _open_deck_editor(deck_id: String, is_new: bool) -> void:
	var root := get_tree().root
	root.set_meta("selected_deck_id", deck_id)
	root.set_meta("create_new_deck", is_new)
	root.set_meta("return_scene", get_scene_file_path())

	var ui_manager := _get_ui_manager()
	if ui_manager:
		var decks_scene = load("res://scenes/DeckEdit.tscn")
		if decks_scene is PackedScene:
			var decks_instance = decks_scene.instantiate()
			if decks_instance.has_method("set_previous_scene"):
				decks_instance.set_previous_scene(get_scene_file_path())
			ui_manager.switch_scene_with_instance(decks_instance)
	else:
		# Standalone fallback.
		get_tree().change_scene_to_file("res://scenes/DeckEdit.tscn")

func _collect_decks(tab_index: int) -> Array:
	var decks: Array = []

	# Directory sources by category
	if tab_index == TAB_STARTER:
		decks.append_array(_scan_dir_for_decks("res://output/decks/starter/", "starter"))
	elif tab_index == TAB_META:
		decks.append_array(_scan_dir_for_decks("res://output/decks/ultra/", "meta"))
	elif tab_index == TAB_CUSTOM:
		decks.append_array(_scan_dir_for_decks("user://cache/data/decks/", "custom"))
		decks.append_array(_scan_dir_for_decks("res://data/decks/", "custom"))

	# De-dup by deck_id, keep first (prefer cache over res)
	var seen := {}
	var unique: Array = []
	for d in decks:
		var did := str(d.get("deck_id", ""))
		if did == "" or seen.has(did):
			continue
		seen[did] = true
		unique.append(d)

	# Sort by display name
	unique.sort_custom(func(a, b):
		return str(a.get("display_name", a.get("deck_id", ""))) < str(b.get("display_name", b.get("deck_id", "")))
	)

	return unique

func _scan_dir_for_decks(dir_path: String, kind: String) -> Array:
	var out: Array = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return out

	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var deck_id := f.get_basename()
		if deck_id == "deck_export":
			continue
		if kind == "custom" and deck_id.begins_with("ST"):
			# Avoid duplicating starters in Custom.
			continue

		var full_path := dir_path + f
		var data = DeckManager.load_json(full_path)
		if typeof(data) != TYPE_DICTIONARY:
			continue

		var info := _deck_summary(deck_id, full_path, data)
		out.append(info)

	return out

func _deck_summary(deck_id: String, deck_path: String, deck_json: Dictionary) -> Dictionary:
	var main: Array = deck_json.get("main", [])
	var don: Array = deck_json.get("don", [])

	var leader_total := 0
	var non_leader_total := 0
	var leader_entry: Dictionary = {}

	for e in main:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var t := str(e.get("type", "")).strip_edges().to_lower()
		var c := int(e.get("count", 1))
		if t == "leader":
			leader_total += c
			leader_entry = e
			continue
		if t == "don" or t == "don!!":
			continue
		non_leader_total += c

	var don_total := 0
	for d in don:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		don_total += int(d.get("count", 0))

	var ok := (leader_total == 1 and non_leader_total == 50 and don_total == 10)
	var main_total := leader_total + non_leader_total

	var display_name := str(deck_json.get("display_name", "")).strip_edges()
	if display_name == "":
		display_name = deck_id

	var leader_tex: Texture2D = null
	var colors: Array = []
	if not leader_entry.is_empty():
		var tmp := leader_entry.duplicate(true)
		DeckManager.assign_card_image_path(tmp)
		var ip := str(tmp.get("image_path", ""))
		if ip != "" and ResourceLoader.exists(ip):
			leader_tex = load(ip)

		var raw_colors = tmp.get("colors", tmp.get("color", []))
		if typeof(raw_colors) == TYPE_ARRAY:
			for c in raw_colors:
				var s = str(c).strip_edges()
				if s != "":
					colors.append(s)
		elif typeof(raw_colors) == TYPE_STRING:
			var s2 = str(raw_colors).strip_edges()
			if s2 != "":
				colors.append(s2)

	# Override known edge cases where color data is missing/incorrect in JSON.
	if deck_id.begins_with("ST-29") and colors.is_empty():
		colors.append("yellow")

	return {
		"deck_id": deck_id,
		"deck_path": deck_path,
		"display_name": display_name,
		"leader_texture": leader_tex,
		"colors": colors,
		"main_total": main_total,
		"is_legal": ok,
	}
