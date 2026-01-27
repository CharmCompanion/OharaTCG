extends Node

@export_node_path var field_path: NodePath
@export_node_path var search_grid_path: NodePath
@export_node_path var main_deck_grid_path: NodePath
@export_node_path var don_deck_grid_path: NodePath

@onready var field_node = get_node(field_path)
@onready var search_grid = get_node(search_grid_path)
@onready var main_deck_grid = get_node(main_deck_grid_path)
@onready var don_deck_grid = get_node(don_deck_grid_path)

@onready var deck_dropdown = $HeaderBar/DeckDropdown
@onready var starter_toggle: OptionButton = $HeaderBar/StarterToggle
@onready var back_button: Button = $HeaderBar/BackButton
@onready var rename_button = $HeaderBar/RenameButton
@onready var save_button = $HeaderBar/SaveDeckButton
@onready var delete_button = $HeaderBar/DeleteButton
@onready var export_button = $HeaderBar/ExportButton
@onready var clear_main_button = $HeaderBar/ClearMainDeckButton
@onready var save_menu: PopupMenu = $HeaderBar/SaveMenu
@onready var import_export_menu: PopupMenu = $HeaderBar/ImportExportMenu
@onready var clear_menu: PopupMenu = $HeaderBar/ClearMenu
@onready var save_conflict_menu: PopupMenu = $HeaderBar/SaveConflictMenu
@onready var save_as_dialog: AcceptDialog = $SaveAsDialog
@onready var save_as_name_edit: LineEdit = $SaveAsDialog/VBox/NameEdit

@onready var deck_stats_label: Label = $DeckStatsLabel

@onready var search_box: LineEdit = $Control/SearchBox
@onready var search_button: Button = $Control/SearchButton
@onready var apply_filters_button: Button = $Control/ApplyFiltersButton
@onready var clear_button: Button = $Control/ClearButton
@onready var color_dropdown: OptionButton = $Control/ColorDropdown
@onready var category_dropdown: OptionButton = $Control/CategoryDropdown

const SAVE_DIR = "res://data/decks/"
const EXPORT_PATH = "res://data/decks/deck_export"
var current_deck_name := ""
var current_deck_path: String = ""
var original_deck_path: String = ""
var deck_paths := {}
var all_search_cards: Array = []
var filtered_search_cards: Array = []
var all_cards_db: Array = []
var cards_by_code: Dictionary = {}
var selected_color: String = "All"
var selected_set: String = "All"
var search_text: String = ""

var _stats_refresh_queued := false
var previous_scene_path: String = ""

var _pending_custom_save_path: String = ""
var _pending_custom_base: String = ""

func _ready():
	DirAccess.make_dir_absolute(SAVE_DIR)
	_load_deck_list()
	_apply_incoming_navigation_state()
	call_deferred("_fix_header_overlap")

	if back_button and not back_button.pressed.is_connected(Callable(self, "_on_back_pressed")):
		back_button.pressed.connect(Callable(self, "_on_back_pressed"))

	# Starter/Meta filter via dropdown.
	var cb_filter := Callable(self, "_on_deck_filter_toggled")
	if starter_toggle and not starter_toggle.item_selected.is_connected(cb_filter):
		starter_toggle.item_selected.connect(cb_filter)

	# Auto-refresh deck stats when cards are added/removed.
	if main_deck_grid and not main_deck_grid.child_entered_tree.is_connected(Callable(self, "_on_deck_grid_changed")):
		main_deck_grid.child_entered_tree.connect(Callable(self, "_on_deck_grid_changed"))
		main_deck_grid.child_exiting_tree.connect(Callable(self, "_on_deck_grid_changed"))
	if don_deck_grid and not don_deck_grid.child_entered_tree.is_connected(Callable(self, "_on_deck_grid_changed")):
		don_deck_grid.child_entered_tree.connect(Callable(self, "_on_deck_grid_changed"))
		don_deck_grid.child_exiting_tree.connect(Callable(self, "_on_deck_grid_changed"))

	var cb_deck_selected := Callable(self, "_on_deck_selected")
	if deck_dropdown and not deck_dropdown.item_selected.is_connected(cb_deck_selected):
		deck_dropdown.item_selected.connect(cb_deck_selected)

	var cb_rename := Callable(self, "_on_rename_deck")
	if rename_button and not rename_button.pressed.is_connected(cb_rename):
		rename_button.pressed.connect(cb_rename)

	var cb_delete := Callable(self, "_on_delete_deck")
	if delete_button and not delete_button.pressed.is_connected(cb_delete):
		delete_button.pressed.connect(cb_delete)

	var cb_export := Callable(self, "_on_export_pressed")
	if export_button and not export_button.pressed.is_connected(cb_export):
		export_button.pressed.connect(cb_export)

	var cb_clear_menu := Callable(self, "_on_clear_main_deck_button_pressed")
	if clear_main_button and not clear_main_button.pressed.is_connected(cb_clear_menu):
		clear_main_button.pressed.connect(cb_clear_menu)

	var cb_search := Callable(self, "_on_search_button_pressed")
	if search_button and not search_button.pressed.is_connected(cb_search):
		search_button.pressed.connect(cb_search)

	var cb_apply_filters := Callable(self, "_on_apply_filters_button_pressed")
	if apply_filters_button and not apply_filters_button.pressed.is_connected(cb_apply_filters):
		apply_filters_button.pressed.connect(cb_apply_filters)

	var cb_clear := Callable(self, "_on_clear_button_pressed")
	if clear_button and not clear_button.pressed.is_connected(cb_clear):
		clear_button.pressed.connect(cb_clear)

	var cb_color := Callable(self, "_on_color_selected")
	if color_dropdown and not color_dropdown.item_selected.is_connected(cb_color):
		color_dropdown.item_selected.connect(cb_color)

	var cb_category := Callable(self, "_on_category_selected")
	if category_dropdown and not category_dropdown.item_selected.is_connected(cb_category):
		category_dropdown.item_selected.connect(cb_category)

	if import_export_menu and not import_export_menu.id_pressed.is_connected(Callable(self, "_on_import_export_menu_id_pressed")):
		import_export_menu.id_pressed.connect(Callable(self, "_on_import_export_menu_id_pressed"))

	if clear_menu and not clear_menu.id_pressed.is_connected(Callable(self, "_on_clear_menu_id_pressed")):
		clear_menu.id_pressed.connect(Callable(self, "_on_clear_menu_id_pressed"))

	if save_menu and not save_menu.id_pressed.is_connected(Callable(self, "_on_save_menu_id_pressed")):
		save_menu.id_pressed.connect(Callable(self, "_on_save_menu_id_pressed"))

	if save_conflict_menu and not save_conflict_menu.id_pressed.is_connected(Callable(self, "_on_save_conflict_menu_id_pressed")):
		save_conflict_menu.id_pressed.connect(Callable(self, "_on_save_conflict_menu_id_pressed"))

	if save_as_dialog and not save_as_dialog.confirmed.is_connected(Callable(self, "_on_save_as_dialog_confirmed")):
		save_as_dialog.confirmed.connect(Callable(self, "_on_save_as_dialog_confirmed"))

	load_search_cards()
	if current_deck_name != "":
		load_main_deck(current_deck_name)
		load_don_deck(current_deck_name)
	_schedule_stats_refresh()


