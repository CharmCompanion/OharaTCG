# tests/brook_on_play_smoke.gd -- ST01-011 Brook [On Play] give rested DON!!
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
		print("BROOK ON PLAY SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
	return false

func _st01_deck(cdb: Node) -> Dictionary:
	var main_codes: Array = []
	for code in ["ST01-002", "ST01-003", "ST01-004", "ST01-005", "ST01-006",
			"ST01-007", "ST01-008", "ST01-009", "ST01-010", "ST01-011", "ST01-012", "ST01-013",
			"ST01-015"]:
		for _i in range(4):
			main_codes.append(code)
	return MtDeckLoader.build_from_lists("ST01-001", main_codes, cdb.get_card_data)

func _run(cdb: Node) -> void:
	print("--- Brook [On Play] and given DON!! rules ---")
	var brook_d: Dictionary = cdb.get_card_data("ST01-011")
	_check("Brook data loaded", not brook_d.is_empty(), brook_d)
	var parsed: Dictionary = MtEffectParser.parse(brook_d)
	_check("Brook parses [On Play]", not parsed.get("on_play", []).is_empty())
	var acts: Array = []
	if not parsed.get("on_play", []).is_empty():
		acts = parsed.on_play[0].get("actions", [])
	var attach = null
	for a in acts:
		if a is Array and a.size() > 0 and a[0] == MtEffectParser.TOK_ATTACH_DON:
			attach = a[1]
			break
	_check("Brook On Play gives DON!!", attach != null, acts)
	if attach is Dictionary:
		_check("Brook gives 2 DON!!", int(attach.get("n", 0)) == 2, attach)
		_check("Brook is up to 2", bool(attach.get("up_to", false)), attach)
		_check("Brook uses rested DON!!", String(attach.get("from", "")) == "rested", attach)
	elif attach != null:
		_check("Brook gives 2 DON!! (legacy int)", int(attach) == 2, attach)

	var luffy_d: Dictionary = cdb.get_card_data("ST01-001")
	var lf: Dictionary = MtEffectParser.parse(luffy_d)
	_check("Luffy has [Activate: Main]", not lf.get("activate_main", []).is_empty())
	var lf_acts: Array = []
	if not lf.get("activate_main", []).is_empty():
		lf_acts = lf.activate_main[0].get("actions", [])
	var lf_attach = null
	for a in lf_acts:
		if a is Array and a.size() > 0 and a[0] == MtEffectParser.TOK_ATTACH_DON:
			lf_attach = a[1]
			break
	_check("Luffy Activate: Main gives rested DON!!", lf_attach != null, lf_acts)
	if lf_attach is Dictionary:
		_check("Luffy gives 1 DON!!", int(lf_attach.get("n", 0)) == 1, lf_attach)

	var nami_d: Dictionary = cdb.get_card_data("ST01-007")
	var nf: Dictionary = MtEffectParser.parse(nami_d)
	_check("Nami has [Activate: Main] actions", not nf.get("activate_main", []).is_empty() and not nf.activate_main[0].get("actions", []).is_empty())

	var mt := MtMatch.new()
	mt.auto_resolve_choices = true
	mt.start(_st01_deck(cdb), _st01_deck(cdb), 0)
	mt.phase = MtMatch.Phase.MAIN
	var me: MtPlayerState = mt.players[0]
	me.don_active = 6
	me.don_rested = 0
	var brook: MtMatchCard = null
	for c in me.hand:
		if c.card_code() == "ST01-011":
			brook = c
			break
	if brook == null:
		for c in me.deck:
			if c.card_code() == "ST01-011":
				me.deck.erase(c)
				c.zone = MtMatchCard.ZONE_HAND
				me.hand.append(c)
				brook = c
				break
	_check("Brook in hand", brook != null)
	if brook == null:
		return
	var res := mt.apply({"type": mt.ACTION_PLAY, "card_uid": brook.uid})
	_check("Play Brook ok", res.ok, res)
	_check("Brook in Character Area", brook in me.field)
	_check("Brook was given 2 rested DON!!", brook.don_count() == 2, brook.don_count())
	_check("Cost-area DON!! used for the give are no longer rested", me.don_rested == 0, me.don_rested)
	_check("Given DON!! still count toward DON!! in play", me.don_active == 6, me.don_active)

	# Refresh Phase: given DON!! return, then all set as active.
	me.reset_don_refresh()
	_check("Refresh returns given DON!!", brook.don_count() == 0, brook.don_count())
	_check("Refresh sets cost-area DON!! as active", me.don_rested == 0, me.don_rested)
	_check("Returned DON!! remain in play", me.don_active == 6, me.don_active)

	# Give 1 active DON!! (comprehensive rules 6-5-5)
	mt.phase = MtMatch.Phase.MAIN
	var give := mt.apply({"type": mt.ACTION_ATTACH_DON, "card_uid": brook.uid})
	_check("Give 1 Active DON!! ok", give.ok, give)
	_check("Brook now has 1 given DON!!", brook.don_count() == 1, brook.don_count())

	# K.O. returns given DON!! to the cost area rested.
	mt._ko(brook)
	_check("K.O. places Brook in Trash", brook in me.trash)
	_check("Given DON!! return rested on K.O.", me.don_rested >= 1, me.don_rested)

	# Human choice path: auto_resolve_choices false leaves a pending give.
	var mt2 := MtMatch.new()
	mt2.auto_resolve_choices = false
	mt2.start(_st01_deck(cdb), _st01_deck(cdb), 0)
	mt2.phase = MtMatch.Phase.MAIN
	var me2: MtPlayerState = mt2.players[0]
	me2.don_active = 6
	me2.don_rested = 0
	var brook2: MtMatchCard = null
	for c in me2.hand:
		if c.card_code() == "ST01-011":
			brook2 = c
			break
	if brook2 == null:
		for c in me2.deck:
			if c.card_code() == "ST01-011":
				me2.deck.erase(c)
				c.zone = MtMatchCard.ZONE_HAND
				me2.hand.append(c)
				brook2 = c
				break
	_check("Choice-mode Brook in hand", brook2 != null)
	if brook2 == null:
		return
	var res2 := mt2.apply({"type": mt2.ACTION_PLAY, "card_uid": brook2.uid})
	_check("Choice-mode play Brook ok", res2.ok, res2)
	_check("On Play pends a give-DON!! choice", mt2.pending_choice != null and String(mt2.pending_choice.get("type", "")) == "give_don", mt2.pending_choice)
	_check("Pending max is 2", int(mt2.pending_choice.get("max", 0)) == 2, mt2.pending_choice)
	var choose := mt2.apply({"type": mt2.ACTION_CHOOSE_EFFECT, "n": 2, "target_uid": me2.leader.uid})
	_check("Choose give 2 to Leader ok", choose.ok, choose)
	_check("Leader received 2 given DON!!", me2.leader.don_count() == 2, me2.leader.don_count())
	_check("Choice cleared", mt2.pending_choice == null)

	var mt3 := MtMatch.new()
	mt3.auto_resolve_choices = true
	mt3.start(_st01_deck(cdb), _st01_deck(cdb), 0)
	mt3.phase = MtMatch.Phase.MAIN
	var me3: MtPlayerState = mt3.players[0]
	me3.don_active = 6
	me3.don_rested = 2
	var lact := mt3.apply({"type": mt3.ACTION_ACTIVATE, "card_uid": me3.leader.uid})
	_check("Activate Luffy ok", lact.ok, lact)
	_check("Luffy [Activate: Main] gave 1 rested DON!!", me3.leader.don_count() == 1, me3.leader.don_count())
	_check("Luffy consumed 1 rested DON!!", me3.don_rested == 1, me3.don_rested)
