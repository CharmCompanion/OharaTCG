# res://scripts/match/Effects.gd
# Best-effort compiler from official card EN text into a small structured
# action DSL the Match engine can resolve. Anything it can't parse is left
# out; such cards still play with base stats + keywords.
class_name MtEffectParser

const HARD_KEYWORDS := [
	"Blocker", "Rush", "Rush: Character", "Double Attack", "Banish", "Unblockable",
]
const TOK_GRANT_KW := "grant_kw"

# Keys in the returned effect tokens
const TOK_DRAW := "draw"
const TOK_ADD_DON := "add_don"
const TOK_ATTACH_DON := "attach_don"
const TOK_KO := "ko"
const TOK_POWER := "power"
const TOK_REST_DON := "rest_don"
const TOK_TRASH_DECK := "trash_deck"
const TOK_PLAY_SELF := "play_self"
const TOK_GRANT_RUSH := "grant_rush"
const TOK_NO_BLOCK := "no_block"
const TOK_LIFE_TO_HAND := "life_to_hand"
const TOK_DECK_TO_LIFE := "deck_to_life"
const TOK_HAND_TO_LIFE := "hand_to_life"
const TOK_TRASH_LIFE := "trash_life"
const TOK_FACE_LIFE := "face_life"
const TOK_CHAR_TO_LIFE := "char_to_life"
const TOK_LOOK_LIFE := "look_life"
const TOK_TRASH_FACEUP := "trash_faceup"
const TOK_TO_DECK := "to_deck"
const TOK_TRASH_TO_DECK := "trash_to_deck"
const TOK_TRASH_HAND := "trash_hand"
const TOK_PAY := "pay_cost"
const TOK_DON_MINUS := "don_minus"
const TOK_REST_SELF := "rest_self"
const TOK_SET_DON_ACTIVE := "set_don_active"
const TOK_PLAY := "play_card"
const TOK_BOUNCE := "bounce"
const TOK_LOOK_DECK := "look_deck"
const TOK_COST := "cost"
const TOK_PROTECT := "protect"
const TOK_SET_ACTIVE := "set_active"
const TOK_REST_CHAR := "rest_char"
const TOK_SKIP_REFRESH := "skip_refresh"
const TOK_SHUFFLE := "shuffle"
const TOK_MUST_ATTACK := "must_attack"
const TOK_REMOVE := "remove"
const TOK_REVEAL_HAND := "reveal_hand"
const TOK_TRASH_SELF := "trash_self"
const TOK_OPP_CHOOSE := "opp_choose"
const TOK_OPP_MAY := "opp_may"
const TOK_CHOOSE := "choose"
const TOK_HAND_TO_DECK := "hand_to_deck"
const TOK_TRASH_TO_HAND := "trash_to_hand"
const TOK_NO_ATTACK := "no_attack"
const TOK_FIELD_TRASH := "field_trash"
const TOK_DAMAGE := "damage"
const TOK_NO_LIFE_ADD := "no_life_add"
const TOK_WIN := "win"
const TOK_SWAP_POWER := "swap_power"
const TOK_NEGATE := "negate"
const TOK_NO_PLAY := "no_play"
const TOK_HAND_COST := "hand_cost"
const TOK_SET_POWER := "set_power"

# Entry point: parse a normalized card dict into effect tokens.
# Returns:
# {
#   "keywords": Array[String] (Blocker, Rush, Double Attack, Banish),
#   "can_attack_turn_played": bool,
#   "no_block_with_don": int,          # [DON!! xN] [When Attacking] opponent cannot activate Blocker
#   "triggers": Array[Dictionary],     # {"trigger": "...", "actions": Array}
#   "on_play": Array[Dictionary],       # {"condition": "", "actions": Array}
#   "activate_main": Array[Dictionary], # {"rest_cost": bool, "actions": Array}
#   "on_attack": Array[Dictionary],     # {"don_min": N, "actions": Array}
#   "on_ko": Array[Dictionary],
#   "on_end": Array[Dictionary],       # [End of Your Turn] bodies
#   "rules": Dictionary,               # leader base-rule changes (optional)
#   "turn_power": Array[Dictionary],    # {"amount": N, "dur": "turn", "condition_don": N}
#   "don_power": Array[Dictionary],     # {"amount": N, "min_don": N, "dur": "own_turn"/"opp_turn"/"always"}
#   "play_self_on_trigger": bool,
#   "blocks_disabled": bool,
# }
static func parse(card: Dictionary) -> Dictionary:
	var out := {
		"keywords": [],
		"can_attack_turn_played": false,
		"rush_character_only": false,
		"unblockable": false,
		"no_block_with_don": 0,
		"triggers": [],
		"on_play": [],
		"activate_main": [],
		"on_attack": [],
		"on_ko": [],
		"on_block": [],
		"on_opp_attack": [],
		"on_end": [],
		"on_opp_end": [],
		"on_main": [],
		"counter": [],
		"turn_power": [],
		"don_power": [],
		"play_self_on_trigger": false,
		"blocks_disabled": false,
		"protect_fx": [],
		"must_attack_fx": [],
		"turn_actions": [],
		"can_attack_active": false,
		"on_give_don": [],
		"on_opp_turn": [],
		"replace_ko": [],
		"on_battle_ko": [],
		"on_start_turn": [],
		"cannot_attack_fx": [],
		"win_on_block_zero_life": false,
		"on_trash": [],
		"hand_cost": {},
		"hand_cost_aura": {},
		"on_you_play": [],
		"on_opp_play": [],
		"on_take_damage": [],
		"on_don_return": [],
		"on_life_damage": [],
		"on_opp_block": [],
		"on_life_zero": [],
		"on_life_removed": [],
		"on_opp_char_ko": [],
		"on_opp_event": [],
		"on_you_event": [],
		"on_self_rest": [],
		"on_char_leave": [],
		"on_hand_trash": [],
		"on_play_from_trash": [],
		"no_remove_fx": [],
		"lock_opp_chars": false,
	}
	var effect_text := _expand_slash_timings(_normalize_brackets(String(card.get("effect", ""))))
	var trigger_text := _normalize_brackets(String(card.get("trigger", "")))
	if effect_text.strip_edges() == "-":
		effect_text = ""

	# 1) Static keyword abilities (not "gains [Rush]" conditionals)
	for kw in HARD_KEYWORDS:
		if _has_static_keyword(effect_text, kw) or _has_static_keyword(trigger_text, kw):
			out.keywords.append(kw)
	if "Rush" in out.keywords or "Rush: Character" in out.keywords:
		out.can_attack_turn_played = true
	if "Rush: Character" in out.keywords and not ("Rush" in out.keywords):
		out.rush_character_only = true
	if "Unblockable" in out.keywords or _text_has(effect_text, "cannot be blocked"):
		out.unblockable = true
		if not ("Unblockable" in out.keywords):
			out.keywords.append("Unblockable")
	# Official: "This Character/Leader can also attack active Characters."
	if (_text_has(effect_text, "this character can also attack") \
			or _text_has(effect_text, "this leader can also attack")) \
			and _text_has(effect_text, "active") \
			and not _text_has(effect_text, "cannot attack"):
		out.can_attack_active = true
		out["can_attack_active_don"] = _don_min_near(effect_text, "active")

	# 2) "can attack the turn it comes into play" (not reminder text on gains [Rush])
	if not _text_has(effect_text, "gains [Rush]") and not _text_has(effect_text, "gains [Rush: Character]"):
		if _text_has(effect_text, "can attack on the turn in which it is played") \
				or _text_has(effect_text, "can attack when it comes into play") \
				or _text_has(effect_text, "can attack Characters on the turn"):
			out.can_attack_turn_played = true
			if _text_has(effect_text, "can attack Characters on the turn"):
				out.rush_character_only = true
				if not ("Rush: Character" in out.keywords) and not ("Rush" in out.keywords):
					out.keywords.append("Rush: Character")

	# 3) Timing sections
	for entry in _section_entries(effect_text, "On Play"):
		out.on_play.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "Activate: Main"):
		var tok: Dictionary = _entry_tok(entry)
		tok["rest_cost"] = _text_has(String(entry.get("body", "")), "rest this")
		out.activate_main.append(tok)
	for entry in _section_entries(effect_text, "When Attacking"):
		var tok: Dictionary = _entry_tok(entry)
		var nbd := _no_block_don(effect_text)
		if nbd > 0:
			out.no_block_with_don = nbd
		var at := _attack_target_filter(String(entry.get("body", "")))
		if at != "":
			tok["attack_target"] = at
		out.on_attack.append(tok)
	for entry in _section_entries(effect_text, "When Attacking a Leader"):
		var tok: Dictionary = _entry_tok(entry)
		tok["attack_target"] = "leader"
		out.on_attack.append(tok)
	for entry in _section_entries(effect_text, "On K.O."):
		out.on_ko.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "On KO"):
		out.on_ko.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "When Destroyed"):
		out.on_ko.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "On Block"):
		out.on_block.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "On Your Opponent's Attack"):
		out.on_opp_attack.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "End of Your Turn"):
		out.on_end.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "End of Your Opponent's Turn"):
		out.on_opp_end.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "Main"):
		var tok: Dictionary = _entry_tok(entry)
		out.on_main.append(tok)
		var body := String(entry.get("body", ""))
		if _text_has(body, "cannot activate [Blocker]") or _text_has(body, "cannot activate a [Blocker]"):
			out["blocks_disabled"] = true
	for entry in _section_entries(effect_text, "Counter"):
		out.counter.append(_entry_tok(entry))
	for entry in _section_entries(effect_text, "Your Turn"):
		_absorb_turn_power(out, String(entry.get("body", "")), "own_turn")
		_absorb_turn_statics(out, String(entry.get("body", "")), "own_turn")
	for entry in _section_entries(effect_text, "Opponent's Turn"):
		_absorb_turn_power(out, String(entry.get("body", "")), "opp_turn")
		_absorb_turn_statics(out, String(entry.get("body", "")), "opp_turn")
		var obody := String(entry.get("body", ""))
		if _text_has(obody, "when this character is k.o"):
			var kidx := obody.to_lower().find("when this character is k.o")
			var after := obody.substr(kidx)
			var colon := after.find(":")
			var kbody := after.substr(colon + 1) if colon != -1 else after
			var ktok := _entry_tok({"body": kbody, "once_per_turn": entry.get("once_per_turn", false), "don_min": entry.get("don_min", 0)})
			ktok["cond_turn"] = "opp_turn"
			out.on_ko.append(ktok)
	for entry in _section_entries(effect_text, "On Your Opponent's Turn"):
		out.on_opp_turn.append(_entry_tok(entry))
		_absorb_turn_statics(out, String(entry.get("body", "")), "opp_turn")
	for entry in _section_entries(effect_text, "When Given DON!!"):
		out.on_give_don.append(_entry_tok(entry))
	# Bare "When this Character is given a DON!!" without a unique hat.
	if _text_has(effect_text, "when this character is given") and _text_has(effect_text, "don"):
		if out.on_give_don.is_empty():
			var gidx := effect_text.to_lower().find("when this character is given")
			var gafter := effect_text.substr(gidx)
			var gcol := gafter.find(":")
			var gbody := gafter.substr(gcol + 1) if gcol != -1 else gafter
			out.on_give_don.append(_entry_tok({"body": gbody, "once_per_turn": _text_has(gafter, "Once Per Turn")}))

	# 7) [DON!! xN] power / conditional abilities
	var don_poser := _parse_don_abilities(effect_text)
	out.don_power = don_poser.get("power", [])
	for tp in don_poser.get("turn_power", []):
		out.turn_power.append(tp)
	if don_poser.get("grants_rush_at_don", 0) > 0:
		out["grants_rush_at_don"] = don_poser.get("grants_rush_at_don", 0)

	# 8) Trigger card.trigger field
	if not trigger_text.is_empty():
		var trigger_actions := _parse_trigger(trigger_text, out)
		out.triggers.append({"trigger": trigger_text, "actions": trigger_actions})
		if _text_has(trigger_text, "Play this card"):
			out.play_self_on_trigger = true
		if _text_has(trigger_text, "this card's [Main] effect"):
			out["rerun_main_on_trigger"] = true
	elif _text_has(effect_text, "[Trigger]"):
		for entry in _section_entries(effect_text, "Trigger"):
			var tbody := String(entry.get("body", ""))
			var trigger_actions := _parse_trigger(tbody, out)
			out.triggers.append({"trigger": tbody, "actions": trigger_actions,
				"once_per_turn": entry.get("once_per_turn", false)})
	_absorb_static(out, _static_remainder(effect_text))

	# 9) Generic "during this turn / during your turn" static power lines not in a hat
	var gpow := _generic_turn_power(effect_text)
	for g in gpow:
		out.turn_power.append(g)

	# 10) Leader rule modifications. Cards that change base rules say
	# "Under the rules of this game, ..." / "... , according to the rules."
	# Examples: Nami OP03-040 (deck-out = you WIN), Enel OP15-058 (DON!! deck
	# consists of 6 cards).
	var leader_rules := _parse_leader_rules(effect_text)
	if not leader_rules.is_empty():
		out["rules"] = leader_rules
	out.replace_ko = _parse_replace_ko(effect_text)
	out.on_battle_ko = _parse_battle_ko(effect_text)
	if _text_has(effect_text, "activates [Blocker]") and _text_has(effect_text, "you win the game"):
		out.win_on_block_zero_life = true
	var ca := _parse_cannot_attack_static(effect_text)
	if not ca.is_empty():
		out.cannot_attack_fx.append(ca)
	if _text_has(effect_text, "at the start of your turn"):
		var sbody := _start_of_turn_body(effect_text)
		if not sbody.is_empty():
			out.on_start_turn.append(_entry_tok({"body": sbody, "once_per_turn": true}))
	if _text_has(effect_text, "when this card is trashed") or _text_has(effect_text, "when this character is trashed"):
		var tidx := effect_text.to_lower().find("trashed")
		var tafter := effect_text.substr(tidx)
		var tcol := tafter.find(":")
		var tbody := tafter.substr(tcol + 1) if tcol != -1 else tafter
		out.on_trash.append(_entry_tok({"body": tbody}))
	var hc := _parse_hand_cost(effect_text)
	if not hc.is_empty():
		out.hand_cost = hc
	var ha := _parse_hand_cost_aura(effect_text)
	if not ha.is_empty():
		out.hand_cost_aura = ha
	if _text_has(effect_text, "when you play a character"):
		out.on_you_play.append(_entry_tok({"body": _after_when(effect_text, "when you play a character"),
			"once_per_turn": _text_has(effect_text, "Once Per Turn")}))
	if _text_has(effect_text, "when your opponent plays a character"):
		out.on_opp_play.append(_entry_tok({"body": _after_when(effect_text, "when your opponent plays"),
			"once_per_turn": _text_has(effect_text, "Once Per Turn")}))
	if _text_has(effect_text, "when you take damage"):
		out.on_take_damage.append(_entry_tok({"body": _after_when(effect_text, "when you take damage"),
			"once_per_turn": true, "don_min": _don_min_near(effect_text, "when you take damage")}))
	_push_when(out, "on_don_return", effect_text, "don!! card on your field is returned")
	_push_when(out, "on_don_return", effect_text, "don!! cards on your field are returned")
	if _text_has(effect_text, "attack deals damage to your opponent's life"):
		_push_when(out, "on_life_damage", effect_text, "attack deals damage to your opponent's life")
	if _text_has(effect_text, "when your opponent activates a [blocker]") \
			or _text_has(effect_text, "when your opponent activates [blocker]"):
		_push_when(out, "on_opp_block", effect_text, "when your opponent activates")
	_push_when(out, "on_life_zero", effect_text, "when your number of life cards becomes 0")
	if _text_has(effect_text, "when a card is removed from") and _text_has(effect_text, "life"):
		_push_when(out, "on_life_removed", effect_text, "when a card is removed from")
	_push_when(out, "on_opp_char_ko", effect_text, "when your opponent's character is k.o")
	_push_when(out, "on_opp_event", effect_text, "when your opponent activates an event")
	_push_when(out, "on_you_event", effect_text, "when you activate an event")
	_push_when(out, "on_self_rest", effect_text, "when this character becomes rested")
	if _text_has(effect_text, "removed from the field") \
			and not _text_has(effect_text, "would be") \
			and not _text_has(effect_text, "cannot be removed"):
		_push_when(out, "on_char_leave", effect_text, "removed from the field")
	_push_when(out, "on_hand_trash", effect_text, "when a card is trashed from your hand")
	_push_when(out, "on_play_from_trash", effect_text, "played from your trash")
	if _text_has(effect_text, "when this leader or") and _text_has(effect_text, "is given"):
		if out.on_give_don.is_empty():
			out.on_give_don.append(_entry_tok({"body": _after_when(effect_text, "is given"),
				"once_per_turn": _text_has(effect_text, "Once Per Turn"), "give_scope": "any_own"}))
		else:
			out.on_give_don[0]["give_scope"] = "any_own"
	if _text_has(effect_text, "cannot be removed from the field"):
		if _text_has(effect_text, "all of your opponent"):
			out.lock_opp_chars = true
		else:
			out.no_remove_fx.append({"from": "opp_effects", "dur": "always"})
	if _text_has(effect_text, "when this leader attacks") and not _text_has(effect_text, "[When Attacking]"):
		var latk_body := _cut_next_window(_after_when(effect_text, "when this leader attacks"))
		var latk := _entry_tok({"body": latk_body,
			"once_per_turn": _text_has(latk_body, "Once Per Turn")})
		if _text_has(effect_text, "opponent's leader"):
			latk["attack_target"] = "leader"
		out.on_attack.append(latk)

	_sanitize(out)
	return out


