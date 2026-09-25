extends Control

# --- Exports (Wired in the scene file) ---
@export var deck_dropdown_path: NodePath
@export var rename_button_path: NodePath
@export var save_button_path: NodePath
@export var delete_button_path: NodePath
@export var file_dialog_path: NodePath
@export var deck_name_edit_path: NodePath
@export var import_button_path: NodePath
@export var export_button_path: NodePath
@export var clear_main_deck_button_path: NodePath
@export var clear_don_deck_button_path: NodePath
@export var name_search_path: NodePath
@export var search_button_path: NodePath
@export var filter_toggle_path: NodePath
@export var filters_row_path: NodePath
@export var set_dropdown_path: NodePath
@export var color_dropdown_path: NodePath
@export var type_dropdown_path: NodePath
@export var card_type_dropdown_path: NodePath
@export var filter_method_dropdown_path: NodePath
@export var archetype_dropdown_path: NodePath
@export var alt_art_toggle_path: NodePath
@export var apply_button_path: NodePath
@export var clear_button_path: NodePath
@export var search_grid_path: NodePath
@export var main_deck_grid_path: NodePath
@export var don_deck_grid_path: NodePath
@export var leader_container_path: NodePath
@export var deck_stats_line1_path: NodePath
@export var deck_stats_line2_path: NodePath
@export var validation_format_dropdown_path: NodePath
@export var validation_button_path: NodePath
@export var validation_result_label_path: NodePath
@export var card_preview_path: NodePath
@export var card_name_label_path: NodePath
@export var card_details_label_path: NodePath
@export var counters_label_path: NodePath
@export var hover_popup_path: NodePath


# --- Onready References ---
@onready var DeckDropdown: OptionButton = get_node(deck_dropdown_path)
@onready var RenameButton: Button = get_node(rename_button_path)
@onready var SaveButton: Button = get_node(save_button_path)
@onready var DeleteButton: Button = get_node(delete_button_path)
@onready var save_file_dialog: FileDialog = get_node(file_dialog_path)
@onready var DeckNameEdit: LineEdit = get_node(deck_name_edit_path)
@onready var ImportButton: Button = get_node(import_button_path)
@onready var ExportButton: Button = get_node_or_null(export_button_path)
@onready var NameSearch: LineEdit = get_node(name_search_path)
@onready var SearchBtn: Button = get_node(search_button_path)
@onready var FilterToggle: BaseButton = get_node(filter_toggle_path)
@onready var FiltersRow: Control = get_node(filters_row_path)
@onready var SetDropdown: OptionButton = get_node(set_dropdown_path)
@onready var ColorDropdown: OptionButton = get_node(color_dropdown_path)
@onready var TypeDropdown: OptionButton = get_node(type_dropdown_path)
@onready var CardTypeDropdown: OptionButton = get_node(card_type_dropdown_path)
@onready var FilterMethodDropdown: OptionButton = get_node(filter_method_dropdown_path)
@onready var ArchetypeDropdown: OptionButton = get_node(archetype_dropdown_path)
@onready var AltArtToggle: CheckBox = get_node(alt_art_toggle_path)
@onready var ApplyBtn: Button = get_node(apply_button_path)
@onready var ClearBtn: Button = get_node(clear_button_path)
@onready var SearchGrid: GridContainer = get_node(search_grid_path)
@onready var MainDeckGrid: GridContainer = get_node(main_deck_grid_path)
@onready var DonDeckContainer: Container = get_node(don_deck_grid_path)
@onready var LeaderContainer: Container = get_node(leader_container_path)
@onready var StatsLine1: Label = get_node(deck_stats_line1_path)
@onready var StatsLine2: Label = get_node(deck_stats_line2_path)
@onready var FormatDropdown: OptionButton = get_node(validation_format_dropdown_path)
@onready var ValidateButton: Button = get_node(validation_button_path)
@onready var ValidationResultLabel: RichTextLabel = get_node(validation_result_label_path)
@onready var CardPreview: Panel = get_node(card_preview_path)
@onready var CardName: Label = get_node(card_name_label_path)
@onready var CardDetails: RichTextLabel = get_node(card_details_label_path)
@onready var CountersLabel: Label = get_node(counters_label_path)
@onready var HoverPopup: PopupPanel = get_node(hover_popup_path)
@onready var HoverName: Label = HoverPopup.get_node("HoverVBox/HoverName")
@onready var HoverStats: Label = HoverPopup.get_node("HoverVBox/HoverStats")