func _fix_header_overlap() -> void:
	# Ensure the deck name dropdown never overlaps the Starter/Meta/Custom toggle,
	# regardless of resolution or ui_scale.
	await get_tree().process_frame
	if deck_dropdown == null or starter_toggle == null:
		return
	var margin := 6.0
	var left := deck_dropdown.global_position.x
	var desired_right := starter_toggle.global_position.x - margin
	var desired_width := desired_right - left
	# Don’t let it collapse completely; better to truncate text than overlap UI.
	desired_width = max(desired_width, 120.0)
	if desired_width < deck_dropdown.size.x:
		deck_dropdown.size = Vector2(desired_width, deck_dropdown.size.y)


func set_previous_scene(path: String) -> void:
	previous_scene_path = path


func _on_back_pressed() -> void:
	# Always return to DeckSelection from DeckEdit.
	var ui_manager = get_parent()
	if not (ui_manager and ui_manager.has_method("switch_scene")):
		ui_manager = get_tree().root.get_node_or_null("Main/UIContainer")
	if ui_manager and ui_manager.has_method("switch_scene"):
		ui_manager.switch_scene("res://scenes/DeckSelection.tscn")
	else:
		# Standalone fallback.
		get_tree().change_scene_to_file("res://scenes/DeckSelection.tscn")


func _apply_incoming_navigation_state() -> void:
	# DeckSelection uses root metadata to request a specific deck or "create new".
	var root := get_tree().root
	if root == null:
		return

	var create_new := bool(root.get_meta("create_new_deck", false))
	var requested := str(root.get_meta("selected_deck_id", "")).strip_edges()

	# One-shot: clear request so it doesn't persist across other navigations.
	root.set_meta("create_new_deck", false)
	root.set_meta("selected_deck_id", "")

	if create_new:
		clear_grid(main_deck_grid)
		clear_grid(don_deck_grid)
		current_deck_name = "CustomDeck"
		current_deck_path = ""
		original_deck_path = ""
		_schedule_stats_refresh()
		return

	if requested == "":
		return
	# Try to select the deck in the dropdown by its underlying id (metadata).
	for i in range(deck_dropdown.item_count):
		var meta = deck_dropdown.get_item_metadata(i)
		var deck_id := str(meta if meta != null else deck_dropdown.get_item_text(i))
		if deck_id == requested and not deck_dropdown.is_item_disabled(i):
			deck_dropdown.select(i)
			current_deck_name = deck_id
			current_deck_path = str(deck_paths.get(current_deck_name, ""))
			original_deck_path = current_deck_path
			load_main_deck(current_deck_name)
			load_don_deck(current_deck_name)
			_schedule_stats_refresh()
			return

