# res://scripts/match/CardProfile.gd
# Full printed + parsed record the game reads in hand, field, Life, Trash, etc.
extends RefCounted
class_name MtCardProfile

static func from_dict(card: Dictionary) -> Dictionary:
	var fx: Dictionary = MtEffectParser.parse(card)
	var traits: Array = []
	if card.get("traits", []) is Array:
		traits = (card.get("traits", []) as Array).duplicate()
	return {
		"name": String(card.get("name", "")),
		"card_code": String(card.get("card_code", "")),
		"type": String(card.get("type", "")),
		"color": String(card.get("color", "")),
		"cost": int(card.get("cost", 0)),
		"power": int(card.get("power", 0)),
		"counter": int(card.get("counter", 0)),
		"life": int(card.get("life", 0)),
		"attribute": String(card.get("attribute", "")),
		"traits": traits,
		"rarity": String(card.get("rarity", "")),
		"set_code": String(card.get("set_code", "")),
		"set_name": String(card.get("set_name", "")),
		"block_number": int(card.get("block_number", 0)),
		"effect": String(card.get("effect", "")),
		"trigger": String(card.get("trigger", "")),
		"keywords": (fx.get("keywords", []) as Array).duplicate(),
		"can_attack_turn_played": bool(fx.get("can_attack_turn_played", false)),
		"rush_character_only": bool(fx.get("rush_character_only", false)),
		"unblockable": bool(fx.get("unblockable", false)),
		"has_blocker": (fx.get("keywords", []) as Array).has("Blocker"),
		"has_rush": (fx.get("keywords", []) as Array).has("Rush"),
		"has_double_attack": (fx.get("keywords", []) as Array).has("Double Attack"),
		"has_banish": (fx.get("keywords", []) as Array).has("Banish"),
		"can_attack_active": bool(fx.get("can_attack_active", false)),
		"has_counter_effect": not (fx.get("counter", []) as Array).is_empty(),
		"has_trigger": not String(card.get("trigger", "")).strip_edges().is_empty(),
		"timings": _timings(fx),
		"fx": fx,
	}

static func _timings(fx: Dictionary) -> Array:
	var out: Array = []
	_add_timing(out, "[On Play]", fx.get("on_play", []))
	_add_timing(out, "[Activate: Main]", fx.get("activate_main", []))
	_add_timing(out, "[When Attacking]", fx.get("on_attack", []))
	_add_timing(out, "[On Block]", fx.get("on_block", []))
	_add_timing(out, "[On Your Opponent's Attack]", fx.get("on_opp_attack", []))
	_add_timing(out, "[On K.O.]", fx.get("on_ko", []))
	if not (fx.get("on_battle_ko", []) as Array).is_empty():
		out.append({"hat": "[When this Character battles and K.O.'s]", "once_per_turn": false, "don_min": 0,
			"rest_cost": false, "body": "", "action_count": (fx.get("on_battle_ko", []) as Array).size()})
	_add_timing(out, "[End of Your Turn]", fx.get("on_end", []))
	_add_timing(out, "[End of Your Opponent's Turn]", fx.get("on_opp_end", []))
	_add_timing(out, "[Main]", fx.get("on_main", []))
	_add_timing(out, "[Counter]", fx.get("counter", []))
	_add_timing(out, "[Trigger]", fx.get("triggers", []))
	for p in fx.get("protect_fx", []):
		var dur := String(p.get("dur", ""))
		var hat := "[Opponent's Turn]" if dur == "opp_turn" else "[Your Turn]"
		out.append({"hat": hat, "once_per_turn": false, "don_min": 0, "rest_cost": false,
			"body": "cannot be K.O.'d", "action_count": 1})
	for m in fx.get("must_attack_fx", []):
		out.append({"hat": "[Opponent's Turn]", "once_per_turn": false, "don_min": 0, "rest_cost": false,
			"body": "cannot attack any card other than [%s]" % String(m.get("name", "")), "action_count": 1})
	_add_timing(out, "[On Your Opponent's Turn]", fx.get("on_opp_turn", []))
	_add_timing(out, "[When given DON!!]", fx.get("on_give_don", []))
	_add_timing(out, "[Start of Your Turn]", fx.get("on_start_turn", []))
	_add_timing(out, "[When trashed]", fx.get("on_trash", []))
	_add_timing(out, "[When you play a Character]", fx.get("on_you_play", []))
	_add_timing(out, "[When your opponent plays a Character]", fx.get("on_opp_play", []))
	_add_timing(out, "[When you take damage]", fx.get("on_take_damage", []))
	_add_timing(out, "[When DON!! is returned]", fx.get("on_don_return", []))
	_add_timing(out, "[When attack deals damage to Life]", fx.get("on_life_damage", []))
	_add_timing(out, "[When opponent activates Blocker]", fx.get("on_opp_block", []))
	_add_timing(out, "[When Life becomes 0]", fx.get("on_life_zero", []))
	_add_timing(out, "[When a Life card is removed]", fx.get("on_life_removed", []))
	_add_timing(out, "[When opponent's Character is K.O.'d]", fx.get("on_opp_char_ko", []))
	_add_timing(out, "[When opponent activates an Event]", fx.get("on_opp_event", []))
	_add_timing(out, "[When you activate an Event]", fx.get("on_you_event", []))
	_add_timing(out, "[When this Character becomes rested]", fx.get("on_self_rest", []))
	_add_timing(out, "[When a Character leaves the field]", fx.get("on_char_leave", []))
	_add_timing(out, "[When a card is trashed from your hand]", fx.get("on_hand_trash", []))
	_add_timing(out, "[When a Character is played from trash]", fx.get("on_play_from_trash", []))
	if bool(fx.get("win_on_block_zero_life", false)):
		out.append({"hat": "[When opponent activates Blocker]", "once_per_turn": false, "don_min": 0,
			"rest_cost": false, "body": "you win the game if either player has 0 Life", "action_count": 1})
	for tp in fx.get("turn_power", []):
		if not (tp is Dictionary):
			continue
		var dur := String(tp.get("dur", "turn"))
		var hat := "[During this turn]"
		if dur == "own_turn":
			hat = "[Your Turn]"
		elif dur == "opp_turn":
			hat = "[Opponent's Turn]"
		out.append({
			"hat": hat,
			"once_per_turn": false,
			"don_min": int(tp.get("condition_don", 0)),
			"rest_cost": false,
			"body": "%+d power" % int(tp.get("amount", 0)),
			"action_count": 1,
		})
	return out

