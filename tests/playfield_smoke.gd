# tests/playfield_smoke.gd -- PlayField.tscn + PlayerMat halves + mat split rule.
extends SceneTree

var _frame := 0
var _started := false
var _fail := 0
var _mt: MtMatch
var _pf: MtPlayField
var _setup_frame := 0
var _checked := false

func _process(_delta: float) -> bool:
	_frame += 1
	var cdb = root.get_node_or_null("CardDatabase")
	if not cdb or not cdb.is_data_loaded:
		if _frame > 900:
			printerr("TEST FAIL: CardDatabase never loaded")
			quit(1)
			return true
		return false
	if not _started:
		_started = true
		_setup(cdb)
		_setup_frame = _frame
		return false
	if not _checked and _frame >= _setup_frame + 3:
		_checked = true
		_run()
		print("PLAYFIELD SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _setup(cdb: Node) -> void:
	var deck := _deck(cdb, "ST01-001", "ST01")
	_mt = MtMatch.new()
	_mt.start(deck, deck, 0)
	var packed: PackedScene = load("res://scenes/PlayField.tscn")
	_pf = packed.instantiate() as MtPlayField
	root.add_child(_pf)

func _run() -> void:
	var pf := _pf

	_check("9 zones P0", pf.zone_total() == 9, pf.zone_total())
	_check("8 zones P1", pf.get_zone(1, "life") != null and pf.get_zone(1, "cost") != null, "refs")
	_check("5 char slots", pf.char_slots(0).size() == 5, pf.char_slots(0).size())
	_check("top half rotated", pf.top_rotated(), "rotation")
	_check("no mats initially", pf.split_state() == "none", pf.split_state())

	pf.bind_engine(_mt)
	_check("life count 5/5", pf.zone_count(0, "life") == "5/5", pf.zone_count(0, "life"))
	_check("don cap 10", pf.zone_count(0, "cost").ends_with("/10"), pf.zone_count(0, "cost"))
	_check("5 life ticks", pf.visible_ticks(0) == 5, pf.visible_ticks(0))
	_check("life fan 5 backs", pf.get_zone(0, "life").get_node("Fan").get_child_count() == 5,
		pf.get_zone(0, "life").get_node("Fan").get_child_count())

	# Mat split rule: different arts -> split; same/shared -> shared; none -> none.
	var tex_a := _solid_tex(Color(0.2, 0.3, 0.5))
	var tex_b := _solid_tex(Color(0.5, 0.2, 0.2))
	pf.set_player_mat(0, tex_a)
	pf.set_player_mat(1, tex_b)
	_check("split on different arts", pf.split_state() == "split", pf.split_state())
	pf.set_shared_mat(tex_a)
	_check("shared on set_shared", pf.split_state() == "shared", pf.split_state())
	pf.set_player_mat(0, tex_a)
	pf.set_player_mat(1, tex_a)
	_check("same art collapses", pf.split_state() == "shared", pf.split_state())
	pf.clear_mats()
	_check("cleared hides all", pf.split_state() == "none", pf.split_state())

	# Leader-color skins: resolution, distinctness, auto-split halves.
	_check("primary first color", MtMatSkin.primary(["Green", "Blue"]) == "Green", MtMatSkin.primary(["Green", "Blue"]))
	_check("pair rank order", MtMatSkin.pair_key(["Green", "Red"]) == "RedGreen", MtMatSkin.pair_key(["Green", "Red"]))
	_check("pair single", MtMatSkin.pair_key(["Blue"]) == "Blue", MtMatSkin.pair_key(["Blue"]))
	_check("primary unknown", MtMatSkin.primary(["???"]) == "Default", MtMatSkin.primary(["???"]))
	var red := MtMatSkin.art_for(["Red"])
	var green := MtMatSkin.art_for(["Green"])
	var red2 := MtMatSkin.art_for(["Red"])
	_check("skins resolve", red != null and green != null, "null?")
	_check("skins cached", red == red2, "cache")
	_check("skins differ", red != green, "same?")
	pf.set_player_mat(0, red)
	pf.set_player_mat(1, green)
	_check("color skins split", pf.split_state() == "split", pf.split_state())
	pf.clear_mats()

	pf.queue_free()

func _deck(cdb: Node, leader_code: String, main_prefix: String) -> Dictionary:
	var leader: Dictionary = cdb.get_card_data(leader_code)
	var main: Array = []
	var slots := 0
	for i in range(100):
		var d: Dictionary = cdb.get_card_data("%s-%03d" % [main_prefix, (i % 14) + 1])
		if not d.is_empty():
			main.append(d)
			slots += 1
			if slots >= 50:
				break
	return {"leader": leader, "main": main}

func _solid_tex(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _check(label: String, cond: bool, got) -> void:
	if not cond:
		_fail += 1
		print("FAIL %-26s got=%s" % [label, str(got)])