func _on_deck_selected(index):
	var meta = deck_dropdown.get_item_metadata(index)
	current_deck_name = str(meta if meta != null else deck_dropdown.get_item_text(index))
	current_deck_path = str(deck_paths.get(current_deck_name, ""))
	original_deck_path = current_deck_path
	load_main_deck(current_deck_name)
	load_don_deck(current_deck_name)
	_schedule_stats_refresh()

func _on_deck_filter_toggled(_index: int) -> void:
	var prev := current_deck_name
	_load_deck_list()
	# Keep previous selection if it still exists and is enabled.
	if prev != "" and deck_paths.has(prev):
		for i in range(deck_dropdown.item_count):
			var meta = deck_dropdown.get_item_metadata(i)
			var deck_id := str(meta if meta != null else deck_dropdown.get_item_text(i))
			if deck_id == prev and not deck_dropdown.is_item_disabled(i):
				deck_dropdown.select(i)
				current_deck_name = prev
				current_deck_path = str(deck_paths.get(current_deck_name, ""))
				original_deck_path = current_deck_path
				load_main_deck(current_deck_name)
				load_don_deck(current_deck_name)
				_schedule_stats_refresh()
				return
	# Otherwise pick first valid.
	for i in range(deck_dropdown.item_count):
		if not deck_dropdown.is_item_disabled(i):
			deck_dropdown.select(i)
			var meta = deck_dropdown.get_item_metadata(i)
			current_deck_name = str(meta if meta != null else deck_dropdown.get_item_text(i))
			current_deck_path = str(deck_paths.get(current_deck_name, ""))
			original_deck_path = current_deck_path
			load_main_deck(current_deck_name)
			load_don_deck(current_deck_name)
			_schedule_stats_refresh()
			return

func _on_deck_dropdown_pressed():
	pass

func _on_rename_button_pressed():
	_on_rename_deck()

func _on_save_deck_button_pressed():
	if save_menu:
		save_menu.popup()
	else:
		_on_save_pressed()

func _on_delete_button_pressed():
	_on_delete_deck()

func _on_export_button_pressed():
	if import_export_menu:
		import_export_menu.popup()

func _on_clear_main_deck_button_pressed():
	if clear_menu:
		clear_menu.popup()

func _on_save_menu_id_pressed(id: int) -> void:
	match id:
		0:
			_on_save_pressed()
		1:
			_show_save_as_dialog()

func _on_save_conflict_menu_id_pressed(id: int) -> void:
	match id:
		0:
			if _pending_custom_save_path != "":
				_save_to_path(_pending_custom_save_path)
				current_deck_path = _pending_custom_save_path
				original_deck_path = _pending_custom_save_path
		1:
			_perform_save_custom_copy()

func _show_save_as_dialog() -> void:
	if save_as_name_edit:
		var base := current_deck_name.strip_edges()
		if base == "":
			base = "CustomDeck"
		save_as_name_edit.text = base
		save_as_name_edit.caret_column = base.length()
	if save_as_dialog:
		save_as_dialog.popup_centered()

func _on_save_as_dialog_confirmed() -> void:
	var base := current_deck_name
	if save_as_name_edit:
		base = save_as_name_edit.text
	_save_as_custom_with_base(base)

func _save_as_custom_with_base(base: String) -> void:
	base = base.strip_edges()
	if base == "":
		base = "CustomDeck"
	_pending_custom_base = base
	_pending_custom_save_path = SAVE_DIR + base + ".json"
	if FileAccess.file_exists(_pending_custom_save_path):
		if save_conflict_menu:
			# Update labels to mention the deck name.
			save_conflict_menu.clear()
			save_conflict_menu.add_item("Overwrite \"%s\"" % base, 0)
			var copy_label := "Save copy \"%s_copy\"" % base
			save_conflict_menu.add_item(copy_label, 1)
			save_conflict_menu.popup()
		else:
			_perform_save_custom_copy()
	else:
		_save_to_path(_pending_custom_save_path)
		current_deck_name = base
		current_deck_path = _pending_custom_save_path
		original_deck_path = _pending_custom_save_path

func _perform_save_custom_copy() -> void:
	var base := _pending_custom_base
	if base == "":
		base = current_deck_name
	if base == "":
		base = "CustomDeck"
	var idx := 1
	var final_name := "%s_copy" % base
	var final_path := SAVE_DIR + final_name + ".json"
	while FileAccess.file_exists(final_path):
		idx += 1
		final_name = "%s_copy%d" % [base, idx]
		final_path = SAVE_DIR + final_name + ".json"
	_save_to_path(final_path)
	current_deck_name = final_name
	current_deck_path = final_path
	original_deck_path = final_path

func _on_import_export_menu_id_pressed(id: int) -> void:
	match id:
		0:
			_on_import_clipboard_pressed()
		1:
			_on_export_tts_pressed()
		2:
			_on_export_sim_pressed()
		3:
			_on_export_image_pressed()

func _on_clear_menu_id_pressed(id: int) -> void:
	match id:
		0:
			_on_clear_main_deck()
		1:
			_on_clear_don_deck()

func _on_search_box_editing_toggled(_toggled: bool) -> void:
	pass

func _on_color_dropdown_pressed():
	pass

func _on_category_dropdown_pressed():
	pass

