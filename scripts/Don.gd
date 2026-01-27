extends Node

const DEFAULT_DON_PATH = "res://data/decks/Don.json"

var selected_alt_don := ""
var don_cards: Array = []

func _ready():
	load_don_cards()

func load_don_cards():
	if FileAccess.file_exists(DEFAULT_DON_PATH):
		var content = FileAccess.get_file_as_string(DEFAULT_DON_PATH)
		var parsed = JSON.parse_string(content)
		if typeof(parsed) == TYPE_ARRAY:
			don_cards = parsed

func get_don_cards() -> Array:
	return don_cards

func get_available_alt_don_files() -> Array:
	var files := []
	var dir := DirAccess.open("res://assets/cards/DON/")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".png") or file.ends_with(".jpg"):
				files.append("res://assets/cards/DON/" + file)
			file = dir.get_next()
		dir.list_dir_end()
	return files

func set_alt_don_file(file_path: String):
	selected_alt_don = file_path
