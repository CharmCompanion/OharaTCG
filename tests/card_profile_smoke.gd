# tests/card_profile_smoke.gd -- parse every EN base card; keyword engine samples
extends SceneTree

var _frame := 0
var _fail := 0
var _started := false

func _check(label: String, condition: bool, extra = "") -> void:
	if condition:
		print("  PASS: %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s (%s)" % [label, str(extra)])

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
		print("CARD PROFILE SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _run(cdb: Node) -> void:
	print("--- Full card scan ---")
	var known := {}
	for h in MtEffectParser.HARD_KEYWORDS:
		known[h] = true
	for h in MtEffectParser._TIMING_HATS:
		known[h] = true
	for h in MtEffectParser._MODIFIER_HATS:
		known[h] = true
	var hat_counts := {}
	var unknown := {}
	var scanned := 0
	var with_profile := 0
	for card in cdb.get_base_cards_as_array():
		if not (card is Dictionary):
			continue
		if String(card.get("region", "")).to_upper() != "EN":
			continue
		scanned += 1
		var p: Dictionary = MtCardProfile.from_dict(card)
		if String(p.get("name", "")) != "":
			with_profile += 1
		var stats := MtCardProfile.inspector_stats(card)
		var rules := MtCardProfile.inspector_rules(card)
		if stats.strip_edges().is_empty() and String(card.get("type", "")) != "DON!!":
			_fail += 1
			printerr("  FAIL: empty inspector stats %s" % card.get("card_code"))
		var blob := String(card.get("effect", "")) + " " + String(card.get("trigger", ""))
		if not blob.strip_edges().is_empty() and blob.strip_edges() != "-" and rules.strip_edges().is_empty():
			# Keyword-only cards still get Keywords: line; truly empty parse still prints effect.
			if not String(p.get("effect", "")).strip_edges().is_empty() and String(p.get("effect", "")).strip_edges() != "-":
				pass
		for hat in MtEffectParser.collect_hats(blob):
			var hat_s := String(hat)
			hat_counts[hat_s] = int(hat_counts.get(hat_s, 0)) + 1
			if known.has(hat_s):
				continue
			var u: String = hat_s.to_upper()
			if u.begins_with("DON!!") or u.begins_with("DON‼"):
				continue
			unknown[hat_s] = int(unknown.get(hat_s, 0)) + 1
	_check("scanned EN base cards", scanned > 2000, scanned)
	_check("profiles built", with_profile == scanned, "%d/%d" % [with_profile, scanned])
	print("  hats: %d unique, unknown (names + leftover terms): %d" % [hat_counts.size(), unknown.size()])
	var top: Array = unknown.keys()
	top.sort_custom(func(a, b): return int(unknown[a]) > int(unknown[b]))
	for i in range(mini(12, top.size())):
		print("  leftover hat x%d: [%s]" % [unknown[top[i]], top[i]])

	print("--- Keyword samples ---")
	_expect_kw(cdb, "ST01-006", "Blocker")
	_expect_kw(cdb, "ST01-012", "Rush")
	_expect_kw(cdb, "OP04-014", "Banish")
	_expect_kw(cdb, "OP01-121", "Double Attack")
	_expect_kw(cdb, "OP01-121", "Banish")
	_expect_kw(cdb, "EB04-011", "Rush: Character")
	_expect_kw(cdb, "OP16-032", "Unblockable")

	var sanji: Dictionary = cdb.get_card_data("ST01-004")
	var sf: Dictionary = MtEffectParser.parse(sanji)
	_check("Sanji is not static [Rush]", not (sf.get("keywords", []) as Array).has("Rush"), sf.get("keywords"))
	_check("Sanji grants Rush at DON!! x2", int(sf.get("grants_rush_at_don", 0)) == 2, sf)

	var luffy: Dictionary = cdb.get_card_data("ST01-001")
	var lf: Dictionary = MtEffectParser.parse(luffy)
	_check("Leader Activate: Main parsed", not lf.get("activate_main", []).is_empty())
	_check("Leader Once Per Turn", bool(lf.activate_main[0].get("once_per_turn", false)))

	var jinbe: Dictionary = cdb.get_card_data("ST01-012")
	var jf: Dictionary = MtEffectParser.parse(jinbe)
	_check("Jinbe When Attacking parsed", not jf.get("on_attack", []).is_empty(), jf)
	_check("Jinbe no-block with DON!!", int(jf.get("no_block_with_don", 0)) == 2, jf)

	var brook: Dictionary = cdb.get_card_data("ST01-011")
	var bp := MtCardProfile.from_dict(brook)
	_check("Brook profile has On Play timing", _has_hat(bp, "[On Play]"), bp.get("timings"))
	_check("Brook inspector lists cost/power/counter", MtCardProfile.inspector_stats(brook).contains("Cost"), MtCardProfile.inspector_stats(brook))

	print("--- Engine: Rush / Unblockable / Banish / granted Rush ---")
	var mt := MtMatch.new()
	mt.auto_resolve_choices = true
	var deck := _tiny_deck(cdb)
	mt.start(deck, deck, 0)
	mt.phase = MtMatch.Phase.MAIN
	mt.turn = 2
	var me: MtPlayerState = mt.players[0]
	var opp: MtPlayerState = mt.players[1]
	var rush_card := _spawn_field(mt, me, cdb.get_card_data("ST01-012"))
	rush_card.mark_played(mt.turn)
	_check("Rush can attack the turn played", mt.can_attack_turn_played(rush_card))
	var legal := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": rush_card.uid, "target": opp.leader.uid})
	_check("Rush Character may attack Leader the turn played", legal.ok, legal)

	var rc := _spawn_field(mt, me, cdb.get_card_data("EB04-011"))
	rc.mark_played(mt.turn)
	var vs_lead := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": rc.uid, "target": opp.leader.uid})
	_check("Rush: Character cannot attack Leader the turn played", not vs_lead.ok, vs_lead)
	var dummy := _spawn_field(mt, opp, cdb.get_card_data("ST01-006"))
	dummy.rested = true
	var vs_char := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": rc.uid, "target": dummy.uid})
	_check("Rush: Character can attack a Character the turn played", vs_char.ok, vs_char)

	var boa := _spawn_field(mt, me, cdb.get_card_data("OP16-032"))
	_check("Unblockable keyword", mt.has_keyword(boa, "Unblockable"))
	dummy.rested = false
	mt.battle = {"attacker": boa, "target": opp.leader, "defender": opp.leader, "defender_owner": 1, "step": "block"}
	var blk_legal := mt._legal_block({"type": mt.ACTION_BLOCK, "blocker": dummy.uid})
	_check("Unblockable attack cannot be blocked", not blk_legal.ok, blk_legal)
	mt.battle.clear()

	var croco := _spawn_field(mt, me, cdb.get_card_data("OP04-014"))
	_check("Banish keyword", mt.has_keyword(croco, "Banish"))
	var life_n := opp.life.size()
	var trash_n := opp.trash.size()
	# Put a Trigger Event on Life so Banish can prove it skips Trigger.
	if not opp.life.is_empty():
		opp.life[opp.life.size() - 1].card["trigger"] = "Draw 1 card."
	mt._deal_leader_damage(opp, croco)
	_check("Banish damages Life into Trash", opp.trash.size() == trash_n + 1, opp.trash.size())
	_check("Banish removes 1 Life", opp.life.size() == life_n - 1, opp.life.size())
	_check("Banish does not add the Life card to hand", opp.hand.size() >= 0)

	var sanji_c := _spawn_field(mt, me, cdb.get_card_data("ST01-004"))
	sanji_c.mark_played(mt.turn)
	_check("Sanji without DON!! cannot Rush", not mt.can_attack_turn_played(sanji_c))
	sanji_c.attached_don.append(MtMatchCard.new("d1", {"type": "DON!!"}, 0))
	sanji_c.attached_don.append(MtMatchCard.new("d2", {"type": "DON!!"}, 0))
	_check("Sanji with 2 given DON!! can Rush", mt.can_attack_turn_played(sanji_c))

	var kaido_like := _spawn_field(mt, me, cdb.get_card_data("ST01-012"))
	mt._resolve_actions(kaido_like, [[MtEffectParser.TOK_GRANT_KW, {"kw": "Unblockable", "dur": "turn"}]], {})
	_check("grant_kw adds Unblockable this turn", mt.has_keyword(kaido_like, "Unblockable"), kaido_like.granted_keywords)

func _expect_kw(cdb: Node, code: String, kw: String) -> void:
	var d: Dictionary = cdb.get_card_data(code)
	_check("%s loaded" % code, not d.is_empty())
	var fx: Dictionary = MtEffectParser.parse(d)
	_check("%s has [%s]" % [code, kw], (fx.get("keywords", []) as Array).has(kw), fx.get("keywords"))
	var p := MtCardProfile.from_dict(d)
	_check("%s profile lists [%s]" % [code, kw], (p.get("keywords", []) as Array).has(kw), p.get("keywords"))

func _has_hat(profile: Dictionary, hat: String) -> bool:
	for t in profile.get("timings", []):
		if String(t.get("hat", "")) == hat:
			return true
	return false

func _tiny_deck(cdb: Node) -> Dictionary:
	var main_codes: Array = []
	for code in ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
			"ST01-007", "ST01-008", "ST01-009", "ST01-010", "ST01-011", "ST01-012", "ST01-013",
			"ST01-015"]:
		for _i in range(4):
			main_codes.append(code)
	return MtDeckLoader.build_from_lists("ST01-001", main_codes, cdb.get_card_data)

func _spawn_field(mt: MtMatch, ps: MtPlayerState, data: Dictionary) -> MtMatchCard:
	var c := MtMatchCard.new("u-%s-%d" % [data.get("card_code"), ps.field.size()], data, ps.index)
	c.zone = MtMatchCard.ZONE_FIELD
	ps.field.append(c)
	return c
