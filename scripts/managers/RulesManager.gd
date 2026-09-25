extends Node

# Official formats live in res://data/formats.json (Block rotation + banlist path).
# Ban/limited lists live in res://data/banlists/*.json.

var formats: Array = []

func _ready() -> void:
	print("RulesManager: Loading format rules...")
	_load_formats()
	print("RulesManager: Load complete. %d formats loaded." % formats.size())

func get_all_format_names() -> Array[String]:
	var names: Array[String] = []
	for format in formats:
		names.append(String(format.get("name", "")))
	return names

func get_format_by_name(format_name: String) -> Dictionary:
	for format in formats:
		if String(format.get("name", "")) == format_name or String(format.get("id", "")) == format_name:
			return format
	return {}

func is_card_banned(card_id: String, format_name: String) -> bool:
	return copy_limit(card_id, format_name) == 0

func get_card_restriction(card_id: String, format_name: String) -> int:
	var limit := copy_limit(card_id, format_name)
	if limit >= 4:
		return -1
	return limit

func copy_limit(card_id: String, format_name: String) -> int:
	var format := get_format_by_name(format_name)
	if format.is_empty():
		return 4
	return MtDeckLoader.copy_limit(card_id, format.get("banlist_data", {}))

func validate_built_deck(leader: Dictionary, main: Array, format_name: String) -> Array[String]:
	var format := get_format_by_name(format_name)
	var fmt_raw: Dictionary = format.get("format_raw", {})
	var ban: Dictionary = format.get("banlist_data", {})
	return MtDeckLoader.validate_deck({"leader": leader, "main": main}, ban, fmt_raw, MtDeckLoader.load_blocks())

func reload() -> void:
	_load_formats()
	print("RulesManager: Reloaded. %d formats." % formats.size())

func _load_formats() -> void:
	formats.clear()
	for f in MtDeckLoader.list_formats():
		if not (f is Dictionary):
			continue
		var ban := MtDeckLoader.load_banlist(String(f.get("banlist", "")))
		formats.append({
			"name": String(f.get("id", "")),
			"id": String(f.get("id", "")),
			"description": String(f.get("description", "")),
			"allowed_blocks": f.get("allowed_blocks", []),
			"format_raw": f,
			"banlist_data": ban,
		})
