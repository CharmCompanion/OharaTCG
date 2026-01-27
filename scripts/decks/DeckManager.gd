extends Node

var card_scene: PackedScene = preload("res://scenes/cards/card.tscn")

const BASE_IMAGE_PATH := "res://assets/cards/Base/BaseCard.png"

func create_card(card_data: Dictionary, field: Node, spawn_multiple: bool = true) -> Array:
	var results := []

	if card_scene == null:
		push_error("Card.tscn scene not found.")
		return results

	var count := int(card_data.get("count", 1))
	var to_spawn := count if spawn_multiple else 1
	for i in range(to_spawn):
		var card = card_scene.instantiate()
		card.setup(card_data.duplicate(true), field)
		results.append(card)

	return results

func assign_card_image_path(card_data: Dictionary) -> void:
	var set_code = card_data.get("set_code", "")
	var card_code = card_data.get("card_code", "")
	var card_type = card_data.get("type", "")
	var zone = card_data.get("zone", "")

	# Normalize set_code to match folder naming under res://assets/cards.
	# The DB sometimes uses values like "OP-01" or "ST-01".
	set_code = str(set_code).strip_edges().to_upper().replace("-", "").replace(" ", "")
	card_code = str(card_code).strip_edges().to_upper()

	if card_type == "DON!!":
		card_data["image_path"] = "res://assets/cards/Don/Don.png"
		return

	if card_code == "" or set_code == "":
		card_data["image_path"] = BASE_IMAGE_PATH
		return

	var resolved_path := _resolve_card_image_path(set_code, card_code, zone == "search")
	card_data["image_path"] = resolved_path

func _resolve_card_image_path(set_code: String, card_code: String, prefer_small: bool) -> String:
	var base_dir := "res://assets/cards/%s/" % set_code

	# Some sources encode variants as suffixes like "ST16-029_R1" or "ST16-057_P1",
	# while the local assets are typically stored under the base code ("ST16-029.png").
	# Try exact match first, then fall back to the base portion before an underscore.
	var codes_to_try := [card_code]
	if card_code.contains("_"):
		var base_code := card_code.split("_")[0]
		if base_code != "" and base_code != card_code:
			codes_to_try.append(base_code)

	for code_try in codes_to_try:
		var full_size := [
			"%s%s.png" % [base_dir, code_try],
			"%s%s.jpg" % [base_dir, code_try],
			"%s%s.jpeg" % [base_dir, code_try],
		]
		var small_size := [
			"%s%s_small.png" % [base_dir, code_try],
			"%s%s_small.jpg" % [base_dir, code_try],
			"%s%s_small.jpeg" % [base_dir, code_try],
		]
		var candidates := []
		if prefer_small:
			candidates.append_array(small_size)
			candidates.append_array(full_size)
		else:
			candidates.append_array(full_size)
			candidates.append_array(small_size)

		for path in candidates:
			if ResourceLoader.exists(path):
				return path

	# Fallback: OPTCGSim local build (Unity StreamingAssets). This contains a full
	# set-organized card image library (e.g. OP01/OP01-001.png, ST01/ST01-001.jpg).
	var sim_dir := "res://addons/Builds_Windows/OPTCGSim_Data/StreamingAssets/Cards/%s/" % set_code
	for code_try in codes_to_try:
		var sim_full_size := [
			"%s%s.png" % [sim_dir, code_try],
			"%s%s.jpg" % [sim_dir, code_try],
			"%s%s.jpeg" % [sim_dir, code_try],
		]
		var sim_small_size := [
			"%s%s_small.png" % [sim_dir, code_try],
			"%s%s_small.jpg" % [sim_dir, code_try],
			"%s%s_small.jpeg" % [sim_dir, code_try],
		]
		var sim_candidates := []
		if prefer_small:
			sim_candidates.append_array(sim_small_size)
			sim_candidates.append_array(sim_full_size)
		else:
			sim_candidates.append_array(sim_full_size)
			sim_candidates.append_array(sim_small_size)

		for path in sim_candidates:
			if ResourceLoader.exists(path):
				return path

	# Fallback: scraper output images (flat layout) may contain art even when
	# the assets/cards folder hasn't been fully synced yet.
	var output_dir := "res://output/images/cards/"
	for code_try in codes_to_try:
		var output_candidates := []
		if prefer_small:
			output_candidates.append("%s%s_small.png" % [output_dir, code_try])
			output_candidates.append("%s%s_small.jpg" % [output_dir, code_try])
			output_candidates.append("%s%s_small.jpeg" % [output_dir, code_try])
		output_candidates.append("%s%s.png" % [output_dir, code_try])
		output_candidates.append("%s%s.jpg" % [output_dir, code_try])
		output_candidates.append("%s%s.jpeg" % [output_dir, code_try])

		for path in output_candidates:
			if ResourceLoader.exists(path):
				return path

	return BASE_IMAGE_PATH

func load_json(path: String) -> Variant:
	var cache_path := _resolve_cache_path(path)
	var final_path := cache_path if FileAccess.file_exists(cache_path) else path

	if not FileAccess.file_exists(final_path):
		push_error("JSON not found: %s" % final_path)
		return null

	var file = FileAccess.open(final_path, FileAccess.READ)
	if file == null:
		push_error("Couldn't open file: %s" % final_path)
		return null

	var json_str = file.get_as_text()
	var result = JSON.parse_string(json_str)
	if result == null:
		push_error("Failed to parse JSON: %s" % final_path)
	return result

func _resolve_cache_path(path: String) -> String:
	if not path.begins_with("res://"):
		return path
	return path.replace("res://", "user://cache/")

func load_main_deck(path: String) -> Dictionary:
	var data = load_json(path)
	if typeof(data) != TYPE_DICTIONARY or not data.has("main"):
		push_error("Deck JSON must have 'main' section")
		return {}
	return data

func load_don_deck(path: String) -> Dictionary:
	var data = load_json(path)
	if typeof(data) != TYPE_DICTIONARY or not data.has("don"):
		push_error("Deck JSON must have 'don' section")
		return {}
	return data