# --- Constants ---
const CARD_TYPE_ORDER := { "Leader": 0, "Character": 1, "Event": 2, "Stage": 3, "DON!!": 4 }
const CARD_ASPECT_RATIO = 88.0 / 63.0
const DON_SLOTS := 10
const DECK_SAVE_DIR = "res://data/decks/"
const DECK_USER_DIR = "user://decks/"

# --- Data ---
var main_deck: Array[Dictionary] = []
var don_deck: Array[Dictionary] = []
var leader_card: Dictionary = {}
var _test_layer: PanelContainer
var _test_cards: HBoxContainer
var _test_used := false
var current_deck_path: String = ""
var _previous_scene_path: String = "res://scenes/ui/PostLogin.tscn"

# --- Pagination ---
const CARDS_PER_PAGE: int = 40
var _filtered_results: Array = []
var _current_page: int = 0
var _total_pages: int = 1

func _db() -> Node:
	var n := get_node_or_null("/root/CardDatabase")
	if n != null:
		return n
	return get_node_or_null("/root/DeckManager")

func _data_ready() -> bool:
	var cdb := get_node_or_null("/root/CardDatabase")
	return cdb != null and bool(cdb.is_data_loaded)

func _lookup_card(card_id: String) -> Dictionary:
	var db := _db()
	if db != null and db.has_method("get_card_data"):
		return db.get_card_data(card_id)
	return {}

func _all_cards() -> Array:
	var db := _db()
	if db != null and db.has_method("get_all_card_data_as_array"):
		return db.get_all_card_data_as_array()
	return []

func _make_card_view(card_data: Dictionary, context: String) -> Control:
	var dm := get_node_or_null("/root/DeckManager")
	if dm != null and dm.has_method("create_card_view"):
		return dm.create_card_view(card_data, context)
	return null

func _ready() -> void:
	if Engine.is_editor_hint(): return
	var guard := 0
	while not _data_ready() and guard < 900:
		await get_tree().process_frame
		guard += 1
	if not _data_ready():
		push_error("DECK EDITOR ERROR: CardDatabase has no card data loaded.")
		return
	_init_filters()
	_load_default_don()
	_layout_editor()
	
	# Back button
	var back_btn := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Header/HeaderBar/BackButton")
	if back_btn != null:
		(back_btn as Button).text = "< Back"
		if not (back_btn as Button).pressed.is_connected(_on_back_pressed):
			(back_btn as Button).pressed.connect(_on_back_pressed)
	
	DeckDropdown.item_selected.connect(_on_deck_selected)
	SaveButton.pressed.connect(_on_save_button_pressed)
	RenameButton.pressed.connect(_on_rename_button_pressed)
	DeleteButton.pressed.connect(_on_delete_button_pressed)
	save_file_dialog.file_selected.connect(_on_file_dialog_save)
	SearchBtn.pressed.connect(apply_filters)
	ApplyBtn.pressed.connect(apply_filters)
	ClearBtn.pressed.connect(_reset_filters)
	ImportButton.pressed.connect(_import_from_clipboard)
	if ExportButton != null:
		ExportButton.pressed.connect(_export_to_clipboard)
	var clear_main := get_node_or_null(clear_main_deck_button_path)
	if clear_main != null and not (clear_main as Button).pressed.is_connected(_on_clear_main_pressed):
		(clear_main as Button).pressed.connect(_on_clear_main_pressed)
	var clear_don := get_node_or_null(clear_don_deck_button_path)
	if clear_don != null and not (clear_don as Button).pressed.is_connected(_load_default_don):
		(clear_don as Button).pressed.connect(func():
			_load_default_don()
			_render_don_deck())
	if FilterToggle.has_signal("toggled"): FilterToggle.toggled.connect(_toggle_filters)
	else: FilterToggle.pressed.connect(_toggle_filters_pressed)
	NameSearch.text_changed.connect(_filters_changed)
	SetDropdown.item_selected.connect(_filters_changed_i)
	ColorDropdown.item_selected.connect(_filters_changed_i)
	TypeDropdown.item_selected.connect(_filters_changed_i)
	CardTypeDropdown.item_selected.connect(_filters_changed_i)
	FilterMethodDropdown.item_selected.connect(_filters_changed_i)
	ArchetypeDropdown.item_selected.connect(_filters_changed_i)
	AltArtToggle.toggled.connect(_filters_changed_b)
	ValidateButton.pressed.connect(_on_validate_deck_pressed)
	
	var prev_btn := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Body/Whole/TopFrame/Content/LeftSearch/LeftPanelVBox/PaginationBar/PrevPageButton")
	var next_btn := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Body/Whole/TopFrame/Content/LeftSearch/LeftPanelVBox/PaginationBar/NextPageButton")
	if prev_btn != null:
		(prev_btn as Button).text = "< Prev"
		(prev_btn as Button).pressed.connect(_on_prev_page)
	if next_btn != null:
		(next_btn as Button).text = "Next >"
		(next_btn as Button).pressed.connect(_on_next_page)

	_populate_deck_dropdown()
	_populate_format_dropdown()
	apply_filters()
	_render_don_deck()
	_update_deck_stats()

