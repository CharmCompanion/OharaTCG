# tests/mechanics_smoke.gd -- Block format, ban/limited, attack/activate, Life/Trash/deck
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
		print("MECHANICS SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _run(cdb: Node) -> void:
	print("--- Block format and ban/limited ---")
	var blocks := MtDeckLoader.load_blocks()
	var st01: Dictionary = cdb.get_card_data("ST01-002")
	_check("ST01 printed Block 1", MtDeckLoader.card_block(st01, blocks) == 1, MtDeckLoader.card_block(st01, blocks))
	var op16: Dictionary = cdb.get_card_data("OP16-032")
	_check("OP16 printed Block 5", MtDeckLoader.card_block(op16, blocks) == 5, MtDeckLoader.card_block(op16, blocks))
	var tcg := MtDeckLoader.load_banlist("res://data/banlists/tcg.json")
	_check("Nami leader copy_limit 0", MtDeckLoader.copy_limit("OP03-040", tcg) == 0, MtDeckLoader.copy_limit("OP03-040", tcg))
	_check("unlisted card copy_limit 4", MtDeckLoader.copy_limit("ST01-002", tcg) == 4)
	var limited := {"name": "L", "banned": [], "limited": {"ST01-005": 1}, "restricted": {}}
	var st01_deck := _fifty(cdb, "ST01-001", "ST01")
	var extra5: Dictionary = cdb.get_card_data("ST01-005")
	if not extra5.is_empty():
		for i in range(st01_deck.main.size()):
			if _count_code(st01_deck.main, "ST01-005") >= 4:
				break
			if String(st01_deck.main[i].get("card_code", "")) != "ST01-005":
				st01_deck.main[i] = extra5
	var lim_errs := MtDeckLoader.validate_deck(st01_deck, limited)
	_check("limited=1 flags extra copies", ";".join(lim_errs).contains("ST01-005"), ";".join(lim_errs))
	var modern := {}
	for f in MtDeckLoader.list_formats():
		if String(f.get("id", "")) == "modern-tcg":
			modern = f
	var rot := MtDeckLoader.validate_deck(st01_deck, tcg, modern, blocks)
	_check("Block 1 rotated out of Standard", ";".join(rot).contains("Block 1"), ";".join(rot))
	var leader_in_main := st01_deck.duplicate(true)
	leader_in_main.main[0] = cdb.get_card_data("ST01-001")
	var lm := MtDeckLoader.validate_deck(leader_in_main)
	_check("Leader cannot sit in the main deck", ";".join(lm).contains("Leader"), ";".join(lm))
	var rm = root.get_node_or_null("RulesManager")
	_check("RulesManager formats loaded", rm != null and rm.get_all_format_names().has("modern-tcg"), rm.get_all_format_names() if rm else [])
	if rm:
		_check("RulesManager bans Nami in modern-tcg", rm.is_card_banned("OP03-040", "modern-tcg"))

	print("--- Attack / activate windows ---")
	var zoro: Dictionary = cdb.get_card_data("OP04-090")
	var zf := MtEffectParser.parse(zoro)
	_check("Zoro can attack active Characters", bool(zf.get("can_attack_active", false)), zf)
	var bart: Dictionary = cdb.get_card_data("OP04-081")
	var bf := MtEffectParser.parse(bart)
	_check("Bartolomeo When Attacking trashes top of deck", _has_tok(bf.get("on_attack", []), MtEffectParser.TOK_TRASH_DECK), bf.get("on_attack"))
	_check("Zoro Activate returns trash to bottom of deck", _has_tok(zf.get("activate_main", []), MtEffectParser.TOK_TRASH_TO_DECK), zf.get("activate_main"))

	var mt := MtMatch.new()
	mt.auto_resolve_choices = true
	mt.start(_tiny(cdb), _tiny(cdb), 0)
	var me: MtPlayerState = mt.players[0]
	var opp: MtPlayerState = mt.players[1]
	mt.phase = MtMatch.Phase.MAIN
	var atk := _spawn(me, cdb.get_card_data("ST01-012"))
	var legal_t1 := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": atk.uid, "target": opp.leader.uid})
	_check("first player cannot attack on turn 1", not legal_t1.ok, legal_t1)
	mt.turn = 2
	var rush := atk
	rush.mark_played(mt.turn)
	_check("[Rush] may attack the Leader the turn it is played", mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": rush.uid, "target": opp.leader.uid}).ok)
	var rc := _spawn(me, cdb.get_card_data("EB04-011"))
	rc.mark_played(mt.turn)
	_check("[Rush: Character] may not attack the Leader the turn it is played", not mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": rc.uid, "target": opp.leader.uid}).ok)
	var active_char := _spawn(opp, cdb.get_card_data("ST01-004"))
	active_char.rested = false
	var vs_active := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": atk.uid, "target": active_char.uid})
	_check("cannot attack an Active Character by default", not vs_active.ok, vs_active)
	var zc := _spawn(me, zoro)
	var z_vs_active := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": zc.uid, "target": active_char.uid})
	_check("Zoro may attack an Active Character", z_vs_active.ok, z_vs_active)
	var rested := _spawn(opp, cdb.get_card_data("ST01-006"))
	rested.rested = true
	var vs_rested := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": atk.uid, "target": rested.uid})
	_check("can attack a rested Character", vs_rested.ok, vs_rested)
	var vs_lead := mt._legal_attack({"type": mt.ACTION_ATTACK, "attacker": atk.uid, "target": opp.leader.uid})
	_check("can attack the Leader", vs_lead.ok, vs_lead)

	var luffy := me.leader
	var act1 := mt._legal_activate({"type": mt.ACTION_ACTIVATE, "card_uid": luffy.uid})
	_check("Leader [Activate: Main] legal", act1.ok, act1)
	mt.apply({"type": mt.ACTION_ACTIVATE, "card_uid": luffy.uid})
	var act2 := mt._legal_activate({"type": mt.ACTION_ACTIVATE, "card_uid": luffy.uid})
	_check("[Once Per Turn] blocks a second Activate", not act2.ok, act2)

	print("--- Life, Trash, deck top/bottom ---")
	var top_code := "TOP-KEEP"
	var bot_code := "BOT-KEEP"
	if me.deck.size() >= 2:
		me.deck[0].card = {"card_code": top_code, "name": "Top", "type": "Character"}
		me.deck[me.deck.size() - 1].card = {"card_code": bot_code, "name": "Bottom", "type": "Character"}
	var trash_n := me.trash.size()
	mt._trash_top_of_deck(me, 1)
	_check("trash top of deck takes index 0", me.trash.size() == trash_n + 1, me.trash.size())
	if not me.trash.is_empty():
		_check("trashed card was the top", me.trash[me.trash.size() - 1].card_code() == top_code, me.trash[me.trash.size() - 1].card_code())
	var field_c := _spawn(me, cdb.get_card_data("ST01-004"))
	mt._place_on_deck(me, field_c, "bottom")
	_check("return to bottom leaves the card last in deck", me.deck[me.deck.size() - 1].uid == field_c.uid, me.deck[me.deck.size() - 1].card_code())
	_check("returned card left the field", not (field_c in me.field), field_c.zone)
	mt._place_on_deck(me, field_c, "top")
	_check("return to top makes it the next draw", me.deck[0].uid == field_c.uid)
	var drawn := mt.draw_card(me)
	_check("draw is from the top", drawn != null and drawn.uid == field_c.uid, drawn)

	var no_trig := MtMatchCard.new("life-plain", {"card_code": "X-0", "name": "Karoo", "type": "Character", "trigger": ""}, 1)
	no_trig.zone = MtMatchCard.ZONE_LIFE
	no_trig.face_down = true
	opp.life = [no_trig]
	var hand_n := opp.hand.size()
	mt._deal_leader_damage(opp, atk)
	_check("no-Trigger damage adds the Life card to hand", opp.hand.size() == hand_n + 1, opp.hand.size())
	_check("no-Trigger damage leaves Life empty", opp.life.is_empty(), opp.life.size())

	var play_trig: Dictionary = cdb.get_card_data("ST01-002")
	var trig_card := MtMatchCard.new("life-trig", play_trig, 1)
	trig_card.zone = MtMatchCard.ZONE_LIFE
	trig_card.face_down = true
	opp.life = [trig_card]
	var field_n := opp.field.size()
	var hand2 := opp.hand.size()
	mt._deal_leader_damage(opp, atk)
	_check("Trigger Play this card puts the Character in play", opp.field.size() == field_n + 1, opp.field.size())
	_check("Trigger Play this card does not add to hand", opp.hand.size() == hand2, opp.hand.size())

	var event: Dictionary = cdb.get_card_data("ST01-015")
	var evfx := MtEffectParser.parse(event)
	_check("Event [Main] is playable from hand", not evfx.get("on_main", []).is_empty(), evfx)

	print("--- Overflow, Stage replace, slash, costs ---")
	var cav := MtEffectParser.parse(cdb.get_card_data("EB01-012"))
	_check("slash On Play present", not cav.get("on_play", []).is_empty(), cav.get("on_play"))
	_check("slash When Attacking present", not cav.get("on_attack", []).is_empty(), cav.get("on_attack"))
	_check("slash set DON active parsed", _has_tok(cav.get("on_play", []), MtEffectParser.TOK_SET_DON_ACTIVE), cav.get("on_play"))

	var cost_card := MtEffectParser.parse(cdb.get_card_data("EB04-021"))
	_check("activation cost is TOK_PAY", _has_tok(cost_card.get("activate_main", []), MtEffectParser.TOK_PAY), cost_card.get("activate_main"))

	me.don_active = 10
	me.don_rested = 0
	me.don_in_deck = 0
	while me.field.size() < 5:
		_spawn(me, cdb.get_card_data("ST01-006"))
	var sixth: Dictionary = cdb.get_card_data("ST01-007")
	var sixth_c := MtMatchCard.new("hand-6", sixth, 0)
	sixth_c.zone = MtMatchCard.ZONE_HAND
	me.hand.append(sixth_c)
	var victim_uid: String = me.field[0].uid
	var r := mt.apply({"type": mt.ACTION_PLAY, "card_uid": sixth_c.uid, "trash_uid": victim_uid})
	_check("6th Character play is legal with overflow trash", r.ok, r)
	_check("Character Area stays at 5", me.field.size() == 5, me.field.size())
	_check("overflow victim went to Trash", _uid_in(me.trash, victim_uid), me.trash.size())

	var stg: Dictionary = cdb.get_card_data("ST01-017")
	if not stg.is_empty():
		var s1 := MtMatchCard.new("stg1", stg, 0)
		s1.zone = MtMatchCard.ZONE_STAGE
		me.stage = s1
		var s2 := MtMatchCard.new("stg2", stg, 0)
		s2.zone = MtMatchCard.ZONE_HAND
		me.hand.append(s2)
		var rs := mt.apply({"type": mt.ACTION_PLAY, "card_uid": s2.uid})
		_check("new Stage replaces the old one", rs.ok and me.stage == s2, rs)
		_check("old Stage is trashed not K.O.'d", _uid_in(me.trash, "stg1"), me.trash.size())

	var mt2 := MtMatch.new()
	mt2.auto_resolve_choices = false
	mt2.start(_tiny(cdb), _tiny(cdb), 0)
	mt2.phase = MtMatch.Phase.MAIN
	mt2.turn = 2
	var p1: MtPlayerState = mt2.players[1]
	var tcard := MtMatchCard.new("life-t2", play_trig, 1)
	tcard.zone = MtMatchCard.ZONE_LIFE
	tcard.face_down = true
	p1.life = [tcard]
	var h0 := p1.hand.size()
	mt2._deal_leader_damage(p1, mt2.players[0].leader)
	_check("Trigger pending does not add to hand yet", p1.hand.size() == h0, p1.hand.size())
	mt2.apply({"type": mt2.ACTION_TRIGGER_NO, "player": 1, "card_uid": tcard.uid})
	_check("declined Trigger adds the card to hand", p1.hand.size() == h0 + 1, p1.hand.size())

	var mt3 := MtMatch.new()
	mt3.start(_tiny(cdb), _tiny(cdb), 0)
	var p0: MtPlayerState = mt3.players[0]
	p0.deck = [MtMatchCard.new("last", {"card_code": "Z", "name": "Last", "type": "Character"}, 0)]
	mt3._effect_depth = 1
	mt3._trash_top_of_deck(p0, 1)
	_check("mill last card mid-effect does not end the game yet", not mt3.over, mt3.over)
	mt3._effect_depth = 0
	mt3._rule_process()
	_check("deck-out is judged at the next rule check", mt3.over, mt3.over)

	print("--- Compiler verbs: play/bounce/look/cost/protect/active/picks ---")
	var play_fx := MtEffectParser.parse({"effect": "[On Play] Play up to 1 Character card with a cost of 5 or less from your trash.", "trigger": ""})
	_check("play-from-trash token", _has_tok(play_fx.get("on_play", []), MtEffectParser.TOK_PLAY), play_fx.get("on_play"))
	var bounce_fx := MtEffectParser.parse({"effect": "[On Play] Return up to 1 of your opponent's Characters with a cost of 2 or less to the owner's hand.", "trigger": ""})
	_check("bounce token", _has_tok(bounce_fx.get("on_play", []), MtEffectParser.TOK_BOUNCE), bounce_fx.get("on_play"))
	var look_fx := MtEffectParser.parse({"effect": "[On Play] Look at 5 cards from the top of your deck; reveal up to 1 {Straw Hat Crew} type card and add it to your hand. Then, place the rest at the bottom of your deck in any order.", "trigger": ""})
	_check("look-at-deck token", _has_tok(look_fx.get("on_play", []), MtEffectParser.TOK_LOOK_DECK), look_fx.get("on_play"))
	var cost_fx := MtEffectParser.parse({"effect": "[On Play] Your opponent's Character cards gain +2 cost during this turn.", "trigger": ""})
	_check("plus-cost token", _has_tok(cost_fx.get("on_play", []), MtEffectParser.TOK_COST), cost_fx.get("on_play"))
	var prot_fx := MtEffectParser.parse({"effect": "[Opponent's Turn] This Character cannot be K.O.'d.", "trigger": ""})
	_check("cannot-be-KO static", (prot_fx.get("protect_fx", []) as Array).size() > 0, prot_fx.get("protect_fx"))
	var act_fx := MtEffectParser.parse({"effect": "[End of Your Turn] Set this Character as active.", "trigger": ""})
	_check("set-as-active token", _has_tok(act_fx.get("on_end", []), MtEffectParser.TOK_SET_ACTIVE), act_fx.get("on_end"))

	var mtv := MtMatch.new()
	mtv.auto_resolve_choices = true
	mtv.start(_tiny(cdb), _tiny(cdb), 0)
	mtv.phase = MtMatch.Phase.MAIN
	mtv.turn = 2
	var vme: MtPlayerState = mtv.players[0]
	var vopp: MtPlayerState = mtv.players[1]
	var trash_char := MtMatchCard.new("tr-play", {"name": "TrashChar", "type": "Character", "cost": 3, "power": 4000, "color": "Red", "effect": ""}, 0)
	trash_char.zone = MtMatchCard.ZONE_TRASH
	vme.trash.append(trash_char)
	var player_src := MtMatchCard.new("src-play", {"name": "Player", "type": "Character", "cost": 4, "power": 5000, "color": "Red",
		"effect": "[On Play] Play up to 1 Character card with a cost of 5 or less from your trash."}, 0)
	player_src.zone = MtMatchCard.ZONE_FIELD
	vme.field.append(player_src)
	mtv._fx_cache.clear()
	mtv._resolve_actions(player_src, mtv.fx(player_src).get("on_play", [{}])[0].get("actions", []), {})
	_check("play from trash puts Character in play", _uid_in(vme.field, "tr-play"), vme.field.size())

	var bounced := MtMatchCard.new("bn1", {"name": "Small", "type": "Character", "cost": 1, "power": 2000, "color": "Red", "effect": ""}, 1)
	bounced.zone = MtMatchCard.ZONE_FIELD
	vopp.field.append(bounced)
	var bsrc := MtMatchCard.new("src-b", {"name": "BounceSrc", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[On Play] Return up to 1 of your opponent's Characters with a cost of 2 or less to the owner's hand."}, 0)
	bsrc.zone = MtMatchCard.ZONE_FIELD
	vme.field.append(bsrc)
	mtv._fx_cache.clear()
	mtv._resolve_actions(bsrc, mtv.fx(bsrc).get("on_play", [{}])[0].get("actions", []), {})
	_check("bounce returns opponent Character to hand", _uid_in(vopp.hand, "bn1"), vopp.hand.size())

	var prot_c := MtMatchCard.new("prot", {"name": "Wall", "type": "Character", "cost": 3, "power": 4000, "color": "Red",
		"effect": "[Opponent's Turn] This Character cannot be K.O.'d."}, 1)
	prot_c.zone = MtMatchCard.ZONE_FIELD
	vopp.field.append(prot_c)
	mtv.active = 0
	mtv._fx_cache.clear()
	mtv._ko(prot_c)
	_check("cannot-be-KO'd on opponent's turn blocks effect KO", _uid_in(vopp.field, "prot"), vopp.field.size())

	var rest_c := MtMatchCard.new("rst", {"name": "Rested", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[End of Your Turn] Set this Character as active."}, 0)
	rest_c.zone = MtMatchCard.ZONE_FIELD
	rest_c.rested = true
	vme.field.append(rest_c)
	mtv._fx_cache.clear()
	mtv._resolve_actions(rest_c, mtv.fx(rest_c).get("on_end", [{}])[0].get("actions", []), {})
	_check("set this Character as active", rest_c.rested == false, rest_c.rested)

	var look_src := MtMatchCard.new("lk", {"name": "Looker", "type": "Character", "cost": 1, "power": 2000, "color": "Red",
		"effect": "[On Play] Look at 3 cards from the top of your deck; reveal up to 1 Character card and add it to your hand. Then, place the rest at the bottom of your deck in any order."}, 0)
	look_src.zone = MtMatchCard.ZONE_FIELD
	vme.field.append(look_src)
	vme.deck = [
		MtMatchCard.new("d1", {"name": "A", "type": "Character", "cost": 1, "power": 1000, "color": "Red", "effect": ""}, 0),
		MtMatchCard.new("d2", {"name": "B", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0),
		MtMatchCard.new("d3", {"name": "C", "type": "Character", "cost": 2, "power": 2000, "color": "Red", "effect": ""}, 0),
	]
	for dc in vme.deck:
		dc.zone = MtMatchCard.ZONE_DECK
	var hand_before := vme.hand.size()
	mtv._fx_cache.clear()
	mtv._resolve_actions(look_src, mtv.fx(look_src).get("on_play", [{}])[0].get("actions", []), {})
	_check("look-at-deck adds a Character to hand", vme.hand.size() == hand_before + 1, vme.hand.size())
	_check("unselected look cards return to deck", vme.deck.size() == 2, vme.deck.size())

	var cost_t := MtMatchCard.new("ct", {"name": "Taxed", "type": "Character", "cost": 3, "power": 4000, "color": "Red", "effect": ""}, 1)
	cost_t.zone = MtMatchCard.ZONE_FIELD
	vopp.field = [cost_t]
	var cost_src := MtMatchCard.new("cs", {"name": "Taxer", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[On Play] Up to 1 of your opponent's Characters gains +2 cost during this turn."}, 0)
	cost_src.zone = MtMatchCard.ZONE_FIELD
	vme.field.append(cost_src)
	mtv._fx_cache.clear()
	mtv._resolve_actions(cost_src, mtv.fx(cost_src).get("on_play", [{}])[0].get("actions", []), {})
	_check("plus cost this turn", cost_t.cost_value() == 5, cost_t.cost_value())

	var mtp := MtMatch.new()
	mtp.auto_resolve_choices = false
	mtp.start(_tiny(cdb), _tiny(cdb), 0)
	mtp.phase = MtMatch.Phase.MAIN
	mtp.turn = 2
	var pme: MtPlayerState = mtp.players[0]
	var popp: MtPlayerState = mtp.players[1]
	var t1 := MtMatchCard.new("ko-a", {"name": "Alpha", "type": "Character", "cost": 2, "power": 2000, "color": "Red", "effect": ""}, 1)
	var t2 := MtMatchCard.new("ko-b", {"name": "Beta", "type": "Character", "cost": 2, "power": 5000, "color": "Red", "effect": ""}, 1)
	t1.zone = MtMatchCard.ZONE_FIELD
	t2.zone = MtMatchCard.ZONE_FIELD
	popp.field.append(t1)
	popp.field.append(t2)
	var kos := MtMatchCard.new("ko-s", {"name": "Killer", "type": "Character", "cost": 4, "power": 6000, "color": "Red",
		"effect": "[On Play] K.O. up to 1 of your opponent's Characters with a cost of 3 or less."}, 0)
	kos.zone = MtMatchCard.ZONE_FIELD
	pme.field.append(kos)
	mtp._fx_cache.clear()
	mtp._resolve_actions(kos, mtp.fx(kos).get("on_play", [{}])[0].get("actions", []), {})
	_check("manual pick is pending when auto_resolve_choices is off", mtp.pending_choice != null and String(mtp.pending_choice.get("type", "")) == "pick", mtp.pending_choice)
	var legal := mtp.get_legal_actions()
	var pick_n := 0
	for a in legal:
		if String(a.get("type", "")) == mtp.ACTION_CHOOSE_EFFECT:
			pick_n += 1
	_check("legal pick actions include each candidate", pick_n >= 2, pick_n)
	var choose := mtp.apply({"type": mtp.ACTION_CHOOSE_EFFECT, "n": 1, "target_uid": "ko-a", "uids": ["ko-a"]})
	_check("choosing a KO target is legal", choose.ok, choose)
	_check("chosen Character is K.O.'d", _uid_in(popp.trash, "ko-a"), popp.trash.size())
	_check("unchosen Character remains", _uid_in(popp.field, "ko-b"), popp.field.size())

	print("--- instead / reveal-hand / opponent chooses / if you do ---")
	var instead := MtEffectParser.parse({"effect": "[Once Per Turn] If this Character would be K.O.'d by an effect, you may trash 1 card from your hand instead.", "trigger": ""})
	_check("instead-of-KO replacement parsed", (instead.get("replace_ko", []) as Array).size() > 0, instead.get("replace_ko"))
	var rev := MtEffectParser.parse({"effect": "[On Play] You may reveal 2 Events from your hand: Draw 1 card.", "trigger": ""})
	_check("reveal-from-hand cost", _has_tok(rev.get("on_play", []), MtEffectParser.TOK_REVEAL_HAND), rev.get("on_play"))
	var oc := MtEffectParser.parse({"effect": "[On K.O.] Your opponent chooses 1 card from your hand; trash that card.", "trigger": ""})
	_check("opponent chooses parsed", _has_tok(oc.get("on_ko", []), MtEffectParser.TOK_OPP_CHOOSE), oc.get("on_ko"))
	var look_any := MtEffectParser.parse({"effect": "[On Play] Look at 3 cards from the top of your deck; reveal up to 1 Character card and add it to your hand. Then, place the rest at the bottom of your deck in any order.", "trigger": ""})
	var look_acts: Array = []
	if (look_any.get("on_play", []) as Array).size() > 0:
		look_acts = look_any.get("on_play", [])[0].get("actions", [])
	var look_reorder := false
	for a in look_acts:
		if a is Array and String(a[0]) == MtEffectParser.TOK_LOOK_DECK and a.size() > 1:
			look_reorder = bool(a[1].get("reorder", false)) and not bool(a[1].get("shuffle", false))
	_check("in any order is a manual reorder, not a shuffle", look_reorder, look_acts)

	var mti := MtMatch.new()
	mti.auto_resolve_choices = true
	mti.start(_tiny(cdb), _tiny(cdb), 0)
	mti.phase = MtMatch.Phase.MAIN
	mti.turn = 2
	var ime: MtPlayerState = mti.players[0]
	var wall := MtMatchCard.new("wall-i", {"name": "Wall", "type": "Character", "cost": 3, "power": 4000, "color": "Red",
		"effect": "[Once Per Turn] If this Character would be K.O.'d by an effect, you may trash 1 card from your hand instead."}, 0)
	wall.zone = MtMatchCard.ZONE_FIELD
	ime.field.append(wall)
	var fodder := MtMatchCard.new("fod", {"name": "Fodder", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	fodder.zone = MtMatchCard.ZONE_HAND
	ime.hand.append(fodder)
	mti._fx_cache.clear()
	var hi := ime.hand.size()
	mti._ko(wall)
	_check("instead replacement keeps the Character", _uid_in(ime.field, "wall-i"), ime.field.size())
	_check("instead replacement trashes from hand", ime.hand.size() == hi - 1, ime.hand.size())

	var ev1 := MtMatchCard.new("ev1", {"name": "E1", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	var ev2 := MtMatchCard.new("ev2", {"name": "E2", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	ev1.zone = MtMatchCard.ZONE_HAND
	ev2.zone = MtMatchCard.ZONE_HAND
	ime.hand.append(ev1)
	ime.hand.append(ev2)
	var rsrc := MtMatchCard.new("rsrc", {"name": "Revealer", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[On Play] You may reveal 2 Events from your hand: Draw 1 card."}, 0)
	rsrc.zone = MtMatchCard.ZONE_FIELD
	ime.field.append(rsrc)
	var h_before := ime.hand.size()
	var d_before := ime.deck.size()
	mti._fx_cache.clear()
	mti._resolve_actions(rsrc, mti.fx(rsrc).get("on_play", [{}])[0].get("actions", []), {})
	_check("reveal-from-hand does not trash the Events", ime.hand.size() == h_before + 1, ime.hand.size())
	_check("reveal-from-hand then draws", ime.deck.size() == d_before - 1, ime.deck.size())

	var ifdo := MtMatchCard.new("ifdo", {"name": "IfDo", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[On Play] You may trash 1 card from your hand. If you do, set up to 3 of your DON!! cards as active."}, 0)
	ifdo.zone = MtMatchCard.ZONE_FIELD
	ime.field.append(ifdo)
	ime.don_active = 5
	ime.don_rested = 3
	var trash_me := MtMatchCard.new("tm", {"name": "T", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	trash_me.zone = MtMatchCard.ZONE_HAND
	ime.hand.append(trash_me)
	mti._fx_cache.clear()
	mti._resolve_actions(ifdo, mti.fx(ifdo).get("on_play", [{}])[0].get("actions", []), {})
	_check("if you do sets DON active after a paid trash", ime.don_rested < 3, ime.don_rested)

	var mto := MtMatch.new()
	mto.auto_resolve_choices = true
	mto.start(_tiny(cdb), _tiny(cdb), 0)
	var ome: MtPlayerState = mto.players[0]
	var oopp: MtPlayerState = mto.players[1]
	var vic := MtMatchCard.new("vko", {"name": "Victim", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[On K.O.] Your opponent chooses 1 card from your hand; trash that card."}, 0)
	vic.zone = MtMatchCard.ZONE_FIELD
	ome.field.append(vic)
	var handc := MtMatchCard.new("oh", {"name": "Gone", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	handc.zone = MtMatchCard.ZONE_HAND
	ome.hand.append(handc)
	mto._fx_cache.clear()
	var hsz := ome.hand.size()
	mto._ko(vic)
	_check("opponent chooses trashes a card from your hand", ome.hand.size() == hsz - 1, ome.hand.size())

	print("--- Leftover printed verbs ---")
	var bounce_txt := "[Once Per Turn] If this Character would be removed from the field, you may trash 1 card from your hand instead."
	var leave_fx := MtEffectParser.parse({"effect": bounce_txt, "type": "Character", "name": "Stay"})
	_check("leave-play replacement parses", not (leave_fx.get("replace_ko", []) as Array).is_empty(), leave_fx.get("replace_ko"))
	var mtl := MtMatch.new()
	mtl.auto_resolve_choices = true
	mtl.start(_tiny(cdb), _tiny(cdb), 0)
	var lme: MtPlayerState = mtl.players[0]
	var stay := MtMatchCard.new("stay", {"name": "Stay", "type": "Character", "cost": 3, "power": 4000, "color": "Red", "effect": bounce_txt}, 0)
	stay.zone = MtMatchCard.ZONE_FIELD
	lme.field.append(stay)
	var fod := MtMatchCard.new("fod", {"name": "Fodder", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	fod.zone = MtMatchCard.ZONE_HAND
	lme.hand.append(fod)
	mtl._fx_cache.clear()
	var stay_count := lme.field.size()
	mtl._bounce_to_hand(stay)
	_check("bounce replacement keeps the Character on the field", _uid_in(lme.field, "stay") and lme.field.size() == stay_count, lme.field.size())

	var bko := MtEffectParser.parse({"effect": "When this Character battles and K.O.'s, draw 1 card.", "type": "Character", "name": "Ace"})
	_check("battles and K.O.'s compiles", not (bko.get("on_battle_ko", []) as Array).is_empty(), bko.get("on_battle_ko"))

	var from_trash := MtEffectParser.parse({"effect": "[Activate: Main] Play this Character card from your trash rested.", "type": "Character", "name": "Back"})
	_check("play this from trash compiles", _has_tok(from_trash.get("activate_main", []), MtEffectParser.TOK_PLAY), from_trash.get("activate_main"))
	var dual := MtEffectParser.parse({"effect": "[On Play] Play 1 card and play the other as rested from your trash.", "type": "Character", "name": "Twin"})
	var play_opts := {}
	for tok in dual.get("on_play", []):
		for a in tok.get("actions", []):
			if a is Array and String(a[0]) == MtEffectParser.TOK_PLAY:
				play_opts = a[1]
	_check("play two from trash marks second rested", bool(play_opts.get("second_rested", false)) and int(play_opts.get("number", 0)) == 2, play_opts)

	var choose_fx := MtEffectParser.parse({"effect": "[Activate: Main] Choose one: Draw 1 card. - Add 1 DON!! from your DON!! deck to your active area.", "type": "Character", "name": "Pick"})
	_check("controller Choose one compiles", _has_tok(choose_fx.get("activate_main", []), MtEffectParser.TOK_CHOOSE), choose_fx.get("activate_main"))

	var evst := MtEffectParser.parse({"effect": "[On Play] Trash 1 Event or Stage from your hand.", "type": "Character", "name": "Filter"})
	var th_opts := {}
	for tok in evst.get("on_play", []):
		for a in tok.get("actions", []):
			if a is Array and String(a[0]) == MtEffectParser.TOK_TRASH_HAND:
				th_opts = a[1]
	_check("trash Event or Stage is type-filtered", String(th_opts.get("card_type", "")) == "EventOrStage", th_opts)

	var their := MtEffectParser.parse({"effect": "[On Play] Your opponent may add 1 DON!! from their DON!! deck to their active area.", "type": "Character", "name": "Offer"})
	_check("opponent may their DON compiles", _has_tok(their.get("on_play", []), MtEffectParser.TOK_OPP_MAY), their.get("on_play"))

	var bottom := MtEffectParser.parse({"effect": "[Activate: Main] Place this card and 1 card from your hand at the bottom of your deck: Draw 2 cards.", "type": "Character", "name": "Sink"})
	_check("this card and 1 from hand to bottom compiles", _has_tok(bottom.get("activate_main", []), MtEffectParser.TOK_HAND_TO_DECK), bottom.get("activate_main"))

	var ctr := MtEffectParser.parse({"effect": "[Counter] If your Character would be K.O.'d in battle this turn, you may trash 1 card from your hand instead.", "type": "Event", "name": "Save"})
	_check("counter battle-KO instead parses", not (ctr.get("replace_ko", []) as Array).is_empty(), ctr.get("replace_ko"))
	lme.ko_instead.append((ctr.get("replace_ko", [{}]) as Array)[0])
	var prey := MtMatchCard.new("prey", {"name": "Prey", "type": "Character", "cost": 2, "power": 2000, "color": "Red", "effect": ""}, 0)
	prey.zone = MtMatchCard.ZONE_FIELD
	lme.field.append(prey)
	var fod2 := MtMatchCard.new("fod2", {"name": "F2", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	fod2.zone = MtMatchCard.ZONE_HAND
	lme.hand.append(fod2)
	mtl.battle = {"attacker": stay, "defender": prey, "defender_owner": 0}
	mtl._fx_cache.clear()
	mtl._ko(prey, stay)
	_check("granted counter instead stops battle K.O.", _uid_in(lme.field, "prey"), prey.zone)

	var mtc := MtMatch.new()
	mtc.auto_resolve_choices = false
	mtc.start(_tiny(cdb), _tiny(cdb), 0)
	var cme: MtPlayerState = mtc.players[0]
	var cfoe: MtPlayerState = mtc.players[1]
	var ksrc := MtMatchCard.new("ks", {"name": "PickKO", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[On Play] K.O. up to 1 of your opponent's Characters."}, 0)
	ksrc.zone = MtMatchCard.ZONE_FIELD
	cme.field.append(ksrc)
	var kv := MtMatchCard.new("kv", {"name": "Mark", "type": "Character", "cost": 1, "power": 1000, "color": "Red", "effect": ""}, 1)
	kv.zone = MtMatchCard.ZONE_FIELD
	cfoe.field.append(kv)
	mtc._fx_cache.clear()
	mtc._resolve_actions(ksrc, mtc.fx(ksrc).get("on_play", [{}])[0].get("actions", []), {})
	_check("manual pick is pending", mtc.pending_choice != null, mtc.pending_choice)
	var cres := mtc.apply({"type": mtc.ACTION_CANCEL_CHOICE})
	_check("cancel pending continues without a pick", cres.get("ok", false) and mtc.pending_choice == null, cres)
	_check("cancel did not K.O. the target", _uid_in(cfoe.field, "kv"), cfoe.field.size())

	print("--- Remaining printed verbs ---")
	var t2h := MtEffectParser.parse({"effect": "[On K.O.] If your Leader has the {Baroque Works} type, add up to 1 Event from your trash to your hand.", "type": "Character", "name": "Mr1"})
	_check("add from trash to hand compiles", _has_tok(t2h.get("on_ko", []), MtEffectParser.TOK_TRASH_TO_HAND), t2h.get("on_ko"))
	var mth := MtMatch.new()
	mth.auto_resolve_choices = true
	mth.start(_tiny(cdb), _tiny(cdb), 0)
	var hme: MtPlayerState = mth.players[0]
	var ev := MtMatchCard.new("ev1", {"name": "Event", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 0)
	ev.zone = MtMatchCard.ZONE_TRASH
	hme.trash.append(ev)
	var rec := MtMatchCard.new("rec", {"name": "Rec", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "[On Play] Add up to 1 Event from your trash to your hand."}, 0)
	rec.zone = MtMatchCard.ZONE_FIELD
	hme.field.append(rec)
	mth._fx_cache.clear()
	var hsz2 := hme.hand.size()
	mth._resolve_actions(rec, mth.fx(rec).get("on_play", [{}])[0].get("actions", []), {})
	_check("trash to hand moves the Event", hme.hand.size() == hsz2 + 1 and _uid_in(hme.hand, "ev1"), hme.hand.size())

	var lock := MtEffectParser.parse({"effect": "This Character cannot attack unless your opponent has 2 or more Characters with a base power of 5000 or more.", "type": "Character", "name": "Lock"})
	_check("cannot-attack-unless parses", not (lock.get("cannot_attack_fx", []) as Array).is_empty(), lock.get("cannot_attack_fx"))
	var lk := MtMatchCard.new("lk", {"name": "Lock", "type": "Character", "cost": 3, "power": 4000, "color": "Red",
		"effect": "This Character cannot attack unless your opponent has 2 or more Characters with a base power of 5000 or more."}, 0)
	lk.zone = MtMatchCard.ZONE_FIELD
	hme.field.append(lk)
	mth._fx_cache.clear()
	mth.phase = MtMatch.Phase.MAIN
	mth.active = 0
	mth.turn = 2
	var vs := mth._legal_attack({"type": mth.ACTION_ATTACK, "attacker": "lk", "target": mth.players[1].leader.uid})
	_check("locked Character cannot attack yet", not vs.ok, vs)

	var grant := MtEffectParser.parse({"effect": "[On Play] Up to 1 of your opponent's Characters with a cost of 5 or less cannot attack until the start of your next turn.", "type": "Character", "name": "Stop"})
	_check("grant cannot-attack compiles", _has_tok(grant.get("on_play", []), MtEffectParser.TOK_NO_ATTACK), grant.get("on_play"))

	var sw := MtEffectParser.parse({"effect": "[Activate: Main] [Once Per Turn] Select 2 of your {Supernovas} or {Heart Pirates} type Characters. Swap the base power of the selected Characters with each other during this turn.", "type": "Leader", "name": "Law"})
	_check("swap base power compiles", _has_tok(sw.get("activate_main", []), MtEffectParser.TOK_SWAP_POWER), sw.get("activate_main"))
	var a := MtMatchCard.new("sa", {"name": "A", "type": "Character", "cost": 2, "power": 2000, "color": "Red", "effect": "", "traits": ["Supernovas"]}, 0)
	var b := MtMatchCard.new("sb", {"name": "B", "type": "Character", "cost": 3, "power": 5000, "color": "Red", "effect": "", "traits": ["Heart Pirates"]}, 0)
	a.zone = MtMatchCard.ZONE_FIELD
	b.zone = MtMatchCard.ZONE_FIELD
	hme.field.append(a)
	hme.field.append(b)
	mth._swap_base_power(a, b, "turn")
	_check("swap exchanges printed power", a.base_power() == 5000 and b.base_power() == 2000, [a.base_power(), b.base_power()])

	var ng := MtEffectParser.parse({"effect": "[On Play] DON!! −1: Negate the effect of up to 1 of your opponent's Characters during this turn. Then, if that Character has 5000 power or less, K.O. it.", "type": "Character", "name": "Zephyr"})
	_check("negate effect compiles", _has_tok(ng.get("on_play", []), MtEffectParser.TOK_NEGATE), ng.get("on_play"))
	var vicn := MtMatchCard.new("vn", {"name": "Blocked", "type": "Character", "cost": 4, "power": 4000, "color": "Red",
		"effect": "[Blocker] [When Attacking] Draw 1 card."}, 1)
	vicn.zone = MtMatchCard.ZONE_FIELD
	mth.players[1].field.append(vicn)
	vicn.effects_negated = true
	_check("negated Character loses Blocker", not mth.has_keyword(vicn, "Blocker"), mth.fx(vicn))

	var st := MtEffectParser.parse({"effect": "This effect can be activated at the start of your turn. If you have 8 or more DON!! cards on your field, look at 5 cards from the top of your deck; reveal up to 1 {Straw Hat Crew} type card and add it to your hand. Then, place the rest at the top or bottom of the deck in any order.", "type": "Leader", "name": "Luffy"})
	_check("start of your turn compiles", not (st.get("on_start_turn", []) as Array).is_empty(), st.get("on_start_turn"))
	_check("start of turn look-at-deck", _has_tok(st.get("on_start_turn", []), MtEffectParser.TOK_LOOK_DECK), st.get("on_start_turn"))

	var roger := MtEffectParser.parse({"effect": "[Rush] When your opponent activates [Blocker], if either you or your opponent has 0 Life cards, you win the game.", "type": "Character", "name": "Roger"})
	_check("win on Blocker at 0 Life parses", bool(roger.get("win_on_block_zero_life", false)), roger)
	var mtr := MtMatch.new()
	mtr.auto_resolve_choices = true
	mtr.start(_tiny(cdb), _tiny(cdb), 0)
	var rme: MtPlayerState = mtr.players[0]
	var ropp: MtPlayerState = mtr.players[1]
	var rg := MtMatchCard.new("rg", {"name": "Roger", "type": "Character", "cost": 10, "power": 13000, "color": "Red",
		"effect": "[Rush] When your opponent activates [Blocker], if either you or your opponent has 0 Life cards, you win the game."}, 0)
	rg.zone = MtMatchCard.ZONE_FIELD
	rme.field.append(rg)
	var blk := MtMatchCard.new("blk", {"name": "Wall", "type": "Character", "cost": 3, "power": 2000, "color": "Red",
		"effect": "[Blocker] (After your opponent declares an attack, you may rest this card to make it the new target of the attack.)"}, 1)
	blk.zone = MtMatchCard.ZONE_FIELD
	ropp.field.append(blk)
	ropp.life.clear()
	mtr._fx_cache.clear()
	mtr.battle = {"attacker": rg, "target": ropp.leader, "defender": ropp.leader, "defender_owner": 1, "step": "block"}
	mtr._do_block({"blocker": "blk"})
	_check("Roger wins when Blocker is activated at 0 Life", mtr.over and mtr.winner == 0, [mtr.over, mtr.winner])

	var wal := MtEffectParser.parse({"effect": "[When Attacking] If this Character is attacking a Leader, draw 1 card.", "type": "Character", "name": "LeadHit"})
	var att := ""
	for tok in wal.get("on_attack", []):
		att = String(tok.get("attack_target", ""))
	_check("when attacking a Leader is filtered", att == "leader", wal.get("on_attack"))

	var mtlk := MtMatch.new()
	mtlk.auto_resolve_choices = false
	mtlk.start(_tiny(cdb), _tiny(cdb), 0)
	var life_ps: MtPlayerState = mtlk.players[1]
	while life_ps.life.size() < 3:
		var lc := MtMatchCard.new("lf%d" % life_ps.life.size(), {"name": "Life", "type": "Character", "cost": 1, "power": 1000, "color": "Red", "effect": ""}, 1)
		lc.zone = MtMatchCard.ZONE_LIFE
		life_ps.life.append(lc)
	var lookc := MtMatchCard.new("ll", {"name": "Seer", "type": "Character", "cost": 2, "power": 2000, "color": "Red",
		"effect": "[On Play] Look at all of your opponent's Life cards and place them in any order."}, 0)
	lookc.zone = MtMatchCard.ZONE_FIELD
	mtlk.players[0].field.append(lookc)
	mtlk._fx_cache.clear()
	mtlk._resolve_actions(lookc, mtlk.fx(lookc).get("on_play", [{}])[0].get("actions", []), {})
	if mtlk.pending_choice == null:
		_check("look-order pending for Life", false, mtlk.pending_choice)
	else:
		var cands: Array = mtlk.pending_choice.get("candidates", [])
		var first := String(cands[0]) if not cands.is_empty() else ""
		mtlk.apply({"type": mtlk.ACTION_CHOOSE_EFFECT, "n": 1, "uids": [first]})
		_check("look-order is sequential", mtlk.pending_choice != null, mtlk.pending_choice)

	print("--- One-off leftover lines ---")
	var trait_fx := MtEffectParser.parse({"effect": "[On Play] If your Leader has the {Straw Hat Crew} type, draw 1 card.", "type": "Character", "name": "Crew"})
	var tcond := {}
	for tok in trait_fx.get("on_play", []):
		for actn in tok.get("actions", []):
			if actn is Array and actn.size() > 1 and actn[1] is Dictionary:
				tcond = actn[1].get("cond", {})
	_check("Leader has {type} stamps leader_trait", String(tcond.get("leader_trait", "")) == "Straw Hat Crew", tcond)

	var treat_fx := MtEffectParser.parse({"effect": "Also treat this card's name as [Kouzuki Oden] according to the rules.", "type": "Character", "name": "OdenKid"})
	_check("treat as name is in rules", (treat_fx.get("rules", {}) as Dictionary).get("treat_as_names", []).has("Kouzuki Oden"), treat_fx.get("rules"))
	var mtt := MtMatch.new()
	mtt.auto_resolve_choices = true
	mtt.start(_tiny(cdb), _tiny(cdb), 0)
	var kid := MtMatchCard.new("odenkid", {"name": "OdenKid", "type": "Character", "cost": 2, "power": 3000, "color": "Red",
		"effect": "Also treat this card's name as [Kouzuki Oden] according to the rules."}, 0)
	_check("treat-as matches Kouzuki Oden", mtt._name_matches(kid, "Kouzuki Oden"), kid.card_name())

	var oh := MtEffectParser.parse({"effect": "[On Play] Trash 1 card from your opponent's hand.", "type": "Character", "name": "Discard"})
	var oh_opts := {}
	for tok in oh.get("on_play", []):
		for actn in tok.get("actions", []):
			if actn is Array and String(actn[0]) == MtEffectParser.TOK_TRASH_HAND:
				oh_opts = actn[1]
	_check("trash opponent hand is player opp", String(oh_opts.get("player", "")) == "opp", oh_opts)
	var ohand := MtMatchCard.new("oh1", {"name": "Gone", "type": "Event", "cost": 1, "power": 0, "color": "Red", "effect": "[Main] Draw 1 card."}, 1)
	ohand.zone = MtMatchCard.ZONE_HAND
	mtt.players[1].hand.append(ohand)
	var dsrc := MtMatchCard.new("ds", {"name": "Discard", "type": "Character", "cost": 3, "power": 4000, "color": "Red",
		"effect": "[On Play] Trash 1 card from your opponent's hand."}, 0)
	dsrc.zone = MtMatchCard.ZONE_FIELD
	mtt.players[0].field.append(dsrc)
	mtt._fx_cache.clear()
	var opp_h := int(mtt.players[1].hand.size())
	mtt._resolve_actions(dsrc, mtt.fx(dsrc).get("on_play", [{}])[0].get("actions", []), {})
	_check("opponent hand loses a card", mtt.players[1].hand.size() == opp_h - 1, mtt.players[1].hand.size())

	var donc := MtEffectParser.parse({"effect": "[On Play] If the number of DON!! cards on your field is equal to or less than the number on your opponent's field, draw 1 card.", "type": "Character", "name": "Even"})
	var dcond := {}
	for tok in donc.get("on_play", []):
		for actn in tok.get("actions", []):
			if actn is Array and actn.size() > 1 and actn[1] is Dictionary:
				dcond = actn[1].get("cond", actn[1])
	_check("DON!! vs opponent stamps don_lte_opp", bool(dcond.get("don_lte_opp", false)) or bool((dcond.get("cond", {}) as Dictionary).get("don_lte_opp", false)), dcond)

	var zerod := MtEffectParser.parse({"effect": "[Activate: Main] If you have 0 DON!! cards on your field, draw 1 card.", "type": "Character", "name": "Empty"})
	_check("0 DON!! compiles a draw", _has_tok(zerod.get("activate_main", []), MtEffectParser.TOK_DRAW), zerod.get("activate_main"))

	var kolife := MtEffectParser.parse({"effect": "[On Play] K.O. up to 1 of your opponent's Characters with a cost equal to or less than the number of your opponent's Life cards.", "type": "Character", "name": "Scale"})
	var ko_opts := {}
	for tok in kolife.get("on_play", []):
		for actn in tok.get("actions", []):
			if actn is Array and String(actn[0]) == MtEffectParser.TOK_KO:
				ko_opts = actn[1]
	_check("KO cost vs opponent Life", bool(ko_opts.get("cost_vs_opp_life", false)), ko_opts)

	var trash_fx := MtEffectParser.parse({"effect": "When this Character is trashed, draw 1 card.", "type": "Character", "name": "Bin"})
	_check("when trashed compiles", not (trash_fx.get("on_trash", []) as Array).is_empty(), trash_fx.get("on_trash"))
	var bin := MtMatchCard.new("bin", {"name": "Bin", "type": "Character", "cost": 2, "power": 2000, "color": "Red",
		"effect": "When this Character is trashed, draw 1 card."}, 0)
	bin.zone = MtMatchCard.ZONE_FIELD
	mtt.players[0].field.append(bin)
	mtt._fx_cache.clear()
	var hands := int(mtt.players[0].hand.size())
	mtt._move_to_trash(mtt.players[0], bin)
	_check("trash trigger draws", mtt.players[0].hand.size() == hands + 1, mtt.players[0].hand.size())

	print("--- Hand cost, cannot play, extra windows ---")
	var hcf := MtEffectParser.parse({"effect": "Give this card in your hand −3 cost.", "type": "Character", "name": "Cheap", "cost": 5})
	_check("this-card-in-hand stamps hand_cost", int(hcf.get("hand_cost", {}).get("amount", 0)) == -3, hcf.get("hand_cost"))
	_check("this-card-in-hand is not a field TOK_COST", not _has_tok(hcf.get("on_play", []), MtEffectParser.TOK_COST), hcf.get("on_play"))
	var aura_fx := MtEffectParser.parse({"effect": "Give blue Events in your hand −1 cost.", "type": "Stage", "name": "Shop"})
	var aura: Dictionary = aura_fx.get("hand_cost_aura", {})
	_check("hand-cost aura amount", int(aura.get("amount", 0)) == -1, aura)
	_check("hand-cost aura filters Events", String(aura.get("card_type", "")) == "Event", aura)
	var npfx := MtEffectParser.parse({"effect": "[On Play] Draw 1 card. Then, you cannot play Character cards during this turn.", "type": "Character", "name": "Lock"})
	_check("cannot play Character compiles", _has_tok(npfx.get("on_play", []), MtEffectParser.TOK_NO_PLAY), npfx.get("on_play"))
	var win_fx := MtEffectParser.parse({"effect": "[Once Per Turn] When you play a Character, draw 1 card.", "type": "Leader", "name": "Host"})
	_check("when you play a Character compiles", not (win_fx.get("on_you_play", []) as Array).is_empty(), win_fx.get("on_you_play"))
	var dmg_fx := MtEffectParser.parse({"effect": "[DON!! x1] [Once Per Turn] When you take damage, draw 1 card.", "type": "Leader", "name": "Tank"})
	_check("when you take damage compiles", not (dmg_fx.get("on_take_damage", []) as Array).is_empty(), dmg_fx.get("on_take_damage"))
	var defc := MtEffectParser.parse({"effect": "If the number of DON!! cards on your field is at least 2 less than the number of DON!! cards on your opponent's field, give this card in your hand −5 cost.", "type": "Character", "name": "Gap"})
	_check("DON deficit cond on hand cost", int(defc.get("hand_cost", {}).get("cond", {}).get("don_deficit", 0)) == 2, defc.get("hand_cost"))

	var mthc := MtMatch.new()
	mthc.auto_resolve_choices = true
	mthc.start(_tiny(cdb), _tiny(cdb), 0)
	mthc.phase = MtMatch.Phase.MAIN
	var cheap := MtMatchCard.new("cheap", {"name": "Cheap", "type": "Character", "cost": 5, "power": 4000, "color": "Red",
		"effect": "Give this card in your hand −3 cost."}, 0)
	cheap.zone = MtMatchCard.ZONE_HAND
	mthc.players[0].hand.append(cheap)
	mthc.players[0].don_active = 10
	mthc.players[0].don_rested = 0
	mthc._fx_cache.clear()
	_check("play_cost applies in-hand discount", mthc.play_cost(cheap) == 2, mthc.play_cost(cheap))
	var shop := MtMatchCard.new("shop", {"name": "Shop", "type": "Stage", "cost": 1, "power": 0, "color": "Blue",
		"effect": "Give blue Events in your hand −1 cost."}, 0)
	shop.zone = MtMatchCard.ZONE_STAGE
	mthc.players[0].stage = shop
	var evb := MtMatchCard.new("evb", {"name": "Blue Event", "type": "Event", "cost": 3, "power": 0, "color": "Blue",
		"effect": "[Main] Draw 1 card."}, 0)
	evb.zone = MtMatchCard.ZONE_HAND
	mthc.players[0].hand.append(evb)
	mthc._fx_cache.clear()
	_check("play_cost applies field aura to Events", mthc.play_cost(evb) == 2, mthc.play_cost(evb))

	var locker := MtMatchCard.new("lock", {"name": "Lock", "type": "Character", "cost": 1, "power": 1000, "color": "Red",
		"effect": "[On Play] You cannot play Character cards during this turn."}, 0)
	locker.zone = MtMatchCard.ZONE_FIELD
	mthc.players[0].field.append(locker)
	mthc._fx_cache.clear()
	mthc._resolve_actions(locker, mthc.fx(locker).get("on_play", [{}])[0].get("actions", []), {})
	var blocked := mthc._legal_play({"type": mthc.ACTION_PLAY, "card_uid": cheap.uid})
	_check("cannot play Characters this turn", not blocked.ok, blocked)

	var mtw := MtMatch.new()
	mtw.auto_resolve_choices = true
	mtw.start(_tiny(cdb), _tiny(cdb), 0)
	mtw.phase = MtMatch.Phase.MAIN
	var host := MtMatchCard.new("host", {"name": "Host", "type": "Character", "cost": 2, "power": 2000, "color": "Red",
		"effect": "[Once Per Turn] When you play a Character, draw 1 card."}, 0)
	host.zone = MtMatchCard.ZONE_FIELD
	mtw.players[0].field.append(host)
	var newbie := MtMatchCard.new("newb", {"name": "New", "type": "Character", "cost": 1, "power": 1000, "color": "Red", "effect": ""}, 0)
	newbie.zone = MtMatchCard.ZONE_FIELD
	mtw.players[0].field.append(newbie)
	mtw._fx_cache.clear()
	var hw := int(mtw.players[0].hand.size())
	mtw._notify_character_played(mtw.players[0], newbie)
	_check("when you play a Character draws", mtw.players[0].hand.size() == hw + 1, mtw.players[0].hand.size())

	var tank := MtMatchCard.new("tank", {"name": "Tank", "type": "Leader", "cost": 0, "power": 5000, "color": "Red",
		"effect": "[DON!! x1] [Once Per Turn] When you take damage, draw 1 card."}, 0)
	tank.zone = MtMatchCard.ZONE_FIELD
	var dummydon := MtMatchCard.new("ddon", {"name": "DON!!", "type": "DON!!"}, 0)
	tank.attached_don.append(dummydon)
	mtw.players[0].field.append(tank)
	mtw._fx_cache.clear()
	while mtw.players[0].life.size() < 1:
		var lf := MtMatchCard.new("life-x", {"name": "Life", "type": "Character", "cost": 1, "power": 1000, "color": "Red", "effect": ""}, 0)
		lf.zone = MtMatchCard.ZONE_LIFE
		mtw.players[0].life.append(lf)
	var hd := int(mtw.players[0].hand.size())
	mtw._deal_leader_damage(mtw.players[0], null)
	_check("when you take damage draws", mtw.players[0].hand.size() == hd + 2, mtw.players[0].hand.size())

	print("--- Unique leftover windows ---")
	var donr := MtEffectParser.parse({"effect": "When a DON!! card on your field is returned to your DON!! deck, draw 1 card.", "type": "Character", "name": "Kid"})
	_check("DON return window compiles", not (donr.get("on_don_return", []) as Array).is_empty(), donr.get("on_don_return"))
	var evw := MtEffectParser.parse({"effect": "When your opponent activates an Event, draw 1 card.", "type": "Character", "name": "Watch"})
	_check("opponent Event window compiles", not (evw.get("on_opp_event", []) as Array).is_empty(), evw.get("on_opp_event"))
	var rsw := MtEffectParser.parse({"effect": "When this Character becomes rested, draw 1 card.", "type": "Character", "name": "Sit"})
	_check("becomes rested window compiles", not (rsw.get("on_self_rest", []) as Array).is_empty(), rsw.get("on_self_rest"))
	var kow := MtEffectParser.parse({"effect": "When your opponent's Character is K.O.'d, draw 1 card.", "type": "Character", "name": "Koby"})
	_check("opp Character K.O. window compiles", not (kow.get("on_opp_char_ko", []) as Array).is_empty(), kow.get("on_opp_char_ko"))
	var norem := MtEffectParser.parse({"effect": "This Character cannot be removed from the field by your opponent's effects.", "type": "Character", "name": "Ice"})
	_check("cannot-be-removed compiles", not (norem.get("no_remove_fx", []) as Array).is_empty(), norem)
	var locko := MtEffectParser.parse({"effect": "All of your opponent's Characters cannot be removed from the field by your effects.", "type": "Character", "name": "Croc"})
	_check("lock opponent chars compiles", bool(locko.get("lock_opp_chars", false)), locko)
	var until := MtEffectParser.parse({"effect": "[Main] Draw until you have 5 cards.", "type": "Event", "name": "Fill"})
	_check("draw until compiles", _has_tok(until.get("on_main", []), MtEffectParser.TOK_DRAW), until.get("on_main"))

	var mtu := MtMatch.new()
	mtu.auto_resolve_choices = true
	mtu.start(_tiny(cdb), _tiny(cdb), 0)
	mtu.phase = MtMatch.Phase.MAIN
	var sit := MtMatchCard.new("sit", {"name": "Sit", "type": "Character", "cost": 2, "power": 2000, "color": "Red",
		"effect": "When this Character becomes rested, draw 1 card."}, 0)
	sit.zone = MtMatchCard.ZONE_FIELD
	mtu.players[0].field.append(sit)
	mtu._fx_cache.clear()
	var hs := int(mtu.players[0].hand.size())
	mtu._note_rested(sit)
	_check("becomes rested draws", mtu.players[0].hand.size() == hs + 1, mtu.players[0].hand.size())
	var kidw := MtMatchCard.new("kidw", {"name": "Kid", "type": "Character", "cost": 5, "power": 6000, "color": "Red",
		"effect": "When a DON!! card on your field is returned to your DON!! deck, draw 1 card."}, 0)
	kidw.zone = MtMatchCard.ZONE_FIELD
	mtu.players[0].field.append(kidw)
	mtu.players[0].don_active = 4
	mtu.players[0].don_in_deck = 6
	mtu._fx_cache.clear()
	var hk := int(mtu.players[0].hand.size())
	mtu._return_don_to_deck(mtu.players[0], 1)
	_check("DON return draws", mtu.players[0].hand.size() == hk + 1, mtu.players[0].hand.size())
	var ice := MtMatchCard.new("ice", {"name": "Ice", "type": "Character", "cost": 4, "power": 5000, "color": "Blue",
		"effect": "This Character cannot be removed from the field by your opponent's effects."}, 1)
	ice.zone = MtMatchCard.ZONE_FIELD
	mtu.players[1].field.append(ice)
	mtu._fx_cache.clear()
	mtu._ko(ice, sit)
	_check("cannot-remove blocks effect K.O.", ice in mtu.players[1].field, ice.zone)

func _uid_in(arr: Array, uid: String) -> bool:
	for c in arr:
		if c.uid == uid:
			return true
	return false

func _has_tok(sections, kind: String) -> bool:
	if not (sections is Array):
		return false
	for tok in sections:
		if not (tok is Dictionary):
			continue
		if _actions_have(tok.get("actions", []), kind):
			return true
	return false

func _actions_have(actions, kind: String) -> bool:
	if not (actions is Array):
		return false
	for a in actions:
		if not (a is Array) or a.is_empty():
			continue
		if String(a[0]) == kind:
			return true
		if String(a[0]) == MtEffectParser.TOK_PAY and a.size() > 1 and a[1] is Dictionary:
			if _actions_have(a[1].get("actions", []), kind):
				return true
		if String(a[0]) == MtEffectParser.TOK_OPP_MAY and a.size() > 1 and a[1] is Dictionary:
			if _actions_have(a[1].get("do", []), kind) or _actions_have(a[1].get("else", []), kind):
				return true
	return false

func _fifty(cdb: Node, leader_code: String, prefix: String) -> Dictionary:
	var main: Array = []
	var i := 0
	while main.size() < 50:
		var d: Dictionary = cdb.get_card_data("%s-%03d" % [prefix, (i % 14) + 1])
		i += 1
		if not d.is_empty() and String(d.get("type", "")) != "Leader":
			main.append(d)
		if i > 200:
			break
	return {"leader": cdb.get_card_data(leader_code), "main": main}

func _count_code(arr: Array, code: String) -> int:
	var n := 0
	for c in arr:
		if String((c as Dictionary).get("card_code", "")) == code:
			n += 1
	return n

func _tiny(cdb: Node) -> Dictionary:
	var codes: Array = []
	for code in ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
			"ST01-007", "ST01-008", "ST01-009", "ST01-010", "ST01-011", "ST01-012", "ST01-013",
			"ST01-015"]:
		for _i in range(4):
			codes.append(code)
	return MtDeckLoader.build_from_lists("ST01-001", codes, cdb.get_card_data)

func _spawn(ps: MtPlayerState, data: Dictionary) -> MtMatchCard:
	var c := MtMatchCard.new("u-%s-%d" % [data.get("card_code"), ps.field.size()], data, ps.index)
	c.zone = MtMatchCard.ZONE_FIELD
	ps.field.append(c)
	return c