func _on_rename_deck():
	var new_name = "RenamedDeck" + str(Time.get_ticks_msec())
	var old_path = SAVE_DIR + current_deck_name + ".json"
	var new_path = SAVE_DIR + new_name + ".json"
	if FileAccess.file_exists(old_path):
		DirAccess.rename_absolute(old_path, new_path)
		current_deck_name = new_name
		_load_deck_list()

func _on_delete_deck():
	var path = SAVE_DIR + current_deck_name + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		current_deck_name = ""
		current_deck_path = ""
		original_deck_path = ""
		_load_deck_list()
		clear_grid(main_deck_grid)
		clear_grid(don_deck_grid)
		_schedule_stats_refresh()

func _on_save_pressed():
	var path := original_deck_path
	if path == "":
		var base := current_deck_name.strip_edges()
		if base == "":
			base = "CustomDeck"
		path = SAVE_DIR + base + ".json"
	_save_to_path(path)
	current_deck_path = path
	original_deck_path = path
	_schedule_stats_refresh()

func _save_to_path(path: String) -> void:
	var data = {
		"main": _extract_grid_data(main_deck_grid),
		"don": _extract_grid_data(don_deck_grid),
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open %s for writing" % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _on_export_pressed():
	var data = {
		"main": _extract_grid_data(main_deck_grid),
		"don": _extract_grid_data(don_deck_grid),
	}

	var json_file = FileAccess.open(EXPORT_PATH + ".json", FileAccess.WRITE)
	json_file.store_string(JSON.stringify(data, "\t"))
	json_file.close()

	var txt := ""
	for card in data.main:
		txt += "%s x%s\n" % [card["card_code"], card.get("count", 1)]
	var txt_file = FileAccess.open(EXPORT_PATH + ".txt", FileAccess.WRITE)
	txt_file.store_string(txt)
	txt_file.close()

	var csv := "CardCode,Count\n"
	for card in data.main:
		csv += "%s,%s\n" % [card["card_code"], card.get("count", 1)]
	var csv_file = FileAccess.open(EXPORT_PATH + ".csv", FileAccess.WRITE)
	csv_file.store_string(csv)
	csv_file.close()

func _on_clear_main_deck():
	clear_grid(main_deck_grid)
	_schedule_stats_refresh()

func _on_clear_don_deck():
	clear_grid(don_deck_grid)
	_schedule_stats_refresh()


func _on_deck_grid_changed(_child: Node) -> void:
	_schedule_stats_refresh()


func _schedule_stats_refresh() -> void:
	if _stats_refresh_queued:
		return
	_stats_refresh_queued = true
	call_deferred("_refresh_deck_stats")


func _refresh_deck_stats() -> void:
	_stats_refresh_queued = false
	if deck_stats_label == null:
		return

	var main_entries := _extract_grid_data(main_deck_grid)
	var leader_count := 0
	var main_total := 0
	var character_total := 0
	var event_total := 0
	var stage_total := 0
	var other_total := 0

	for entry in main_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var t := str(entry.get("type", "")).strip_edges().to_lower()
		var c := int(entry.get("count", 1))
		if t == "leader":
			leader_count += 1
			continue
		if t == "don" or t == "don!!":
			continue
		main_total += c
		match t:
			"character", "characters":
				character_total += c
			"event", "events":
				event_total += c
			"stage", "stages":
				stage_total += c
			_:
				other_total += c

	# Don grid currently spawns per-card (visual 10 DON cards), so count children.
	var don_total := 0
	if don_deck_grid:
		don_total = don_deck_grid.get_child_count()

	var total_main_with_leader := main_total + leader_count
	# OPTCG deck rules: 1 Leader + 50-card main deck (Leader not part of the 50) + 10 DON.
	var valid_main := (leader_count == 1 and main_total == 50 and don_total == 10)

	var parts := []
	parts.append("Total: %d" % total_main_with_leader)
	parts.append("Leader: %d" % leader_count)
	var main_part := "Main: %d (Character:%d | Event:%d | Stage:%d" % [main_total, character_total, event_total, stage_total]
	if other_total > 0:
		main_part += " | Other:%d" % other_total
	main_part += ")"
	parts.append(main_part)
	parts.append("Don: %d" % don_total)
	var prefix := ""
	if not valid_main:
		prefix = "INVALID | "
	deck_stats_label.text = prefix + " | ".join(parts)

func clear_grid(grid: Node):
	for child in grid.get_children():
		child.queue_free()

func _extract_grid_data(grid: Node) -> Array:
	var cards_data = []
	for card in grid.get_children():
		if card.has_method("get_card_data"):
			cards_data.append(card.get_card_data())
	return cards_data

func _load_deck_list():
	deck_dropdown.clear()
	deck_paths.clear()
	var mode := 0
	if starter_toggle:
		mode = starter_toggle.selected

	if mode == 2:
		# Custom: only show user/custom decks from SAVE_DIR.
		_add_custom_decks_from_dir(SAVE_DIR)
	else:
		var show_starter := true
		var show_meta := false
		if mode == 0:
			show_starter = true
			show_meta = false
		elif mode == 1:
			show_starter = false
			show_meta = true
		# Prefer auto-updated decks copied into cache by AutoUpdate.gd
		_add_decks_from_dir("user://cache/data/decks/", show_starter, show_meta)
		# Starter decks shipped with the project (authoritative lists).
		_add_decks_from_dir("res://data/decks/", show_starter, show_meta)
		# Legacy/derived exports (may be incomplete depending on source).
		_add_decks_from_dir("res://output/decks/starter/", show_starter, show_meta)
		# Optional additional exports.
		_add_decks_from_dir("res://output/decks/ultra/", show_starter, show_meta)
		if deck_paths.size() == 0:
			_add_decks_from_dir(SAVE_DIR, show_starter, show_meta)

	# Pick the first valid (enabled) deck by default.
	current_deck_name = ""
	for i in range(deck_dropdown.item_count):
		if not deck_dropdown.is_item_disabled(i):
			var meta = deck_dropdown.get_item_metadata(i)
			current_deck_name = str(meta if meta != null else deck_dropdown.get_item_text(i))
			break

func _deck_kind(deck_name: String, dir_path: String) -> String:
	# Directory hint first.
	var dp := dir_path.to_lower()
	if dp.contains("/starter/"):
		return "starter"
	if dp.contains("/ultra/"):
		return "meta"
	# Name-based fallback.
	return "starter" if _is_starter_deck_name(deck_name) else "meta"


func _add_decks_from_dir(dir_path: String, show_starter: bool, show_meta: bool) -> void:
	var dir = DirAccess.open(dir_path)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				var deck_name = f.get_basename()
				if deck_name.ends_with("_complete"):
					continue
				if deck_name == "deck_export":
					continue
				var kind := _deck_kind(deck_name, dir_path)
				if kind == "starter" and not show_starter:
					continue
				if kind == "meta" and not show_meta:
					continue
				if not deck_paths.has(deck_name):
					var full_path: String = dir_path + deck_name + ".json"
					deck_paths[deck_name] = full_path

					# Prefer a richer label from deck JSON if available.
					var label: String = deck_name
					var deck_data = DeckManager.load_json(full_path)
					if typeof(deck_data) == TYPE_DICTIONARY:
						var dn := str(deck_data.get("display_name", "")).strip_edges()
						if dn != "":
							label = dn

					deck_dropdown.add_item(label)
					var idx: int = deck_dropdown.item_count - 1
					deck_dropdown.set_item_metadata(idx, deck_name)

					var summary := _validate_deck_file(full_path)
					if not bool(summary.get("ok", false)):
						deck_dropdown.set_item_disabled(idx, true)
						deck_dropdown.set_item_tooltip(idx, "%s | %s" % [kind.capitalize(), str(summary.get("message", "Invalid deck"))])
					else:
						deck_dropdown.set_item_tooltip(idx, "%s | OK: 1 Leader + 50 Main + 10 DON" % kind.capitalize())

func _add_custom_decks_from_dir(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if dir:
		for f in dir.get_files():
			if not f.ends_with(".json"):
				continue
			var deck_name = f.get_basename()
			if deck_name == "deck_export":
				continue
			if not deck_paths.has(deck_name):
				var full_path: String = dir_path + deck_name + ".json"
				deck_paths[deck_name] = full_path

				var label: String = deck_name
				var deck_data = DeckManager.load_json(full_path)
				if typeof(deck_data) == TYPE_DICTIONARY:
					var dn := str(deck_data.get("display_name", "")).strip_edges()
					if dn != "":
						label = dn

				deck_dropdown.add_item(label)
				var idx: int = deck_dropdown.item_count - 1
				deck_dropdown.set_item_metadata(idx, deck_name)

				var summary := _validate_deck_file(full_path)
				if not bool(summary.get("ok", false)):
					deck_dropdown.set_item_disabled(idx, true)
					deck_dropdown.set_item_tooltip(idx, "Custom | %s" % str(summary.get("message", "Invalid deck")))
				else:
					deck_dropdown.set_item_tooltip(idx, "Custom | OK: 1 Leader + 50 Main + 10 DON")


func _validate_deck_file(deck_path: String) -> Dictionary:
	var data = DeckManager.load_json(deck_path)
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "message": "Invalid: unreadable JSON"}

	var main: Array = data.get("main", [])
	var don: Array = data.get("don", [])
	if typeof(main) != TYPE_ARRAY:
		return {"ok": false, "message": "Invalid: missing main[]"}

	var leader_total := 0
	var main_total := 0
	for entry in main:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var t := str(entry.get("type", "")).strip_edges().to_lower()
		var count := int(entry.get("count", 1))
		if t == "leader":
			leader_total += count
			continue
		if t == "don" or t == "don!!":
			continue
		main_total += count

	var don_total := 0
	if typeof(don) == TYPE_ARRAY:
		for d in don:
			if typeof(d) != TYPE_DICTIONARY:
				continue
			don_total += int(d.get("count", 0))

	var ok := (leader_total == 1 and main_total == 50 and don_total == 10)
	if ok:
		return {"ok": true}
	return {
		"ok": false,
		"message": "INVALID: Leader %d | Main %d (Total %d) | DON %d" % [leader_total, main_total, leader_total + main_total, don_total]
	}

func _is_starter_deck_name(deck_name: String) -> bool:
	return deck_name.begins_with("ST")

func load_search_cards():
	clear_grid(search_grid)

	# AutoUpdate.gd refreshes output DB cards into user://cache/assets/JSON/cards.json.
	# DeckManager.load_json will prefer the cached copy when available.
	var path = "res://assets/JSON/cards.json"
	var data = DeckManager.load_json(path)

	if typeof(data) != TYPE_ARRAY:
		push_error("cards.json must be an array!")
		return

	all_cards_db.clear()
	cards_by_code.clear()
	all_search_cards.clear()
	for card_data in data:
		if typeof(card_data) != TYPE_DICTIONARY:
			continue
		var code := str(card_data.get("card_code", "")).strip_edges().to_upper()
		if code != "" and not cards_by_code.has(code):
			cards_by_code[code] = card_data
		all_cards_db.append(card_data)

		# Default search pool: only OP01–OP14.
		if _is_op01_to_op14_card(card_data):
			all_search_cards.append(card_data)

	_populate_filters()
	_apply_filters()


func _on_export_tts_pressed() -> void:
	var export_array := []
	export_array.append("Exported from OharaTCG")

	var data := _extract_grid_data(main_deck_grid)
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var t := str(entry.get("type", "")).strip_edges().to_lower()
		if t == "don" or t == "don!!":
			continue
		var code := str(entry.get("card_code", "")).strip_edges().to_upper()
		if code == "":
			continue
		var count := int(entry.get("count", 1))
		count = maxi(1, count)
		for i in range(count):
			export_array.append(code)

	DisplayServer.clipboard_set(JSON.stringify(export_array))


func _on_export_sim_pressed() -> void:
	var grouped := {}
	var data := _extract_grid_data(main_deck_grid)
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var t := str(entry.get("type", "")).strip_edges().to_lower()
		if t == "don" or t == "don!!":
			continue
		var code := str(entry.get("card_code", "")).strip_edges().to_upper()
		if code == "":
			continue
		var count := int(entry.get("count", 1))
		count = maxi(1, count)
		grouped[code] = int(grouped.get(code, 0)) + count

	var lines := []
	var codes := grouped.keys()
	codes.sort()
	for code in codes:
		lines.append("%dx%s" % [int(grouped[code]), code])

	DisplayServer.clipboard_set("\n".join(lines))


func _on_import_clipboard_pressed() -> void:
	var text := DisplayServer.clipboard_get()
	if text.strip_edges() == "":
		return

	var import_counts := _parse_deck_import(text)
	if import_counts.is_empty():
		push_warning("Clipboard did not look like a supported deck format")
		return

	# Build entries with best-effort card metadata for images/types.
	var grouped := {}
	for code_key in import_counts.keys():
		var code := str(code_key).strip_edges().to_upper()
		var count := int(import_counts[code_key])
		if code == "" or count <= 0:
			continue

		var base: Dictionary = {}
		if cards_by_code.has(code):
			base = (cards_by_code[code] as Dictionary).duplicate(true)
		else:
			# Fallback: create minimal entry so images can still resolve.
			var set_code := code.split("-")[0] if code.contains("-") else ""
			base = {
				"card_code": code,
				"set_code": set_code,
				"name": code,
				"type": "Character",
			}
		base["count"] = count
		grouped[code] = base

	# Ensure leader exists and is 1 copy.
	for k in grouped.keys():
		var e := grouped[k] as Dictionary
		var t := str(e.get("type", "")).strip_edges().to_lower()
		if t == "leader":
			e["count"] = 1

	# Apply type-order sort on initial import.
	var entries: Array = grouped.values()
	entries.sort_custom(Callable(self, "_deck_entry_sort"))

	clear_grid(main_deck_grid)
	for card_data in entries:
		(card_data as Dictionary)["zone"] = "main"
		var cards = DeckManager.create_card(card_data, field_node, false)
		for card in cards:
			if card is Card:
				card.custom_minimum_size = Vector2(75, 125)
			main_deck_grid.add_child(card)

	_schedule_stats_refresh()


func _parse_deck_import(raw: String) -> Dictionary:
	var s := raw.strip_edges()
	var result := {}

	# Attempt JSON array format: ["Exported from ...", "OP07-099", ...]
	var parsed = JSON.parse_string(s)
	if typeof(parsed) == TYPE_ARRAY:
		var arr: Array = parsed
		for i in range(arr.size()):
			var item := str(arr[i]).strip_edges().to_upper()
			# Skip header strings and empties
			if item == "" or item.begins_with("EXPORTED FROM"):
				continue
			if not item.contains("-"):
				continue
			result[item] = int(result.get(item, 0)) + 1
		return result

	# Text format: 1xOP07-099 per line
	for line in s.split("\n"):
		var l := str(line).strip_edges()
		if l == "":
			continue
		# Remove common prefixes
		if l.to_lower().begins_with("decklist"):
			continue
		# Match N x CODE
		var m := RegEx.new()
		m.compile("^\\s*(\\d+)\\s*[xX]\\s*([A-Za-z0-9-]+)\\s*$")
		var r = m.search(l)
		if r:
			var n := int(r.get_string(1))
			var code := str(r.get_string(2)).strip_edges().to_upper()
			if code.contains("-") and n > 0:
				result[code] = int(result.get(code, 0)) + n
			continue
		# Or raw card code per line
		var code2 := l.strip_edges().to_upper()
		if code2.contains("-"):
			result[code2] = int(result.get(code2, 0)) + 1

	return result


func _on_export_image_pressed() -> void:
	_export_deck_image_async()


func _export_deck_image_async() -> void:
	# Wait a frame to ensure UI is rendered.
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return

	# Crop to DeckField area if possible.
	var crop_img := img
	if field_node and field_node is Control:
		var rect: Rect2 = (field_node as Control).get_global_rect()
		var r := Rect2i(Vector2i(int(rect.position.x), int(rect.position.y)), Vector2i(int(rect.size.x), int(rect.size.y)))
		r.position.x = maxi(0, r.position.x)
		r.position.y = maxi(0, r.position.y)
		r.size.x = mini(r.size.x, img.get_width() - r.position.x)
		r.size.y = mini(r.size.y, img.get_height() - r.position.y)
		if r.size.x > 0 and r.size.y > 0:
			crop_img = img.get_region(r)

	DirAccess.make_dir_absolute("user://exports")
	var ts := Time.get_datetime_string_from_system().replace(":", "").replace(" ", "_")
	var safe_name := (current_deck_name if current_deck_name != "" else "deck").replace("/", "_")
	var out_path := "user://exports/%s_%s.png" % [safe_name, ts]
	crop_img.save_png(out_path)
	DisplayServer.clipboard_set(out_path)


func _is_op01_to_op14_card(card_data: Dictionary) -> bool:
	var set_code := str(card_data.get("set_code", "")).strip_edges().to_upper().replace("-", "").replace(" ", "")
	if not set_code.begins_with("OP"):
		return false
	var num_str := set_code.substr(2)
	if num_str == "" or not num_str.is_valid_int():
		return false
	var n := int(num_str)
	return n >= 1 and n <= 14

func _populate_filters() -> void:
	if color_dropdown:
		color_dropdown.clear()
		color_dropdown.add_item("All")
		for color in ["Red", "Blue", "Green", "Purple", "Black", "Yellow"]:
			color_dropdown.add_item(color)
		selected_color = "All"
		color_dropdown.select(0)

	if category_dropdown:
		category_dropdown.clear()
		category_dropdown.add_item("All")
		var set_ids := {}
		for card_data in all_search_cards:
			var set_id = str(card_data.get("set_id", "")).strip_edges()
			var set_code = str(card_data.get("set_code", "")).strip_edges()
			var label = set_id if set_id != "" else set_code
			if label == "":
				continue
			set_ids[label] = true
		var sorted_sets := set_ids.keys()
		sorted_sets.sort()
		for set_label in sorted_sets:
			category_dropdown.add_item(set_label)
		selected_set = "All"
		category_dropdown.select(0)

func _apply_filters() -> void:
	clear_grid(search_grid)
	var shown_cards := {}
	filtered_search_cards.clear()
	# (Removed) ResultsLabel UI no longer needs total count.

	for card_data in all_search_cards:
		if typeof(card_data) != TYPE_DICTIONARY:
			continue

		if not _card_matches_filters(card_data):
			continue

		var card_code = card_data.get("card_code", "")
		if shown_cards.has(card_code):
			continue
		shown_cards[card_code] = true

		var entry = card_data.duplicate(true)
		entry["zone"] = "search"
		filtered_search_cards.append(entry)

		var cards = DeckManager.create_card(entry, field_node)
		for card in cards:
			if card is Card:
				card.custom_minimum_size = Vector2(75, 125)
				if card.card_image:
					card.card_image.custom_minimum_size = Vector2(75, 125)
			search_grid.add_child(card)

	# Removed ResultsLabel UI


func _count_unique_cards_in_selected_set() -> int:
	var seen := {}
	for card_data in all_search_cards:
		if typeof(card_data) != TYPE_DICTIONARY:
			continue
		if selected_set != "All":
			var set_id = str(card_data.get("set_id", "")).strip_edges()
			var set_code = str(card_data.get("set_code", "")).strip_edges()
			if not ((selected_set == set_id) or (selected_set == set_code)):
				continue
		var card_code = str(card_data.get("card_code", "")).strip_edges()
		if card_code == "":
			continue
		seen[card_code] = true
	return seen.size()




func _card_matches_filters(card_data: Dictionary) -> bool:
	var matches_color := true
	if selected_color != "All":
		var colors = card_data.get("colors", card_data.get("color", []))
		if typeof(colors) == TYPE_ARRAY:
			matches_color = selected_color in colors
		else:
			matches_color = false

	var matches_set := true
	if selected_set != "All":
		var set_id = str(card_data.get("set_id", "")).strip_edges()
		var set_code = str(card_data.get("set_code", "")).strip_edges()
		matches_set = (selected_set == set_id) or (selected_set == set_code)

	var matches_search := true
	if search_text.strip_edges() != "":
		var text = search_text.to_lower()
		var card_name = str(card_data.get("name", "")).to_lower()
		var code = str(card_data.get("card_code", "")).to_lower()
		matches_search = card_name.contains(text) or code.contains(text)

	return matches_color and matches_set and matches_search

func _on_search_button_pressed() -> void:
	search_text = search_box.text
	_apply_filters()

func _on_apply_filters_button_pressed() -> void:
	search_text = search_box.text
	_apply_filters()

func _on_clear_button_pressed() -> void:
	search_box.text = ""
	search_text = ""
	selected_color = "All"
	selected_set = "All"
	if color_dropdown:
		color_dropdown.select(0)
	if category_dropdown:
		category_dropdown.select(0)
	_apply_filters()

func _on_color_selected(index: int) -> void:
	if color_dropdown:
		selected_color = color_dropdown.get_item_text(index)
	_apply_filters()

func _on_category_selected(index: int) -> void:
	if category_dropdown:
		selected_set = category_dropdown.get_item_text(index)
	_apply_filters()

func load_main_deck(deck_name: String):
	clear_grid(main_deck_grid)
	var path = deck_paths.get(deck_name, SAVE_DIR + deck_name + ".json")
	var data = DeckManager.load_json(path)

	if typeof(data) != TYPE_DICTIONARY:
		push_error("Deck JSON must be a dictionary")
		return

	var main_key := "main"
	if not data.has(main_key) and data.has("main_deck"):
		main_key = "main_deck"
	if not data.has(main_key):
		push_error("Deck JSON must have 'main' or 'main_deck' section")
		return

	var leader_data = null
	if data.has("leader") and typeof(data["leader"]) == TYPE_DICTIONARY:
		leader_data = data["leader"]

	var grouped := {}
	if leader_data:
		var leader_code = leader_data.get("card_code", "")
		leader_data["count"] = 1
		grouped[leader_code] = leader_data
	for card_data in data[main_key]:
		if typeof(card_data) != TYPE_DICTIONARY:
			continue
		var code = card_data.get("card_code", "")
		var count = int(card_data.get("count", 1))
		var card_type := str(card_data.get("type", "")).to_lower()
		var is_don := (card_type == "don") or (card_type == "don!!") or str(code).to_upper().begins_with("DON")
		var is_leader := (card_type == "leader")
		if is_leader:
			count = 1
		if not is_don:
			count = mini(count, 4)
		if not grouped.has(code):
			card_data["count"] = count
			grouped[code] = card_data
		else:
			grouped[code]["count"] += count
			if is_leader:
				grouped[code]["count"] = 1
			elif not is_don:
				grouped[code]["count"] = mini(int(grouped[code]["count"]), 4)

	var entries: Array = grouped.values()
	entries.sort_custom(Callable(self, "_deck_entry_sort"))
	for card_data in entries:
		card_data["zone"] = "main"
		var cards = DeckManager.create_card(card_data, field_node, false)
		for card in cards:
			if card is Card:
				card.custom_minimum_size = Vector2(75, 125)
			main_deck_grid.add_child(card)
	_schedule_stats_refresh()


func _deck_entry_sort(a: Variant, b: Variant) -> bool:
	var ad := a as Dictionary
	var bd := b as Dictionary
	var ar := _deck_type_rank(str(ad.get("type", "")))
	var br := _deck_type_rank(str(bd.get("type", "")))
	if ar != br:
		return ar < br
	var ac := str(ad.get("card_code", ""))
	var bc := str(bd.get("card_code", ""))
	return ac.naturalnocasecmp_to(bc) < 0


func _deck_type_rank(t: String) -> int:
	var tt := t.strip_edges().to_lower()
	match tt:
		"leader", "leaders":
			return 0
		"character", "characters":
			return 1
		"event", "events":
			return 2
		"stage", "stages":
			return 3
		_:
			return 9
			
func load_don_deck(deck_name: String):
	clear_grid(don_deck_grid)
	var path = deck_paths.get(deck_name, SAVE_DIR + deck_name + ".json")
	var data = DeckManager.load_json(path)

	var don_list := []
	if typeof(data) == TYPE_DICTIONARY and data.has("don"):
		don_list = data["don"]
	elif typeof(data) == TYPE_DICTIONARY and data.has("don_cards"):
		don_list = data["don_cards"]
	else:
		var fallback = DeckManager.load_json("res://assets/JSON/Don.json")
		if typeof(fallback) == TYPE_DICTIONARY and fallback.has("don"):
			don_list = fallback["don"]

	if don_list.is_empty():
		don_list = [{
			"card_code": "DON!!",
			"type": "DON!!",
			"count": 10
		}]

	for card_data in don_list:
		if typeof(card_data) != TYPE_DICTIONARY:
			continue
		card_data["zone"] = "don"
		var cards = DeckManager.create_card(card_data, field_node)
		for card in cards:
			if card is Card:
				card.custom_minimum_size = Vector2(75, 125)
			don_deck_grid.add_child(card)
	_schedule_stats_refresh()