func _layout_editor() -> void:
	var frame := get_node_or_null("CanvasClamp/Frame1152x648")
	if frame is Control:
		(frame as Control).custom_minimum_size = Vector2(1152, 648)
		(frame as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(frame as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_search := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Body/Whole/TopFrame/Content/LeftSearch")
	if left_search is Control:
		(left_search as Control).custom_minimum_size = Vector2(460, 0)
		(left_search as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if SearchGrid != null:
		SearchGrid.columns = 5
		SearchGrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		SearchGrid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if MainDeckGrid != null:
		MainDeckGrid.columns = 10
		MainDeckGrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MainDeckGrid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		for leftover in MainDeckGrid.get_children():
			if leftover is Panel and leftover.name == "MainDeckPanel":
				leftover.queue_free()
	var header := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Header/HeaderBar")
	if header != null and DeckNameEdit != null and DeckNameEdit.get_parent() != header:
		if DeckNameEdit.get_parent() != null:
			DeckNameEdit.get_parent().remove_child(DeckNameEdit)
		header.add_child(DeckNameEdit)
		header.move_child(DeckNameEdit, mini(2, header.get_child_count() - 1))
		DeckNameEdit.visible = true
		DeckNameEdit.custom_minimum_size = Vector2(160, 0)
		DeckNameEdit.placeholder_text = "Deck name"
	if header != null:
		for npath in [validation_format_dropdown_path, validation_button_path]:
			var n := get_node_or_null(npath)
			if n != null and n.get_parent() != header:
				if n.get_parent() != null:
					n.get_parent().remove_child(n)
				header.add_child(n)
				n.visible = true
		if ValidationResultLabel != null and ValidationResultLabel.get_parent() != header:
			if ValidationResultLabel.get_parent() != null:
				ValidationResultLabel.get_parent().remove_child(ValidationResultLabel)
			header.add_child(ValidationResultLabel)
			ValidationResultLabel.visible = true
			ValidationResultLabel.custom_minimum_size = Vector2(180, 24)
	_ensure_leader_slot()
	if header != null:
		_add_hand_test(header)

func _ensure_leader_slot() -> void:
	if LeaderContainer == null:
		return
	var right := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Body/Whole/TopFrame/Content/RightCombined")
	if right == null:
		return
	if LeaderContainer.get_parent() != right:
		if LeaderContainer.get_parent() != null:
			LeaderContainer.get_parent().remove_child(LeaderContainer)
		right.add_child(LeaderContainer)
		right.move_child(LeaderContainer, 0)
	LeaderContainer.visible = true
	LeaderContainer.custom_minimum_size = Vector2(0, 150)
	LeaderContainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
func _init_filters() -> void:
	SetDropdown.clear()
	SetDropdown.add_item("All Sets")
	var sets = []
	for card in _all_cards():
		var card_set_name = card.get("set_name")
		if card_set_name and not card_set_name in sets: sets.append(card_set_name)
	sets.sort()
	for card_set in sets: SetDropdown.add_item(card_set)
	ColorDropdown.clear(); for c in ["All","Red","Green","Blue","Purple","Black","Yellow"]: ColorDropdown.add_item(c)
	TypeDropdown.clear(); for t in ["All","Leader","Character","Event","Stage"]: TypeDropdown.add_item(t)
	CardTypeDropdown.clear(); for s in ["Any","Slash","Strike","Ranged","Wisdom","Special"]: CardTypeDropdown.add_item(s)
	FilterMethodDropdown.clear(); for m in ["Contains","Starts With","Exact"]: FilterMethodDropdown.add_item(m)
	ArchetypeDropdown.clear(); for a in ["Any","Navy","Animal","Supernovas","Donquixote","Straw Hat"]: ArchetypeDropdown.add_item(a)

func _populate_deck_dropdown() -> void:
	DeckDropdown.clear()
	var names: Array = []
	for dir_path in [DECK_SAVE_DIR, DECK_USER_DIR]:
		var dir = DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".json") or file_name.ends_with(".deck"):
					names.append([file_name, dir_path + file_name])
			file_name = dir.get_next()
	names.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	for entry in names:
		DeckDropdown.add_item(String(entry[0]).get_basename())
		DeckDropdown.set_item_metadata(DeckDropdown.item_count - 1, String(entry[1]))
	if DeckDropdown.item_count > 0:
		_on_deck_selected(0)
	else:
		_clear_deck()

func _on_deck_selected(index: int) -> void:
	var deck_name = DeckDropdown.get_item_text(index)
	DeckNameEdit.text = deck_name
	var meta = DeckDropdown.get_item_metadata(index)
	if meta != null and String(meta) != "":
		current_deck_path = String(meta)
	else:
		current_deck_path = DECK_SAVE_DIR + deck_name + ".json"
	_load_deck_from_file(current_deck_path)

func _load_deck_from_file(path: String) -> void:
	_clear_deck()
	var loaded := MtDeckLoader.load_deck_file(path, _lookup_card)
	if loaded.get("leader", {}) is Dictionary and not (loaded.get("leader", {}) as Dictionary).is_empty():
		leader_card = loaded.leader
	var main_cards: Array = loaded.get("main", [])
	for card_info in main_cards:
		if card_info is Dictionary and not (card_info as Dictionary).is_empty():
			main_deck.append(card_info)
	DeckNameEdit.text = path.get_file().get_basename()
	_render_main_deck()
	_update_deck_stats()

func _on_save_button_pressed() -> void:
	var deck_name = DeckNameEdit.text.strip_edges()
	if deck_name.is_empty(): return
	var path = DECK_SAVE_DIR + deck_name + ".json"
	_save_deck_to_file(path)
	_populate_deck_dropdown()
	var new_index = -1
	for i in range(DeckDropdown.item_count):
		if DeckDropdown.get_item_text(i) == deck_name:
			new_index = i
			break
	if new_index != -1: DeckDropdown.select(new_index)


func _on_rename_button_pressed() -> void:
	save_file_dialog.popup_centered()

func _on_delete_button_pressed() -> void:
	if current_deck_path.is_empty() or not FileAccess.file_exists(current_deck_path): return
	DirAccess.remove_absolute(current_deck_path)
	current_deck_path = ""
	_clear_deck()
	_populate_deck_dropdown()

func _on_file_dialog_save(path: String) -> void:
	if not path.ends_with(".json"): path += ".json"
	_save_deck_to_file(path)
	_populate_deck_dropdown()
	var new_deck_name = path.get_file().get_basename()
	var new_index = -1
	for i in range(DeckDropdown.item_count):
		if DeckDropdown.get_item_text(i) == new_deck_name:
			new_index = i
			break
	if new_index != -1: DeckDropdown.select(new_index)

func _save_deck_to_file(path: String) -> void:
	var deck_to_save := {"leader": "", "main": []}
	if not leader_card.is_empty():
		deck_to_save.leader = leader_card.get("card_code", "")
	for card_data in main_deck:
		deck_to_save.main.append(card_data.get("card_code", ""))
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(deck_to_save, "\t"))

func _selected_format() -> Dictionary:
	if FormatDropdown == null or FormatDropdown.selected < 0:
		return {}
	return RulesManager.get_format_by_name(FormatDropdown.get_item_text(FormatDropdown.selected))

func _banlist() -> Dictionary:
	return _selected_format().get("banlist_data", {})

func _format_raw() -> Dictionary:
	return _selected_format().get("format_raw", {})

func _note_construction() -> void:
	if leader_card.is_empty() or main_deck.is_empty():
		return
	var lines: PackedStringArray = PackedStringArray()
	for e in MtDeckLoader.validate_deck({"leader": leader_card, "main": main_deck}, _banlist(), _format_raw(), MtDeckLoader.load_blocks()):
		var s := String(e)
		if s.begins_with("Main deck must contain"):
			continue
		lines.append(s)
	if lines.is_empty():
		return
	ValidationResultLabel.text = "[color=red]This Leader makes the deck illegal:[/color]\n- " + "\n- ".join(lines)

func _on_validate_deck_pressed() -> void:
	var selected_id = FormatDropdown.get_selected_id()
	if selected_id < 0:
		ValidationResultLabel.text = "[color=orange]Please select a format.[/color]"
		return
	var format_name = FormatDropdown.get_item_text(selected_id)
	var errors: Array[String] = RulesManager.validate_built_deck(leader_card, main_deck, format_name)
	if errors.is_empty():
		ValidationResultLabel.text = "[color=green]Deck is LEGAL for '%s' format.[/color]" % format_name
	else:
		var error_text = "[color=red]Deck is ILLEGAL for '%s' format:[/color]\n" % format_name
		for error in errors:
			error_text += "- %s\n" % error
		ValidationResultLabel.text = error_text

func _populate_format_dropdown() -> void:
	FormatDropdown.clear()
	var format_names = RulesManager.get_all_format_names()
	for i in range(format_names.size()): FormatDropdown.add_item(format_names[i], i)

func apply_filters() -> void:
	_filtered_results.clear()
	_current_page = 0
	var name_text = NameSearch.text.strip_edges().to_lower()
	var color_text = ColorDropdown.get_item_text(ColorDropdown.selected)
	var type_text  = TypeDropdown.get_item_text(TypeDropdown.selected)
	var subtype = CardTypeDropdown.get_item_text(CardTypeDropdown.selected)
	var method = FilterMethodDropdown.get_item_text(FilterMethodDropdown.selected)
	var arch = ArchetypeDropdown.get_item_text(ArchetypeDropdown.selected)
	var setname = SetDropdown.get_item_text(SetDropdown.selected)
	var alt_on = AltArtToggle.button_pressed
	var all_cards = _all_cards()
	for card_data in all_cards:
		if _passes_filters(card_data, name_text, color_text, type_text, subtype, method, arch, setname, alt_on):
			_filtered_results.append(card_data)
	_total_pages = maxi(1, ceili(float(_filtered_results.size()) / CARDS_PER_PAGE))
	_render_search_page()

func _render_main_deck() -> void:
	if not is_instance_valid(LeaderContainer): return
	_clear_children(MainDeckGrid)
	_clear_children(LeaderContainer)
	if not leader_card.is_empty(): add_card_to_container(LeaderContainer, leader_card, "leader")
	main_deck.sort_custom(func(a,b): return CARD_TYPE_ORDER.get(a.get("type", "Character"), 99) < CARD_TYPE_ORDER.get(b.get("type", "Character"), 99))
	for card in main_deck: add_card_to_container(MainDeckGrid, card, "main")
	_update_deck_stats()

func _render_don_deck() -> void:
	_clear_children(DonDeckContainer)
	for card_data in don_deck: add_card_to_container(DonDeckContainer, card_data, "don")

func add_card_to_container(container: Container, card_data: Dictionary, context: String):
	if not is_instance_valid(container): return
	var card_node = _make_card_view(card_data, context)
	if card_node == null:
		return
	card_node.request_add_to_main.connect(add_card_to_main_deck)
	card_node.request_remove_from_main.connect(_on_remove_card_from_deck)
	var aspect_wrapper = AspectRatioContainer.new()
	aspect_wrapper.ratio = CARD_ASPECT_RATIO
	aspect_wrapper.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect_wrapper.custom_minimum_size = Vector2(72, 100)
	aspect_wrapper.size_flags_horizontal = SIZE_FILL
	aspect_wrapper.size_flags_vertical = SIZE_FILL
	aspect_wrapper.add_child(card_node)
	container.add_child(aspect_wrapper)

func add_card_to_main_deck(card: Dictionary):
	if card.get("type", "") == "Leader":
		leader_card = card
		_load_default_don()
		_render_main_deck()
		_update_deck_stats()
		_note_construction()
		return
	if card.get("type", "") == "DON!!":
		return
	if main_deck.size() >= 50:
		ValidationResultLabel.text = "Main deck is already 50 cards."
		return
	var reason := MtDeckLoader.why_not_add(leader_card, card, main_deck, _banlist(), _format_raw(), MtDeckLoader.load_blocks())
	if reason != "":
		ValidationResultLabel.text = reason
		return
	main_deck.append(card)
	_render_main_deck()
	_update_deck_stats()

func _on_add_card_to_deck(card: Dictionary):
	add_card_to_main_deck(card)

func _on_remove_card_from_deck(card: Dictionary):
	if leader_card == card:
		leader_card = {}
	else:
		var id_to_remove = card.get("card_code")
		for i in range(main_deck.size() - 1, -1, -1):
			if main_deck[i].get("card_code") == id_to_remove:
				main_deck.remove_at(i)
				break
	_render_main_deck()
	_update_deck_stats()

func _passes_filters(card, name, color, type, subtype, method, arch, setname, alt_on) -> bool:
	if color != "" and color != "All" and not MtDeckLoader.card_colors(card).has(color): return false
	if type  != "" and type != "All" and String(card.get("type",""))  != type:  return false
	if subtype != "" and subtype != "Any":
		if not Array(card.get("tags", [])).has(subtype): return false
	if arch != "" and arch != "Any" and String(card.get("archetype","")) != arch: return false
	if setname != "" and setname != "All Sets" and String(card.get("set_name","")) != setname: return false
	if not alt_on and String(card.get("art_type", "")) == "AA": return false
	var region := String(card.get("region", "EN")).to_upper()
	if region != "" and region != "EN": return false
	var nm = String(card.get("name","")).to_lower()
	if not name.is_empty():
		match method:
			"Starts With":
				if not nm.begins_with(name): return false
			"Exact":
				if nm != name: return false
			_:
				if not nm.contains(name): return false
	return true

func _clear_deck():
	leader_card = {}
	main_deck.clear()
	DeckNameEdit.text = ""
	_render_main_deck()
	_update_deck_stats()
	ValidationResultLabel.text = "Deck cleared."

func _load_default_don():
	don_deck.clear()
	var n := DON_SLOTS
	if not leader_card.is_empty():
		var r: Dictionary = MtEffectParser.parse(leader_card).get("rules", {})
		n = int(r.get("don_deck_size", DON_SLOTS))
	var don_card := _lookup_card("DON-001")
	if don_card.is_empty():
		don_card = {"type": "DON!!", "name": "Don!!"}
	for i in n:
		don_deck.append(don_card.duplicate())
	if is_instance_valid(DonDeckContainer):
		_render_don_deck()

func _update_deck_stats():
	var character = 0; var event = 0; var stage = 0
	for item in main_deck:
		var t = String(item.get("type",""))
		if t == "Character": character += 1
		elif t == "Event": event += 1
		elif t == "Stage": stage += 1
	var leader_set_text = "1/1" if not leader_card.is_empty() else "0/1"
	StatsLine1.text = "Main Deck: %d/50 (max 4 per card)" % main_deck.size()
	StatsLine2.text = "Leader: %s | DON!!: %d/%d | Chars: %d | Events: %d | Stages: %d" % [
		leader_set_text, don_deck.size(), don_deck.size(), character, event, stage]

func _export_to_clipboard() -> void:
	var lines: Array = []
	if not leader_card.is_empty():
		lines.append("1x%s" % String(leader_card.get("card_code", "")))
	var counts: Dictionary = {}
	var order: Array = []
	for card in main_deck:
		var code := String(card.get("card_code", ""))
		if code.is_empty():
			continue
		if not counts.has(code):
			order.append(code)
			counts[code] = 0
		counts[code] = int(counts[code]) + 1
	for code in order:
		lines.append("%dx%s" % [int(counts[code]), code])
	DisplayServer.clipboard_set("\n".join(lines))
	ValidationResultLabel.text = "Exported %d main-deck cards to clipboard." % main_deck.size()

func _on_clear_main_pressed() -> void:
	main_deck.clear()
	_render_main_deck()
	_update_deck_stats()

func _import_from_clipboard():
	var s = DisplayServer.clipboard_get().strip_edges()
	if s.is_empty(): return
	var id_to_count = {}
	var line_re := RegEx.new()
	line_re.compile(r"(?i)^(\d+)\s*x\s*([A-Z]+\d+-\d+\w*)$")
	var lines = s.split("\n", false)
	for line in lines:
		var tline = line.strip_edges()
		if tline.is_empty(): continue
		var id := ""
		var count := 1
		var m := line_re.search(tline.replace(" ", ""))
		if m != null:
			count = int(m.get_string(1))
			id = m.get_string(2).to_upper()
		else:
			id = tline.to_upper()
		if id != "":
			id_to_count[id] = int(id_to_count.get(id, 0)) + count
	_clear_deck()
	for id_key in id_to_count:
		var base = _lookup_card(id_key)
		if not base.is_empty():
			for _i in range(int(id_to_count[id_key])):
				add_card_to_main_deck(base)
	_render_main_deck()
	_update_deck_stats()

func _clear_children(n: Node):
	if not is_instance_valid(n): return
	for c in n.get_children(): c.queue_free()

func _toggle_filters(on: bool): FiltersRow.visible = on
func _toggle_filters_pressed(): FiltersRow.visible = not FiltersRow.visible
func _filters_changed(_s: String):
	apply_filters()
func _filters_changed_i(_i: int):
	apply_filters()
func _filters_changed_b(_b: bool):
	apply_filters()

func _reset_filters() -> void:
	NameSearch.text = ""
	SetDropdown.select(0)
	ColorDropdown.select(0)
	TypeDropdown.select(0)
	CardTypeDropdown.select(0)
	FilterMethodDropdown.select(0)
	ArchetypeDropdown.select(0)
	AltArtToggle.button_pressed = false
	apply_filters()

# --- Pagination ---

func _render_search_page() -> void:
	_clear_children(SearchGrid)
	var start_idx: int = _current_page * CARDS_PER_PAGE
	var end_idx: int = mini(start_idx + CARDS_PER_PAGE, _filtered_results.size())
	for i in range(start_idx, end_idx):
		add_card_to_container(SearchGrid, _filtered_results[i], "search")
	_update_pagination_ui()

func _update_pagination_ui() -> void:
	var page_label := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Body/Whole/TopFrame/Content/LeftSearch/LeftPanelVBox/PaginationBar/PageLabel")
	var prev_btn := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Body/Whole/TopFrame/Content/LeftSearch/LeftPanelVBox/PaginationBar/PrevPageButton")
	var next_btn := get_node_or_null("CanvasClamp/Frame1152x648/Inset/RootVBox/Body/Whole/TopFrame/Content/LeftSearch/LeftPanelVBox/PaginationBar/NextPageButton")
	if page_label != null:
		(page_label as Label).text = "Page %d / %d  (%d cards)" % [_current_page + 1, _total_pages, _filtered_results.size()]
	if prev_btn != null:
		(prev_btn as Button).disabled = _current_page <= 0
	if next_btn != null:
		(next_btn as Button).disabled = _current_page >= _total_pages - 1

func _on_prev_page() -> void:
	if _current_page > 0:
		_current_page -= 1
		_render_search_page()

func _on_next_page() -> void:
	if _current_page < _total_pages - 1:
		_current_page += 1
		_render_search_page()

func _add_hand_test(header: Node) -> void:
	if header == null:
		return
	var btn := Button.new()
	btn.text = "Test hand"
	btn.tooltip_text = "Draw 5 cards from this deck. One mulligan, same as a duel."
	btn.pressed.connect(_deal_test.bind(true))
	header.add_child(btn)

func _ensure_test_panel() -> void:
	if _test_layer != null:
		return
	_test_layer = PanelContainer.new()
	_test_layer.visible = false
	_test_layer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_test_layer.offset_left = -460
	_test_layer.offset_right = 460
	_test_layer.offset_top = -230
	_test_layer.offset_bottom = -12
	add_child(_test_layer)
	var box := VBoxContainer.new()
	_test_layer.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var again := Button.new()
	again.text = "New hand"
	again.pressed.connect(_deal_test.bind(true))
	row.add_child(again)
	var mull := Button.new()
	mull.text = "Mulligan"
	mull.pressed.connect(_on_test_mulligan)
	row.add_child(mull)
	var close_b := Button.new()
	close_b.text = "Close"
	close_b.pressed.connect(func() -> void: _test_layer.visible = false)
	row.add_child(close_b)
	_test_cards = HBoxContainer.new()
	_test_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_test_cards)