# --- Helpers ---
static func _has_bracket(text: String, kw: String) -> bool:
	return text.contains("[" + kw + "]") or text.contains("【" + kw + "】")

static func _text_has(text: String, sub: String) -> bool:
	return text.to_lower().contains(sub.to_lower())

static func _sanitize(_out: Dictionary) -> void:
	# No-op safety hook; engine ignores unknown action tokens.
	pass


# [On Play]/[When Attacking] BODY  ->  [On Play] BODY [When Attacking] BODY
static func _expand_slash_timings(text: String) -> String:
	if not text.contains("/["):
		return text
	var out := ""
	var idx := 0
	while idx < text.length():
		if text[idx] != "[":
			out += text[idx]
			idx += 1
			continue
		var hats: Array = []
		var cursor := idx
		while cursor < text.length() and text[cursor] == "[":
			var close := text.find("]", cursor + 1)
			if close == -1:
				out += text.substr(idx)
				return out
			hats.append(text.substr(cursor + 1, close - cursor - 1).strip_edges())
			cursor = close + 1
			if cursor < text.length() and text[cursor] == "/":
				cursor += 1
			else:
				break
		var all_timing := hats.size() >= 2
		for h in hats:
			if not _is_timing_hat(String(h)):
				all_timing = false
				break
		if not all_timing:
			out += text.substr(idx, cursor - idx)
			idx = cursor
			continue
		var end := text.length()
		var scan := cursor
		while true:
			var br := text.find("[", scan)
			if br == -1:
				break
			var hat2 := _hat_at(text, br)
			if _is_timing_hat(hat2):
				end = br
				break
			var close2 := text.find("]", br + 1)
			scan = (close2 + 1) if close2 != -1 else br + 1
		var body := text.substr(cursor, end - cursor)
		for i in range(hats.size()):
			if i > 0:
				out += " "
			out += "[" + String(hats[i]) + "]" + body
		idx = end
	return out

# --- Leader base-rule modifications ---
static func _parse_leader_rules(effect_text: String) -> Dictionary:
	var rules := {}
	var low := effect_text.to_lower()
	# DON!! deck size. Default construction is exactly 10; Enel OP15-058 is 6.
	if low.contains("don!! deck consists of") or low.contains("don deck consists of"):
		var n := _rule_number_after(effect_text, "consist")
		if n > 0 and n <= MAX_DON_RULE:
			rules["don_deck_size"] = n
	# Blue Nami OP03-040 / P-117: deck to 0 is a win, not a loss.
	if low.contains("you win the game instead of losing"):
		rules["deckout_is_win"] = true
	# Green/Black Brook OP15-022: do not lose on 0 cards; lose at end of that turn.
	if low.contains("do not lose when your deck has 0") \
			or low.contains("lose at the end of the turn in which your deck becomes 0"):
		rules["deckout_end_of_turn"] = true
	# ST13 Bege: face-up Life goes to the bottom of the deck, no hand, no Trigger.
	if low.contains("face-up life") and low.contains("instead of being added to your hand"):
		rules["faceup_life_to_deck"] = true
	# OP01/OP08/OP16 millennials etc.: ignore the 4-copy cap for this card.
	if low.contains("any number of this card"):
		rules["any_number"] = true
	# OP12 Rayleigh: no cost 5+ in the 50.
	if low.contains("cannot include cards with a cost of"):
		for n in _match_int(effect_text, r"(?i)cost of (\d+) or more"):
			rules["deck_max_cost"] = n - 1
			break
	# OP13 Imu: no Events with cost 2+.
	if low.contains("cannot include events with a cost of"):
		for n in _match_int(effect_text, r"(?i)cost of (\d+) or more"):
			rules["event_max_cost"] = n - 1
			break
	# P-117 Nami: only {East Blue} type cards in the deck.
	if low.contains("you can only include"):
		var t := _first_brace_type(effect_text)
		if t != "":
			rules["deck_only_trait"] = t
	# EB01 Oden: {Land of Wano} Characters with printed Counter 0 get +1000 Counter.
	if low.contains("without a counter") and low.contains("counter"):
		var t := _first_brace_type(effect_text)
		if t != "":
			rules["bonus_counter_trait"] = t
			rules["bonus_counter"] = 1000
	# OP13 Imu: at the start of the game, play a {Mary Geoise} Stage from the deck.
	if low.contains("at the start of the game") and low.contains("stage"):
		var t := _first_brace_type(effect_text)
		if t != "":
			rules["start_play_stage_trait"] = t
	# "Also treat this card's name as [X]"
	var nre := RegEx.new()
	nre.compile(r"(?i)(?:also )?treat this card's name as\s*((?:\[[^\]]+\]\s*(?:and\s*)?)+)")
	for m in nre.search_all(effect_text):
		var names: Array = []
		var ire := RegEx.new()
		ire.compile(r"\[([^\]]+)\]")
		for im in ire.search_all(m.get_string(1)):
			names.append(String(im.get_string(1)).strip_edges())
		if not names.is_empty():
			rules["treat_as_names"] = names
	return rules

static func _first_brace_type(text: String) -> String:
	var re := RegEx.new()
	re.compile(r"\{([^}]+)\}")
	var m := re.search(text)
	if m == null:
		return ""
	return String(m.get_string(1)).strip_edges()

const MAX_DON_RULE := 10

static func _rule_number_after(text: String, hint: String) -> int:
	var ci := text.to_lower().find(hint.to_lower())
	if ci == -1:
		return 0
	var tail := text.substr(ci)
	for j in range(tail.length()):
		var ch: String = tail[j]
		if ch.is_valid_int():
			var k := j
			while k < tail.length() and tail[k].is_valid_int():
				k += 1
			return int(tail.substr(j, k - j))
	return 0

# Timing hats start a new effect. Modifier hats stack on the current timing
# (official: [Activate: Main] [Once Per Turn] Give... / [DON!! x2] [When Attacking]...).
const _TIMING_HATS := [
	"On Play", "Activate: Main", "When Attacking", "When Attacking a Leader", "On K.O.", "On KO",
	"End of Your Turn", "End of Your Opponent's Turn", "Main", "Counter", "Trigger",
	"On Block", "When Destroyed", "On Your Opponent's Attack", "Your Turn", "Opponent's Turn",
	"On Your Opponent's Turn", "When Given DON!!",
]
const _MODIFIER_HATS := [
	"Once Per Turn", "Once Per Game", "On Your Opponent's Turn",
]

