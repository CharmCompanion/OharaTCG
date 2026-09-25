# tests/rules_smoke.gd -- leader-based Life + "under the rules of this game"
# Checks:
#   * Life start = leader's printed Life (curated table, default 5)
#   * Enel OP15-058: DON!! deck of 6
#   * Nami OP03-040: deck-out = WIN instead of loss
extends SceneTree

var _frame := 0
var _started := false
var _fail := 0

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
		_run(cdb)
		print("RULES SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _run(cdb: Node) -> void:
	# A) Nami (Life 5, deckout-win) vs Purple Enel (DON deck 6)
	var mt := MtMatch.new()
	mt.start(_deck(cdb, "OP03-040", "ST01"), _deck(cdb, "OP15-058", "ST02"), 0)
	var p0: MtPlayerState = mt.players[0]
	var p1: MtPlayerState = mt.players[1]
	_check("Nami life max=5", p0.max_life == 5, p0.max_life)
	_check("Nami 5 life cards", p0.life.size() == 5, p0.life.size())
	_check("Enel life max=5", p1.max_life == 5, p1.max_life)
	_check("Enel DON cap=6", p1.don_deck_size == 6, p1.don_deck_size)
	_check("Enel DON deck=6", p1.don_in_deck == 6, p1.don_in_deck)
	_check("Nami DON cap=10", p0.don_deck_size == 10, p0.don_deck_size)

	# DON cap enforced: fill to 5/5 then try to add 10 more
	p1.don_active = 5
	p1.don_in_deck = 5
	mt._add_active_don(p1, 10)
	_check("Enel DON cap holds 6", p1.don_active == 6 and p1.don_in_deck == 4, "%d/%d" % [p1.don_active, p1.don_in_deck])

	# Nami deck-out reverses the loss
	p0.deck = []
	mt.draw_card(p0)
	_check("Nami deck-out wins", mt.over and mt.winner == 0, "over=%s winner=%d" % [mt.over, mt.winner])

	# A2) Green/Black Brook OP15-022: no lose on 0 cards until end of turn
	var mtBr := MtMatch.new()
	mtBr.start(_deck(cdb, "OP15-022", "ST01"), _deck(cdb, "ST01-001", "ST01"), 0)
	var br: MtPlayerState = mtBr.players[0]
	_check("Brook DON is still 10", br.don_deck_size == 10, br.don_deck_size)
	br.deck.clear()
	mtBr.draw_card(br)
	_check("Brook does not lose on draw from 0", not mtBr.over, mtBr.over)
	_check("Brook marks delayed deck-out", br.deckout_pending, br.deckout_pending)
	mtBr.end_turn_current()
	_check("Brook loses at end of that turn", mtBr.over and mtBr.winner == 1, "over=%s winner=%d" % [mtBr.over, mtBr.winner])

	# B) Sabo ST13-001: a Life-4 leader
	var mtB := MtMatch.new()
	mtB.start(_deck(cdb, "ST13-001", "ST13"), _deck(cdb, "ST01-001", "ST01"), 0)
	_check("Sabo life max=4", mtB.players[0].max_life == 4, mtB.players[0].max_life)
	_check("Sabo 4 life cards", mtB.players[0].life.size() == 4, mtB.players[0].life.size())

	# C) Newgate OP02-001: Life 6
	var mtC := MtMatch.new()
	mtC.start(_deck(cdb, "OP02-001", "OP02"), _deck(cdb, "ST01-001", "ST01"), 0)
	_check("Newgate life max=6", mtC.players[0].max_life == 6 and mtC.players[0].life.size() == 6, "%d/%d" % [mtC.players[0].max_life, mtC.players[0].life.size()])

	# D) Banlists: TCG/OCG files load; banned + restricted enforced.
	var st01 := _deck(cdb, "ST01-001", "ST01")
	_check("clean deck valid", MtDeckLoader.validate_deck(st01).is_empty(), MtDeckLoader.validate_deck(st01))
	var ban := {"name": "T", "banned": ["ST01-004"], "restricted": {"ST01-005": 1}}
	var errs := MtDeckLoader.validate_deck(st01, ban)
	var txt := ";".join(errs)
	_check("banned flagged", txt.contains("ST01-004") and txt.contains("banned"), txt)
	_check("restricted flagged", txt.contains("ST01-005") and txt.contains("restricted"), txt)
	_check("tcg file loads", (MtDeckLoader.load_banlist("res://data/banlists/tcg.json") as Dictionary).has("name"), "tcg")
	_check("ocg file loads", (MtDeckLoader.load_banlist("res://data/banlists/ocg.json") as Dictionary).has("name"), "ocg")
	# Real TCG list: Nami leader banned; banned pairs rejected.
	var tcg := MtDeckLoader.load_banlist("res://data/banlists/tcg.json")
	var nami_errs := MtDeckLoader.validate_deck(_deck(cdb, "OP03-040", "ST01"), tcg)
	_check("banned leader flagged", ";".join(nami_errs).contains("OP03-040"), ";".join(nami_errs))
	var pair_deck := _deck(cdb, "ST01-001", "ST01")
	if pair_deck.main.size() >= 2:
		pair_deck.main[0] = cdb.get_card_data("OP07-115")
		pair_deck.main[1] = cdb.get_card_data("EB04-058")
	var pair_errs := MtDeckLoader.validate_deck(pair_deck, tcg)
	_check("banned pair flagged", ";".join(pair_errs).contains("Banned pair"), ";".join(pair_errs))
	_test_simdeck(cdb)

	# E) Formats: manifest, blocks map, Standard rotation, open-vs-modern.
	var fmts := MtDeckLoader.list_formats()
	_check("formats >= 8", fmts.size() >= 8, fmts.size())
	var blocks := MtDeckLoader.load_blocks()
	_check("blocks map", int((blocks.get("sets", {}) as Dictionary).get("OP01", 0)) == 1 and int((blocks.get("sets", {}) as Dictionary).get("OP16", 0)) == 5, "map")
	var modern := {}
	for f in fmts:
		if String((f as Dictionary).get("id", "")) == "modern-tcg":
			modern = f
	_check("modern-tcg found", not modern.is_empty(), "fmt")
	var st01_errs := MtDeckLoader.validate_deck(_deck(cdb, "ST01-001", "ST01"), tcg, modern, blocks)
	_check("ST01 rotated out of Standard", ";".join(st01_errs).contains("Block 1"), ";".join(st01_errs))
	var open_errs := MtDeckLoader.validate_deck(_deck(cdb, "ST01-001", "ST01"), {}, {}, {})
	_check("open allows ST01", open_errs.is_empty(), ";".join(open_errs))
	_test_colors()
	# A Block-5 OP16 meta deck is Standard-legal on blocks.
	if FileAccess.file_exists("res://data/meta/decks.json"):
		var mdecks = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta/decks.json"))
		var picked := {}
		for d in mdecks:
			if String((d as Dictionary).get("leader", "")).begins_with("OP16"):
				picked = d
				break
		if not picked.is_empty():
			var codes: Array = []
			for c in picked.get("main", []):
				for i in range(int((c as Dictionary).get("count", 0))):
					codes.append(String((c as Dictionary).get("code", "")))
			var md := MtDeckLoader.build_from_lists(String(picked.get("leader", "")), codes, cdb.get_card_data)
			var merrs := MtDeckLoader.validate_deck(md, tcg, modern, blocks)
			var block_bad := false
			for e in merrs:
				if String(e).contains("Block"):
					block_bad = true
			_check("OP16 meta Standard on blocks", not block_bad, ";".join(merrs))


func _fill(color: String, n: int, cost: int = 1) -> Array:
	var out: Array = []
	for i in n:
		out.append({"card_code": "%s%d" % [color.substr(0, 1), i], "type": "Character", "color": color, "cost": cost, "effect": ""})
	return out

func _test_colors() -> void:
	var red := {"card_code": "LEAD", "type": "Leader", "color": "Red", "effect": ""}
	var dual := {"card_code": "LEAD2", "type": "Leader", "color": "Red/Green", "effect": ""}
	var off := _fill("Red", 49)
	off.append({"card_code": "BLUE", "type": "Character", "color": "Blue", "cost": 1, "effect": ""})
	var off_errs := MtDeckLoader.validate_deck({"leader": red, "main": off})
	_check("off-color rejected", ";".join(off_errs).contains("BLUE") and ";".join(off_errs).contains("Blue"), ";".join(off_errs))
	var splash := _fill("Red", 49)
	splash.append({"card_code": "RG", "type": "Character", "color": "Red/Green", "cost": 1, "effect": ""})
	var splash_errs := MtDeckLoader.validate_deck({"leader": red, "main": splash})
	_check("multicolor card needs both colors", ";".join(splash_errs).contains("RG"), ";".join(splash_errs))
	var ok_main := _fill("Red", 25)
	ok_main.append_array(_fill("Green", 24))
	ok_main.append({"card_code": "RG", "type": "Character", "color": "Red/Green", "cost": 1, "effect": ""})
	var ok_errs := MtDeckLoader.validate_deck({"leader": dual, "main": ok_main})
	_check("dual leader accepts both colors", ok_errs.is_empty(), ";".join(ok_errs))
	var ray := {"card_code": "RAY", "type": "Leader", "color": "Red", "effect": "Under the rules of this game, you cannot include cards with a cost of 5 or more in your deck."}
	var pricey := _fill("Red", 49)
	pricey.append({"card_code": "BIG", "type": "Character", "color": "Red", "cost": 5, "effect": ""})
	var cost_errs := MtDeckLoader.validate_deck({"leader": ray, "main": pricey})
	_check("leader cost cap rejected", ";".join(cost_errs).contains("BIG"), ";".join(cost_errs))
	var why := MtDeckLoader.why_not_add(red, {"card_code": "BLUE", "type": "Character", "color": "Blue", "cost": 1, "effect": ""}, _fill("Red", 10))
	_check("builder refuses off-color add", why.contains("BLUE"), why)

func _test_simdeck(cdb: Node) -> void:
	# Sim-style NxCODE deck files (their 12 shipped lists) load as fallback.
	var path := "user://simdeck_probe.deck"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("1xST01-001\n4xST01-002\n2xST01-015\n")
	f.flush()
	f.close()
	var d := MtDeckLoader.load_deck_file(path, cdb.get_card_data)
	_check("simdeck leader", String(d.get("leader", {}).get("card_code", "")) == "ST01-001", d.get("leader", {}).get("card_code", "?"))
	_check("simdeck 6 main", (d.get("main", []) as Array).size() == 6, (d.get("main", []) as Array).size())
	DirAccess.remove_absolute(path)

func _deck(cdb: Node, leader_code: String, main_prefix: String) -> Dictionary:
	var leader: Dictionary = cdb.get_card_data(leader_code)
	var main: Array = []
	var slots := 0
	for i in range(100):
		var dd: Dictionary = cdb.get_card_data("%s-%03d" % [main_prefix, (i % 14) + 1])
		if not dd.is_empty() and String(dd.get("type", "")) != "Leader":
			main.append(dd)
			slots += 1
			if slots >= 50:
				break
	if leader.is_empty():
		print("WARN: no leader data for %s" % leader_code)
	return {"leader": leader, "main": main}

func _check(label: String, cond: bool, got) -> void:
	if not cond:
		_fail += 1
		print("FAIL %-24s got=%s" % [label, str(got)])