func _deal_test(fresh: bool) -> void:
	if main_deck.size() < 5:
		ValidationResultLabel.text = "The main deck needs at least 5 cards to test a hand."
		return
	if fresh:
		_test_used = false
	_show_test(MtDeckLoader.opening_hand(main_deck))

func _on_test_mulligan() -> void:
	if _test_used:
		ValidationResultLabel.text = "That hand already took its mulligan."
		return
	_test_used = true
	_show_test(MtDeckLoader.opening_hand(main_deck))

func _show_test(cards: Array) -> void:
	_ensure_test_panel()
	for c in _test_cards.get_children():
		c.queue_free()
	for card in cards:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(120, 0)
		_test_cards.add_child(col)
		var data: Dictionary = card
		var path := String(data.get("image_path", ""))
		if path != "" and ResourceLoader.exists(path):
			var art := TextureRect.new()
			art.texture = load(path)
			art.custom_minimum_size = Vector2(110, 150)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			col.add_child(art)
		var lab := Label.new()
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.text = "%s\nCost %s" % [String(data.get("name", data.get("card_name", "?"))), str(data.get("cost", ""))]
		col.add_child(lab)
	_test_layer.visible = true
	ValidationResultLabel.text = "Opening hand. Mulligan redraws all 5, once."

# --- Navigation ---

func _on_back_pressed() -> void:
	var ui_manager = get_parent()
	var dest := _previous_scene_path if not _previous_scene_path.is_empty() else "res://scenes/ui/PostLogin.tscn"
	if ui_manager and ui_manager.has_method("switch_scene"):
		ui_manager.switch_scene(dest)

func set_previous_scene(path: String) -> void:
	if path != "":
		_previous_scene_path = path

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back_pressed()
		get_viewport().set_input_as_handled()