static func _add_timing(out: Array, hat: String, arr) -> void:
	if not (arr is Array):
		return
	for tok in arr:
		if not (tok is Dictionary):
			continue
		out.append({
			"hat": hat,
			"once_per_turn": bool(tok.get("once_per_turn", false)),
			"once_per_game": bool(tok.get("once_per_game", false)),
			"don_min": int(tok.get("don_min", 0)),
			"rest_cost": bool(tok.get("rest_cost", false)),
			"body": String(tok.get("body", tok.get("trigger", ""))),
			"action_count": (tok.get("actions", []) as Array).size(),
		})

static func inspector_stats(card: Dictionary, live_power: int = -1) -> String:
	var p := from_dict(card)
	var bits: Array = []
	bits.append(String(p.type))
	if String(p.color) != "":
		bits.append(String(p.color))
	if String(p.attribute) != "":
		bits.append(String(p.attribute))
	var line1 := " · ".join(bits)
	var pow_s := str(int(p.power))
	if live_power >= 0:
		pow_s = str(live_power)
	var line2 := "Cost %d · Power %s" % [int(p.cost), pow_s]
	if int(p.counter) > 0 or String(p.type) != "Leader":
		line2 += " · Counter %d" % int(p.counter)
	if String(p.type) == "Leader":
		line2 += " · Life %d" % int(p.life)
	if int(p.block_number) > 0:
		line2 += " · Block %d" % int(p.block_number)
	var line3 := ""
	var traits: Array = p.traits
	if not traits.is_empty():
		line3 = "Traits: " + ", ".join(traits)
	return "\n".join([line1, line2] if line3.is_empty() else [line1, line2, line3])

static func inspector_rules(card: Dictionary) -> String:
	var p := from_dict(card)
	var lines: Array = []
	var kws: Array = p.keywords
	if not kws.is_empty():
		var kwl: Array = []
		for k in kws:
			kwl.append("[%s]" % k)
		lines.append("Keywords: " + " ".join(kwl))
	for t in p.timings:
		var extra := ""
		if bool(t.get("once_per_turn", false)):
			extra += " [Once Per Turn]"
		if bool(t.get("once_per_game", false)):
			extra += " [Once Per Game]"
		if int(t.get("don_min", 0)) > 0:
			extra += " [DON!! x%d]" % int(t.get("don_min", 0))
		if bool(t.get("rest_cost", false)):
			extra += " (rest this card)"
		var body := String(t.get("body", "")).strip_edges()
		if body.is_empty():
			lines.append("%s%s" % [t.get("hat", ""), extra])
		else:
			lines.append("%s%s %s" % [t.get("hat", ""), extra, body])
	var effect := String(p.effect).strip_edges()
	if effect != "" and effect != "-":
		lines.append("")
		lines.append(effect)
	var trig := String(p.trigger).strip_edges()
	if trig != "":
		lines.append("[Trigger] " + trig)
	return "\n".join(lines)