static func _hat_at(text: String, idx: int) -> String:
	if idx < 0 or idx >= text.length() or text[idx] != "[":
		return ""
	var end := text.find("]", idx + 1)
	if end == -1:
		return ""
	return text.substr(idx + 1, end - idx - 1).strip_edges()

static func _is_modifier_hat(hat: String) -> bool:
	if hat.is_empty():
		return false
	if hat in _MODIFIER_HATS:
		return true
	var u := hat.to_upper()
	return u.begins_with("DON!!") or u.begins_with("DON‼")

static func _hat_is_reference(text: String, br: int) -> bool:
	var start := maxi(0, br - 18)
	var before := text.substr(start, br - start).to_lower()
	return before.ends_with("with a ") or before.ends_with("gains ") \
		or before.ends_with("activate ") or before.ends_with("activates ") \
		or before.ends_with("activate a ") or before.ends_with("card's ") \
		or before.ends_with("including ") or before.ends_with("or ") \
		or before.ends_with("other than ") or before.ends_with("and a ") \
		or before.ends_with("without ") or before.ends_with("without a ") \
		or before.ends_with("without an ") or before.ends_with("the ")


static func _normalize_brackets(text: String) -> String:
	return text.replace("【", "[").replace("】", "]")


static func _static_remainder(text: String) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		if text[i] == "[":
			var hat := _hat_at(text, i)
			if _is_timing_hat(hat) and not _hat_is_reference(text, i):
				var close := text.find("]", i)
				if close == -1:
					break
				i = close + 1
				var end := text.length()
				var scan := i
				while true:
					var br := text.find("[", scan)
					if br == -1:
						break
					var hat2 := _hat_at(text, br)
					if _is_timing_hat(hat2) and not _hat_is_reference(text, br):
						end = br
						break
					var close2 := text.find("]", br + 1)
					scan = (close2 + 1) if close2 != -1 else br + 1
				i = end
				continue
		out += text[i]
		i += 1
	return out.strip_edges()


