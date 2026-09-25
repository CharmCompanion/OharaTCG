extends SceneTree

var _frame := 0
var _inst: Node = null
var _profile: Node = null

func _process(_delta: float) -> bool:
	_frame += 1
	var cdb = root.get_node_or_null("CardDatabase")
	if not cdb or not cdb.is_data_loaded:
		if _frame > 600:
			printerr("SMOKE FAIL: CardDatabase never loaded")
			quit(1)
			return true
		return false

	if _inst == null:
		var deck_scene := load("res://scenes/ui/DeckEdit.tscn")
		if deck_scene == null:
			printerr("SMOKE FAIL: DeckEdit.tscn missing")
			quit(1)
			return true
		_inst = deck_scene.instantiate()
		root.add_child(_inst)

	# Also exercise the wanted-poster Profile scene once data + deck are up
	if _profile == null:
		var prof_scene := load("res://scenes/Profile.tscn")
		if prof_scene == null:
			printerr("SMOKE FAIL: Profile.tscn missing")
			quit(1)
			return true
		_profile = prof_scene.instantiate()
		root.add_child(_profile)

	if _frame > 900:
		print("SMOKE OK: DeckEdit+Profile ran (cards=%d base=%d textures=%d)" % [
			cdb.all_cards.size(), cdb.base_card_map.size(), cdb.texture_cache.size()])
		quit(0)
	return false