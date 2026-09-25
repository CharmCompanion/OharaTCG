# One-shot coverage scan: every Character / Leader / Event / Stage.
extends SceneTree

const TYPES := ["Character", "Leader", "Event", "Stage"]
const ARRAY_KEYS := [
	"triggers", "on_play", "activate_main", "on_attack", "on_ko", "on_block",
	"on_opp_attack", "on_end", "on_opp_end", "on_main", "counter", "turn_power",
	"don_power", "protect_fx", "must_attack_fx", "turn_actions", "on_give_don",
	"on_opp_turn", "replace_ko", "on_battle_ko", "on_start_turn", "cannot_attack_fx",
	"on_trash", "on_you_play", "on_opp_play", "on_take_damage", "on_don_return",
	"on_life_damage", "on_opp_block", "on_life_zero", "on_life_removed",
	"on_opp_char_ko", "on_opp_event", "on_you_event", "on_self_rest",
	"on_char_leave", "on_hand_trash", "on_play_from_trash", "no_remove_fx",
]

func _process(_d: float) -> bool:
	var cdb = root.get_node_or_null("CardDatabase")
	if cdb == null or not cdb.is_data_loaded:
		return false
	_scan(cdb)
	quit(0)
	return true

func _scan(cdb: Node) -> void:
	var empty_body := {}
	var empty_ex := {}
	var dead := {}
	var dead_ex := {}
	var n := 0
	var covered := 0
	var dead_n := 0
	var empty_n := 0
	for card in cdb.get_base_cards_as_array():
		if not (card is Dictionary):
			continue
		if String(card.get("region", "")).to_upper() != "EN":
			continue
		if not TYPES.has(String(card.get("type", ""))):
			continue
		n += 1
		var effect := String(card.get("effect", "")).strip_edges()
		var trigger := String(card.get("trigger", "")).strip_edges()
		var fx: Dictionary = MtEffectParser.parse(card)
		var actions := 0
		var statics := 0
		if not (fx.get("keywords", []) as Array).is_empty():
			statics += 1
		if not (fx.get("rules", {}) as Dictionary).is_empty():
			statics += 1
		if not (fx.get("hand_cost", {}) as Dictionary).is_empty():
			statics += 1
		if not (fx.get("hand_cost_aura", {}) as Dictionary).is_empty():
			statics += 1
		if bool(fx.get("play_self_on_trigger", false)) or bool(fx.get("rerun_main_on_trigger", false)) \
				or bool(fx.get("rerun_counter_on_trigger", false)) or bool(fx.get("rerun_on_play_on_trigger", false)):
			statics += 1
		if bool(fx.get("can_attack_active", false)) or bool(fx.get("can_attack_turn_played", false)):
			statics += 1
		if not (fx.get("static_actions", []) as Array).is_empty():
			statics += (fx.get("static_actions", []) as Array).size()
		if bool(fx.get("win_on_block_zero_life", false)) or bool(fx.get("lock_opp_chars", false)):
			statics += 1
		if int(fx.get("no_block_with_don", 0)) > 0 or int(fx.get("grants_rush_at_don", 0)) > 0:
			statics += 1
		for key in ARRAY_KEYS:
			for tok in fx.get(key, []):
				if not (tok is Dictionary):
					statics += 1
					continue
				var acts: Array = tok.get("actions", [])
				if acts.is_empty():
					var body := String(tok.get("body", tok.get("trigger", ""))).strip_edges()
					var blow := body.to_lower()
					if bool(fx.get("play_self_on_trigger", false)) and blow.contains("play this card"):
						statics += 1
						continue
					if (bool(fx.get("rerun_main_on_trigger", false)) or bool(fx.get("rerun_counter_on_trigger", false)) or bool(fx.get("rerun_on_play_on_trigger", false))) and blow.contains("activate this card"):
						statics += 1
						continue
					if body != "" and body != "-":
						empty_n += 1
						var k := _norm(body)
						empty_body[k] = int(empty_body.get(k, 0)) + 1
						if not empty_ex.has(k):
							empty_ex[k] = "%s %s" % [card.get("card_code"), body.substr(0, 140)]
					else:
						statics += 1
				else:
					actions += acts.size()
		var payload := actions + statics
		var text := effect
		if text == "-" or text == "":
			text = trigger
		if text != "" and text != "-" and payload == 0:
			dead_n += 1
			var k2 := _norm(text)
			dead[k2] = int(dead.get(k2, 0)) + 1
			if not dead_ex.has(k2):
				dead_ex[k2] = "%s %s | %s" % [card.get("card_code"), card.get("name"), text.substr(0, 160)]
		else:
			covered += 1
	var path := "res://tools/_coverage.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("cards %d covered %d dead %d empty_sections %d" % [n, covered, dead_n, empty_n])
	f.store_line("\n=== DEAD CARDS (no tokens) top 80 ===")
	_dump(f, dead, dead_ex, 80)
	f.store_line("\n=== TIMED BODIES WITH ZERO ACTIONS top 120 ===")
	_dump(f, empty_body, empty_ex, 120)
	f.close()
	print("COVERAGE cards=%d covered=%d dead=%d empty_sections=%d" % [n, covered, dead_n, empty_n])

func _dump(f: FileAccess, counts: Dictionary, ex: Dictionary, limit: int) -> void:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var n := mini(limit, keys.size())
	for i in range(n):
		var k: String = keys[i]
		f.store_line("%4d  %s" % [counts[k], k.substr(0, 180)])
		f.store_line("      %s" % ex.get(k, ""))

func _norm(s: String) -> String:
	var t := s.to_lower()
	var re := RegEx.new()
	re.compile("\\[[^\\]]+\\]")
	t = re.sub(t, "N", true)
	re.compile("\\{[^}]+\\}")
	t = re.sub(t, "T", true)
	re.compile("\\d+")
	t = re.sub(t, "N", true)
	return t.substr(0, 220)
