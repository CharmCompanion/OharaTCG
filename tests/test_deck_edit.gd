# res://tests/test_deck_edit.gd
extends SceneTree

var _frame := 0
var _inst: Control
var _spawned := false

func _process(_delta: float) -> bool:
	_frame += 1
	if not _spawned:
		# Autoloads (CardDatabase / DeckManager) are registered after SceneTree init.
		if _frame < 4:
			return false
		print("--- Testing DeckEdit.tscn Instantiation ---")
		var scene = load("res://scenes/ui/DeckEdit.tscn")
		if not scene:
			print("FAILED: Could not load res://scenes/ui/DeckEdit.tscn")
			quit(1)
			return true
		print("Scene loaded successfully.")
		_inst = scene.instantiate()
		root.add_child(_inst)
		_spawned = true
		print("Instantiated and added to root.")
		return false

	var cdb = root.get_node_or_null("/root/CardDatabase")
	if cdb == null or not cdb.is_data_loaded:
		if _frame > 900:
			printerr("FAILED: CardDatabase never loaded")
			quit(1)
			return true
		return false

	# Deck editor waits for data then fills SearchGrid / dropdown on the next frames.
	if _frame < 80:
		return false

	print("Frame %d: checking status..." % _frame)
	print("CardDatabase is_data_loaded = ", cdb.is_data_loaded)
	if _inst.get_script() == null:
		printerr("FAILED: DeckEdit script did not attach")
		quit(1)
		return true
	var grid = _inst.get("SearchGrid")
	if grid == null:
		printerr("FAILED: SearchGrid missing")
		quit(1)
		return true
	print("SearchGrid child count = ", grid.get_child_count())
	print("SearchGrid columns = ", grid.columns)
	assert(grid.get_child_count() > 0, "Default search must show cards")
	var dd = _inst.get("DeckDropdown")
	print("Deck dropdown count = ", dd.item_count if dd else -1)
	assert(dd != null and dd.item_count > 0, "Saved decks must load")
	print("SUCCESS: DeckEdit loaded without crashing!")
	quit(0)
	return true
