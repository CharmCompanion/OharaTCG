extends PanelContainer

# This script creates its own UI, so it no longer needs @onready variables.
var status_label: Label
var update_button: Button
var progress_bar: ProgressBar
var log_view: RichTextLabel

# --- Configuration (unchanged) ---
const API_BASE_URL = "https://api.apitcg.com/one-piece/cards"
const JSON_SAVE_PATH = "res://assets/JSON/cards.json"
const CARD_DATA_RESOURCE_PATH = "res://data/card_data.gd"
const CARD_OUTPUT_FOLDER = "res://data/cards/"
const DECK_OUTPUT_FOLDER = "res://data/decks/"
const DECK_DATA = {
	"ST01-StrawHats.json": """[
{ "id": "ST01-001", "count": 1 }, { "id": "ST01-006", "count": 4 }, { "id": "ST01-007", "count": 4 },
{ "id": "ST01-002", "count": 4 }, { "id": "ST01-003", "count": 4 }, { "id": "ST01-011", "count": 2 },
{ "id": "ST01-004", "count": 4 }, { "id": "ST01-009", "count": 4 }, { "id": "ST01-005", "count": 4 },
{ "id": "ST01-008", "count": 4 }, { "id": "ST01-013", "count": 2 }, { "id": "ST01-010", "count": 4 },
{ "id": "ST01-012", "count": 2 }, { "id": "ST01-014", "count": 2 }, { "id": "ST01-016", "count": 2 },
{ "id": "ST01-015", "count": 2 }, { "id": "ST01-017", "count": 2 }
]"""
}

var http_request: HTTPRequest

func _ready():
	hide()
	build_ui()
	hide()
	update_button.pressed.connect(_on_update_button_pressed)

func build_ui():
	hide()
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "Content Updater"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	status_label = Label.new()
	status_label.text = "Ready to check for updates."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	update_button = Button.new()
	update_button.text = "Download and Process All Card Data"
	vbox.add_child(update_button)

	progress_bar = ProgressBar.new()
	progress_bar.value = 100.0
	progress_bar.show_percentage = false
	vbox.add_child(progress_bar)
	
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.text = "Log will appear here..."
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(log_view)


# --- The rest of the logic is the same ---

func _log(message: String):
	print(message)
	log_view.append_text(message + "\n")

func _on_update_button_pressed():
	update_button.disabled = true
	log_view.clear()
	progress_bar.value = 0
	await get_tree().process_frame
	_run_update()

func _run_update():
	var all_card_results = []
	var current_page = 1
	var total_pages = 1

	status_label.text = "Downloading card data..."
	_log("Step 1: Downloading from API...")
	
	while current_page <= total_pages:
		status_label.text = "Downloading page %d of %d..." % [current_page, total_pages]
		var page_data = await _fetch_page(current_page)
		if page_data == null:
			status_label.text = "Update Failed! Check logs."
			update_button.disabled = false
			return
		
		all_card_results.append_array(page_data.get("data", []))
		total_pages = page_data.get("totalPages", 1)
		_log("...Downloaded page %d of %d." % [current_page, total_pages])
		current_page += 1

	status_label.text = "Saving database file..."
	await get_tree().process_frame
	_save_json_file(all_card_results)

	status_label.text = "Processing cards..."
	await get_tree().process_frame
	var card_count = await _convert_cards_from_json()

	if card_count > 0:
		status_label.text = "Generating starter decks..."
		await get_tree().process_frame
		_generate_deck_files()

	_log("\n[color=green]--- ALL TASKS COMPLETE! ---[/color]")
	status_label.text = "Update Complete! (%d cards processed)" % card_count
	update_button.disabled = false
	progress_bar.value = progress_bar.max_value

