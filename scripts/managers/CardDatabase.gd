# res://scripts/managers/CardDatabase.gd
extends Node

# --- Master Data Lists ---
var all_cards: Dictionary = {}        # Keyed by unique variant_id
var base_card_map: Dictionary = {}    # Keyed by base card_code -> variant_index 0 card
var texture_cache: Dictionary = {}    # Cache for card textures
var is_data_loaded := false

func _ready() -> void:
	if OS.get_name() == "Android":
		OS.request_permission("android.permission.READ_MEDIA_IMAGES")
		OS.request_permission("android.permission.READ_EXTERNAL_STORAGE")
	call_deferred("start_background_card_load")

# --- Main Loading Trigger ---
func start_background_card_load() -> void:
	if is_data_loaded: return

	print("CardDatabase: Starting background card data load...")
	_load_all_card_data()
	# NOTE: textures load LAZILY via get_cached_texture() on first display.
	# Eagerly preloading all ~5k arts exhausts GPU VRAM (vmaCreateImage -2
	# crashes) on real hardware, so no bulk preload happens here.

	is_data_loaded = true
	print("CardDatabase: Loading complete. %d unique cards (%d base) and %d textures loaded." % [
		all_cards.size(), base_card_map.size(), texture_cache.size()
	])

func reload() -> void:
	all_cards.clear()
	base_card_map.clear()
	is_data_loaded = false
	start_background_card_load()

# --- Public API ---
func get_card_data(card_id: String) -> Dictionary:
	if all_cards.has(card_id):
		return all_cards[card_id]
	if base_card_map.has(card_id):
		return base_card_map[card_id]
	return {}

func get_don_card() -> Dictionary:
	return get_card_data("DON-001")

func get_all_card_data_as_array() -> Array:
	return all_cards.values()

func get_base_cards_as_array() -> Array:
	return base_card_map.values()

# --- Variant helpers ---
func get_variants(card_code: String) -> Array:
	var out: Array = []
	for card_data in all_cards.values():
		if card_data.get("card_code", "") == card_code:
			out.append(card_data)
	out.sort_custom(func(a, b): return int(a.get("variant_index", 0)) < int(b.get("variant_index", 0)))
	return out

func get_has_variants(card_code: String) -> bool:
	var base := base_card_map.get(card_code, {})
	if base.is_empty(): return false
	return int(base.get("variant_index", 0)) == 0 and get_variants(card_code).size() > 1

func get_cached_texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if texture_cache.has(path):
		return texture_cache[path]
	var tex: Texture2D = null
	if path.begins_with("res://") and FileAccess.file_exists(path):
		tex = load(path)
	if tex == null:
		var outside := external_file(path)
		if outside != "":
			var img := Image.new()
			if img.load(outside) == OK:
				tex = ImageTexture.create_from_image(img)
	if tex != null:
		texture_cache[path] = tex
	return tex

func external_file(res_path: String) -> String:
	const PREFIX := "res://assets/cards/"
	if not res_path.begins_with(PREFIX):
		return ""
	var rel := res_path.trim_prefix(PREFIX)
	for root in _card_roots():
		var abs_path := root.path_join(rel)
		if FileAccess.file_exists(abs_path):
			return abs_path
	return ""

func _card_roots() -> PackedStringArray:
	var roots: PackedStringArray = [ProjectSettings.globalize_path("user://cards")]
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads != "":
		roots.append(downloads.path_join("OharaTCG/cards"))
	return roots

# --- Private Loading Functions ---
func _load_all_card_data() -> void:
	_load_directory("res://data/cards/sets/")
	_load_directory("res://data/cards/alts/")

func _load_directory(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and file_name != "." and file_name != "..":
				_load_directory(path.path_join(file_name))
			elif file_name.ends_with(".json") and not file_name.ends_with("manifest.json"):
				_load_json_file(path.path_join(file_name))
			file_name = dir.get_next()
	else:
		printerr("CardDatabase: Could not open directory: %s" % path)

func _load_json_file(file_path: String) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		printerr("CardDatabase: Failed to open JSON file: %s" % file_path)
		return

	var json_result = JSON.parse_string(file.get_as_text())
	if not json_result:
		printerr("CardDatabase: Failed to parse JSON from: %s" % file_path)
		return

	var card_list = json_result.get("main", json_result)
	if card_list is Array:
		for card in card_list:
			if card is Dictionary:
				var vid: String = card.get("variant_id", card.get("card_code", ""))
				if vid.is_empty(): continue

				var card_with_path = _assign_card_image_path(card)
				all_cards[vid] = card_with_path

				var code: String = card_with_path.get("card_code", "")
				if not code.is_empty() and (not base_card_map.has(code) or card_with_path.get("variant_index", 0) == 0):
					base_card_map[code] = card_with_path

func _assign_card_image_path(card_data: Dictionary) -> Dictionary:
	# Explicit override (e.g. for DON!! variants)
	if card_data.has("image_override") and not String(card_data["image_override"]).is_empty():
		card_data["image_path"] = card_data["image_override"]
		return card_data

	var set_code := String(card_data.get("set_code", ""))
	var vid := String(card_data.get("variant_id", ""))
	var card_code := String(card_data.get("card_code", ""))

	# Try exact variant_id image first
	var candidate_paths = [
		"res://assets/cards/%s/%s.png" % [set_code, vid],
		"res://assets/cards/%s/%s.jpg" % [set_code, vid],
		"res://assets/cards/%s/%s.jpeg" % [set_code, vid],
		"res://assets/cards/%s/%s.webp" % [set_code, vid],
		# Fallback to base card_code image
		"res://assets/cards/%s/%s.png" % [set_code, card_code],
		"res://assets/cards/%s/%s.jpg" % [set_code, card_code],
	]

	for p in candidate_paths:
		if FileAccess.file_exists(p):
			card_data["image_path"] = p
			return card_data

	var named := vid if vid != "" else card_code
	if set_code != "" and named != "":
		card_data["image_path"] = "res://assets/cards/%s/%s.png" % [set_code, named]
		return card_data
	card_data["image_path"] = "res://assets/cards/Base/BaseCard.png"
	return card_data

func _preload_and_cache_textures() -> void:
	for card_data in all_cards.values():
		var image_path: String = card_data.get("image_path", "")
		if image_path.is_empty() or image_path.begins_with("res://assets/cards/Base/"):
			continue
		if not texture_cache.has(image_path) and FileAccess.file_exists(image_path):
			var texture = load(image_path)
			if texture:
				texture_cache[image_path] = texture
