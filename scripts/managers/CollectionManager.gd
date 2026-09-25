# res://scripts/managers/CollectionManager.gd
# Persists per-card collection preferences: foil toggles and owned prize holos.
extends Node

const SAVE_PATH := "user://collection.json"

var foils: Dictionary = {}      # card_code -> bool (false = not foiled)
var prizes_owned: Dictionary = {}  # trophy/tournament cards the player owns
var owned: Dictionary = {}      # card_code -> count from the shop

func _ready() -> void:
	_load()

# --- Public API ---
func is_foiled(card_code: String) -> bool:
	return foils.get(card_code, false)

func set_foiled(card_code: String, enabled: bool) -> void:
	if enabled:
		foils[card_code] = true
	else:
		foils.erase(card_code)
	_save()

func toggle_foil(card_code: String) -> bool:
	var on := not is_foiled(card_code)
	set_foiled(card_code, on)
	return on

func own_prize(card_code: String) -> bool:
	return prizes_owned.get(card_code, false)

func set_prize_owned(card_code: String, owned: bool) -> void:
	if owned:
		prizes_owned[card_code] = true
	else:
		prizes_owned.erase(card_code)
	_save()

func add_owned(card_code: String, n: int = 1) -> void:
	if card_code == "":
		return
	owned[card_code] = int(owned.get(card_code, 0)) + n
	_save()

func owned_count(card_code: String) -> int:
	return int(owned.get(card_code, 0))

func foil_all() -> void:
	for card in CardDatabase.get_all_card_data_as_array():
		set_foiled(card.get("card_code", ""), true)

func foil_none() -> void:
	foils.clear()
	_save()

# --- Persistence ---
func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"foils": foils.keys(),
			"prizes_owned": prizes_owned.keys(),
			"owned": owned,
		}))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return
	for code in data.get("foils", []):
		foils[code] = true
	for code in data.get("prizes_owned", []):
		prizes_owned[code] = true
	var saved = data.get("owned", {})
	if saved is Dictionary:
		owned = saved