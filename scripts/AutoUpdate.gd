extends Node

const OUTPUT_DIR := "res://output"
const CACHE_ROOT := "user://cache"
const HEADLESS_SCRIPT := "res://addons/GrandLineScraper/run_headless.py"
const SCRAPE_STAMP := "res://output/last_scrape.json"

var _did_run := false

func _ready() -> void:
	# Defer heavy work until after the main scene has been added to the tree,
	# and skip entirely when running individual scenes (like Decks.tscn) in
	# isolation from the editor.
	call_deferred("_maybe_run_auto_update")

func _maybe_run_auto_update() -> void:
	if _did_run:
		return
	var tree := get_tree()
	if tree == null:
		return
	var root := tree.root
	if root == null:
		return
	# Only run when the Main scene is present (normal game flow).
	if root.get_node_or_null("Main") == null:
		return
	_did_run = true
	_run_headless_scraper()
	_update_from_output()

func _update_from_output() -> void:
	_copy_starter_decks()
	_copy_banlists()
	_refresh_cards_json()
	_refresh_last_scrape_stamp()

func _run_headless_scraper() -> void:
	var script_path := ProjectSettings.globalize_path(HEADLESS_SCRIPT)
	if not FileAccess.file_exists(script_path):
		return

	var python_path := _get_python_path()
	if python_path == "":
		return

	var args = [script_path]
	OS.create_process(python_path, args)

func _get_python_path() -> String:
	var cache_path := "user://cache/python_path.txt"
	if FileAccess.file_exists(cache_path):
		var file = FileAccess.open(cache_path, FileAccess.READ)
		if file:
			var text = file.get_as_text().strip_edges()
			file.close()
			return text

	return "python"

func _copy_starter_decks() -> void:
	var source_dir := OUTPUT_DIR + "/decks/starter"
	var target_dir := CACHE_ROOT + "/data/decks"
	_copy_json_files(source_dir, target_dir, ["_complete.json"])

func _copy_banlists() -> void:
	var source_dir := OUTPUT_DIR + "/banlists"
	var target_dir := CACHE_ROOT + "/assets/JSON/banlists"
	_copy_json_files(source_dir, target_dir, [])

func _refresh_cards_json() -> void:
	var db_path := OUTPUT_DIR + "/databases/complete_card_database.json"
	if not FileAccess.file_exists(db_path):
		return

	var file = FileAccess.open(db_path, FileAccess.READ)
	if file == null:
		return
	var content = file.get_as_text()
	var result = JSON.parse_string(content)
	if typeof(result) != TYPE_DICTIONARY:
		return
	if not result.has("cards"):
		return

	var cards = result.get("cards")
	if typeof(cards) != TYPE_ARRAY:
		return

	var target_dir := CACHE_ROOT + "/assets/JSON"
	_ensure_dir(target_dir)
	var target_path := target_dir + "/cards.json"
	var out = FileAccess.open(target_path, FileAccess.WRITE)
	if out == null:
		return
	out.store_string(JSON.stringify(cards))
	out.close()

func _refresh_last_scrape_stamp() -> void:
	var source_path := SCRAPE_STAMP
	if not FileAccess.file_exists(source_path):
		return
	var target_dir := CACHE_ROOT + "/metadata"
	_ensure_dir(target_dir)
	var target_path := target_dir + "/last_scrape.json"
	var bytes = FileAccess.get_file_as_bytes(source_path)
	var out = FileAccess.open(target_path, FileAccess.WRITE)
	if out:
		out.store_buffer(bytes)
		out.close()

func _copy_json_files(source_dir: String, target_dir: String, exclude_suffixes: Array) -> void:
	var dir = DirAccess.open(source_dir)
	if dir == null:
		return
	_ensure_dir(target_dir)

	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var should_skip := false
		for suffix in exclude_suffixes:
			if f.ends_with(suffix):
				should_skip = true
				break
		if should_skip:
			continue

		var src := source_dir + "/" + f
		var dst := target_dir + "/" + f
		var bytes = FileAccess.get_file_as_bytes(src)
		var out = FileAccess.open(dst, FileAccess.WRITE)
		if out:
			out.store_buffer(bytes)
			out.close()

func _ensure_dir(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		DirAccess.make_dir_recursive_absolute(absolute_path)