static func _absorb_static(out: Dictionary, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	out["static_actions"] = _parse_action_clause(text, false)


static func _is_timing_hat(hat: String) -> bool:
	return hat in _TIMING_HATS

static func _skip_ws(text: String, idx: int) -> int:
	while idx < text.length():
		var ch := text[idx]
		if ch != " " and ch != "\n" and ch != "\t":
			break
		idx += 1
	return idx

static func _has_static_keyword(text: String, kw: String) -> bool:
	var marker := "[" + kw + "]"
	var idx := 0
	while true:
		idx = text.find(marker, idx)
		if idx == -1:
			return false
		var start := maxi(0, idx - 6)
		var before := text.substr(start, idx - start).to_lower()
		if before.ends_with("gains "):
			idx += marker.length()
			continue
		return true
	return false

static func _entry_tok(entry: Dictionary) -> Dictionary:
	return {
		"actions": _parse_actions(String(entry.get("body", ""))),
		"once_per_turn": bool(entry.get("once_per_turn", false)),
		"once_per_game": bool(entry.get("once_per_game", false)),
		"don_min": int(entry.get("don_min", 0)),
		"cond_turn": String(entry.get("cond_turn", "")),
		"give_scope": String(entry.get("give_scope", "")),
		"body": String(entry.get("body", "")),
	}

static func _absorb_turn_power(out: Dictionary, body: String, dur: String) -> void:
	if body.is_empty():
		return
	var amount := 0
	for a in _match_int(body, r"(?i)(\+?\d+)\s*power"):
		amount = a
		break
	if amount != 0:
		out.turn_power.append({"amount": amount, "dur": dur, "condition_don": 0, "who": "self"})

static func _absorb_turn_statics(out: Dictionary, body: String, dur: String) -> void:
	if body.is_empty():
		return
	# "This effect can be activated when ..." is a window, not a standing turn action.
	if _text_has(body, "can be activated when") or _text_has(body, "when your opponent activates"):
		return
	if _text_has(body, "cannot be k.o"):
		var frm := "effects" if _text_has(body, "by effect") else "all"
		out.protect_fx.append({"dur": dur, "from": frm})
	if _text_has(body, "cannot attack any card other than"):
		var nm := ""
		var nre := RegEx.new()
		nre.compile(r"\[([^\]]+)\]")
		var m := nre.search(body)
		if m:
			nm = String(m.get_string(1)).strip_edges()
		out.must_attack_fx.append({"dur": dur, "name": nm, "if_rested": _text_has(body, "rested")})
	if _text_has(body, "when this character is k.o") or _text_has(body, "when this character is k.o"):
		return
	var acts := _parse_action_body(body, false)
	var kept: Array = []
	for a in acts:
		if a is Array and String(a[0]) != TOK_POWER and String(a[0]) != TOK_PROTECT:
			kept.append(a)
	if not kept.is_empty():
		out.turn_actions.append({"dur": dur, "actions": kept})

static func _section_entries(text: String, title: String) -> Array:
	var entries: Array = []
	var marker := "[" + title + "]"
	var idx := 0
	while true:
		idx = text.find(marker, idx)
		if idx == -1:
			break
		if _hat_is_reference(text, idx):
			idx += marker.length()
			continue
		idx = _skip_ws(text, idx + marker.length())
		var once := false
		var once_game := false
		var cond_turn := ""
		var don_min := 0
		while true:
			var hat := _hat_at(text, idx)
			if hat.is_empty() or not _is_modifier_hat(hat):
				break
			if hat == "Once Per Turn":
				once = true
			if hat == "Once Per Game":
				once_game = true
			if hat == "On Your Opponent's Turn":
				cond_turn = "opp_turn"
			var u := hat.to_upper()
			if u.begins_with("DON!!") or u.begins_with("DON‼"):
				for n in _match_int(hat, r"(\d+)"):
					don_min = n
					break
			var close := text.find("]", idx + 1)
			if close == -1:
				break
			idx = _skip_ws(text, close + 1)
		var end := text.length()
		var scan := idx
		while true:
			var br := text.find("[", scan)
			if br == -1:
				break
			var hat2 := _hat_at(text, br)
			if _is_timing_hat(hat2) and hat2 != title and not _hat_is_reference(text, br):
				end = br
				break
			var close2 := text.find("]", br + 1)
			scan = (close2 + 1) if close2 != -1 else br + 1
		var body := text.substr(idx, end - idx).strip_edges()
		if not body.is_empty():
			entries.append({"body": body, "once_per_turn": once, "once_per_game": once_game,
				"don_min": don_min, "cond_turn": cond_turn})
		idx = end
	return entries

static func _section_bodies(text: String, title: String) -> Array:
	var bodies: Array = []
	for e in _section_entries(text, title):
		bodies.append(e.get("body", ""))
	return bodies

static func _trigger_name(text: String) -> String:
	return text

static func _no_block_don(text: String) -> int:
	# "[DON!! xN] [When Attacking] ... cannot activate [Blocker]" -> N
	if not _text_has(text, "cannot activate [Blocker]") and not _text_has(text, "cannot activate a [Blocker]"):
		return 0
	var re := RegEx.new()
	re.compile(r"\[DON!!\s*x(\d+)\]\s*\[When Attacking\]")
	for m in re.search_all(text):
		return int(m.get_string(1))
	return 2  # default assume [DON!! x2] hats

static func _parse_actions(text: String) -> Array:
	var split := _split_cost_effect(text)
	if bool(split.get("has_cost", false)):
		var cost_acts := _parse_action_body(String(split.get("cost", "")), true)
		var effect_acts := _parse_action_body(String(split.get("effect", "")), false)
		var out: Array = []
		out.append([TOK_PAY, {"optional": bool(split.get("optional", false)), "actions": cost_acts}])
		out.append_array(effect_acts)
		return out
	return _parse_action_body(text, false)


static func _split_cost_effect(text: String) -> Dictionary:
	var colon := text.find(":")
	if colon <= 0:
		return {"has_cost": false}
	var before := text.substr(0, colon).strip_edges()
	var after := text.substr(colon + 1).strip_edges()
	var blow := before.to_lower()
	if blow.begins_with("if "):
		return {"has_cost": false}
	var optional := _text_has(blow, "you may")
	var is_cost := optional \
		or _text_has(before, "DON!! −") or _text_has(before, "DON!! -") \
		or _text_has(blow, "rest this") \
		or _text_has(blow, "trash this") \
		or _text_has(blow, "reveal") \
		or before.contains("①") or before.contains("②") or before.contains("③") \
		or before.contains("➀")
	if not is_cost:
		return {"has_cost": false}
	return {"has_cost": true, "optional": optional, "cost": before, "effect": after}


static func _split_then(text: String) -> Array:
	var re := RegEx.new()
	re.compile(r"(?i)(?=\. Then,?)|(?=; Then,?)|(?=\. If you do)")
	var starts: Array = [0]
	for m in re.search_all(text):
		var s := m.get_start()
		if s > 0:
			starts.append(s)
	starts.append(text.length())
	var out: Array = []
	var stripper := RegEx.new()
	stripper.compile(r"(?i)^(?:\. Then,?|; Then,?)\s*")
	for i in range(starts.size() - 1):
		var chunk := text.substr(int(starts[i]), int(starts[i + 1]) - int(starts[i])).strip_edges()
		var sm := stripper.search(chunk)
		if sm:
			chunk = chunk.substr(sm.get_end()).strip_edges()
		if chunk.begins_with("."):
			chunk = chunk.substr(1).strip_edges()
		if not chunk.is_empty():
			out.append(chunk)
	return out if not out.is_empty() else [text]


static func _clause_cond(text: String) -> Dictionary:
	var cond := {}
	var lower := text.to_lower()
	for m in _match_int(text, r"(?i)if you have (\d+) or less life"):
		cond["life_lte"] = m
		cond["player"] = "self"
		break
	for m in _match_int(text, r"(?i)if you have (\d+) or less cards in your hand"):
		cond["hand_lte"] = m
		break
	for m in _match_int(text, r"(?i)if you have (\d+) or more don"):
		cond["don_gte"] = m
		break
	if _text_has(lower, "if the revealed card has a cost of"):
		for m in _match_int(text, r"(?i)cost of (\d+) or more"):
			cond["revealed_cost_gte"] = m
			break
		if not cond.has("revealed_cost_gte"):
			for m in _match_int(text, r"(?i)cost of (\d+)"):
				cond["revealed_cost_gte"] = m
				break
	if _text_has(lower, "if you do"):
		cond["if_you_do"] = true
	if _text_has(lower, "if you don't have [") or _text_has(lower, "if you do not have ["):
		var nre := RegEx.new()
		nre.compile(r"(?i)if you do(?:n't| not) have \[([^\]]+)\]")
		var m := nre.search(text)
		if m:
			cond["missing_name"] = String(m.get_string(1)).strip_edges()
	for m2 in _match_int(text, r"(?i)if your opponent has (\d+) or more character"):
		cond["opp_chars_gte"] = m2
		break
	if _text_has(lower, "if your leader has the {") or _text_has(lower, "if your leader's type includes"):
		var t := _first_brace_type(text)
		if t != "":
			cond["leader_trait"] = t
	for m in _match_int(text, r"(?i)if you have (\d+) or less don"):
		cond["don_lte"] = m
		break
	if _text_has(lower, "if you have 0 don"):
		cond["don_lte"] = 0
	if _text_has(lower, "equal to or less than the number on your opponent") \
			or _text_has(lower, "equal to or less than the number of don"):
		cond["don_lte_opp"] = true
	for m in _match_int(text, r"(?i)at least (\d+) less than"):
		if _text_has(lower, "don"):
			cond["don_deficit"] = m
		elif _text_has(lower, "hand"):
			cond["hand_deficit"] = m
		break
	for m in _match_int(text, r"(?i)if your opponent has (\d+) or more cards in their hand"):
		cond["opp_hand_gte"] = m
		break
	for m in _match_int(text, r"(?i)if your opponent has (\d+) or more life"):
		cond["opp_life_gte"] = m
		break
	if _text_has(lower, "either you or your opponent has"):
		for m in _match_int(text, r"(?i)has (\d+) life"):
			cond["either_life_lte"] = m
			break
	var cre := RegEx.new()
	cre.compile(r"(?i)if you have (\d+) or more characters with a (?:base )?cost of (\d+)")
	var cm := cre.search(text)
	if cm:
		cond["own_chars_cost_n"] = int(cm.get_string(1))
		cond["own_chars_cost_min"] = int(cm.get_string(2))
	for m in _match_int(text, r"(?i)if you have (\d+) or more cards in your trash"):
		cond["trash_gte"] = m
		break
	for m in _match_int(text, r"(?i)if you have (\d+) or more events in your trash"):
		cond["events_trash_gte"] = m
		break
	for m in _match_int(text, r"(?i)if your leader has (\d+) power or less"):
		cond["leader_power_lte"] = m
		break
	for m in _match_int(text, r"(?i)if your opponent has a character with (\d+)"):
		cond["opp_char_power_gte"] = m
		break
	for m in _match_int(text, r"(?i)if you have a character with (\d+)"):
		cond["self_char_power_gte"] = m
		break
	for m in _match_int(text, r"(?i)your opponent has (\d+) or more rested"):
		cond["opp_rested_gte"] = m
		break
	if _text_has(lower, "card name includes"):
		var ire := RegEx.new()
		ire.compile(r'(?i)includes\s*"([^"]+)"')
		var im := ire.search(text)
		if im:
			cond["leader_name_includes"] = String(im.get_string(1)).strip_edges()
	if _text_has(lower, "a card in your hand is trashed"):
		cond["hand_trashed_this_turn"] = true
	for m in _match_int(text, r"(?i)plays a character with a base cost of (\d+) or more"):
		cond["played_cost_gte"] = m
		break
	if _text_has(lower, "if you have [") and not _text_has(lower, "if you have 0") \
			and not _text_has(lower, "if you don't have [") and not _text_has(lower, "if you do not have ["):
		var hre := RegEx.new()
		hre.compile(r"(?i)if you have \[([^\]]+)\]")
		var hm := hre.search(text)
		if hm:
			cond["has_name"] = String(hm.get_string(1)).strip_edges()
	if _text_has(lower, "if your leader is ["):
		var lre := RegEx.new()
		lre.compile(r"(?i)if your leader is \[([^\]]+)\]")
		var lm := lre.search(text)
		if lm:
			cond["leader_name"] = String(lm.get_string(1)).strip_edges()
	if _text_has(lower, "if your leader is multicolored"):
		cond["leader_multicolor"] = true
	for m in _match_int(text, r"(?i)if you have (\d+) or less active don"):
		cond["active_don_lte"] = m
		break
	for m in _match_int(text, r"(?i)if you have (\d+) or more rested characters"):
		cond["rested_chars_gte"] = m
		break
	for m in _match_int(text, r"(?i)if you have (\d+) or more rested don"):
		cond["rested_don_gte"] = m
		break
	if _text_has(lower, "if you have no other character"):
		cond["no_other_chars"] = true
	if _text_has(lower, "if you have a face-up life"):
		cond["faceup_life"] = true
	if _text_has(lower, "if you have less characters than your opponent"):
		cond["less_chars_than_opp"] = true
	for m in _match_int(text, r"(?i)when (\d+) or more don"):
		cond["don_returned_gte"] = m
		break
	if _text_has(lower, "if you have 0 life") or _text_has(lower, "if you have less life cards than your opponent"):
		if _text_has(lower, "less life"):
			cond["life_lt_opp"] = true
		else:
			cond["life_lte"] = 0
			cond["player"] = "self"
	for m in _match_int(text, r"(?i)total of (\d+) or less life"):
		cond["life_sum_lte"] = m
		break
	for m in _match_int(text, r"(?i)this (?:character|leader) has (\d+) power or more"):
		cond["self_power_gte"] = m
		break
	if _text_has(lower, "played on this turn") or _text_has(lower, "was played this turn"):
		cond["played_this_turn"] = true
	for m in _match_int(text, r"(?i)if there is a character with a cost of (\d+)"):
		if not _text_has(lower, "or more") and not _text_has(lower, "or less"):
			cond["any_cost_eq"] = m
		break
	for m in _match_int(text, r"(?i)(?:there is|you have) a character with a cost of (\d+) or more"):
		cond["any_cost_gte"] = m
		break
	return cond


static func _stamp_cond(actions: Array, cond: Dictionary) -> Array:
	if cond.is_empty():
		return actions
	for a in actions:
		if not (a is Array) or a.size() < 2:
			continue
		if a[1] is int:
			a[1] = {"n": a[1], "cond": cond}
			continue
		if a[1] is Dictionary:
			var d: Dictionary = a[1]
			if not d.has("cond"):
				d["cond"] = cond
			else:
				var c: Dictionary = d["cond"]
				for k in cond:
					c[k] = cond[k]
	return actions


static func _parse_action_body(text: String, as_cost: bool) -> Array:
	if not as_cost:
		var parts := _split_then(text)
		if parts.size() > 1:
			var all: Array = []
			for p in parts:
				var pl := String(p).to_lower()
				if pl.contains("place the rest") and pl.contains("deck"):
					for a in all:
						if a is Array and String(a[0]) == TOK_LOOK_DECK and a.size() > 1 and a[1] is Dictionary:
							a[1]["rest"] = "bottom" if pl.contains("bottom") else "top"
							a[1]["shuffle"] = pl.contains("shuffle") and not pl.contains("any order")
							a[1]["reorder"] = pl.contains("any order")
					continue
				all.append_array(_parse_action_clause(String(p), false))
			return all
	return _parse_action_clause(text, as_cost)


static func _parse_action_clause(text: String, as_cost: bool) -> Array:
	var actions: Array = []
	if text.strip_edges().is_empty():
		return actions
	var lower := text.to_lower()
	var cond := _clause_cond(text)

	if not as_cost and _text_has(lower, "your opponent chooses one"):
		actions.append([TOK_OPP_CHOOSE, {"kind": "modal", "options": _parse_modal_options(text)}])
		return _stamp_cond(actions, cond)
	if not as_cost and _text_has(lower, "swap the base power"):
		var sf := _card_filter(text, "self")
		sf["zone"] = "field"
		sf["number"] = 2
		sf["up_to"] = false
		if _text_has(lower, "your opponent"):
			sf["player"] = "opp"
		if _text_has(lower, "your leader"):
			sf["include_leader"] = true
		sf["dur"] = _power_dur(text)
		actions.append([TOK_SWAP_POWER, sf])
	if not as_cost and (_text_has(lower, "negate the effect") or _text_has(lower, "negate the effects") \
			or _text_has(lower, "effect is negated") or _text_has(lower, "effects are negated")):
		var nf := _card_filter(text, "opp")
		nf["zone"] = "field"
		nf["dur"] = _power_dur(text)
		if _text_has(lower, "all of") or _text_has(lower, "and all of"):
			nf["number"] = 0
		if _text_has(lower, "leader"):
			nf["include_leader"] = true
		actions.append([TOK_NEGATE, nf])
	if not as_cost and _text_has(lower, "cannot attack") \
			and (_text_has(lower, "until") or _text_has(lower, "during this turn")) \
			and not _text_has(lower, "cannot attack unless") and not _text_has(lower, "cannot attack any card other") \
			and not _text_has(lower, "this character cannot attack") and not _text_has(lower, "this leader cannot attack"):
		var af := _card_filter(text, "opp")
		af["zone"] = "field"
		af["dur"] = _power_dur(text)
		if _text_has(lower, "leader") and not _text_has(lower, "character"):
			af["leaders_only"] = true
			af["include_leader"] = true
		actions.append([TOK_NO_ATTACK, af])
	if not as_cost and (_text_has(lower, "from your trash") or _text_has(lower, "from the trash")) \
			and _text_has(lower, "hand") and (_text_has(lower, "add") or _text_has(lower, "return")) \
			and not _text_has(lower, "play"):
		var tf := _card_filter(text, "self")
		tf["zone"] = "trash"
		tf["player"] = "self"
		if not _text_has(lower, "character") and not _text_has(lower, "event") and not _text_has(lower, "stage"):
			tf["card_type"] = ""
		if _text_has(lower, "[trigger]"):
			tf["has_trigger"] = true
		actions.append([TOK_TRASH_TO_HAND, tf])
	if not as_cost and _text_has(lower, "your opponent chooses") and not _text_has(lower, "chooses one"):
		var oc := {"kind": "trash_hand", "whose": "controller"}
		if _text_has(lower, "their hand") or _text_has(lower, "from their"):
			oc["whose"] = "opponent"
		if _text_has(lower, "character"):
			oc["kind"] = "bounce"
			oc["filter"] = _card_filter(text, "opp")
			oc["whose"] = "opponent"
		actions.append([TOK_OPP_CHOOSE, oc])
		return _stamp_cond(actions, cond)
	if not as_cost and _text_has(lower, "your opponent may"):
		var bits := _split_if_they_do_not(text)
		var do_acts := _parse_action_clause(String(bits[0]), false)
		if _text_has(String(bits[0]), "their"):
			_force_player(do_acts, "opp")
		actions.append([TOK_OPP_MAY, {"do": do_acts, "else": _parse_action_clause(String(bits[1]), false)}])
		return _stamp_cond(actions, cond)
	if not as_cost and _text_has(lower, "choose one") and not _text_has(lower, "your opponent chooses"):
		actions.append([TOK_CHOOSE, {"kind": "modal", "options": _parse_modal_options(text)}])
		return _stamp_cond(actions, cond)

	if _text_has(lower, "place this card") and _text_has(lower, "from your hand") and (_text_has(lower, "bottom") or _text_has(lower, "top")):
		var edge := "bottom" if _text_has(lower, "bottom") else "top"
		actions.append([TOK_TO_DECK, {"target": "self", "edge": edge}])
		actions.append([TOK_HAND_TO_DECK, {"n": 1, "edge": edge, "player": "self"}])

	if _text_has(lower, "trash this character") or _text_has(lower, "trash this card"):
		actions.append([TOK_TRASH_SELF, {}])

	if _text_has(lower, "reveal") and _text_has(lower, "from your hand"):
		var rn := 1
		for m in _match_int(text, r"(?i)reveal (\d+)"):
			rn = m
			break
		var rf := _card_filter(text, "self")
		rf["zone"] = "hand"
		rf["number"] = rn
		if _text_has(lower, "event") and _text_has(lower, "stage"):
			rf["card_type"] = "EventOrStage"
		elif _text_has(lower, "event"):
			rf["card_type"] = "Event"
		actions.append([TOK_REVEAL_HAND, rf])

	# Draw N card(s)
	if not as_cost and _text_has(lower, "draw"):
		if _text_has(lower, "draw until you have") or _text_has(lower, "draw cards until you have"):
			var until_n := 0
			for m in _match_int(text, r"(?i)until you have (\d+)"):
				until_n = m
				break
			actions.append([TOK_DRAW, {"until": until_n}])
		elif _text_has(lower, "draw 2") or _text_has(lower, "draw2") or _text_has(lower, "draw two"):
			actions.append([TOK_DRAW, 2])
		elif _text_has(lower, "draw 3") or _text_has(lower, "draw three"):
			actions.append([TOK_DRAW, 3])
		else:
			actions.append([TOK_DRAW, 1])

	# DON!! −N : return that many DON!! to the DON!! deck.
	if _text_has(lower, "return") and _text_has(lower, "don") and _text_has(lower, "until you have"):
		actions.append([TOK_DON_MINUS, {"until_opp": true, "player": "self"}])
	elif _text_has(lower, "return") and _text_has(lower, "don") and _text_has(lower, "deck") \
			and not _text_has(lower, "don!! −"):
		var rn := 1
		for m in _match_int(text, r"(?i)returns? (\d+)\s*don"):
			rn = m
			break
		var rp := "opp" if _text_has(lower, "opponent") or _text_has(lower, "their don") else "self"
		actions.append([TOK_DON_MINUS, {"n": rn, "player": rp}])
	elif _text_has(text, "DON!! −") or _text_has(text, "DON!! -") or _text_has(lower, "don!! −") or _text_has(lower, "don!! -"):
		var n := 1
		for m in _match_int(text, r"(?i)DON!!\s*[−\-]\s*(\d+)"):
			n = m
			break
		actions.append([TOK_DON_MINUS, {"n": n, "player": "self"}])

	# Circled activation cost: rest N Active DON!! in the cost area.
	if text.contains("①") or text.contains("➀"):
		actions.append([TOK_REST_DON, {"player": "self", "n": 1}])
	elif text.contains("②"):
		actions.append([TOK_REST_DON, {"player": "self", "n": 2}])
	elif text.contains("③"):
		actions.append([TOK_REST_DON, {"player": "self", "n": 3}])

	if as_cost and _text_has(lower, "rest this"):
		actions.append([TOK_REST_SELF, {}])
	elif as_cost and _text_has(lower, "rest") and _text_has(lower, "your cards") and not _text_has(lower, "don"):
		var rc := _card_filter(text, "self")
		rc["player"] = "self"
		rc["include_leader"] = true
		rc["zone"] = "field"
		for m in _match_int(text, r"(?i)rest (\d+)"):
			rc["number"] = m
			break
		actions.append([TOK_REST_CHAR, rc])

	# Add DON!! from the DON!! deck to the cost area (active).
	if not as_cost and (_text_has(lower, "don deck to your active area") or _text_has(lower, "don!! deck to your active area") \
			or (_text_has(lower, "add") and _text_has(lower, "don") and _text_has(lower, "don!! deck"))):
		var amount := 1
		for m in _match_int(text, r"(?i)(\d+)\s*don"):
			amount = m
			break
		var rested_add := _text_has(lower, "rest it") or _text_has(lower, "rest them") or _text_has(lower, "and rest")
		actions.append([TOK_ADD_DON, {"n": amount, "rested": rested_add}])

	# Set as active: DON!! vs Character/Leader.
	if not as_cost and _text_has(lower, "as active"):
		if _text_has(lower, "don"):
			var n := 1
			for m in _match_int(text, r"(?i)up to (\d+)"):
				n = m
				break
			actions.append([TOK_SET_DON_ACTIVE, {"n": n, "player": "self"}])
		else:
			var who := "self"
			if _text_has(lower, "up to") or _text_has(lower, "1 of your"):
				who = "self_char"
			actions.append([TOK_SET_ACTIVE, {"who": who}])
	if not as_cost and (_text_has(lower, "will not become active") or _text_has(lower, "does not become active")):
		if _text_has(lower, "opponent"):
			var sk := _card_filter(text, "opp")
			sk["player"] = "opp"
			sk["zone"] = "field"
			sk["include_leader"] = _text_has(lower, "leader") or _text_has(lower, "cards")
			if _text_has(lower, "rested"):
				sk["rested_only"] = true
			actions.append([TOK_SKIP_REFRESH, sk])
		else:
			actions.append([TOK_SKIP_REFRESH, {"this_card": true}])

	# Play a card from hand / trash / deck (effect-play, no extra cost).
	if not as_cost and (_text_has(lower, "play up to") or _text_has(lower, "play 1 ") \
			or _text_has(lower, "play a ") or _text_has(lower, "play one ") \
			or _text_has(lower, "play this character card from your trash") \
			or _text_has(lower, "play this card from your trash") \
			or (_text_has(lower, "play 1 card and play the other")) \
			or (_text_has(lower, "activate") and _text_has(lower, "event") and _text_has(lower, "from your hand")) \
			or (_text_has(lower, "activate") and _text_has(lower, "event") and (_text_has(lower, "in your trash") or _text_has(lower, "from your trash")))):
		if _text_has(lower, "play this card") and not _text_has(lower, "from your trash") \
				and not _text_has(lower, "without paying"):
			pass
		elif _text_has(lower, "look at") and not _text_has(lower, "from your trash"):
			pass
		else:
			var filt := _card_filter(text, "self")
			filt["zone"] = "hand"
			if _text_has(lower, "from your trash") or _text_has(lower, "from the trash") or _text_has(lower, "in your trash"):
				filt["zone"] = "trash"
			elif _text_has(lower, "from your deck") or _text_has(lower, "from the top of your deck"):
				filt["zone"] = "deck"
			if _text_has(lower, "character"):
				filt["card_type"] = "Character"
			elif _text_has(lower, "event"):
				filt["card_type"] = "Event"
			elif _text_has(lower, "stage"):
				filt["card_type"] = "Stage"
			if _text_has(lower, "this character") or _text_has(lower, "this card from your trash"):
				filt["this_card"] = true
			if _text_has(lower, "play 1 card and play the other"):
				filt["number"] = 2
				filt["second_rested"] = true
				filt["zone"] = "trash"
			if _text_has(lower, "rested"):
				filt["play_rested"] = true
			actions.append([TOK_PLAY, filt])

	# Bounce to owner's hand.
	var _returning_card := _text_has(lower, "character") or _text_has(lower, "this card") \
			or _text_has(lower, "leader") or _text_has(lower, "owner's hand") \
			or (_text_has(lower, "add") and _text_has(lower, "this character"))
	if not as_cost and _text_has(lower, "hand") \
			and (_text_has(lower, "return") or _text_has(lower, "place") or (_text_has(lower, "add") and _text_has(lower, "this character"))) \
			and not _text_has(lower, "from your hand") and not _text_has(lower, "to your life") \
			and not _text_has(lower, "look at") \
			and not _text_has(lower, "add it to your hand") and not _text_has(lower, "from your trash") \
			and (_returning_card or not _text_has(lower, "don!!")):
		if _returning_card or _text_has(lower, " to the owner's hand"):
			var bf := _card_filter(text, "opp")
			if _text_has(lower, "this card") or _text_has(lower, "this character"):
				bf["this_card"] = true
				bf["player"] = "self"
			bf["zone"] = "field"
			actions.append([TOK_BOUNCE, bf])

	# Look at / reveal from deck; add/play; rest to bottom.
	if not as_cost and ((_text_has(lower, "look at") or _text_has(lower, "reveal")) and _text_has(lower, "deck")):
		var n := 1
		for m in _match_int(text, r"(?i)look at (\d+)"):
			n = m
			break
		if n == 1:
			for m in _match_int(text, r"(?i)reveal (\d+)"):
				n = m
				break
		if _text_has(lower, "look at all") or _text_has(lower, "search your deck"):
			n = 999
		var add_hand := _text_has(lower, "add it to your hand") or _text_has(lower, "add them to your hand") \
			or _text_has(lower, "add up to") or (_text_has(lower, "reveal") and _text_has(lower, "hand"))
		var play := _text_has(lower, "play up to") or _text_has(lower, "play 1")
		var rest := "bottom" if _text_has(lower, "bottom") else "top"
		var filt := _card_filter(text, "self")
		if not _text_has(lower, "character") and not _text_has(lower, "event") and not _text_has(lower, "stage"):
			filt["card_type"] = ""
		actions.append([TOK_LOOK_DECK, {"n": n, "add_hand": add_hand, "play": play,
			"rest": rest, "filter": filt, "shuffle": _text_has(lower, "shuffle") or n >= 999,
			"reorder": _text_has(lower, "in any order")}])

	if not as_cost and _text_has(lower, "remove from the game"):
		var rf := _card_filter(text, "self")
		if _text_has(lower, "this card") or _text_has(lower, "this character"):
			rf["this_card"] = true
		actions.append([TOK_REMOVE, rf])

	if not as_cost and _text_has(lower, "shuffle") and _text_has(lower, "deck") and not _text_has(lower, "look at"):
		actions.append([TOK_SHUFFLE, {"player": "self"}])

	if not as_cost and _text_has(lower, "set the cost"):
		var set_to := 0
		for m in _match_int(text, r"(?i)to (\d+)"):
			set_to = m
			break
		var cf := _card_filter(text, "opp")
		cf["zone"] = "field"
		cf["set_to"] = set_to
		cf["dur"] = _power_dur(text)
		actions.append([TOK_COST, cf])

	if not as_cost and (_text_has(lower, "base power becomes") or _text_has(lower, "becomes the same power") \
			or _text_has(lower, "power becomes the same") or _text_has(lower, "set the power")):
		var sp := {"who": "self", "dur": _power_dur(text)}
		if _text_has(lower, "same") and _text_has(lower, "leader"):
			sp["same_as"] = "opp_leader"
		elif _text_has(lower, "same as the selected"):
			sp["same_as"] = "picked"
			sp["filter"] = _card_filter(text, "opp")
		else:
			for m in _match_int(text, r"(?i)(?:becomes|to) (\d+)"):
				sp["set_to"] = m
				break
		actions.append([TOK_SET_POWER, sp])
	if not as_cost:
		var cost_amt := _cost_delta(text)
		if cost_amt != 0:
			if _text_has(lower, "this card in your hand"):
				pass
			elif _text_has(lower, "in your hand"):
				actions.append([TOK_HAND_COST, _hand_filter(text, cost_amt)])
			else:
				var cwho := "opp_char"
				if _text_has(lower, "this character") or _text_has(lower, "this card"):
					cwho = "self"
				elif _text_has(lower, "all of your opponent"):
					cwho = "all_opp_chars"
				elif _text_has(lower, "your opponent"):
					cwho = "opp_char"
				actions.append([TOK_COST, {"who": cwho, "amount": cost_amt, "dur": _power_dur(text)}])

	if not as_cost and _text_has(lower, "cannot play"):
		var np := {"scope": "chars"}
		if _text_has(lower, "from your hand") or _text_has(lower, "cards from"):
			np["scope"] = "hand"
		elif _text_has(lower, "base cost"):
			np["scope"] = "char_cost"
			for m in _match_int(text, r"(?i)base cost of (\d+)"):
				np["n"] = m
				break
		elif _text_has(lower, "character"):
			np["scope"] = "chars"
		elif _text_has(lower, "any card") or _text_has(lower, "cards this turn"):
			np["scope"] = "hand"
		actions.append([TOK_NO_PLAY, np])

	# Cannot be K.O.'d (granted this turn).
	if not as_cost and _text_has(lower, "cannot be k.o"):
		var frm := "all"
		if _text_has(lower, "in battle"):
			frm = "battle"
		elif _text_has(lower, "by effect"):
			frm = "effects"
		var prot := {"from": frm, "dur": _power_dur(text)}
		var are := RegEx.new()
		are.compile("(?i)<([^>]+)>")
		var am := are.search(text)
		if am and _text_has(lower, "attribute"):
			prot["attr"] = String(am.get_string(1)).strip_edges()
		for m in _match_int(text, r"(?i)(\d+)\s*base power or less"):
			prot["opp_power_lte"] = m
			break
		actions.append([TOK_PROTECT, prot])

	# Rest Characters (not DON!!).
	if not as_cost and _text_has(lower, "rest") and not _text_has(lower, "don"):
		if _text_has(lower, "rest this"):
			actions.append([TOK_REST_SELF, {}])
		elif _text_has(lower, "character") or _text_has(lower, "opponent's cards") or _text_has(lower, "leader") \
				or _text_has(lower, "your cards"):
			var rf := _card_filter(text, "opp")
			rf["zone"] = "field"
			if _text_has(lower, "opponent's cards") or (_text_has(lower, "leader") and _text_has(lower, "character")):
				rf["include_leader"] = true
			if _text_has(lower, "leader") and not _text_has(lower, "character"):
				rf["leaders_only"] = true
				rf["include_leader"] = true
			if _text_has(lower, "your cards"):
				rf["player"] = "self"
				rf["include_leader"] = true
				for m in _match_int(text, r"(?i)rest (\d+)"):
					rf["number"] = m
					break
			actions.append([TOK_REST_CHAR, rf])

	# Give DON!! (rested from cost, or Active if the text does not say rested).
	var _don_cards := _text_has(lower, "rested don") or _text_has(lower, "don!! card") or _text_has(lower, "active don")
	if (_text_has(lower, "give") or _text_has(lower, "attach")) and _text_has(lower, "don") \
			and not _text_has(lower, "don!! deck") and (_don_cards or not _text_has(lower, "power")):
		var amount := 1
		var up_to := _text_has(lower, "up to")
		var from := "active"
		if _text_has(lower, "rested don"):
			from = "rested"
			for m in _match_int(text, r"(?i)up to (\d+)\s*rested"):
				amount = m
				break
			if not up_to:
				for m in _match_int(text, r"(?i)(\d+)\s*rested don"):
					amount = m
					break
		else:
			for m in _match_int(text, r"(?i)(?:up to )?(\d+)\s*don"):
				amount = m
				break
		actions.append([TOK_ATTACH_DON, {"n": amount, "up_to": up_to, "from": from, "to": "leader_or_char"}])

	# Trash a Character on the field (not a K.O., not a hand or deck trash).
	if not as_cost and _text_has(lower, "trash") and _text_has(lower, "character") \
			and not _text_has(lower, "from your hand") and not _text_has(lower, "from their hand") \
			and not _text_has(lower, "from the top") and not _text_has(lower, "from your deck") \
			and not _text_has(lower, "k.o."):
		var field_f := _card_filter(text, "opp")
		field_f["zone"] = "field"
		actions.append([TOK_FIELD_TRASH, field_f])

	if not as_cost and _text_has(lower, "cannot activate") and _text_has(lower, "[blocker]"):
		var nb := _card_filter(text, "opp")
		nb["zone"] = "field"
		nb["dur"] = _power_dur(text)
		nb["keyword"] = "Blocker"
		if _text_has(lower, "if that") or _text_has(lower, "if the selected"):
			nb["mode"] = "on_attack"
			nb["player"] = "self"
			nb["keyword"] = ""
		else:
			nb["mode"] = "seal"
			if not _text_has(lower, "up to"):
				nb["number"] = 0
		actions.append([TOK_NO_BLOCK, nb])

	if not as_cost and _text_has(lower, "you win the game") and not _text_has(lower, "instead of losing"):
		actions.append([TOK_WIN, {}])

	if not as_cost and _text_has(lower, "cannot add life") and _text_has(lower, "to your hand"):
		actions.append([TOK_NO_LIFE_ADD, {"player": "self"}])

	if not as_cost and _text_has(lower, "deal") and _text_has(lower, "damage"):
		var dn := 1
		for m in _match_int(text, r"(?i)deal (\d+)\s*damage"):
			dn = m
			break
		actions.append([TOK_DAMAGE, {"n": dn, "player": "opp"}])

	# KO effects
	if not as_cost and _text_has(lower, "k.o."):
		var ko_act := _parse_ko(lower, text)
		if not ko_act.is_empty():
			actions.append(ko_act)

	# Power adjustments (+ or −), with who + duration.
	if not as_cost:
		var pow_act := _parse_power(text)
		if not pow_act.is_empty():
			actions.append(pow_act)

	# Rest opponent's DON
	if _text_has(lower, "rest") and _text_has(lower, "don"):
		if _text_has(lower, "your opponent") or _text_has(lower, "opponent's"):
			var n := 1
			for m in _match_int(text, r"(?i)rest (\d+)\s*don"):
				n = m
				break
			actions.append([TOK_REST_DON, {"player": "opp", "n": n}])

	# Trash the top N cards of a deck
	if _text_has(lower, "trash") and _text_has(lower, "from the top of") and _text_has(lower, "deck"):
		var n := 1
		for m in _match_int(text, r"(?i)trash (\d+)\s*card"):
			n = m
			break
		var player := "self"
		if _text_has(lower, "your opponent") or _text_has(lower, "opponent's deck"):
			player = "opp"
		actions.append([TOK_TRASH_DECK, {"player": player, "n": n}])
	elif not as_cost and _text_has(lower, "top card"):
		if _text_has(lower, "your opponent"):
			actions.append([TOK_TRASH_DECK, {"player": "opp", "n": 1}])
		elif _text_has(lower, "your deck"):
			actions.append([TOK_TRASH_DECK, {"player": "self", "n": 1}])

	# Return / place on deck (this card, or cards from trash)
	if _text_has(lower, "deck") and (_text_has(lower, "return") or _text_has(lower, "place")):
		var edge := "top"
		if _text_has(lower, "bottom of"):
			edge = "bottom"
		if _text_has(lower, "from your trash") or _text_has(lower, "from the trash"):
			var n := 1
			for m in _match_int(text, r"(?i)return (\d+)\s*card"):
				n = m
				break
			actions.append([TOK_TRASH_TO_DECK, {"n": n, "edge": edge, "player": "self"}])
		elif _text_has(lower, "this card") and (_text_has(lower, "your deck") or _text_has(lower, "owner's deck")) \
				and not _text_has(lower, "character"):
			actions.append([TOK_TO_DECK, {"target": "self", "edge": edge}])
		elif _text_has(lower, "from their hand") or _text_has(lower, "from your hand") or _text_has(lower, "from their hand"):
			var hn := 1
			for m in _match_int(text, r"(?i)(?:place|return) (\d+)\s*card"):
				hn = m
				break
			actions.append([TOK_HAND_TO_DECK, {"n": hn, "edge": edge,
				"player": "opp" if _text_has(lower, "opponent") or _text_has(lower, "their hand") else "self"}])
		elif _text_has(lower, "character") or _text_has(lower, "from their trash") or _text_has(lower, "opponent's trash"):
			var bf := _card_filter(text, "opp")
			bf["edge"] = edge
			if _text_has(lower, "trash"):
				bf["zone"] = "trash"
				bf["player"] = "opp" if _text_has(lower, "opponent") or _text_has(lower, "their trash") else "self"
			else:
				bf["zone"] = "field"
			var pn := 1
			for m in _match_int(text, r"(?i)(?:place|return)(?: up to)? (\d+)"):
				pn = m
				break
			bf["number"] = pn
			actions.append([TOK_TO_DECK, bf])

	# Trash from hand (yours or opponent's)
	if _text_has(lower, "trash") and (_text_has(lower, "from your hand") or _text_has(lower, "from your opponent's hand") \
			or _text_has(lower, "from their hand") or _text_has(lower, "their hand")):
		var n := 1
		for m in _match_int(text, r"(?i)trash(?:es)? (\d+)\s*card"):
			n = m
			break
		var who := "self"
		if _text_has(lower, "opponent") or _text_has(lower, "their hand"):
			who = "opp"
		actions.append([TOK_TRASH_HAND, {
			"n": n,
			"player": who,
			"card_type": "EventOrStage" if (_text_has(lower, "event") and _text_has(lower, "stage")) else "",
		}])
	if not as_cost and _text_has(lower, "reveal") and _text_has(lower, "opponent's hand"):
		var rn := 1
		for m in _match_int(text, r"(?i)(?:choose|reveal) (\d+)"):
			rn = m
			break
		actions.append([TOK_REVEAL_HAND, {"n": rn, "number": rn, "player": "opp", "zone": "hand"}])

	for act in _parse_life(text):
		actions.append(act)

	if not as_cost:
		var gre := RegEx.new()
		gre.compile(r"(?i)gains\s*\[([^\]]+)\]")
		for m in gre.search_all(text):
			var kw := String(m.get_string(1)).strip_edges()
			if (kw == "Rush" or kw == "Rush: Character") and _don_gated_keyword(text, kw):
				continue
			if kw in HARD_KEYWORDS:
				var gwho := "self"
				if _text_has(lower, "all of your"):
					gwho = "all_self"
				elif _text_has(lower, "up to 1 of your") or _text_has(lower, "up to 1 of your"):
					gwho = "self_char"
				actions.append([TOK_GRANT_KW, {"kw": kw, "dur": _power_dur(text), "who": gwho}])
		if _text_has(lower, "can also attack active") and (_text_has(lower, "up to") or _text_has(lower, "all of your")):
			var awho := "all_self" if _text_has(lower, "all of your") else "self_char"
			actions.append([TOK_GRANT_KW, {"kw": "attack_active", "dur": _power_dur(text), "who": awho}])
		if _text_has(lower, "can attack characters on the turn"):
			var rushf := _card_filter(text, "self")
			rushf["kw"] = "Rush: Character"
			rushf["who"] = "self_char" if _text_has(lower, "up to") else "all_self"
			rushf["dur"] = "turn"
			actions.append([TOK_GRANT_KW, rushf])

	return _stamp_cond(actions, cond)


static func _power_dur(text: String) -> String:
	var lower := text.to_lower()
	if lower.contains("until the start of your next turn"):
		return "until_own_next_turn"
	if lower.contains("until the end of your opponent") or lower.contains("opponent's next end"):
		return "until_opp_end"
	if lower.contains("during this battle"):
		return "battle"
	return "turn"


static func _card_filter(text: String, default_player: String) -> Dictionary:
	var lower := text.to_lower()
	var player := default_player
	if _text_has(lower, "your opponent") or _text_has(lower, "opponent's"):
		player = "opp"
	elif _text_has(lower, "your character") or _text_has(lower, "of your"):
		player = "self"
	var number := 1
	var up_to := _text_has(lower, "up to")
	for m in _match_int(text, r"(?i)up to (\d+)"):
		number = m
		break
	if _text_has(lower, "all") and _text_has(lower, "character"):
		number = 0
	var cost := 0
	var has_cost := false
	var op := "<="
	for m in _match_int(text, r"(?i)cost of (\d+) or less"):
		cost = m
		has_cost = true
		op = "<="
		break
	if not has_cost:
		for m in _match_int(text, r"(?i)cost of (\d+) or more"):
			cost = m
			has_cost = true
			op = ">="
			break
	if not has_cost:
		for m in _match_int(text, r"(?i)cost of (\d+)"):
			cost = m
			has_cost = true
			op = "="
			break
	var by_power := 0
	var by_power_op := "<="
	for m in _match_int(text, r"(?i)(\d+)\s*(?:base )?power or less"):
		by_power = m
		by_power_op = "<="
		break
	if by_power == 0:
		for m in _match_int(text, r"(?i)(\d+)\s*(?:base )?power or more"):
			by_power = m
			by_power_op = ">="
			break
	if by_power == 0:
		for m in _match_int(text, r"(?i)with (\d+)\s*(?:base )?power"):
			by_power = m
			by_power_op = "="
			break
	var by_type := ""
	var by_types: Array = []
	var tre := RegEx.new()
	tre.compile(r"\{([^}]+)\}")
	for tm in tre.search_all(text):
		var tn := String(tm.get_string(1)).strip_edges()
		if tn != "" and not by_types.has(tn):
			by_types.append(tn)
	if not by_types.is_empty():
		by_type = String(by_types[0])
	var by_name := ""
	var exclude_name := ""
	var nre := RegEx.new()
	nre.compile(r"\[([^\]]+)\]")
	var nm := nre.search(text)
	if nm != null:
		var maybe := String(nm.get_string(1)).strip_edges()
		if maybe != "Once Per Turn" and not maybe.begins_with("DON") and maybe != "On Play" \
				and maybe != "When Attacking" and maybe != "Blocker":
			by_name = maybe
	if _text_has(lower, "other than [") and by_name != "":
		exclude_name = by_name
		by_name = ""
	var card_type := "Character"
	if _text_has(lower, "event") and _text_has(lower, "stage"):
		card_type = "EventOrStage"
	elif _text_has(lower, "event"):
		card_type = "Event"
	elif _text_has(lower, "stage"):
		card_type = "Stage"
	elif not _text_has(lower, "character"):
		card_type = "Character"
	return {
		"player": player, "zone": "field", "number": number, "up_to": up_to,
		"has_cost": has_cost, "cost": cost, "op": op, "by_power": by_power,
		"by_power_op": by_power_op, "by_type": by_type, "by_types": by_types, "by_name": by_name, "exclude_name": exclude_name,
		"rested_only": _text_has(lower, "rested character") or _text_has(lower, "rested card"),
		"active_only": _text_has(lower, "active character"),
		"has_trigger": _text_has(lower, "[trigger]") and (_text_has(lower, "with a [") or _text_has(lower, "and a [")),
		"this_card": false, "include_leader": _text_has(lower, "leader") and _text_has(lower, "character"),
		"card_type": card_type,
	}


static func _parse_modal_options(text: String) -> Array:
	var low := text.to_lower()
	var idx := low.find("chooses one")
	if idx < 0:
		idx = low.find("choose one")
	var tail := text if idx < 0 else text.substr(idx)
	var colon := tail.find(":")
	if colon != -1:
		tail = tail.substr(colon + 1)
	var parts: Array = []
	var buf := ""
	for i in range(tail.length()):
		var ch := tail[i]
		if ch == "?" or ch == "•" or ch == "●":
			if not buf.strip_edges().is_empty():
				parts.append(buf.strip_edges())
			buf = ""
			continue
		buf += ch
	if not buf.strip_edges().is_empty():
		parts.append(buf.strip_edges())
	if parts.size() <= 1:
		parts = []
		for p in tail.split(" - ", false):
			var s := String(p).strip_edges()
			if s != "" and not s.to_lower().begins_with("your opponent chooses"):
				parts.append(s)
	var options: Array = []
	for p in parts:
		var acts := _parse_action_clause(String(p), false)
		if not acts.is_empty():
			options.append(acts)
	return options


static func _split_if_they_do_not(text: String) -> Array:
	var re := RegEx.new()
	re.compile(r"(?i)if they do not[,:]?\s*")
	var m := re.search(text)
	if m == null:
		var may := text.to_lower().find("your opponent may")
		var body := text if may < 0 else text.substr(may + String("your opponent may").length())
		return [body.strip_edges(), ""]
	var head := text.substr(0, m.get_start())
	var may_i := head.to_lower().find("your opponent may")
	if may_i != -1:
		head = head.substr(may_i + String("your opponent may").length())
	return [head.strip_edges().trim_suffix(".").strip_edges(), text.substr(m.get_end()).strip_edges()]


static func _parse_replace_ko(text: String) -> Array:
	var out: Array = []
	var low := text.to_lower()
	var needle := "would be k.o"
	var idx := 0
	while true:
		var at := low.find(needle, idx)
		var removed := false
		if at == -1:
			at = low.find("would be removed from the field", idx)
			removed = at != -1
			if at == -1:
				break
		var start := maxi(0, at - 180)
		var chunk := text.substr(start, mini(text.length() - start, 360))
		var clow := chunk.to_lower()
		var instead_i := clow.find("instead")
		if instead_i == -1:
			idx = at + 8
			continue
		var may_i := clow.find("you may")
		var pay_txt := ""
		if may_i != -1 and may_i < instead_i:
			pay_txt = chunk.substr(may_i + 7, instead_i - may_i - 7).strip_edges()
			pay_txt = pay_txt.trim_prefix(",").strip_edges()
		var spec := {
			"this_card": clow.contains("this character") or clow.contains("this card"),
			"from": "battle" if clow.contains("in battle") else ("effects" if clow.contains("by an effect") or clow.contains("by your opponent's effect") else "all"),
			"once_per_turn": clow.contains("once per turn") or text.contains("[Once Per Turn]"),
			"pay": _parse_action_body(pay_txt, true) if pay_txt != "" else [],
			"removed": removed,
		}
		for n in _match_int(chunk, r"(?i)base cost of (\d+) or more"):
			spec["min_cost"] = n
			spec["this_card"] = false
			break
		for n2 in _match_int(chunk, r"(?i)base cost of (\d+) or less"):
			spec["max_cost"] = n2
			spec["this_card"] = false
			break
		out.append(spec)
		idx = at + 8
	return out


static func _attack_target_filter(body: String) -> String:
	var bl := body.to_lower()
	if bl.contains("if your leader") or bl.contains("your leader has") or bl.contains("your leader is") \
			or bl.contains("your leader gains") or bl.contains("your leader's"):
		return ""
	if bl.contains("attacking a leader") or bl.contains("attacks a leader") \
			or bl.contains("attack is against a leader") or bl.contains("battle opponent is a leader") \
			or (bl.contains("if this character is attacking") and bl.contains("leader")):
		return "leader"
	if bl.contains("battle opponent is a character") or bl.contains("attacking a character") \
			or bl.contains("attacks a character"):
		return "character"
	return ""


static func _parse_cannot_attack_static(text: String) -> Dictionary:
	var low := text.to_lower()
	if not low.contains("this character cannot attack"):
		return {}
	if low.contains("cannot attack any card other"):
		return {}
	var spec := {"unless": ""}
	for n in _match_int(text, r"(?i)opponent has (\d+) or more character"):
		spec["opp_chars_gte"] = n
		spec["unless"] = "opp_chars"
		break
	for p in _match_int(text, r"(?i)base power of (\d+) or more"):
		spec["power_gte"] = p
		break
	if String(spec.get("unless", "")) == "" and low.contains("unless there is a character"):
		spec["unless"] = "any_char"
		for p2 in _match_int(text, r"(?i)with (\d+)\s*base power"):
			spec["power_gte"] = p2
			break
	return spec


static func _start_of_turn_body(text: String) -> String:
	var low := text.to_lower()
	var at := low.find("at the start of your turn")
	if at < 0:
		return ""
	var rest := text.substr(at)
	var dot := rest.find(".")
	if dot != -1 and dot + 1 < rest.length():
		return rest.substr(dot + 1).strip_edges()
	return rest.strip_edges()


static func _parse_battle_ko(text: String) -> Array:
	var low := text.to_lower()
	if not (low.contains("battles") and (low.contains("and k.o") or low.contains("and ko"))):
		return []
	var body := text
	var at := low.find("and k.o")
	if at == -1:
		at = low.find("and ko")
	if at != -1:
		var after := text.substr(at)
		var colon := after.find(".")
		if colon != -1 and colon + 1 < after.length():
			body = after.substr(colon + 1)
	return _parse_action_body(body, false)


static func _force_player(acts: Array, player: String) -> void:
	for a in acts:
		if a is Array and a.size() >= 2 and a[1] is Dictionary:
			a[1]["player"] = player


static func _parse_power(text: String) -> Array:
	var amount := 0
	for m in _match_int(text, r"(?i)([+\-−]\d+)\s*power"):
		amount = m
		break
	if amount == 0 and text.contains("?"):
		for m in _match_int(text, r"(?i)\?(\d+)\s*power"):
			amount = -m
			break
	if amount == 0:
		return []
	# Unicode minus
	if text.contains("−") and amount > 0 and not text.contains("+"):
		for m in _match_int(text, r"(?i)−(\d+)\s*power"):
			amount = -m
			break
	var who := "self"
	var lower := text.to_lower()
	if lower.contains("all of your") and lower.contains("character"):
		who = "all_self_chars"
	elif lower.contains("your opponent's leader or character") or lower.contains("opponent's leader or character"):
		who = "opp_any"
	elif lower.contains("opponent's leader") or lower.contains("of their character"):
		who = "opp_any"
	elif lower.contains("your opponent") or lower.contains("opponent's"):
		who = "opp_char"
	elif lower.contains("your leader or 1 of your") or lower.contains("this leader or 1 of your"):
		who = "self_or_chosen"
	elif lower.contains("this character") or lower.contains("this leader") or lower.contains("this card"):
		who = "self"
	elif lower.contains("1 of your"):
		who = "self_or_chosen"
	return [TOK_POWER, {"who": who, "amount": amount, "dur": _power_dur(text)}]


static func _parse_life(text: String) -> Array:
	# Life-manipulation verbs, harvested from 611 life-mentioning card texts.
	# Bodies arrive per-section; "If you have N or less Life" gates attach as
	# cond on every token from that body. "You may <cost>: <effect>" cost
	# prefixes execute sequentially, which pays the cost then the effect.
	var out: Array = []
	var lower := text.to_lower()
	if not lower.contains("life"):
		return out
	var cond := {}
	for m in _match_int(text, r"(?i)if you have (\d+) or less life"):
		cond = {"life_lte": m, "player": "self"}
		break
	var player := "self"
	if lower.contains("opponent's life") or lower.contains("opponent’s life"):
		player = "opp"

	# "add N card(s) from the top/bottom/top-or-bottom of (your) Life to hand"
	if lower.contains("each of your and your opponent") and lower.contains("life") and lower.contains("trash"):
		var ln_both := _life_num(text)
		out.append([TOK_TRASH_LIFE, {"n": ln_both[0], "up_to": ln_both[1], "all": ln_both[2],
			"player": "self", "cond": cond}])
		out.append([TOK_TRASH_LIFE, {"n": ln_both[0], "up_to": ln_both[1], "all": ln_both[2],
			"player": "opp", "cond": cond}])
	elif lower.contains("life area") or lower.contains("their life") or lower.contains("of your life") or lower.contains("of your opponent's life") or lower.contains("of your opponent’s life"):
		if lower.contains("their life") or lower.contains("life area") or lower.contains("opponent"):
			player = "opp"
		if lower.contains("to your hand") or lower.contains("to their hand") or lower.contains("owner's hand"):
			var edge := "top"
			if lower.contains("top or bottom") or lower.contains("bottom or top"):
				edge = "either"
			elif lower.contains("bottom of your life") or lower.contains("bottom of your opponent"):
				edge = "bottom"
			var ln := _life_num(text)
			out.append([TOK_LIFE_TO_HAND, {"n": ln[0], "up_to": ln[1], "all": ln[2],
				"edge": edge, "player": player, "cond": cond}])

	# "add (up to) N card(s) from the top of your deck to the top of your Life"
	if lower.contains("from the top of your deck to the top of your life"):
		var ln := _life_num(text)
		out.append([TOK_DECK_TO_LIFE, {"n": ln[0], "up_to": ln[1], "all": ln[2],
			"face": _life_face(text), "cond": cond}])

	# "add (up to) N ... from your hand to the top of your Life"
	if lower.contains("from your hand to the top of your life"):
		var ln := _life_num(text)
		out.append([TOK_HAND_TO_LIFE, {"n": ln[0], "up_to": ln[1], "all": ln[2],
			"face": _life_face(text), "cond": cond}])

	# "trash N card(s) from the top (or bottom) of your/opponent's Life",
	# "trash all your face-up Life cards"
	if lower.contains("trash") and (lower.contains("of your life") or lower.contains("of your opponent's life") or lower.contains("of your opponent’s life") or lower.contains("face-up life") or lower.contains("face up life")):
		if lower.contains("face-up life") or lower.contains("face up life"):
			out.append([TOK_TRASH_FACEUP, {"player": player, "cond": cond}])
		else:
			var ln := _life_num(text)
			out.append([TOK_TRASH_LIFE, {"n": ln[0], "up_to": ln[1], "all": ln[2],
				"player": player, "cond": cond}])

	# "turn (all|N card(s) from the top/bottom of your) Life face-up/down"
	if lower.contains("turn") and lower.contains("life") and (lower.contains("face-up") or lower.contains("face up") or lower.contains("face-down") or lower.contains("face down")):
		var all := lower.contains("turn all of your life")
		var down := lower.contains("face-down") or lower.contains("face down")
		var edge := "top"
		if lower.contains("top or bottom") or lower.contains("bottom or top"):
			edge = "either"
		elif lower.contains("bottom of your life"):
			edge = "bottom"
		out.append([TOK_FACE_LIFE, {"all": all, "down": down, "edge": edge, "cond": cond}])

	# "(Add up to 1 ... Character(s) [cost N ...] to the top (or bottom) of
	#  the owner's/your/opponent's Life (face-up/down))"
	if lower.contains("character") and lower.contains("life") and (lower.contains("to the top") or lower.contains("at the top")):
		if lower.contains("owner's life") or lower.contains("owner’s life") or lower.contains("of your life") or lower.contains("of your opponent's life") or lower.contains("of your opponent’s life"):
			var max_cost := 0
			for m in _match_int(text, r"(?i)cost of (\d+)"):
				max_cost = m
				break
			if max_cost == 0:
				for m in _match_int(text, r"(?i)cost (\d+)"):
					max_cost = m
					break
			var cplayer := "any"
			if lower.contains("your opponent's character") or lower.contains("your opponent’s character"):
				cplayer = "opp"
			elif lower.contains("your character") or lower.contains("of your character"):
				cplayer = "self"
			out.append([TOK_CHAR_TO_LIFE, {"max_cost": max_cost, "player": cplayer,
				"face": _life_face(text), "cond": cond}])

	# "look at ... Life ... place back / place 1 at top of deck"
	if lower.contains("look at") and lower.contains("life"):
		var deck_top := 0
		if lower.contains("place 1 at the top of your deck") or lower.contains("place 1 card at the top of your deck"):
			deck_top = 1
		out.append([TOK_LOOK_LIFE, {"deck_top": deck_top, "cond": cond,
			"player": "opp" if (lower.contains("opponent") or lower.contains("their life")) else "self"}])

	return out

# Returns [n, up_to, all]: "up to N" / "all" / "N card(s)" / default 1.
static func _life_num(text: String) -> Array:
	var lower := text.to_lower()
	if lower.contains("trash all") or (lower.contains(" all ") and lower.contains("life")):
		return [0, false, true]
	for m in _match_int(text, r"(?i)up to (\d+)"):
		return [m, true, false]
	for m in _match_int(text, r"(?i)(\d+)\s*card"):
		return [m, false, false]
	return [1, false, false]

static func _life_face(text: String) -> String:
	var lower := text.to_lower()
	if lower.contains("face-up") or lower.contains("face up"):
		return "up"
	if lower.contains("face-down") or lower.contains("face down"):
		return "down"
	return ""


static func _parse_ko(lower: String, original: String) -> Array:
	var player := "opp"
	if _text_has(lower, "your") and not _text_has(lower, "your opponent") and not _text_has(lower, "opponent"):
		player = "self"
	var cost := 0
	var has_cost := false
	for m in _match_int(original, r"(?i)cost of (\d+)"):
		cost = m; has_cost = true; break
	if not has_cost:
		for m in _match_int(original, r"(?i)cost (\d+)"):
			cost = m; has_cost = true; break
	var op := "<="
	var number := 1  # "up to N"
	for m in _match_int(original, r"(?i)up to (\d+)"):
		number = m
		break
	if _text_has(lower, "all"):
		number = 0  # 0 means "all"
	var by_power := 0
	for m in _match_int(original, r"(?i)(\d+)\s*power or less"):
		by_power = m
		break
	var include_leader := _text_has(lower, "leader") and _text_has(lower, "character")
	var rested_only := _text_has(lower, "rested character") or _text_has(lower, "rested characters")
	var active_only := _text_has(lower, "active character") or _text_has(lower, "active characters")
	var this_card := _text_has(lower, "k.o. this character") or _text_has(lower, "k.o. this card")
	if this_card:
		player = "self"
	var by_name := ""
	var nre := RegEx.new()
	nre.compile(r"\[([^\]]+)\]")
	var nm := nre.search(original)
	if nm != null and _text_has(lower, "character"):
		var maybe := String(nm.get_string(1)).strip_edges()
		if maybe != "Once Per Turn" and not maybe.begins_with("DON"):
			by_name = maybe
	var by_type := _first_brace_type(original)
	if _text_has(lower, "k.o. this character") or _text_has(lower, "k.o. this card"):
		this_card = true
		player = "self"
	return [TOK_KO, {"player": player, "op": op, "cost": cost, "has_cost": has_cost,
		"number": number, "include_leader": include_leader, "by_power": by_power,
		"rested_only": rested_only, "active_only": active_only, "this_card": this_card,
		"by_name": by_name, "by_type": by_type,
		"cost_vs_opp_life": _text_has(lower, "equal to or less than the number of your opponent's life")}]


static func collect_hats(text: String) -> Array:
	var hats: Array = []
	var idx := 0
	while true:
		var br := text.find("[", idx)
		if br == -1:
			break
		var end := text.find("]", br + 1)
		if end == -1:
			break
		hats.append(text.substr(br + 1, end - br - 1).strip_edges())
		idx = end + 1
	return hats


static func _parse_don_abilities(text: String) -> Dictionary:
	var result := {"power": [], "turn_power": [], "grants_rush_at_don": 0}
	# [DON!! xN] ... +N000 power, during your turn / opponent's turn
	var re := RegEx.new()
	re.compile(r"\[DON!!\s*x(\d+)\]\s*([^\[\]]*)")
	for m in re.search_all(text):
		var min_don: int = int(m.get_string(1))
		var body := m.get_string(2)
		var amount := 0
		for a in _match_int(body, r"(?i)(\d+)\s*power"):
			amount = a
			break
		if _text_has(body, "opponent") and amount > 0:
			result.power.append({"amount": amount, "min_don": min_don, "dur": "opp_turn"})
		elif amount > 0:
			result.power.append({"amount": amount, "min_don": min_don, "dur": "own_turn"})
	# "This Character gains [Rush]" tied to a [DON!! xN] hat (e.g. ST01-004)
	if _text_has(text, "gains [Rush]") or _text_has(text, "gains [Rush]"):
		var re2 := RegEx.new()
		re2.compile(r"\[DON!!\s*x(\d+)\]\s*[^\[\]]*gains \[Rush\]")
		for m2 in re2.search_all(text):
			result.grants_rush_at_don = int(m2.get_string(1))
			break
	return result


static func _parse_trigger(text: String, out: Dictionary) -> Array:
	if _text_has(text, "this card's [Main] effect"):
		out["rerun_main_on_trigger"] = true
		return []
	if _text_has(text, "this card's [Counter] effect"):
		out["rerun_counter_on_trigger"] = true
		return []
	if _text_has(text, "this card's [On Play] effect"):
		out["rerun_on_play_on_trigger"] = true
		return []
	if _text_has(text, "Play this card"):
		out.play_self_on_trigger = true
		out["trigger_cond"] = _clause_cond(text)
	var stripped := text
	var cut := RegEx.new()
	cut.compile("(?i)\\.?\\s*(?:then,\\s*)?(?:if [^.]+,\\s*)?play this card\\.?")
	stripped = cut.sub(stripped, "", true)
	if stripped.strip_edges().is_empty():
		return []
	return _parse_actions(stripped)


static func _generic_turn_power(text: String) -> Array:
	var result: Array = []
	var re := RegEx.new()
	re.compile(r"(?i)([+-]\d+)\s*power during (this|your) turn")
	for m in re.search_all(text):
		var amount := int(m.get_string(1))
		result.append({"amount": amount, "dur": "turn", "condition_don": 0, "who": "self"})
	return result


# Returns all int matches (first capture group) for a regex over text.
static func _match_int(text: String, pattern: String) -> Array:
	var re := RegEx.new()
	var err := re.compile(pattern)
	if err != OK:
		return []
	var out: Array = []
	for m in re.search_all(text):
		out.append(int(m.get_string(1)))
	return out


static func _cost_delta(text: String) -> int:
	if text.contains("−"):
		for m in _match_int(text, r"(?i)−(\d+)\s*cost"):
			return -m
	for m in _match_int(text, r"(?i)([+\-]\d+)\s*cost"):
		return m
	if _text_has(text, "cost") and _text_has(text, "less"):
		for m in _match_int(text, r"(?i)(\d+)\s*less"):
			return -m
	for m in _match_int(text, r"(?i)reduced by (\d+)"):
		return -m
	return 0


static func _hand_filter(text: String, amount: int) -> Dictionary:
	var out := {"amount": amount, "dur": "turn"}
	var lower := text.to_lower()
	if _text_has(lower, "event"):
		out["card_type"] = "Event"
	elif _text_has(lower, "stage"):
		out["card_type"] = "Stage"
	elif _text_has(lower, "character"):
		out["card_type"] = "Character"
	var col := _color_word(text)
	if col != "":
		out["color"] = col
	var type_name := _first_brace_type(text)
	if type_name != "":
		out["trait"] = type_name
	for m in _match_int(text, r"(?i)cost of (\d+) or more"):
		out["cost_gte"] = m
		break
	if _text_has(text, "[Your Turn]"):
		out["own_turn"] = true
	return out


static func _color_word(text: String) -> String:
	var re := RegEx.new()
	re.compile(r"(?i)\b(red|green|blue|black|yellow|purple)\b")
	var m := re.search(text)
	if m:
		return String(m.get_string(1)).capitalize()
	return ""


static func _parse_hand_cost(text: String) -> Dictionary:
	if not _text_has(text, "this card in your hand"):
		return {}
	var amt := _cost_delta(text)
	if amt == 0:
		return {}
	return {"amount": amt, "cond": _clause_cond(text)}


static func _parse_hand_cost_aura(text: String) -> Dictionary:
	if not _text_has(text, "in your hand") and not _text_has(text, "from your hand"):
		return {}
	if _text_has(text, "this card in your hand"):
		return {}
	if _text_has(text, "this turn") or _text_has(text, "during this turn"):
		return {}
	var amt := _cost_delta(text)
	if amt == 0:
		return {}
	return _hand_filter(text, amt)


static func _after_when(text: String, phrase: String) -> String:
	var i := text.to_lower().find(phrase.to_lower())
	if i < 0:
		return ""
	var rest := text.substr(i + phrase.length())
	if rest.begins_with(",") or rest.begins_with(":"):
		rest = rest.substr(1)
	return rest.strip_edges()


static func _don_min_near(text: String, _phrase: String) -> int:
	for m in _match_int(text, r"(?i)\[DON!!\s*x(\d+)\]"):
		return m
	return 0


static func _don_gated_keyword(text: String, kw: String) -> bool:
	var re := RegEx.new()
	re.compile("\\[DON!!\\s*x\\d+\\][^\\[]*gains \\[" + kw)
	return re.search(text) != null


static func _cut_next_window(body: String) -> String:
	var cut := body.find("[Once Per Turn]")
	if cut > 0 and _text_has(body.substr(cut), "can be activated"):
		return body.substr(0, cut).strip_edges()
	return body


static func _push_when(out: Dictionary, key: String, text: String, phrase: String) -> void:
	if not _text_has(text, phrase):
		return
	if _text_has(text, "without activating its trigger") and _text_has(phrase, "deals damage"):
		return
	var body := _cut_next_window(_after_when(text, phrase))
	var bare := body.strip_edges().trim_suffix(".").strip_edges()
	if bare == "":
		var at := text.to_lower().find(phrase.to_lower())
		var before := text.substr(0, at)
		var hats := RegEx.new()
		hats.compile("\\[[^\\]]+\\]")
		body = hats.sub(before, "", true).strip_edges()
	var tok := _entry_tok({
		"body": body,
		"once_per_turn": _text_has(text, "Once Per Turn"),
		"don_min": _don_min_near(text, phrase),
	})
	if _text_has(text, "[Your Turn]"):
		tok["cond_turn"] = "own_turn"
	_stamp_cond(tok.get("actions", []), _clause_cond(text))
	if key == "on_opp_event" and _text_has(text, "or [Trigger]"):
		tok["also_trigger"] = true
	out[key].append(tok)