func _fetch_page(page_num: int) -> Variant:
	http_request = HTTPRequest.new()
	add_child(http_request)
	
	var url = "%s?limit=100&page=%d" % [API_BASE_URL, page_num]
	var key := _api_key()
	if key == "":
		_log("No API key. Set OHARA_API_KEY or write it to user://api_key.txt.")
		status_label.text = "Update Failed! No API key."
		update_button.disabled = false
		return
	var headers = ["x-api-key: " + key]
	var error = http_request.request(url, headers)
	
	if error != OK:
		_log("[color=red]Error: HTTPRequest failed for page %d.[/color]" % page_num)
		return null

	var response = await http_request.request_completed
	http_request.queue_free()

	var response_code = response[1]
	var body = response[3]
	
	if response_code != 200:
		_log("[color=red]Error: API request for page %d failed with status code: %d[/color]" % [page_num, response_code])
		return null
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json is Dictionary:
		return json
	
	_log("[color=red]Error: API response for page %d was not a valid Dictionary.[/color]" % page_num)
	return null

func _save_json_file(content: Array):
	_log("\nStep 2: Saving downloaded data to %s" % JSON_SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(JSON_SAVE_PATH.get_base_dir())
	var file = FileAccess.open(JSON_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(content, "\t"))
		_log("Successfully saved card database.")
	else:
		_log("[color=red]Error: Failed to save JSON file.[/color]")

func _convert_cards_from_json() -> int:
	_log("\nStep 3: Converting card data to Godot resources...")
	var file = FileAccess.open(JSON_SAVE_PATH, FileAccess.READ)
	if not file:
		_log("[color=red]Error: Failed to open cards.json at %s[/color]" % JSON_SAVE_PATH)
		return 0
			
	var json_data = JSON.parse_string(file.get_as_text())
	if not json_data is Array:
		_log("[color=red]Error: cards.json is not a valid JSON array.[/color]")
		return 0
	
	DirAccess.make_dir_recursive_absolute(CARD_OUTPUT_FOLDER)

	var unique_cards = {}
	for card_dict in json_data:
		var card_code = card_dict.get("id", "")
		if not card_code.is_empty() and not unique_cards.has(card_code):
			unique_cards[card_code] = card_dict
	
	var total_cards = unique_cards.size()
	progress_bar.max_value = total_cards
	var current_card = 0

	for card_code in unique_cards:
		var card_dict = unique_cards[card_code]
		var card_data = load(CARD_DATA_RESOURCE_PATH).new()
		
		card_data.card_id = card_dict.get("id", "")
		card_data.card_name = card_dict.get("name", "")
		card_data.card_type = card_dict.get("type", "").to_upper()
		
		var raw_colors = card_dict.get("color", "").split("/")
		var typed_colors: Array[String] = []
		for color_item in raw_colors:
			typed_colors.append(color_item.strip_edges())
		card_data.color = typed_colors
		
		card_data.cost = card_dict.get("cost", 0)
		card_data.power = card_dict.get("power", -1)
		
		var counter_val = card_dict.get("counter", "0")
		card_data.counter = int(counter_val) if counter_val.is_valid_int() else 0
		
		card_data.rarity = card_dict.get("rarity", "")
		
		var attribute_dict = card_dict.get("attribute", {})
		if attribute_dict is Dictionary:
			card_data.attribute = attribute_dict.get("name", "")
		
		card_data.traits = card_dict.get("family", "").split("/")
		card_data.effect_text = card_dict.get("ability", "")
		
		var save_path = "%s/%s.tres" % [CARD_OUTPUT_FOLDER, card_data.card_id]
		ResourceSaver.save(card_data, save_path)
		
		current_card += 1
		if current_card % 20 == 0:
			progress_bar.value = current_card
			status_label.text = "Processing card %d / %d" % [current_card, total_cards]
			await get_tree().process_frame

	_log("Card data conversion complete! Processed %d unique cards." % total_cards)
	return total_cards

func _generate_deck_files():
	_log("\nStep 4: Generating starter deck files...")
	DirAccess.make_dir_recursive_absolute(DECK_OUTPUT_FOLDER)
	
	for filename in DECK_DATA:
		var file_path = DECK_OUTPUT_FOLDER.path_join(filename)
		var file_content = DECK_DATA[filename]
		
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_string(file_content)
			_log("Created deck file: " + file_path)
		else:
			_log("[color=red]Error: Failed to create deck file: %s[/color]" % file_path)
			
	_log("Deck generation complete!")

func _api_key() -> String:
	var from_env := OS.get_environment("OHARA_API_KEY").strip_edges()
	if from_env != "":
		return from_env
	var path := "user://api_key.txt"
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	return ""
