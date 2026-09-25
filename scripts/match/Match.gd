# res://scripts/match/Match.gd
# Pure-logic One Piece TCG match engine + rule adjudicator.
# No scene-tree dependency (extends RefCounted): instantiate per game.
# All player actions go through apply() which validates against the current
# rules and returns {ok, code, msg}. get_legal_actions() enumerates the full
# legal action set for AI / UI / tests.

extends RefCounted
class_name MtMatch

const LEADER_LIFE := preload("res://scripts/match/LeaderLife.gd")

const MAX_DON := 10
const HAND_SIZE := 5
const MAX_COPIES := 4

enum Phase { DON, DRAW, MAIN, END }

const BATTLES := ["counter", "block", "counter2", "resolve"]

const ACTION_END_TURN := "end_turn"
const ACTION_PLAY := "play"
const ACTION_PLAY_EVENT := "play_event"
const ACTION_ACTIVATE := "activate"
const ACTION_ATTACH_DON := "attach_don"
const ACTION_ATTACK := "attack"
const ACTION_COUNTER := "counter"
const ACTION_BLOCK := "block"
const ACTION_PASS_BATTLE := "pass_battle"
const ACTION_TRIGGER_YES := "trigger_yes"
const ACTION_TRIGGER_NO := "trigger_no"
const ACTION_MULLIGAN := "mulligan"
const ACTION_KEEP_HAND := "keep_hand"
const ACTION_CHOOSE_EFFECT := "choose_effect"
const ACTION_CANCEL_CHOICE := "cancel_choice"

var rng := RandomNumberGenerator.new()
var turn := 1
var active := 0
var phase: int = Phase.DON
var players: Array = []        # [MtPlayerState, MtPlayerState]
var battle: Dictionary = {}    # non-empty while an attack is resolving
var over := false
var winner := -1
var win_reason := ""
var log_lines: Array = []
# Pending human choice (null when none). Only kind today:
# {"type": "life_trigger", "player": int, "card_uid": String}.
# With auto_resolve_choices (default true, used by AI/headless sims) life
# triggers resolve immediately (legacy behavior) and no choice ever pends.
var pending_choice = null
var auto_resolve_choices := true
var enable_mulligan := false
var mulligan_done: Array = [false, false]
# Quiet clones skip print/log_lines (MCTS runs thousands of silent playouts).
var quiet := false

var first_player_idx := 0
var _fx_cache: Dictionary = {}
var _uid_seed := 0
var _turn_bonuses: Array = []   # [{card, amount, dur, owner}]
var _block_seals: Array = []    # opponent cannot activate [Blocker]
var _effect_depth := 0
var _need_rule_check := false
var _limbo: Array = []
var _last_look: Array = []
var _effect_did := false
var _cond_ctx: Dictionary = {}
var _start_turn_queue: Array = []

func _init() -> void:
	rng.seed = Time.get_ticks_usec()
	reset()

func reset() -> void:
	turn = 1
	active = 0
	first_player_idx = 0
	phase = Phase.DON
	battle.clear()
	over = false
	winner = -1
	win_reason = ""
	pending_choice = null
	mulligan_done = [false, false]
	log_lines.clear()
	_fx_cache.clear()
	_turn_bonuses.clear()
	_effect_depth = 0
	_need_rule_check = false
	_limbo.clear()
	_last_look.clear()
	_start_turn_queue.clear()

# --- Setup ---

## deck_cards: { "leader": Dictionary, "main": Array[Dictionary] } per player.
## don_card: Dictionary used to fabricate the 10 DON (optional).
func start(deck_a: Dictionary, deck_b: Dictionary, first_player: int = -1) -> void:
	reset()
	players.clear()
	players.append(_make_player(0, deck_a))
	players.append(_make_player(1, deck_b))
	if first_player < 0:
		active = rng.randi_range(0, 1)
	else:
		active = first_player & 1
	first_player_idx = active
	_build_zones(players[0])
	_build_zones(players[1])
	_apply_start_of_game_rules(players[0])
	_apply_start_of_game_rules(players[1])
	_log("Match start. First player: P%d" % (active))
	if enable_mulligan and not auto_resolve_choices:
		pending_choice = {"type": "mulligan", "player": first_player_idx}
		_log("P%d may mulligan or keep hand." % first_player_idx)
	else:
		_begin_phase(Phase.DON)

func _make_player(idx: int, deck: Dictionary) -> MtPlayerState:
	var ps := MtPlayerState.new(idx)
	var leader_dict := deck.get("leader", {})
	if not leader_dict.is_empty():
		ps.leader = _mk(leader_dict, idx, MtMatchCard.ZONE_LEADER)
	for card in deck.get("main", []):
		ps.deck.append(_mk(card, idx, MtMatchCard.ZONE_DECK))
	# Leader sets the starting Life total and any DON-deck rule override
	ps.max_life = max_life_for(ps)
	ps.don_deck_size = don_deck_size_for(ps)
	return ps

func _mk(card_dict: Dictionary, owner: int, zone: String) -> MtMatchCard:
	var mc := MtMatchCard.new(_new_uid(), card_dict, owner)
	mc.zone = zone
	return mc

func _new_uid() -> String:
	_uid_seed += 1
	return "c%d_%d" % [active, _uid_seed]

func _build_zones(ps: MtPlayerState) -> void:
	_shuffle(ps.deck)
	for i in range(HAND_SIZE):
		var card: MtMatchCard = ps.deck.pop_front()
		card.zone = MtMatchCard.ZONE_HAND
		ps.hand.append(card)
	ps.don_in_deck = ps.don_deck_size
	for i in range(ps.max_life):
		var card: MtMatchCard = ps.deck.pop_front()
		card.zone = MtMatchCard.ZONE_LIFE
		card.face_down = true
		ps.life.append(card)

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _opp(p: int) -> int:
	return 1 - p

func _P(who: int) -> MtPlayerState:
	return players[who]

func _log(msg: String) -> void:
	if quiet:
		return
	log_lines.append(msg)
	print("MATCH: " + msg)

# Who is to move right now (battle defender or active player).
func mover() -> int:
	if pending_choice != null:
		return int(pending_choice.get("player", get_active_player()))
	if in_battle():
		return int(battle.get("defender_owner", 0))
	return get_active_player()

# Coarse canonical position key for the opening book / transpositions.
# Turn-capped (openings only), sorted field codes, sizes + leader + DON.
func position_key() -> String:
	var parts: Array = ["t%d" % mini(turn, 6), "a%d" % active, "p%d" % phase,
		"m%d" % mover()]
	if pending_choice != null:
		parts.append("c1")
	for ps in players:
		var codes: Array = []
		for c in (ps as MtPlayerState).field:
			codes.append((c as MtMatchCard).card_code())
		codes.sort()
		parts.append("L%dh%df%sD%d" % [(ps as MtPlayerState).life.size(),
			(ps as MtPlayerState).hand.size(), "+".join(codes),
			(ps as MtPlayerState).don_active])
	return "|".join(parts)

# --- Simulation: deep clone + determinization (MCTS) ---
func clone() -> MtMatch:
	var nm := MtMatch.new()
	nm.rng.state = rng.state
	nm.turn = turn
	nm.active = active
	nm.first_player_idx = first_player_idx
	nm.phase = phase
	nm.over = over
	nm.winner = winner
	nm.win_reason = win_reason
	nm.auto_resolve_choices = auto_resolve_choices
	nm.quiet = true
	nm._uid_seed = _uid_seed
	if pending_choice == null:
		nm.pending_choice = null
	else:
		nm.pending_choice = (pending_choice as Dictionary).duplicate()
	var map := {}
	nm.players = [(players[0] as MtPlayerState).clone_mapped(map),
		(players[1] as MtPlayerState).clone_mapped(map)]
	nm.battle = _remap_refs(battle, map)
	nm._turn_bonuses = _remap_refs(_turn_bonuses, map)
	nm._limbo = _remap_refs(_limbo, map)
	return nm

func _remap_refs(v, map: Dictionary):
	if v is MtMatchCard:
		return map.get((v as MtMatchCard).uid, v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _remap_refs(v[k], map)
		return out
	if v is Array:
		var arr: Array = []
		for e in v:
			arr.append(_remap_refs(e, map))
		return arr
	return v

# Single-observer determinization: randomly permute what `viewer` cannot
# know — the opponent's deck order and the face-down Life cards among their
# face-down slots. Hand order has no positional effects, so it is kept.
# Call on a fresh clone per MCTS iteration for one sample of the hidden world.
func determinize(viewer: int) -> void:
	var foe := _P(_opp(viewer))
	_shuffle(foe.deck)
	var slots: Array = []
	var hidden: Array = []
	for i in range(foe.life.size()):
		var c: MtMatchCard = foe.life[i]
		if c.face_down:
			slots.append(i)
			hidden.append(c)
	for i in range(hidden.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = hidden[i]
		hidden[i] = hidden[j]
		hidden[j] = tmp
	for k in range(slots.size()):
		foe.life[int(slots[k])] = hidden[k]

# --- Public query API ---

func is_over() -> bool:
	return over

func get_active_player() -> int:
	return active

func get_phase() -> int:
	return phase

func in_battle() -> bool:
	return not battle.is_empty()

func has_legal_action() -> bool:
	return not get_legal_actions().is_empty()

func is_data_loaded() -> bool:
	return true

# --- Effect parsing (cached) ---
func fx(card: MtMatchCard) -> Dictionary:
	if card != null and card.effects_negated:
		return _blank_fx()
	return fx_dict(card.card)

func _blank_fx() -> Dictionary:
	return {
		"keywords": [], "on_play": [], "activate_main": [], "on_attack": [], "on_ko": [],
		"on_block": [], "on_opp_attack": [], "on_end": [], "on_opp_end": [], "on_main": [],
		"counter": [], "turn_power": [], "don_power": [], "triggers": [], "protect_fx": [],
		"must_attack_fx": [], "turn_actions": [], "on_give_don": [], "on_opp_turn": [],
		"replace_ko": [], "on_battle_ko": [], "on_start_turn": [], "cannot_attack_fx": [],
		"rules": {}, "win_on_block_zero_life": false, "on_trash": [],
	}

func fx_dict(card_dict: Dictionary) -> Dictionary:
	var code := String(card_dict.get("card_code", ""))
	if code.is_empty():
		return MtEffectParser.parse(card_dict)
	if not _fx_cache.has(code):
		_fx_cache[code] = MtEffectParser.parse(card_dict)
	return _fx_cache[code]

# --- Per-leader base-rule lookups ---

func _leader_rules(ps: MtPlayerState) -> Dictionary:
	if ps.leader == null:
		return {}
	return fx(ps.leader).get("rules", {})

# Starting number of Life cards = the Leader's printed Life value.
# Prefer an explicit data "life" field if one is ever added; otherwise use the
# curated table (default 5).
func max_life_for(ps: MtPlayerState) -> int:
	if ps.leader == null:
		return 0
	var life := int(ps.leader.card.get("life", 0))
	if life <= 0:
		life = LEADER_LIFE.value(ps.leader.card_code())
	return life

# DON!! deck size; normally 10, overridden by leaders like Enel OP15-058 (6).
func don_deck_size_for(ps: MtPlayerState) -> int:
	return int(_leader_rules(ps).get("don_deck_size", MAX_DON))

func counter_for(card: MtMatchCard) -> int:
	if card == null:
		return 0
	var printed := card.counter_value()
	if printed > 0:
		return printed
	if not card.is_character():
		return printed
	var rules := _leader_rules(_P(card.owner))
	var bonus_trait := String(rules.get("bonus_counter_trait", ""))
	if bonus_trait == "":
		return printed
	if card.traits().has(bonus_trait):
		return int(rules.get("bonus_counter", 0))
	return printed

func _apply_start_of_game_rules(ps: MtPlayerState) -> void:
	var stage_trait := String(_leader_rules(ps).get("start_play_stage_trait", ""))
	if stage_trait == "" or ps.stage != null:
		return
	for i in range(ps.deck.size()):
		var c: MtMatchCard = ps.deck[i]
		if c.is_stage() and c.traits().has(stage_trait):
			ps.deck.remove_at(i)
			c.zone = MtMatchCard.ZONE_STAGE
			ps.stage = c
			_log("P%d plays %s from the deck at the start of the game." % [ps.index, c.card_name()])
			for tok in fx(c).get("on_play", []):
				_resolve_actions(c, tok.get("actions", []), {})
			return

func has_keyword(card: MtMatchCard, kw: String) -> bool:
	if card == null or card.effects_negated:
		return false
	if card.granted_keywords.has(kw):
		return true
	if fx(card).get("keywords", []).has(kw):
		return true
	for act in fx(card).get("static_actions", []):
		if not (act is Array) or String(act[0]) != MtEffectParser.TOK_GRANT_KW:
			continue
		if act.size() < 2 or not (act[1] is Dictionary):
			continue
		if String(act[1].get("kw", "")) != kw:
			continue
		if _check_cond(card, act[1]):
			return true
	return false

func can_attack_turn_played(card: MtMatchCard) -> bool:
	var f := fx(card)
	if f.get("can_attack_turn_played", false):
		return true
	if has_keyword(card, "Rush") or has_keyword(card, "Rush: Character"):
		return true
	if float(f.get("grants_rush_at_don", 0)) > 0 and card.don_count() >= int(f.get("grants_rush_at_don", 0)):
		return true
	return false

func _attack_cannot_be_blocked(atk: MtMatchCard) -> bool:
	if atk == null:
		return false
	if has_keyword(atk, "Unblockable") or bool(fx(atk).get("unblockable", false)):
		return true
	var nbd: int = fx(atk).get("no_block_with_don", 0)
	if nbd > 0 and atk.don_count() >= nbd:
		return true
	return false

# --- Power ---
func card_power(card: MtMatchCard) -> int:
	if card == null:
		return 0
	if card.is_leader() or card.is_character():
		var p := card.base_power() + card.power_bonus
		# Attached DON give +1000 only during the card's owner's turn
		if active == card.owner:
			p += card.don_count() * 1000
		var f := fx(card)
		for dp in f.get("don_power", []):
			if card.don_count() >= dp.min_don:
				if (dp.dur == "own_turn" and active == card.owner) or (dp.dur == "opp_turn" and active != card.owner) or dp.dur == "always":
					p += dp.amount
		for tp in f.get("turn_power", []):
			var td := String(tp.get("dur", "turn"))
			if td == "own_turn" and active != card.owner:
				continue
			if td == "opp_turn" and active == card.owner:
				continue
			p += int(tp.get("amount", 0))
		for act in f.get("static_actions", []):
			if not (act is Array) or String(act[0]) != MtEffectParser.TOK_POWER:
				continue
			if act.size() < 2 or not (act[1] is Dictionary):
				continue
			if not _check_cond(card, act[1]):
				continue
			p += int(act[1].get("amount", 0))
		return p
	return 0

func effect_cost(card: MtMatchCard) -> int:
	if card == null:
		return 0
	var n := card.cost_value()
	for act in fx(card).get("static_actions", []):
		if not (act is Array) or String(act[0]) != MtEffectParser.TOK_COST:
			continue
		if act.size() < 2 or not (act[1] is Dictionary):
			continue
		if String(act[1].get("who", "self")) != "self":
			continue
		if not _check_cond(card, act[1]):
			continue
		if act[1].has("set_to"):
			n = int(act[1].get("set_to", 0))
		else:
			n += int(act[1].get("amount", 0))
	return maxi(0, n)

func _apply_set_power(card: MtMatchCard, opts: Dictionary) -> void:
	var new_p := int(opts.get("set_to", card.base_power()))
	if String(opts.get("same_as", "")) == "opp_leader":
		var ld := _P(_opp(card.owner)).leader
		if ld != null:
			new_p = ld.base_power()
	var prev := card.power_override
	card.power_override = new_p
	_turn_bonuses.append({"card": card, "amount": 0, "prev": prev,
		"dur": String(opts.get("dur", "turn")), "owner": card.owner, "kind": "swap"})
	_log("%s's base power becomes %d." % [card.card_name(), new_p])

func _in_field(ps: MtPlayerState, card: MtMatchCard) -> bool:
	return card in ps.field or card == ps.leader or card == ps.stage

# --- Deck helpers ---
func draw_card(ps: MtPlayerState) -> MtMatchCard:
	if ps.deck.is_empty():
		_on_deck_empty(ps, true)
		return null
	# Deck order: index 0 is the top (draw / trash-from-top). Last index is the bottom.
	var card: MtMatchCard = ps.deck.pop_front()
	card.zone = MtMatchCard.ZONE_HAND
	ps.hand.append(card)
	if ps.deck.is_empty():
		_on_deck_empty(ps, false)
	return card

func _on_deck_empty(ps: MtPlayerState, from_draw: bool) -> void:
	var rules := _leader_rules(ps)
	if bool(rules.get("deckout_is_win", false)):
		_over_loss(ps.index, "Deck is empty")
		return
	if bool(rules.get("deckout_end_of_turn", false)):
		ps.deckout_pending = true
		if from_draw:
			_log("P%d cannot draw (0 cards). They do not lose yet (lose at end of turn)." % ps.index)
		return
	_need_rule_check = true
	if from_draw or _effect_depth <= 0:
		_rule_process()

func _rule_process() -> void:
	if over:
		return
	_need_rule_check = false
	for ps in players:
		if over:
			return
		if ps.deck.is_empty():
			var rules := _leader_rules(ps)
			if bool(rules.get("deckout_is_win", false)):
				_over_loss(ps.index, "Deck is empty")
				return
			if bool(rules.get("deckout_end_of_turn", false)):
				ps.deckout_pending = true
				continue
			_over_loss(ps.index, "Deck is empty")
			return

func _move_to_trash(ps: MtPlayerState, card: MtMatchCard) -> void:
	var from := String(card.zone)
	if (from == MtMatchCard.ZONE_FIELD or from == MtMatchCard.ZONE_STAGE) and _cannot_leave(card, false, null):
		_log("%s cannot be removed from the field." % card.card_name())
		return
	_finalize_move(card)
	card.zone = MtMatchCard.ZONE_TRASH
	card.rested = false
	ps.trash.append(card)
	if from == MtMatchCard.ZONE_HAND:
		ps.hand_trashed_this_turn = true
		_fire_window(ps, "on_hand_trash")
	if from == MtMatchCard.ZONE_FIELD or from == MtMatchCard.ZONE_STAGE:
		if card.is_character() or card.is_stage():
			_fire_window(ps, "on_char_leave", {"played": card}, card)
	if from == MtMatchCard.ZONE_FIELD or from == MtMatchCard.ZONE_STAGE or from == MtMatchCard.ZONE_HAND:
		for tok in fx(card).get("on_trash", []):
			_resolve_actions(card, tok.get("actions", []), {})

func _finalize_move(card: MtMatchCard) -> void:
	# Comprehensive rules 6-5-5-4: given DON!! return to the cost area RESTED.
	var given := card.don_count()
	if given > 0:
		_P(card.owner).don_rested += given
		card.attached_don.clear()
	card.activated_this_turn = false
	card.granted_keywords.clear()
	for ps in players:
		for zone_arr in [ps.hand, ps.deck, ps.field, ps.trash, ps.life, ps.removed]:
			zone_arr.erase(card)
		if ps.leader == card:
			ps.leader = null
		if ps.stage == card:
			ps.stage = null

func _ko(card: MtMatchCard, source: MtMatchCard = null) -> void:
	if card == null or not _in_field(_P(card.owner), card):
		return
	var from_battle: bool = (not battle.is_empty()) and (battle.get("defender") == card or battle.get("target") == card)
	if _cannot_leave(card, from_battle, source):
		_log("%s cannot be removed from the field." % card.card_name())
		return
	if _card_protected(card, from_battle, source):
		_log("%s cannot be K.O.'d." % card.card_name())
		return
	if _try_replace_ko(card, from_battle):
		return
	_finish_ko(card)

func _finish_ko(card: MtMatchCard) -> void:
	var ps := _P(card.owner)
	card.rested = false
	if card.is_leader():
		_over_loss(card.owner, "0 Life")
		return
	_move_to_trash(ps, card)
	_log("%s is K.O.'d and placed in the owner's Trash." % card.card_name())
	if card.is_character():
		_fire_window(_P(_opp(card.owner)), "on_opp_char_ko", {"played": card}, null)
	var f := fx(card)
	for tok in f.get("on_ko", []):
		var ct := String(tok.get("cond_turn", ""))
		if ct == "opp_turn" and active == card.owner:
			continue
		if ct == "own_turn" and active != card.owner:
			continue
		_resolve_actions(card, tok.actions, {})

func _try_replace_ko(victim: MtMatchCard, from_battle: bool, from_leave: bool = false, finish: String = "ko") -> bool:
	var ps := _P(victim.owner)
	var sources: Array = []
	if victim:
		sources.append(victim)
	if ps.leader and ps.leader != victim:
		sources.append(ps.leader)
	for c in ps.field:
		if c != victim:
			sources.append(c)
	var specs: Array = []
	for src in sources:
		for spec in fx(src).get("replace_ko", []):
			specs.append({"src": src, "spec": spec})
	for spec in ps.ko_instead:
		if spec is Dictionary:
			specs.append({"src": victim, "spec": spec, "granted": true})
	for entry in specs:
		var src: MtMatchCard = entry.get("src")
		var spec = entry.get("spec")
		if not (spec is Dictionary):
			continue
		if bool(spec.get("once_per_turn", false)) and src != null and src.replace_ko_used:
			continue
		if bool(spec.get("this_card", false)) and not bool(entry.get("granted", false)) and src != victim:
			continue
		if from_leave:
			if not bool(spec.get("removed", false)):
				continue
		elif bool(spec.get("removed", false)):
			continue
		if int(spec.get("min_cost", 0)) > 0 and int(victim.card.get("cost", 0)) < int(spec.get("min_cost", 0)):
			continue
		if int(spec.get("max_cost", 0)) > 0 and int(victim.card.get("cost", 0)) > int(spec.get("max_cost", 0)):
			continue
		var frm := String(spec.get("from", "all"))
		if frm == "effects" and from_battle:
			continue
		if frm == "battle" and not from_battle:
			continue
		var pay: Array = spec.get("pay", [])
		var payer: MtMatchCard = src if src != null else victim
		if not _can_pay_acts(payer, pay):
			continue
		if not auto_resolve_choices:
			pending_choice = {
				"type": "replace_ko", "player": victim.owner, "victim_uid": victim.uid,
				"source_uid": payer.uid, "pay": pay, "max": 1, "up_to": true,
				"finish": finish,
			}
			_log("P%d may apply an instead replacement on %s." % [victim.owner, victim.card_name()])
			return true
		_pay_acts(payer, pay)
		if src != null:
			src.replace_ko_used = true
		_log("%s stays (replaced)." % victim.card_name())
		_effect_did = true
		return true
	return false

func _remove_from_game(ps: MtPlayerState, card: MtMatchCard) -> void:
	if _try_replace_ko(card, false, true, "remove"):
		return
	_commit_remove(ps, card)

func _commit_remove(ps: MtPlayerState, card: MtMatchCard) -> void:
	_finalize_move(card)
	card.zone = MtMatchCard.ZONE_REMOVED
	card.rested = false
	card.removed_forever = true
	ps.removed.append(card)

# --- Phases ---
func _begin_phase(p: int) -> void:
	phase = p
	if p == Phase.DON:
		var ps := _P(active)
		ps.reset_don_refresh()
		_clear_turn_bonuses()
		# DON!! Phase: +2 DON (only +1 on the very first turn of the game).
		var don_gain := 1 if turn == 1 else 2
		for i in range(don_gain):
			if ps.don_in_deck > 0 and ps.don_active < ps.don_deck_size:
				ps.don_in_deck -= 1
				ps.don_active += 1
		_log("--- Turn %d: P%d Don phase (DON active %d) ---" % [turn, active, ps.don_active])
		if _offer_start_of_turn():
			return
		_begin_phase(Phase.DRAW)
	elif p == Phase.DRAW:
		# First player skips draw on turn 1
		if not (turn == 1 and active == _first_player()):
			var card := draw_card(_P(active))
			if card:
				_log("P%d draws a card (hand %d)." % [active, _P(active).hand.size()])
		if not over:
			_begin_phase(Phase.MAIN)
	elif p == Phase.MAIN:
		_apply_turn_actions()
	elif p == Phase.END:
		_begin_phase(Phase.DON)

func _apply_turn_actions() -> void:
	for ps in players:
		var src: Array = []
		if ps.leader:
			src.append(ps.leader)
		src.append_array(ps.field)
		if ps.stage:
			src.append(ps.stage)
		for c in src:
			for ta in fx(c).get("turn_actions", []):
				var dur := String(ta.get("dur", ""))
				if dur == "own_turn" and active != c.owner:
					continue
				if dur == "opp_turn" and active == c.owner:
					continue
				_resolve_actions(c, ta.get("actions", []), {})
			if active != c.owner:
				for tok in fx(c).get("on_opp_turn", []):
					_resolve_actions(c, tok.get("actions", []), {})

func _first_player() -> int:
	return first_player_idx

func end_turn_current() -> void:
	if over:
		return
	_resolve_end_of_turn(_P(active))
	_resolve_delayed_deckout()
	if over:
		return
	_log("P%d ends the turn." % active)
	active = _opp(active)
	turn += 1
	_battle_clear()
	_begin_phase(Phase.DON)

func _resolve_delayed_deckout() -> void:
	for ps in players:
		if over:
			return
		if bool(ps.deckout_pending) or (ps.deck.is_empty() and bool(_leader_rules(ps).get("deckout_end_of_turn", false))):
			_over_loss(ps.index, "Deck empty at end of turn")

func _resolve_end_of_turn(ps: MtPlayerState) -> void:
	# "[End of Your Turn]" on the player whose turn is ending.
	var sources: Array = []
	if ps.leader != null:
		sources.append(ps.leader)
	sources.append_array(ps.field)
	if ps.stage != null:
		sources.append(ps.stage)
	for c in sources:
		for tok in fx(c).get("on_end", []):
			_resolve_actions(c, tok.get("actions", []), {})
	# "[End of Your Opponent's Turn]" on the other player's cards.
	var opp := _P(_opp(ps.index))
	var opp_src: Array = []
	if opp.leader != null:
		opp_src.append(opp.leader)
	opp_src.append_array(opp.field)
	if opp.stage != null:
		opp_src.append(opp.stage)
	for c in opp_src:
		for tok in fx(c).get("on_opp_end", []):
			_resolve_actions(c, tok.get("actions", []), {})
	_expire_bonuses("until_opp_end", _opp(ps.index))

func _clear_turn_bonuses() -> void:
	# Called at the start of the active player's DON/Refresh.
	# "during this turn" expires for everyone. "until the start of your next
	# turn" expires only for the player whose turn is starting.
	var keep: Array = []
	for entry in _turn_bonuses:
		var card: MtMatchCard = entry.card
		var dur := String(entry.get("dur", "turn"))
		var owner := int(entry.get("owner", -1))
		var expire := false
		if dur == "turn" or dur == "":
			expire = true
		elif dur == "until_own_next_turn" and owner == active:
			expire = true
		if expire:
			if is_instance_valid(card):
				_revert_bonus(card, entry)
		else:
			keep.append(entry)
	_turn_bonuses = keep
	for p in players:
		var pps := p as MtPlayerState
		pps.ko_instead.clear()
		pps.no_play_chars = false
		pps.no_play_hand = false
		pps.no_play_char_cost_gte = 0
		pps.hand_trashed_this_turn = false
		pps.hand_cost_mods.clear()
		pps.no_life_to_hand = false
	_expire_seals("turn")

func _expire_seals(dur: String) -> void:
	var keep: Array = []
	for seal in _block_seals:
		if String(seal.get("dur", "turn")) != dur:
			keep.append(seal)
	_block_seals = keep

func _seal_hits(atk: MtMatchCard, blk: MtMatchCard) -> bool:
	if blk == null:
		return false
	for seal in _block_seals:
		if String(seal.get("attacker_uid", "")) != "":
			if atk != null and atk.uid == String(seal.get("attacker_uid", "")):
				return true
			continue
		if int(seal.get("against", -1)) != blk.owner:
			continue
		if String(seal.get("uid", "")) != "":
			if blk.uid == String(seal.get("uid", "")):
				return true
			continue
		if _filter_matches(blk, seal, null):
			return true
	return false

func _apply_block_seal(source: MtMatchCard, spec: Dictionary, actions: Array, act_idx: int) -> void:
	var mode := String(spec.get("mode", "seal"))
	if mode == "on_attack":
		_begin_pick(source, "attack_no_block", spec, actions, act_idx)
		return
	if int(spec.get("number", 1)) <= 0:
		var seal := spec.duplicate()
		seal["against"] = _opp(source.owner)
		seal["by_owner"] = source.owner
		_block_seals.append(seal)
		return
	_begin_pick(source, "no_block", spec, actions, act_idx)

func _expire_bonuses(dur: String, owner: int) -> void:
	var keep: Array = []
	for entry in _turn_bonuses:
		if String(entry.get("dur", "")) == dur and int(entry.get("owner", -1)) == owner:
			var card: MtMatchCard = entry.card
			if is_instance_valid(card):
				_revert_bonus(card, entry)
		else:
			keep.append(entry)
	_turn_bonuses = keep

func _revert_bonus(card: MtMatchCard, entry: Dictionary) -> void:
	var kind := String(entry.get("kind", "power"))
	if kind == "cost":
		card.cost_bonus -= int(entry.get("amount", 0))
	elif kind == "protect":
		card.cannot_ko_effects = false
		card.cannot_ko_all = false
	elif kind == "swap":
		card.power_override = int(entry.get("prev", -1))
	elif kind == "negate":
		card.effects_negated = false
	elif kind == "no_attack":
		card.no_attack = false
	elif kind == "no_leave":
		card.cannot_leave_effects = false
	else:
		card.power_bonus -= int(entry.get("amount", 0))

func _offer_start_of_turn() -> bool:
	_start_turn_queue.clear()
	var ps := _P(active)
	var src: Array = []
	if ps.leader:
		src.append(ps.leader)
	src.append_array(ps.field)
	if ps.stage:
		src.append(ps.stage)
	for c in src:
		for tok in fx(c).get("on_start_turn", []):
			_start_turn_queue.append({"card": c, "tok": tok})
	if _start_turn_queue.is_empty():
		return false
	if auto_resolve_choices:
		_drain_start_of_turn()
		return pending_choice != null
	pending_choice = {
		"type": "start_turn", "player": active, "up_to": true, "max": 1,
		"source_uid": (_start_turn_queue[0].get("card") as MtMatchCard).uid,
	}
	return true

func _drain_start_of_turn() -> void:
	while not _start_turn_queue.is_empty() and pending_choice == null and not over:
		var q: Dictionary = _start_turn_queue.pop_front()
		var c: MtMatchCard = q.get("card")
		var tok: Dictionary = q.get("tok", {})
		if c == null:
			continue
		_log("P%d activates a start-of-turn effect on %s." % [c.owner, c.card_name()])
		_resolve_actions(c, tok.get("actions", []), {})

# --- Adjudicator: single entry point ---
func apply(action: Dictionary) -> Dictionary:
	var verdict := _legal(action)
	if not verdict.get("ok", false):
		return verdict
	match action.type:
		ACTION_END_TURN:
			end_turn_current()
			return _ok()
		ACTION_PLAY:
			return _do_play(action)
		ACTION_PLAY_EVENT:
			return _do_play_event(action)
		ACTION_ACTIVATE:
			return _do_activate(action)
		ACTION_ATTACH_DON:
			return _do_attach_don(action)
		ACTION_ATTACK:
			return _do_attack(action)
		ACTION_COUNTER:
			return _do_counter(action)
		ACTION_BLOCK:
			return _do_block(action)
		ACTION_PASS_BATTLE:
			return _do_pass_battle(action)
		ACTION_TRIGGER_YES:
			return _do_trigger_yes(action)
		ACTION_TRIGGER_NO:
			return _do_trigger_no(action)
		ACTION_MULLIGAN:
			return _do_mulligan(action)
		ACTION_KEEP_HAND:
			return _do_keep_hand(action)
		ACTION_CHOOSE_EFFECT:
			var r := _do_choose_effect(action)
			if pending_choice == null and phase == Phase.DON and not over:
				if not _start_turn_queue.is_empty():
					_drain_start_of_turn()
				else:
					_begin_phase(Phase.DRAW)
			return r
		ACTION_CANCEL_CHOICE:
			var cr := _do_cancel_choice(action)
			if pending_choice == null and phase == Phase.DON and not over:
				if not _start_turn_queue.is_empty():
					_drain_start_of_turn()
				else:
					_begin_phase(Phase.DRAW)
			return cr
	return {"ok": false, "code": "unknown_action", "msg": "Unknown action"}

func _ok() -> Dictionary:
	return {"ok": true, "code": "ok", "msg": ""}

func _reject(code: String, msg: String) -> Dictionary:
	return {"ok": false, "code": code, "msg": msg}

func _find_card_by_uid(who: int, uid: String) -> MtMatchCard:
	var ps := _P(who)
	for c in ps.all_zones_array():
		if c.uid == uid:
			return c
	for c in _limbo:
		if c.uid == uid:
			return c
	return null

# --- Legality ---
func _legal(action: Dictionary) -> Dictionary:
	if over:
		return _reject("game_over", "The match has ended.")
	if pending_choice != null:
		var ptype: String = pending_choice.get("type", "")
		var atype: String = String(action.get("type", ""))
		if ptype == "give_don" or ptype == "pick" or ptype == "replace_ko" or ptype == "opp_may" or ptype == "modal" or ptype == "look_order" or ptype == "start_turn" or ptype == "pay_optional" or ptype == "life_edge":
			if atype == ACTION_CANCEL_CHOICE:
				return _ok()
			if atype != ACTION_CHOOSE_EFFECT:
				return _reject("pending_choice", "Resolve the pending effect first.")
			return _legal_choose_effect(action)
		if ptype == "life_trigger":
			if atype == ACTION_CANCEL_CHOICE:
				return _ok()
			if atype != ACTION_TRIGGER_YES and atype != ACTION_TRIGGER_NO:
				return _reject("pending_choice", "Resolve the [Trigger] choice first.")
		elif ptype == "mulligan":
			if atype == ACTION_CANCEL_CHOICE:
				return _ok()
			if atype != ACTION_MULLIGAN and atype != ACTION_KEEP_HAND:
				return _reject("pending_choice", "Resolve the mulligan choice first.")
	match action.type:
		ACTION_END_TURN:
			if in_battle():
				return _reject("in_battle", "Resolve the battle first.")
			if phase != Phase.MAIN and phase != Phase.END:
				return _reject("wrong_phase", "Can only end the turn in Main/End.")
			return _ok()
		ACTION_PLAY:
			return _legal_play(action)
		ACTION_PLAY_EVENT:
			return _legal_play_event(action)
		ACTION_ACTIVATE:
			return _legal_activate(action)
		ACTION_ATTACH_DON:
			return _legal_attach_don(action)
		ACTION_ATTACK:
			return _legal_attack(action)
		ACTION_COUNTER:
			return _legal_counter(action)
		ACTION_BLOCK:
			return _legal_block(action)
		ACTION_PASS_BATTLE:
			if not in_battle():
				return _reject("no_battle", "No battle in progress.")
			return _ok()
		ACTION_TRIGGER_YES, ACTION_TRIGGER_NO:
			return _legal_trigger(action)
		ACTION_MULLIGAN, ACTION_KEEP_HAND:
			return _legal_mulligan(action)
		ACTION_CHOOSE_EFFECT:
			return _legal_choose_effect(action)
		ACTION_CANCEL_CHOICE:
			if pending_choice != null or in_battle():
				return _ok()
			return _reject("nothing_to_cancel", "Nothing to cancel.")
	return _reject("unknown_action", "Unknown action type.")

func _require_no_battle() -> Dictionary:
	if in_battle():
		return _reject("in_battle", "A battle is in progress.")
	if phase != Phase.MAIN:
		return _reject("wrong_phase", "Only during Main phase.")
	return _ok()

func _legal_play(action: Dictionary) -> Dictionary:
	var v := _require_no_battle()
	if not v.ok:
		return v
	var ps := _P(active)
	var card := _find_card_by_uid(active, action.get("card_uid", ""))
	if card == null or not card in ps.hand:
		return _reject("not_in_hand", "Card is not in hand.")
	if card.card_type() not in ["Character", "Stage"]:
		return _reject("bad_type", "Card is not playable as held.")
	var ban := _play_banned(ps, card)
	if not ban.ok:
		return ban
	if play_cost(card) > ps.get_available_don():
		return _reject("not_enough_don", "Not enough active DON to pay the cost.")
	if card.card_type() == "Character" and ps.field.size() >= 5:
		var trash_uid := String(action.get("trash_uid", ""))
		if trash_uid.is_empty() and not auto_resolve_choices:
			return _reject("overflow", "Choose a Character to trash to play a 6th.")
		if not trash_uid.is_empty():
			var vic := _find_card_by_uid(active, trash_uid)
			if vic == null or not vic in ps.field or not vic.is_character():
				return _reject("bad_overflow", "That Character is not in your Character Area.")
	return _color_check(card)

func play_cost(card: MtMatchCard) -> int:
	if card == null:
		return 0
	var n := card.cost_value()
	var hc: Dictionary = fx(card).get("hand_cost", {})
	if not hc.is_empty() and card.zone == MtMatchCard.ZONE_HAND:
		if _check_cond(card, {"cond": hc.get("cond", {})}):
			n += int(hc.get("amount", 0))
	var ps := _P(card.owner)
	var src: Array = []
	if ps.leader:
		src.append(ps.leader)
	src.append_array(ps.field)
	if ps.stage:
		src.append(ps.stage)
	for s in src:
		var aura: Dictionary = fx(s).get("hand_cost_aura", {})
		if aura.is_empty():
			continue
		if bool(aura.get("own_turn", false)) and active != s.owner:
			continue
		if _hand_mod_matches(card, aura):
			n += int(aura.get("amount", 0))
	for mod in ps.hand_cost_mods:
		if _hand_mod_matches(card, mod):
			n += int(mod.get("amount", 0))
	return maxi(0, n)

func _hand_mod_matches(card: MtMatchCard, mod: Dictionary) -> bool:
	var t := String(mod.get("card_type", ""))
	if t != "" and card.card_type() != t:
		return false
	var col := String(mod.get("color", ""))
	if col != "" and not card.colors().has(col):
		return false
	var type_name := String(mod.get("trait", ""))
	if type_name != "" and not _trait_has(card, type_name):
		return false
	if mod.has("cost_gte") and int(card.card.get("cost", 0)) < int(mod.get("cost_gte", 0)):
		return false
	return true

func _play_banned(ps: MtPlayerState, card: MtMatchCard) -> Dictionary:
	if ps.no_play_hand:
		return _reject("no_play", "You cannot play cards from your hand this turn.")
	if card.is_character():
		if ps.no_play_chars:
			return _reject("no_play", "You cannot play Character cards this turn.")
		var printed := int(card.card.get("cost", 0))
		if ps.no_play_char_cost_gte > 0 and printed >= ps.no_play_char_cost_gte:
			return _reject("no_play", "You cannot play Character cards of that base cost this turn.")
	return _ok()

func _apply_no_play(ps: MtPlayerState, opts: Dictionary) -> void:
	var scope := String(opts.get("scope", "chars"))
	if scope == "hand":
		ps.no_play_hand = true
	elif scope == "char_cost":
		ps.no_play_char_cost_gte = int(opts.get("n", 0))
	else:
		ps.no_play_chars = true
	_log("P%d cannot play %s this turn." % [ps.index, scope])

func _notify_character_played(ps: MtPlayerState, card: MtMatchCard) -> void:
	if card == null or not card.is_character():
		return
	_fire_window(ps, "on_you_play", {"played": card}, card)
	_fire_window(_P(_opp(ps.index)), "on_opp_play", {"played": card}, null)

func _fire_window(ps: MtPlayerState, key: String, ctx: Dictionary = {}, skip: MtMatchCard = null) -> void:
	_cond_ctx = ctx
	var src: Array = []
	if ps.leader:
		src.append(ps.leader)
	src.append_array(ps.field)
	if ps.stage:
		src.append(ps.stage)
	for c in src:
		if c == skip:
			continue
		for tok in fx(c).get(key, []):
			if bool(ctx.get("triggers_only", false)) and not bool(tok.get("also_trigger", false)):
				continue
			var ct := String(tok.get("cond_turn", ""))
			if ct == "own_turn" and active != c.owner:
				continue
			if ct == "opp_turn" and active == c.owner:
				continue
			if bool(tok.get("once_per_turn", false)) and bool(c.window_once.get(key, false)):
				continue
			if int(tok.get("don_min", 0)) > 0 and c.don_count() < int(tok.get("don_min", 0)):
				continue
			if bool(tok.get("once_per_turn", false)):
				c.window_once[key] = true
			_resolve_actions(c, tok.get("actions", []), {})
	_cond_ctx = {}

func _note_rested(card: MtMatchCard) -> void:
	if card == null:
		return
	for tok in fx(card).get("on_self_rest", []):
		_resolve_actions(card, tok.get("actions", []), {})

func _grant_kw(card: MtMatchCard, opts: Dictionary) -> void:
	var kw := String(opts.get("kw", "")).strip_edges()
	if kw == "":
		return
	var who := String(opts.get("who", "self"))
	var targets: Array = []
	if who == "all_self":
		var ps := _P(card.owner)
		if ps.leader:
			targets.append(ps.leader)
		targets.append_array(ps.field)
	elif who == "self_char":
		var best: MtMatchCard = null
		var types = opts.get("by_types", [])
		for c in _P(card.owner).field:
			if types is Array and not (types as Array).is_empty():
				var hit := false
				for t in types:
					if _trait_has(c, String(t)):
						hit = true
						break
				if not hit:
					continue
			if best == null or c.base_power() > best.base_power():
				best = c
		if best:
			targets.append(best)
	else:
		targets.append(card)
	for t in targets:
		if t == null:
			continue
		if not t.granted_keywords.has(kw):
			t.granted_keywords.append(kw)
			_log("%s gains [%s] during this turn." % [t.card_name(), kw])

func _cannot_leave(card: MtMatchCard, from_battle: bool, source: MtMatchCard) -> bool:
	if from_battle:
		return false
	if card.cannot_leave_effects:
		return true
	if not fx(card).get("no_remove_fx", []).is_empty():
		return true
	var actor := source.owner if source != null else active
	if actor == card.owner:
		return false
	for c in _board_cards(_P(actor)):
		if bool(fx(c).get("lock_opp_chars", false)):
			return true
	return false

func _board_cards(ps: MtPlayerState) -> Array:
	var src: Array = []
	if ps.leader:
		src.append(ps.leader)
	src.append_array(ps.field)
	if ps.stage:
		src.append(ps.stage)
	return src

func _color_check(card: MtMatchCard) -> Dictionary:
	var colors := card.colors()
	var ps := _P(active)
	for col in colors:
		var present := false
		if ps.leader != null and String(ps.leader.card.get("color", "")).split("/", false).has(col):
			present = true
		if not present:
			for c in ps.field:
				if String(c.card.get("color", "")).split("/", false).has(col):
					present = true
					break
		if not present and ps.stage != null and String(ps.stage.card.get("color", "")).split("/", false).has(col):
			present = true
		if not present:
			return _reject("color_mismatch", "You need a %s card in play to play this." % col)
	return _ok()

func _legal_play_event(action: Dictionary) -> Dictionary:
	var v := _require_no_battle()
	if not v.ok:
		return v
	var ps := _P(active)
	var card := _find_card_by_uid(active, action.get("card_uid", ""))
	if card == null or not card in ps.hand or card.card_type() != "Event":
		return _reject("not_in_hand", "Event card is not in hand.")
	var f := fx(card)
	if f.get("on_main", []).is_empty():
		return _reject("no_main_effect", "This Event has no Main effect to activate.")
	var ban := _play_banned(ps, card)
	if not ban.ok:
		return ban
	if play_cost(card) > ps.get_available_don():
		return _reject("not_enough_don", "Not enough active DON.")
	return _color_check(card)

func _legal_activate(action: Dictionary) -> Dictionary:
	var v := _require_no_battle()
	if not v.ok:
		return v
	var card := _find_card_by_uid(active, action.get("card_uid", ""))
	if card == null or not _in_field(_P(active), card):
		return _reject("not_in_field", "Card is not in play.")
	if card.is_event():
		return _reject("bad_type", "Events are played from hand, not activated on the field.")
	var f := fx(card)
	if f.get("activate_main", []).is_empty():
		if not f.get("on_play", []).is_empty():
			return _reject("on_play_only", "%s has an [On Play] effect, resolved when it is played." % card.card_name())
		return _reject("no_effect", "This card has no [Activate: Main] effect.")
	if _activate_is_once(card) and card.activated_this_turn:
		return _reject("once_per_turn", "[Once Per Turn] already used.")
	if _activate_is_once_game(card) and card.activated_this_game:
		return _reject("once_per_game", "[Once Per Game] already used.")
	if _activate_needs_rest(card) and card.rested:
		return _reject("rested", "[Activate: Main] requires you to rest this card.")
	return _ok()

func _activate_is_once(card: MtMatchCard) -> bool:
	for tok in fx(card).get("activate_main", []):
		if bool(tok.get("once_per_turn", false)):
			return true
	return false

func _activate_is_once_game(card: MtMatchCard) -> bool:
	for tok in fx(card).get("activate_main", []):
		if bool(tok.get("once_per_game", false)):
			return true
	return false

func _activate_needs_rest(card: MtMatchCard) -> bool:
	for tok in fx(card).get("activate_main", []):
		if bool(tok.get("rest_cost", false)):
			return true
	return false

func _legal_attach_don(action: Dictionary) -> Dictionary:
	var v := _require_no_battle()
	if not v.ok:
		return v
	var ps := _P(active)
	if ps.get_available_don() <= 0:
		return _reject("no_free_don", "No un-rested DON available to attach.")
	var target := _find_card_by_uid(active, action.get("card_uid", ""))
	if target == null or not _in_field(ps, target) or (not target.is_leader() and not target.is_character()):
		return _reject("bad_target", "DON can only attach to your Leader or Characters.")
	return _ok()

func _legal_attack(action: Dictionary) -> Dictionary:
	if in_battle():
		return _reject("in_battle", "A battle is in progress.")
	if phase != Phase.MAIN:
		return _reject("wrong_phase", "Attacks happen in the Main phase.")
	# Official: the player who goes first cannot attack on their first turn.
	if turn == 1 and active == first_player_idx:
		return _reject("first_turn", "The first player cannot attack on their first turn.")
	var atk := _find_card_by_uid(active, action.get("attacker", ""))
	if atk == null or not _in_field(_P(active), atk) or (not atk.is_leader() and not atk.is_character()):
		return _reject("bad_attacker", "Only your Active Leader or Character can attack.")
	if atk.rested:
		if not (has_keyword(atk, "Double Attack") and atk.attacked_count >= 1 and atk.attacked_count < 2):
			return _reject("rested", "Rested cards cannot declare an attack.")
	if atk.attacked_count >= (2 if has_keyword(atk, "Double Attack") else 1):
		return _reject("no_attacks_left", "This card has no attacks left.")
	if _cannot_attack(atk):
		return _reject("cannot_attack", "This card cannot attack.")
	if atk.is_character() and atk.played_this_turn_value() and not can_attack_turn_played(atk):
		return _reject("just_played", "A Character cannot attack the turn it is played unless it has [Rush].")
	var tgt := _find_card_by_uid(_opp(active), action.get("target", ""))
	if tgt == null:
		return _reject("bad_target", "Target not found.")
	if tgt.owner == active:
		return _reject("own_card", "You cannot attack your own cards.")
	if tgt.is_stage() or tgt.is_event() or tgt.is_don():
		return _reject("bad_target", "You can only attack a Leader or Character.")
	if tgt.is_character():
		var ops := _P(_opp(active))
		if not tgt in ops.field:
			return _reject("target_not_field", "Target character is not in play.")
		if not tgt.rested and not _can_attack_active(atk):
			return _reject("target_not_rested", "You can only attack rested Characters or the Leader.")
		var must2 := _must_attack_name(_P(_opp(active)))
		if must2 != "" and not tgt.card_name().contains(must2):
			return _reject("must_attack", "You can only attack [%s]." % must2)
		return _ok()
	if tgt.is_leader():
		if atk.played_this_turn_value() and has_keyword(atk, "Rush: Character") and not has_keyword(atk, "Rush"):
			return _reject("rush_character", "[Rush: Character] can attack Characters the turn it is played, not the Leader.")
		var must := _must_attack_name(_P(_opp(active)))
		if must != "" and not tgt.card_name().contains(must):
			return _reject("must_attack", "You can only attack [%s]." % must)
		return _ok()
	return _reject("bad_target", "Target must be a Leader or Character.")

func _can_attack_active(atk: MtMatchCard) -> bool:
	if atk == null:
		return false
	if atk.granted_keywords.has("attack_active"):
		return true
	var need := int(fx(atk).get("can_attack_active_don", 0))
	if bool(fx(atk).get("can_attack_active", false)) and atk.don_count() >= need:
		return true
	return false

func _cannot_attack(card: MtMatchCard) -> bool:
	if card == null:
		return false
	if card.no_attack:
		return true
	for spec in fx(card).get("cannot_attack_fx", []):
		if not (spec is Dictionary):
			continue
		if not _cannot_attack_unless_met(card, spec):
			return true
	return false

func _cannot_attack_unless_met(card: MtMatchCard, spec: Dictionary) -> bool:
	var kind := String(spec.get("unless", ""))
	if kind == "":
		return false
	var need := int(spec.get("power_gte", 0))
	if kind == "opp_chars":
		var n := 0
		for c in _P(_opp(card.owner)).field:
			if (c as MtMatchCard).base_power() >= need:
				n += 1
		return n >= int(spec.get("opp_chars_gte", 1))
	if kind == "any_char":
		for p in players:
			for c in (p as MtPlayerState).field:
				if (c as MtMatchCard).base_power() >= need:
					return true
		return false
	return true

func _legal_counter(action: Dictionary) -> Dictionary:
	if not in_battle():
		return _reject("no_battle", "No battle in progress.")
	var who := battle.get("defender_owner", -1)
	var card := _find_card_by_uid(who, action.get("card_uid", ""))
	if card == null or not card in _P(who).hand:
		return _reject("not_in_hand", "Counter card is not in hand.")
	if counter_for(card) <= 0 and not _has_counter_effect(card):
		return _reject("no_counter", "That card has no Counter value and no [Counter] effect.")
	if card.is_leader() or card.is_don():
		return _reject("no_counter", "Leaders and DON!! cannot be used as Counter.")
	return _ok()

func _has_counter_effect(card: MtMatchCard) -> bool:
	return not (fx(card).get("counter", []) as Array).is_empty()

## Public wrapper for UI (TestBoard) to check counter eligibility.
func has_counter_effect(card: MtMatchCard) -> bool:
	return _has_counter_effect(card)

func _legal_block(action: Dictionary) -> Dictionary:
	if not in_battle():
		return _reject("no_battle", "No battle in progress.")
	if battle.get("step", "") != "block":
		return _reject("wrong_step", "Not the blocker window.")
	var who := battle.get("defender_owner", -1)
	var ps := _P(who)
	var blk := _find_card_by_uid(who, action.get("blocker", ""))
	if blk == null or not blk in ps.field:
		return _reject("bad_blocker", "Blocker is not in your field.")
	if not has_keyword(blk, "Blocker"):
		return _reject("not_blocker", "Card does not have [Blocker].")
	if blk.rested:
		return _reject("rested", "Blocker is already rested.")
	var atk: MtMatchCard = battle.get("attacker", null)
	if _attack_cannot_be_blocked(atk):
		return _reject("cannot_block", "This attack cannot be blocked.")
	if atk:
		var nbd: int = fx(atk).get("no_block_with_don", 0)
		if nbd > 0 and atk.don_count() >= nbd:
			return _reject("cannot_block", "This attack cannot be blocked.")
		if _seal_hits(atk, blk):
			return _reject("cannot_block", "This attack cannot be blocked.")
	return _ok()

# --- Action execution ---
func _pay_cost(ps: MtPlayerState, cost: int) -> void:
	if cost > 0:
		ps.don_rested += cost

func _do_play(action: Dictionary) -> Dictionary:
	var ps := _P(active)
	var card := _find_card_by_uid(active, action.get("card_uid", ""))
	var paid := play_cost(card)
	ps.hand.erase(card)
	_pay_cost(ps, paid)
	if card.is_stage() and ps.stage != null:
		_log("%s is placed in the Trash (replaced Stage)." % ps.stage.card_name())
		_move_to_trash(ps, ps.stage)
	if card.is_character() and ps.field.size() >= 5:
		var victim: MtMatchCard = null
		var trash_uid := String(action.get("trash_uid", ""))
		if not trash_uid.is_empty():
			victim = _find_card_by_uid(active, trash_uid)
		if victim == null:
			victim = _overflow_victim(ps)
		if victim != null:
			_log("%s is placed in the Trash (Character Area overflow)." % victim.card_name())
			_move_to_trash(ps, victim)
	card.mark_played(turn)
	if card.is_stage():
		card.zone = MtMatchCard.ZONE_STAGE
		ps.stage = card
	else:
		card.zone = MtMatchCard.ZONE_FIELD
		ps.field.append(card)
	_after_enter(ps, card)
	_rule_process()
	return _ok()

func _overflow_victim(ps: MtPlayerState) -> MtMatchCard:
	if ps.field.is_empty():
		return null
	var best: MtMatchCard = ps.field[0]
	for c in ps.field:
		if c.base_power() < best.base_power():
			best = c
	return best

func _after_enter(_ps: MtPlayerState, card: MtMatchCard) -> void:
	_log("P%d plays %s (cost %d)." % [active, card.card_name(), card.cost_value()])
	var f := fx(card)
	for tok in f.get("on_play", []):
		_resolve_actions(card, tok.actions, {})
	_notify_character_played(_ps, card)

func _do_play_event(action: Dictionary) -> Dictionary:
	var ps := _P(active)
	var card := _find_card_by_uid(active, action.get("card_uid", ""))
	var paid := play_cost(card)
	ps.hand.erase(card)
	_pay_cost(ps, paid)
	_log("P%d activates Event %s." % [active, card.card_name()])
	var f := fx(card)
	var used_main := false
	for tok in f.get("on_main", []):
		used_main = true
		_resolve_actions(card, tok.actions, {})
	if not used_main:
		for tok in f.get("triggers", []):
			_resolve_actions(card, tok.actions, {})
	_fire_window(ps, "on_you_event", {"played": card}, card)
	_fire_window(_P(_opp(ps.index)), "on_opp_event", {"played": card}, null)
	_move_to_trash(ps, card)
	return _ok()

func _do_activate(action: Dictionary) -> Dictionary:
	var card := _find_card_by_uid(active, action.get("card_uid", ""))
	_log("P%d activates [Activate: Main] on %s." % [active, card.card_name()])
	var f := fx(card)
	for tok in f.get("activate_main", []):
		if tok.get("rest_cost", false):
			card.rested = true
			_note_rested(card)
		_resolve_actions(card, tok.actions, {})
	if _activate_is_once(card):
		card.activated_this_turn = true
	if _activate_is_once_game(card):
		card.activated_this_game = true
	return _ok()

func _do_attach_don(action: Dictionary) -> Dictionary:
	# Comprehensive rules 6-5-5: give 1 active DON!! from the cost area.
	var target := _find_card_by_uid(active, action.get("card_uid", ""))
	_perform_give_don(_P(active), target, 1, "active")
	return _ok()

func _mk_don_matchcard(owner: int) -> MtMatchCard:
	var don_dict := {
		"type": "DON!!", "name": "Don!!", "card_code": "DON-001",
		"color": "", "cost": 0, "power": 0, "counter": 0,
		"effect": "", "trigger": "", "rarity": "Promo",
	}
	return _mk(don_dict, owner, MtMatchCard.ZONE_DON)

func _do_attack(action: Dictionary) -> Dictionary:
	var atk := _find_card_by_uid(active, action.get("attacker", ""))
	var tgt := _find_card_by_uid(_opp(active), action.get("target", ""))
	atk.rested = true
	atk.attacked_count += 1
	_note_rested(atk)
	var first_step := "block"
	if _attack_cannot_be_blocked(atk):
		first_step = "counter"
	battle = {
		"attacker": atk,
		"target": tgt,
		"defender": tgt,
		"defender_owner": _opp(active),
		"step": first_step,
		"counter_bonus": 0,
	}
	_log("P%d attacks with %s (%d) targeting %s (%d)." % [
		active, atk.card_name(), card_power(atk), tgt.card_name(), card_power(tgt)])
	var afx := fx(atk)
	for tok in afx.get("on_attack", []):
		if int(tok.get("don_min", 0)) > 0 and atk.don_count() < int(tok.get("don_min", 0)):
			continue
		if String(tok.get("cond_turn", "")) == "opp_turn" and active == atk.owner:
			continue
		var want := String(tok.get("attack_target", ""))
		if want == "leader" and (tgt == null or not tgt.is_leader()):
			continue
		if want == "character" and (tgt == null or not tgt.is_character()):
			continue
		_resolve_actions(atk, tok.get("actions", []), {})
	var ops := _P(_opp(active))
	var opp_src: Array = []
	if ops.leader != null:
		opp_src.append(ops.leader)
	opp_src.append_array(ops.field)
	for c in opp_src:
		for tok in fx(c).get("on_opp_attack", []):
			_resolve_actions(c, tok.get("actions", []), {})
	_advance_battle_auto()
	return _ok()

func _do_counter(action: Dictionary) -> Dictionary:
	var who := battle.get("defender_owner", -1)
	var card := _find_card_by_uid(who, action.get("card_uid", ""))
	var ps := _P(who)
	ps.hand.erase(card)
	var value := counter_for(card)
	if card.is_event():
		var effect_bonus := _counter_event_bonus(card)
		if effect_bonus > 0:
			value = effect_bonus
		for tok in fx(card).get("counter", []):
			_resolve_actions(card, tok.get("actions", []), {"counter_host": battle.get("defender")})
		for spec in fx(card).get("replace_ko", []):
			if spec is Dictionary:
				ps.ko_instead.append((spec as Dictionary).duplicate(true))
	battle.counter_bonus = battle.get("counter_bonus", 0) + value
	_move_to_trash(ps, card)
	_log("P%d counters for +%d." % [who, value])
	return _ok()

func _counter_event_bonus(card: MtMatchCard) -> int:
	var total := 0
	for act in _effect_flat_actions(card):
		if act[0] == MtEffectParser.TOK_POWER:
			var popts: Dictionary = act[1]
			total += popts.get("amount", 0)
	return total

func _effect_flat_actions(card: MtMatchCard) -> Array:
	# Flatten the parsed effect tokens to a simple action list (used by counters).
	var f := fx(card)
	var out: Array = []
	for key in ["on_main", "on_play", "triggers", "on_attack", "on_ko", "on_block", "on_opp_attack", "activate_main", "counter"]:
		for tok in f.get(key, []):
			if tok is Dictionary and tok.has("actions"):
				out.append_array(tok.actions)
	return out

func _do_block(action: Dictionary) -> Dictionary:
	var who := battle.get("defender_owner", -1)
	var _ps := _P(who)
	var blk := _find_card_by_uid(who, action.get("blocker", ""))
	blk.rested = true
	_note_rested(blk)
	battle["defender"] = blk
	battle["counter_bonus"] = 0
	_log("P%d declares %s as blocker." % [who, blk.card_name()])
	_check_win_on_block()
	if over:
		return _ok()
	var atk: MtMatchCard = battle.get("attacker")
	if atk != null:
		_fire_window(_P(atk.owner), "on_opp_block", {"played": blk}, null)
	for tok in fx(blk).get("on_block", []):
		if int(tok.get("don_min", 0)) > 0 and blk.don_count() < int(tok.get("don_min", 0)):
			continue
		_resolve_actions(blk, tok.get("actions", []), {})
	battle.step = "counter"
	_advance_battle_auto()
	return _ok()

func _do_pass_battle(_action: Dictionary) -> Dictionary:
	battle.step = _next_battle_step(battle.get("step", "resolve"))
	_advance_battle_auto()
	return _ok()

func _advance_battle_auto() -> void:
	# Skip empty windows: if the defender has no legal counter/block, pass for them.
	while not battle.is_empty():
		var step: String = battle.get("step", "resolve")
		if step == "resolve":
			_resolve_battle()
			return
		var defender := _P(battle.defender_owner)
		var has_option := false
		if step == "block":
			has_option = _defender_has_blocker(defender)
		elif step == "counter" or step == "counter2":
			has_option = _defender_has_counter(defender)
		if has_option:
			return
		battle.step = _next_battle_step(step)

func _next_battle_step(step: String) -> String:
	match step:
		"block":
			return "counter"
		"counter", "counter2":
			return "resolve"
	return "resolve"

func _defender_has_counter(defender: MtPlayerState) -> bool:
	for c in defender.hand:
		if counter_for(c) > 0 or _has_counter_effect(c):
			return true
	return false

func _defender_has_blocker(defender: MtPlayerState) -> bool:
	var atk: MtMatchCard = battle.get("attacker", null)
	if _attack_cannot_be_blocked(atk):
		return false
	var nbd := 0
	if atk:
		nbd = fx(atk).get("no_block_with_don", 0)
	for c in defender.field:
		if has_keyword(c, "Blocker") and not c.rested:
			if nbd > 0 and atk and atk.don_count() >= nbd:
				continue
			if _seal_hits(atk, c):
				continue
			return true
	return false

func _resolve_battle() -> void:
	var atk: MtMatchCard = battle.attacker
	var def: MtMatchCard = battle.defender
	var def_owner: int = battle.defender_owner
	var a_power := card_power(atk)
	var d_power = card_power(def) + int(battle.get("counter_bonus", 0))
	var success = a_power >= d_power
	_log("Battle resolve: %s %d vs %s %d -> %s" % [atk.card_name(), a_power, def.card_name(), d_power, "damage" if success else "no damage"])
	if success:
		if def.is_character():
			var duid := def.uid
			_ko(def, atk)
			if pending_choice == null:
				var d2 := _find_any_uid(duid)
				if d2 != null and d2.zone == MtMatchCard.ZONE_TRASH:
					_resolve_actions(atk, fx(atk).get("on_battle_ko", []), {})
		elif def.is_leader():
			var hits := 2 if has_keyword(atk, "Double Attack") else 1
			for _i in range(hits):
				_deal_leader_damage(_P(def_owner), atk)
	_battle_clear()

func _battle_clear() -> void:
	_expire_bonuses("battle", active)
	_expire_bonuses("battle", _opp(active))
	_expire_seals("battle")
	battle.clear()

func _deal_leader_damage(ps: MtPlayerState, source: MtMatchCard) -> void:
	# Official Life: last index is the top. Only Leader damage may activate
	# [Trigger]. You may reveal and activate [Trigger] INSTEAD of adding the
	# card to your hand. Declining adds it to hand without revealing.
	if ps.life.is_empty():
		_over_loss(ps.index, "Leader damage with no Life cards")
		return
	var life_card: MtMatchCard = ps.life.pop_back()
	_fire_window(ps, "on_take_damage")
	_fire_window(ps, "on_life_removed", {"life_owner": ps.index})
	_fire_window(_P(_opp(ps.index)), "on_life_removed", {"life_owner": ps.index})
	if ps.life.is_empty():
		_fire_window(ps, "on_life_zero")
	if source != null:
		for tok in fx(source).get("on_life_damage", []):
			_resolve_actions(source, tok.get("actions", []), {})
	var was_faceup := not life_card.face_down
	if was_faceup and _leader_rules(ps).get("faceup_life_to_deck", false):
		life_card.face_down = true
		life_card.zone = MtMatchCard.ZONE_DECK
		ps.deck.push_back(life_card)
		_log("P%d's face-up Life card goes to the bottom of the deck (leader rule)." % ps.index)
		return
	if source != null and has_keyword(source, "Banish"):
		life_card.face_down = false
		_move_to_trash(ps, life_card)
		_log("P%d's Leader takes damage. %s is placed in the Trash ([Banish], no [Trigger])." % [
			ps.index, life_card.card_name()])
		return
	if not _has_life_trigger(life_card):
		life_card.face_down = false
		life_card.zone = MtMatchCard.ZONE_HAND
		ps.hand.append(life_card)
		_log("P%d's Leader takes damage. A Life card is added to their hand." % ps.index)
		return
	# Limbo: no area while deciding / resolving Trigger (CR 10-1-5-3).
	life_card.zone = ""
	_limbo.append(life_card)
	if auto_resolve_choices:
		_activate_life_trigger(ps, life_card)
		return
	pending_choice = {"type": "life_trigger", "player": ps.index, "card_uid": life_card.uid, "limbo": true}
	_log("P%d may activate [Trigger] on the damaged Life card (trigger_yes/trigger_no)." % ps.index)

func _has_life_trigger(card: MtMatchCard) -> bool:
	var f := fx(card)
	if f.get("play_self_on_trigger", false):
		return true
	if f.get("rerun_main_on_trigger", false) or f.get("rerun_counter_on_trigger", false) \
			or f.get("rerun_on_play_on_trigger", false):
		return true
	return not (f.get("triggers", []) as Array).is_empty()

func _resolve_life_trigger(ps: MtPlayerState, life_card: MtMatchCard) -> void:
	_activate_life_trigger(ps, life_card)

func _activate_life_trigger(ps: MtPlayerState, life_card: MtMatchCard) -> void:
	life_card.face_down = false
	_log("P%d activates %s's [Trigger]." % [ps.index, life_card.card_name()])
	var f := fx(life_card)
	if f.get("play_self_on_trigger", false):
		for tok in f.get("triggers", []):
			_resolve_actions(life_card, tok.get("actions", []), {})
		if not _check_cond(life_card, {"cond": f.get("trigger_cond", {})}):
			_limbo.erase(life_card)
			_move_to_trash(ps, life_card)
			return
		var paid_ok := true
		for tok2 in f.get("triggers", []):
			for a in tok2.get("actions", []):
				if a is Array and String(a[0]) == MtEffectParser.TOK_PAY and not _effect_did:
					paid_ok = false
		if not paid_ok:
			_limbo.erase(life_card)
			_move_to_trash(ps, life_card)
			return
		_limbo.erase(life_card)
		_play_self_from_trigger(ps, life_card)
		_fire_window(_P(_opp(ps.index)), "on_opp_event", {"triggers_only": true}, null)
		return
	if f.get("rerun_main_on_trigger", false):
		for tok in f.get("on_main", []):
			_resolve_actions(life_card, tok.actions, {})
		_fire_window(_P(_opp(ps.index)), "on_opp_event", {"triggers_only": true}, null)
	elif f.get("rerun_counter_on_trigger", false):
		for tok in f.get("counter", []):
			_resolve_actions(life_card, tok.actions, {})
		_fire_window(_P(_opp(ps.index)), "on_opp_event", {"triggers_only": true}, null)
	elif f.get("rerun_on_play_on_trigger", false):
		for tok in f.get("on_play", []):
			_resolve_actions(life_card, tok.actions, {})
		_fire_window(_P(_opp(ps.index)), "on_opp_event", {"triggers_only": true}, null)
	else:
		for tok in f.get("triggers", []):
			_resolve_actions(life_card, tok.actions, {})
		_fire_window(_P(_opp(ps.index)), "on_opp_event", {"triggers_only": true}, null)
	# After Trigger, trash unless the effect placed the card elsewhere.
	if life_card in _limbo or life_card.zone == "":
		_limbo.erase(life_card)
		_move_to_trash(ps, life_card)
		_log("%s is placed in the Trash after [Trigger]." % life_card.card_name())

func _legal_trigger(action: Dictionary) -> Dictionary:
	if pending_choice == null or pending_choice.get("type", "") != "life_trigger":
		return _reject("no_choice", "No trigger choice is pending.")
	if int(action.get("player", pending_choice.get("player", -1))) != int(pending_choice.get("player", -1)):
		return _reject("wrong_player", "That choice belongs to the other player.")
	if String(action.get("card_uid", pending_choice.get("card_uid", ""))) != String(pending_choice.get("card_uid", "")):
		return _reject("wrong_card", "That choice is for a different card.")
	return _ok()

func _do_trigger_yes(action: Dictionary) -> Dictionary:
	var ps := _P(int(pending_choice.get("player", 0)))
	var card := _find_card_by_uid(ps.index, String(action.get("card_uid", "")))
	pending_choice = null
	if card == null:
		return _reject("card_gone", "The trigger card is gone.")
	_activate_life_trigger(ps, card)
	return _ok()

func _do_trigger_no(_action: Dictionary) -> Dictionary:
	var ps := _P(int(pending_choice.get("player", 0)))
	var card := _find_card_by_uid(ps.index, String(pending_choice.get("card_uid", "")))
	pending_choice = null
	_log("P%d declines the [Trigger]." % ps.index)
	if card != null:
		_limbo.erase(card)
		card.face_down = false
		card.zone = MtMatchCard.ZONE_HAND
		ps.hand.append(card)
	return _ok()

# --- Mulligan rule ---
func _legal_mulligan(action: Dictionary) -> Dictionary:
	if pending_choice == null or pending_choice.get("type", "") != "mulligan":
		return _reject("no_mulligan", "No mulligan choice is pending.")
	var m_player: int = int(pending_choice.get("player", -1))
	if int(action.get("player", m_player)) != m_player:
		return _reject("wrong_player", "That mulligan choice belongs to the other player.")
	return _ok()

func _do_mulligan(_action: Dictionary) -> Dictionary:
	var p_idx := int(pending_choice.get("player", 0))
	var ps := _P(p_idx)
	while not ps.hand.is_empty():
		var c: MtMatchCard = ps.hand.pop_back()
		c.zone = MtMatchCard.ZONE_DECK
		ps.deck.append(c)
	_shuffle(ps.deck)
	for i in range(HAND_SIZE):
		var card: MtMatchCard = ps.deck.pop_front()
		card.zone = MtMatchCard.ZONE_HAND
		ps.hand.append(card)
	_log("P%d took a Mulligan (shuffled hand into deck and redrew %d cards)." % [p_idx, HAND_SIZE])
	mulligan_done[p_idx] = true
	_advance_mulligan(p_idx)
	return _ok()

func _do_keep_hand(_action: Dictionary) -> Dictionary:
	var p_idx := int(pending_choice.get("player", 0))
	_log("P%d kept opening hand." % p_idx)
	mulligan_done[p_idx] = true
	_advance_mulligan(p_idx)
	return _ok()

func _advance_mulligan(last_player: int) -> void:
	var next_player := _opp(last_player)
	if not mulligan_done[next_player]:
		pending_choice = {"type": "mulligan", "player": next_player}
		_log("P%d may mulligan or keep hand." % next_player)
	else:
		pending_choice = null
		_begin_phase(Phase.DON)

# --- Life manipulation hooks (leader/effect rule-changers) ---
# Life is an ordered pile; index 0 = bottom, last = top (damage takes top).
# Moving cards here never fires Triggers (only damage does).

func deck_to_life(ps: MtPlayerState, n: int, face_down: bool = true) -> int:
	var moved := 0
	for i in range(n):
		if ps.deck.is_empty():
			break
		var c: MtMatchCard = ps.deck.pop_front()
		c.zone = MtMatchCard.ZONE_LIFE
		c.face_down = face_down
		ps.life.append(c)
		moved += 1
	if moved > 0:
		_log("P%d adds %d card(s) to Life (%s)." % [ps.index, moved, "face-down" if face_down else "face-up"])
	if ps.deck.is_empty():
		_on_deck_empty(ps, false)
	return moved

func life_to_trash(ps: MtPlayerState, n: int) -> int:
	var moved := 0
	for i in range(n):
		if ps.life.is_empty():
			break
		var c: MtMatchCard = ps.life.pop_back()
		c.zone = MtMatchCard.ZONE_TRASH
		c.face_down = false
		ps.trash.append(c)
		moved += 1
	if moved > 0:
		_log("P%d trashes %d card(s) from Life." % [ps.index, moved])
	return moved

func life_set_face(ps: MtPlayerState, idx: int, down: bool) -> bool:
	if idx < 0 or idx >= ps.life.size():
		return false
	(ps.life[idx] as MtMatchCard).face_down = down
	return true

func life_reorder(ps: MtPlayerState, order: Array) -> bool:
	if order.size() != ps.life.size():
		return false
	var seen := {}
	for i in order:
		var ii := int(i)
		if ii < 0 or ii >= ps.life.size() or seen.has(ii):
			return false
		seen[ii] = true
	var next: Array = []
	for i in order:
		next.append(ps.life[int(i)])
	ps.life = next
	_log("P%d reorders their Life." % ps.index)
	return true

func life_trash_faceup(ps: MtPlayerState) -> int:
	var moved := 0
	for i in range(ps.life.size() - 1, -1, -1):
		var c: MtMatchCard = ps.life[i]
		if not c.face_down:
			ps.life.remove_at(i)
			c.zone = MtMatchCard.ZONE_TRASH
			ps.trash.append(c)
			moved += 1
	if moved > 0:
		_log("P%d trashes %d face-up Life card(s)." % [ps.index, moved])
	return moved

# --- Life-token resolvers (moves here never fire Triggers; only damage does) ---

func _resolve_life_to_hand(card: MtMatchCard, opts: Dictionary) -> void:
	var tp := _P(card.owner) if String(opts.get("player", "self")) == "self" else _P(_opp(card.owner))
	var n: int = opts.get("n", 1)
	if bool(opts.get("all", false)):
		n = tp.life.size()
	var edge := String(opts.get("edge", "top"))
	if edge == "either" and not bool(opts.get("_edge_chosen", false)) and not auto_resolve_choices and not tp.life.is_empty():
		pending_choice = {
			"type": "life_edge", "player": card.owner, "source_uid": card.uid,
			"mode": "to_hand", "opts": opts,
		}
		_log("P%d chooses the top or the bottom of Life." % card.owner)
		return
	if edge == "either":
		edge = "top"
	if tp.no_life_to_hand and card.owner == tp.index:
		_log("P%d cannot add Life cards to their hand with their own effects." % tp.index)
		return
	for i in range(n):
		if tp.life.is_empty():
			break
		var c: MtMatchCard
		if edge == "bottom":
			c = tp.life.pop_front()
		else:
			c = tp.life.pop_back()
		c.face_down = false
		c.zone = MtMatchCard.ZONE_HAND
		tp.hand.append(c)
	_log("P%d moves %s Life card(s) to hand." % [tp.index, edge])

func _resolve_hand_to_life(ps: MtPlayerState, opts: Dictionary) -> void:
	var n: int = opts.get("n", 1)
	if bool(opts.get("all", false)):
		n = ps.hand.size()
	var down := String(opts.get("face", "")) != "up"
	for i in range(n):
		if ps.hand.is_empty():
			break
		# Deterministic: first card in hand (documented; MCTS treats as fixed).
		var c: MtMatchCard = ps.hand.pop_front()
		c.zone = MtMatchCard.ZONE_LIFE
		c.face_down = down
		ps.life.append(c)
	_log("P%d adds %d card(s) from hand to Life (%s)." % [ps.index, n, "face-down" if down else "face-up"])

func _resolve_face_life(ps: MtPlayerState, opts: Dictionary, source: MtMatchCard = null) -> void:
	var down := bool(opts.get("down", true))
	if bool(opts.get("all", false)):
		for c in ps.life:
			(c as MtMatchCard).face_down = down
		_log("P%d turns all Life %s." % [ps.index, "face-down" if down else "face-up"])
		return
	if ps.life.is_empty():
		return
	var edge := String(opts.get("edge", "top"))
	if edge == "either" and not bool(opts.get("_edge_chosen", false)) and not auto_resolve_choices and source != null:
		pending_choice = {
			"type": "life_edge", "player": source.owner, "source_uid": source.uid,
			"mode": "face", "life_owner": ps.index, "opts": opts,
		}
		_log("P%d chooses the top or the bottom of Life." % source.owner)
		return
	var idx := ps.life.size() - 1
	if edge == "bottom":
		idx = 0
	(ps.life[idx] as MtMatchCard).face_down = down
	_log("P%d turns 1 Life card %s." % [ps.index, "face-down" if down else "face-up"])

func _resolve_char_to_life(source: MtMatchCard, opts: Dictionary) -> void:
	# Deterministic pick mirrors _auto_ko: highest power first.
	var side := String(opts.get("player", "any"))
	var pool: Array = []
	if side == "self" or side == "any":
		pool.append_array(_P(source.owner).field)
	if side == "opp" or side == "any":
		pool.append_array(_P(_opp(source.owner)).field)
	var max_cost := int(opts.get("max_cost", 0))
	var cands: Array = []
	for c in pool:
		if not (c as MtMatchCard).is_character():
			continue
		if max_cost > 0 and (c as MtMatchCard).cost_value() > max_cost:
			continue
		cands.append(c)
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a.base_power() > b.base_power())
	var target: MtMatchCard = cands[0]
	var owner_ps := _P(target.owner)
	_finalize_move(target)
	target.zone = MtMatchCard.ZONE_LIFE
	target.face_down = String(opts.get("face", "")) != "up"
	owner_ps.life.append(target)
	_log("P%d's %s is placed %s their Life." % [target.owner, target.card_name(),
		"face-up on" if not target.face_down else "face-down on"])

func _resolve_look_life(ps: MtPlayerState, opts: Dictionary, source: MtMatchCard = null, actions: Array = [], act_idx: int = -1) -> void:
	var who := ps
	if String(opts.get("player", "self")) == "opp" and source != null:
		who = _P(_opp(source.owner))
	if int(opts.get("deck_top", 0)) > 0 and not who.life.is_empty():
		var c: MtMatchCard = who.life.pop_back()
		c.zone = MtMatchCard.ZONE_DECK
		c.face_down = true
		who.deck.push_front(c)
		_log("P%d places 1 Life card on top of the deck." % who.index)
		return
	if not auto_resolve_choices and who.life.size() > 1:
		var rest: Array = []
		if act_idx >= 0 and act_idx + 1 < actions.size():
			rest = actions.slice(act_idx + 1)
		var uids: Array = []
		for lc in who.life:
			uids.append((lc as MtMatchCard).uid)
		pending_choice = {
			"type": "look_order", "player": ps.index if source == null else source.owner,
			"source_uid": source.uid if source != null else "",
			"kind": "life", "owner": who.index, "candidates": uids, "all_uids": uids.duplicate(),
			"rest_actions": rest, "max": uids.size(), "up_to": true, "picked": [],
		}
		_log("P%d looks at Life and may reorder it." % who.index)
		return
	_log("P%d looks at Life (order kept)." % who.index)

func _play_self_from_trigger(ps: MtPlayerState, card: MtMatchCard) -> void:
	ps.hand.erase(card)
	_limbo.erase(card)
	if card.card_type() == "Character":
		if ps.field.size() >= 5:
			var victim := _overflow_victim(ps)
			if victim != null:
				_move_to_trash(ps, victim)
		card.zone = MtMatchCard.ZONE_FIELD
		card.mark_played(turn)
		ps.field.append(card)
		_log("P%d plays %s from Life via [Trigger]." % [ps.index, card.card_name()])
		var f := fx(card)
		for tok in f.get("on_play", []):
			_resolve_actions(card, tok.actions, {})
		_notify_character_played(ps, card)
	elif card.card_type() == "Stage":
		if ps.stage != null:
			_move_to_trash(ps, ps.stage)
		card.zone = MtMatchCard.ZONE_STAGE
		card.mark_played(turn)
		ps.stage = card
		_log("P%d plays Stage %s from Life via [Trigger]." % [ps.index, card.card_name()])
	else:
		_move_to_trash(ps, card)

# --- Effect resolution (action DSL) ---
func _check_cond(card: MtMatchCard, opts: Dictionary) -> bool:
	var cond: Dictionary = opts.get("cond", {})
	if cond.is_empty():
		return true
	if cond.has("life_lte"):
		var tp := _P(card.owner) if String(cond.get("player", "self")) == "self" else _P(_opp(card.owner))
		if tp.life.size() > int(cond.get("life_lte", 0)):
			return false
	if cond.has("hand_lte"):
		if _P(card.owner).hand.size() > int(cond.get("hand_lte", 0)):
			return false
	if cond.has("don_gte"):
		if _P(card.owner).don_active < int(cond.get("don_gte", 0)):
			return false
	if cond.has("don_lte"):
		if _P(card.owner).don_active > int(cond.get("don_lte", 0)):
			return false
	if bool(cond.get("don_lte_opp", false)):
		if _P(card.owner).don_active > _P(_opp(card.owner)).don_active:
			return false
	if cond.has("hand_deficit"):
		if _P(card.owner).hand.size() + int(cond.get("hand_deficit", 0)) > _P(_opp(card.owner)).hand.size():
			return false
	if cond.has("opp_hand_gte"):
		if _P(_opp(card.owner)).hand.size() < int(cond.get("opp_hand_gte", 0)):
			return false
	if cond.has("opp_life_gte"):
		if _P(_opp(card.owner)).life.size() < int(cond.get("opp_life_gte", 0)):
			return false
	if cond.has("either_life_lte"):
		var cap := int(cond.get("either_life_lte", 0))
		var either := false
		for p in players:
			if (p as MtPlayerState).life.size() <= cap:
				either = true
		if not either:
			return false
	if cond.has("own_chars_cost_n"):
		var need_n := int(cond.get("own_chars_cost_n", 1))
		var need_c := int(cond.get("own_chars_cost_min", 0))
		var have := 0
		for fc in _P(card.owner).field:
			if int(fc.card.get("cost", 0)) >= need_c:
				have += 1
		if have < need_n:
			return false
	if bool(cond.get("played_this_turn", false)) and not card.played_this_turn_value():
		return false
	if cond.has("leader_trait"):
		var ld := _P(card.owner).leader
		if ld == null or not _trait_has(ld, String(cond.get("leader_trait", ""))):
			return false
	if String(cond.get("has_name", "")) != "":
		var found_n := false
		for c in _P(card.owner).field:
			if _name_matches(c, String(cond.get("has_name", ""))):
				found_n = true
				break
		if _P(card.owner).leader != null and _name_matches(_P(card.owner).leader, String(cond.get("has_name", ""))):
			found_n = true
		if not found_n:
			return false
	if cond.has("revealed_cost_gte"):
		var ok := false
		for c in _last_look:
			if c != null and (c as MtMatchCard).cost_value() >= int(cond.get("revealed_cost_gte", 0)):
				ok = true
				break
		if not ok:
			return false
	if bool(cond.get("if_you_do", false)) and not _effect_did:
		return false
	if String(cond.get("missing_name", "")) != "":
		var want := String(cond.get("missing_name", ""))
		for c in _P(card.owner).field:
			if _name_matches(c, want):
				return false
	if cond.has("opp_chars_gte"):
		if _P(_opp(card.owner)).field.size() < int(cond.get("opp_chars_gte", 0)):
			return false
	if String(cond.get("leader_name", "")) != "":
		var ldn := _P(card.owner).leader
		if ldn == null or not _name_matches(ldn, String(cond.get("leader_name", ""))):
			return false
	if cond.has("don_deficit"):
		if _P(card.owner).don_active + int(cond.get("don_deficit", 0)) > _P(_opp(card.owner)).don_active:
			return false
	if cond.has("trash_gte"):
		if _P(card.owner).trash.size() < int(cond.get("trash_gte", 0)):
			return false
	if cond.has("events_trash_gte"):
		var evn := 0
		for tc in _P(card.owner).trash:
			if (tc as MtMatchCard).is_event():
				evn += 1
		if evn < int(cond.get("events_trash_gte", 0)):
			return false
	if cond.has("leader_power_lte"):
		var ldp := _P(card.owner).leader
		if ldp == null or card_power(ldp) > int(cond.get("leader_power_lte", 0)):
			return false
	if cond.has("opp_char_power_gte"):
		var og := false
		for oc in _P(_opp(card.owner)).field:
			if card_power(oc) >= int(cond.get("opp_char_power_gte", 0)):
				og = true
				break
		if not og:
			return false
	if cond.has("self_char_power_gte"):
		var sg := false
		for sc in _P(card.owner).field:
			if card_power(sc) >= int(cond.get("self_char_power_gte", 0)):
				sg = true
				break
		if not sg:
			return false
	if cond.has("opp_rested_gte"):
		var rn := 0
		for oc2 in _P(_opp(card.owner)).field:
			if oc2.rested:
				rn += 1
		if rn < int(cond.get("opp_rested_gte", 0)):
			return false
	if String(cond.get("leader_name_includes", "")) != "":
		var ldi := _P(card.owner).leader
		if ldi == null or not ldi.card_name().contains(String(cond.get("leader_name_includes", ""))):
			return false
	if bool(cond.get("hand_trashed_this_turn", false)):
		if not _P(card.owner).hand_trashed_this_turn:
			return false
	if cond.has("played_cost_gte"):
		var played = _cond_ctx.get("played", null)
		if played == null or int((played as MtMatchCard).card.get("cost", 0)) < int(cond.get("played_cost_gte", 0)):
			return false
	if bool(cond.get("leader_multicolor", false)):
		var ldm := _P(card.owner).leader
		if ldm == null or ldm.colors().size() < 2:
			return false
	if cond.has("active_don_lte"):
		if _P(card.owner).get_available_don() > int(cond.get("active_don_lte", 0)):
			return false
	if cond.has("rested_chars_gte"):
		var rc := 0
		for sc2 in _P(card.owner).field:
			if sc2.rested:
				rc += 1
		if rc < int(cond.get("rested_chars_gte", 0)):
			return false
	if cond.has("rested_don_gte"):
		if _P(card.owner).don_rested < int(cond.get("rested_don_gte", 0)):
			return false
	if bool(cond.get("no_other_chars", false)):
		if _P(card.owner).field.size() > 1:
			return false
	if bool(cond.get("faceup_life", false)):
		var fu := false
		for lf in _P(card.owner).life:
			if not lf.face_down:
				fu = true
				break
		if not fu:
			return false
	if bool(cond.get("less_chars_than_opp", false)):
		if _P(card.owner).field.size() >= _P(_opp(card.owner)).field.size():
			return false
	if cond.has("don_returned_gte"):
		if int(_cond_ctx.get("don_returned", 0)) < int(cond.get("don_returned_gte", 0)):
			return false
	if bool(cond.get("life_lt_opp", false)):
		if _P(card.owner).life.size() >= _P(_opp(card.owner)).life.size():
			return false
	if cond.has("life_sum_lte"):
		if _P(card.owner).life.size() + _P(_opp(card.owner)).life.size() > int(cond.get("life_sum_lte", 0)):
			return false
	if cond.has("self_power_gte"):
		var spw := card.base_power() + card.power_bonus
		if active == card.owner:
			spw += card.don_count() * 1000
		if spw < int(cond.get("self_power_gte", 0)):
			return false
	if cond.has("any_cost_eq"):
		var need_eq := int(cond.get("any_cost_eq", 0))
		var found_eq := false
		for p in players:
			for fc in (p as MtPlayerState).field:
				if int(fc.card.get("cost", 0)) == need_eq:
					found_eq = true
		if not found_eq:
			return false
	if cond.has("any_cost_gte"):
		var need := int(cond.get("any_cost_gte", 0))
		var found_c := false
		for p in players:
			var ldz = (p as MtPlayerState).leader
			if ldz != null and int(ldz.card.get("cost", 0)) >= need:
				found_c = true
			for fc in (p as MtPlayerState).field:
				if int(fc.card.get("cost", 0)) >= need:
					found_c = true
		if not found_c:
			return false
	return true

func _trait_has(card: MtMatchCard, want: String) -> bool:
	if card == null or want == "":
		return false
	for t in card.traits():
		var ts := String(t)
		if ts == want or ts.contains(want) or want.contains(ts):
			return true
	return false

func _name_matches(card: MtMatchCard, want: String) -> bool:
	if card == null or want == "":
		return false
	if card.card_name().contains(want) or want.contains(card.card_name()):
		return true
	for n in fx(card).get("rules", {}).get("treat_as_names", []):
		var ns := String(n)
		if ns.contains(want) or want.contains(ns):
			return true
	return false

func _dur_on(card: MtMatchCard, dur: String) -> bool:
	if dur == "opp_turn":
		return active != card.owner
	if dur == "own_turn":
		return active == card.owner
	return true

func _card_protected(card: MtMatchCard, from_battle: bool, source: MtMatchCard = null) -> bool:
	if card.cannot_ko_all:
		return true
	if card.cannot_ko_effects and not from_battle:
		return true
	var specs: Array = []
	for p in fx(card).get("protect_fx", []):
		specs.append(p)
	for act in fx(card).get("static_actions", []):
		if act is Array and String(act[0]) == MtEffectParser.TOK_PROTECT and act.size() > 1 and act[1] is Dictionary:
			if _check_cond(card, act[1]):
				specs.append(act[1])
	for p in specs:
		if not _dur_on(card, String(p.get("dur", "opp_turn"))):
			continue
		if p.has("cond") and not _check_cond(card, {"cond": p.get("cond", {})}):
			continue
		var frm := String(p.get("from", "all"))
		if frm == "battle" and not from_battle:
			continue
		if frm == "effects" and from_battle:
			continue
		if frm != "all" and frm != "battle" and frm != "effects":
			continue
		var attr := String(p.get("attr", ""))
		if attr != "" and (source == null or source.attribute_value().to_lower() != attr.to_lower()):
			continue
		var cap := int(p.get("opp_power_lte", 0))
		if cap > 0 and (source == null or source.base_power() > cap):
			continue
		return true
	return false

func _must_attack_name(ops: MtPlayerState) -> String:
	for c in ops.field:
		var f := fx(c)
		for m in f.get("must_attack_fx", []):
			if not _dur_on(c, String(m.get("dur", "opp_turn"))):
				continue
			if bool(m.get("if_rested", false)) and not c.rested:
				continue
			var nm := String(m.get("name", ""))
			if nm != "":
				return nm
	for c in ops.field:
		for g in c.granted_keywords:
			var gs := String(g)
			if gs.begins_with("must_attack:"):
				return gs.substr("must_attack:".length())
	return ""

func _filter_matches(c: MtMatchCard, opts: Dictionary, source = null) -> bool:
	if bool(opts.get("this_card", false)):
		return c == source
	if bool(opts.get("leaders_only", false)):
		return c.is_leader()
	if bool(opts.get("has_trigger", false)) and String(c.card.get("trigger", "")).strip_edges().is_empty() \
			and not String(c.card.get("effect", "")).contains("[Trigger]"):
		return false
	var kw_need := String(opts.get("keyword", ""))
	if kw_need != "" and not has_keyword(c, kw_need):
		return false
	var want_type := String(opts.get("card_type", ""))
	if want_type == "Character" and not c.is_character() and not (bool(opts.get("include_leader", false)) and c.is_leader()):
		if c.is_leader() and bool(opts.get("include_leader", false)):
			pass
		elif not c.is_character():
			return false
	elif want_type == "Event" and not c.is_event():
		return false
	elif want_type == "Stage" and not c.is_stage():
		return false
	elif want_type == "EventOrStage" and not c.is_event() and not c.is_stage():
		return false
	if bool(opts.get("rested_only", false)) and not c.rested:
		return false
	if bool(opts.get("active_only", false)) and c.rested:
		return false
	var by_name := String(opts.get("by_name", ""))
	if by_name != "" and not _name_matches(c, by_name):
		return false
	var by_type := String(opts.get("by_type", ""))
	var by_types = opts.get("by_types", [])
	if by_types is Array and not (by_types as Array).is_empty():
		var hit := false
		for t in by_types:
			if _trait_has(c, String(t)):
				hit = true
				break
		if not hit:
			return false
	elif by_type != "" and not _trait_has(c, by_type):
		return false
	if bool(opts.get("has_cost", false)):
		var ok := false
		var op := String(opts.get("op", "<="))
		var costn := int(opts.get("cost", 0))
		if op == ">=":
			ok = effect_cost(c) >= costn
		elif op == "=":
			ok = effect_cost(c) == costn
		else:
			ok = effect_cost(c) <= costn
		if not ok:
			return false
	var exclude_name := String(opts.get("exclude_name", ""))
	if exclude_name != "" and _name_matches(c, exclude_name):
		return false
	if bool(opts.get("cost_vs_opp_life", false)):
		var src_owner := int(opts.get("src_owner", c.owner))
		if c.cost_value() > _P(_opp(src_owner)).life.size():
			return false
	if int(opts.get("by_power", 0)) > 0:
		var pw := c.base_power()
		var need := int(opts.get("by_power", 0))
		var pop := String(opts.get("by_power_op", "<="))
		if pop == ">=" and pw < need:
			return false
		elif pop == "=" and pw != need:
			return false
		elif pop == "<=" and pw > need:
			return false
	return true

func _zone_pool(ps: MtPlayerState, zone: String, opts: Dictionary) -> Array:
	match zone:
		"hand":
			return ps.hand.duplicate()
		"trash":
			return ps.trash.duplicate()
		"deck":
			return ps.deck.duplicate()
		_:
			var pool: Array = ps.field.duplicate()
			if bool(opts.get("include_leader", false)) and ps.leader:
				pool.append(ps.leader)
			return pool

func _collect_filter(source: MtMatchCard, opts: Dictionary) -> Array:
	if bool(opts.get("this_card", false)):
		return [source]
	var owner_i := source.owner
	var zone := String(opts.get("zone", "field"))
	var pl := String(opts.get("player", "opp"))
	if pl == "opp":
		owner_i = _opp(source.owner)
	var pool: Array = []
	if pl == "any":
		pool.append_array(_zone_pool(_P(source.owner), zone, opts))
		pool.append_array(_zone_pool(_P(_opp(source.owner)), zone, opts))
	else:
		pool = _zone_pool(_P(owner_i), zone, opts)
	var out: Array = []
	for c in pool:
		if _filter_matches(c, opts, source):
			out.append(c)
	out.sort_custom(func(a, b): return a.base_power() > b.base_power())
	return out

func _begin_pick(source: MtMatchCard, kind: String, opts: Dictionary, actions: Array, act_idx: int) -> void:
	opts = opts.duplicate()
	opts["src_owner"] = source.owner
	if bool(opts.get("this_card", false)):
		_apply_pick(kind, [source], opts)
		return
	var cands := _collect_filter(source, opts)
	if cands.is_empty():
		return
	var num := int(opts.get("number", 1))
	if num <= 0:
		num = cands.size()
	var rest: Array = []
	if act_idx >= 0 and act_idx + 1 < actions.size():
		rest = actions.slice(act_idx + 1)
	if auto_resolve_choices:
		_apply_pick(kind, cands.slice(0, num), opts)
		return
	if cands.size() <= num and not bool(opts.get("up_to", false)):
		_apply_pick(kind, cands.slice(0, num), opts)
		return
	var uids: Array = []
	for c in cands:
		uids.append(c.uid)
	pending_choice = {
		"type": "pick", "kind": kind, "player": source.owner, "source_uid": source.uid,
		"max": num, "up_to": bool(opts.get("up_to", true)), "candidates": uids,
		"opts": opts, "rest_actions": rest, "picked": [],
	}

func _apply_pick(kind: String, cards: Array, opts: Dictionary) -> void:
	if cards.size() > 0:
		_effect_did = true
	if kind == "play":
		var i := 0
		for c in cards:
			var rested := bool(opts.get("play_rested", false))
			if bool(opts.get("second_rested", false)) and i > 0:
				rested = true
			_effect_play(c, rested)
			i += 1
		if String(opts.get("zone", "")) == "deck" and not cards.is_empty():
			_shuffle(_P((cards[0] as MtMatchCard).owner).deck)
		return
	for c in cards:
		match kind:
			"ko":
				_ko(c)
			"bounce":
				_bounce_to_hand(c)
			"rest":
				c.rested = true
				_note_rested(c)
			"char_to_life":
				_place_char_life(c, opts)
			"remove":
				_remove_from_game(_P(c.owner), c)
			"power":
				c.power_bonus += int(opts.get("amount", 0))
				_turn_bonuses.append({"card": c, "amount": int(opts.get("amount", 0)),
					"dur": String(opts.get("dur", "turn")), "owner": int(opts.get("src_owner", c.owner))})
			"cost":
				var camt := int(opts.get("amount", 0))
				if opts.has("set_to"):
					camt = int(opts.get("set_to", 0)) - int(c.card.get("cost", 0)) - c.cost_bonus
				c.cost_bonus += camt
				_turn_bonuses.append({"card": c, "amount": camt,
					"dur": String(opts.get("dur", "turn")), "owner": int(opts.get("src_owner", c.owner)), "kind": "cost"})
			"to_deck":
				_place_on_deck(_P(c.owner), c, String(opts.get("edge", "bottom")))
			"set_active":
				c.rested = false
			"look_deck":
				_finish_look_choice(c, opts)
			"trash":
				_move_to_trash(_P(c.owner), c)
			"hand_to_life":
				var hps := _P(c.owner)
				hps.hand.erase(c)
				c.zone = MtMatchCard.ZONE_LIFE
				c.face_down = String(opts.get("face", "")) != "up"
				hps.life.append(c)
				_log("P%d adds %s from hand to Life." % [hps.index, c.card_name()])
			"trash_to_hand":
				_trash_card_to_hand(c)
			"negate":
				c.effects_negated = true
				_turn_bonuses.append({"card": c, "amount": 0, "dur": String(opts.get("dur", "turn")),
					"owner": int(opts.get("src_owner", c.owner)), "kind": "negate"})
				_log("%s's effect is negated." % c.card_name())
			"no_block":
				_block_seals.append({"uid": c.uid, "against": c.owner,
					"dur": String(opts.get("dur", "turn")), "by_owner": int(opts.get("src_owner", c.owner))})
			"attack_no_block":
				_block_seals.append({"attacker_uid": c.uid,
					"dur": String(opts.get("dur", "turn")), "by_owner": int(opts.get("src_owner", c.owner))})
			"skip_refresh":
				c.skip_next_refresh = true
			"no_attack":
				c.no_attack = true
				_turn_bonuses.append({"card": c, "amount": 0, "dur": String(opts.get("dur", "turn")),
					"owner": int(opts.get("src_owner", c.owner)), "kind": "no_attack"})
				_log("%s cannot attack." % c.card_name())
			"swap_power":
				pass
	if kind == "swap_power" and cards.size() >= 2:
		_swap_base_power(cards[0], cards[1], String(opts.get("dur", "turn")))

func _bounce_to_hand(card: MtMatchCard) -> void:
	if _cannot_leave(card, false, null):
		_log("%s cannot be removed from the field." % card.card_name())
		return
	if _try_replace_ko(card, false, true, "bounce"):
		return
	_commit_bounce(card)

func _commit_bounce(card: MtMatchCard) -> void:
	var ps := _P(card.owner)
	_finalize_move(card)
	card.zone = MtMatchCard.ZONE_HAND
	card.rested = false
	card.face_down = false
	ps.hand.append(card)
	_log("%s is returned to the owner's hand." % card.card_name())

func _effect_play(card: MtMatchCard, play_rested: bool) -> void:
	var ps := _P(card.owner)
	var from_zone := String(card.zone)
	if card.is_character() and ps.field.size() >= 5:
		var victim := _overflow_victim(ps)
		if victim != null:
			_move_to_trash(ps, victim)
	_finalize_move(card)
	card.mark_played(turn)
	card.rested = play_rested
	if card.is_stage():
		if ps.stage != null:
			_move_to_trash(ps, ps.stage)
		card.zone = MtMatchCard.ZONE_STAGE
		ps.stage = card
	elif card.is_character():
		card.zone = MtMatchCard.ZONE_FIELD
		ps.field.append(card)
		for tok in fx(card).get("on_play", []):
			_resolve_actions(card, tok.actions, {})
		_notify_character_played(ps, card)
		if from_zone == MtMatchCard.ZONE_TRASH:
			_fire_window(ps, "on_play_from_trash", {"played": card}, card)
	elif card.is_event():
		for tok in fx(card).get("on_main", []):
			_resolve_actions(card, tok.actions, {})
		_move_to_trash(ps, card)
		return
	_log("P%d plays %s by an effect." % [ps.index, card.card_name()])

func _trash_card_to_hand(card: MtMatchCard) -> void:
	var ps := _P(card.owner)
	_finalize_move(card)
	card.zone = MtMatchCard.ZONE_HAND
	card.rested = false
	card.face_down = false
	ps.hand.append(card)
	_log("P%d adds %s from the trash to their hand." % [ps.index, card.card_name()])

func _swap_base_power(a: MtMatchCard, b: MtMatchCard, dur: String) -> void:
	var pa := a.base_power()
	var pb := b.base_power()
	var previa := a.power_override
	var previb := b.power_override
	a.power_override = pb
	b.power_override = pa
	_turn_bonuses.append({"card": a, "amount": 0, "dur": dur, "owner": a.owner, "kind": "swap", "prev": previa})
	_turn_bonuses.append({"card": b, "amount": 0, "dur": dur, "owner": b.owner, "kind": "swap", "prev": previb})
	_log("%s and %s swap base power (%d / %d)." % [a.card_name(), b.card_name(), pb, pa])

func _place_char_life(target: MtMatchCard, opts: Dictionary) -> void:
	var owner_ps := _P(target.owner)
	_finalize_move(target)
	target.zone = MtMatchCard.ZONE_LIFE
	target.face_down = String(opts.get("face", "")) != "up"
	owner_ps.life.append(target)

func _look_deck(source: MtMatchCard, opts: Dictionary, actions: Array = [], act_idx: int = -1) -> void:
	var ps := _P(source.owner)
	var n := mini(int(opts.get("n", 1)), ps.deck.size())
	var taken: Array = []
	for i in range(n):
		if ps.deck.is_empty():
			break
		taken.append(ps.deck.pop_front())
	_last_look = taken.duplicate()
	for c in taken:
		_limbo.append(c)
	var filt: Dictionary = opts.get("filter", {})
	var matches: Array = []
	for c in taken:
		if _filter_matches(c, filt, source):
			matches.append(c)
	var rest_acts: Array = []
	if act_idx >= 0 and act_idx + 1 < actions.size():
		rest_acts = actions.slice(act_idx + 1)
	if not auto_resolve_choices and not matches.is_empty() and (bool(opts.get("add_hand", true)) or bool(opts.get("play", false))):
		var uids: Array = []
		var taken_uids: Array = []
		for c in matches:
			uids.append(c.uid)
		for c in taken:
			taken_uids.append(c.uid)
		pending_choice = {
			"type": "pick", "kind": "look_deck", "player": source.owner, "source_uid": source.uid,
			"max": 1, "up_to": true, "candidates": uids, "taken_uids": taken_uids,
			"opts": opts, "rest_actions": rest_acts,
		}
		return
	var chosen: MtMatchCard = null
	if not matches.is_empty() and (bool(opts.get("add_hand", true)) or bool(opts.get("play", false))):
		chosen = matches[0]
	if chosen != null:
		_finish_look_choice(chosen, opts)
		taken.erase(chosen)
	_return_look_rest(ps, taken, opts, source, rest_acts)
	if pending_choice != null:
		return

func _finish_look_choice(chosen: MtMatchCard, opts: Dictionary) -> void:
	var ps := _P(chosen.owner)
	_limbo.erase(chosen)
	var filt: Dictionary = opts.get("filter", {})
	if bool(opts.get("play", false)) and chosen.is_character():
		_effect_play(chosen, bool(filt.get("play_rested", false)))
	elif bool(opts.get("add_hand", true)):
		chosen.zone = MtMatchCard.ZONE_HAND
		ps.hand.append(chosen)
		_log("P%d adds %s from the deck to their hand." % [ps.index, chosen.card_name()])

func _return_look_rest(ps: MtPlayerState, taken: Array, opts: Dictionary, source: MtMatchCard = null, rest_acts: Array = []) -> void:
	if not auto_resolve_choices and bool(opts.get("reorder", false)) and taken.size() > 1:
		var uids: Array = []
		for c in taken:
			uids.append((c as MtMatchCard).uid)
		pending_choice = {
			"type": "look_order", "player": ps.index, "source_uid": source.uid if source != null else "",
			"kind": "deck", "owner": ps.index, "candidates": uids, "all_uids": uids.duplicate(),
			"opts": opts, "rest_actions": rest_acts, "max": uids.size(), "up_to": true, "picked": [],
		}
		return
	if bool(opts.get("shuffle", false)):
		_shuffle(taken)
	_place_look_rest(ps, taken, opts)

func _place_look_rest(ps: MtPlayerState, taken: Array, opts: Dictionary) -> void:
	var rest := String(opts.get("rest", "bottom"))
	for c in taken:
		_limbo.erase(c)
		c.zone = MtMatchCard.ZONE_DECK
		c.face_down = true
		if rest == "bottom":
			ps.deck.append(c)
		else:
			ps.deck.push_front(c)

func _set_card_active(card: MtMatchCard, opts: Dictionary, actions: Array = [], act_idx: int = -1) -> void:
	var who := String(opts.get("who", "self"))
	if who == "self":
		card.rested = false
		_log("%s is set as active." % card.card_name())
		return
	var fopts := {"player": "self", "zone": "field", "card_type": "Character", "rested_only": true,
		"number": 1, "up_to": true}
	_begin_pick(card, "set_active", fopts, actions, act_idx)

func _apply_cost_bonus(card: MtMatchCard, popts: Dictionary) -> void:
	var amount: int = popts.get("amount", 0)
	var dur := String(popts.get("dur", "turn"))
	var targets: Array = []
	var who := String(popts.get("who", "opp_char"))
	match who:
		"self":
			targets.append(card)
		"all_opp_chars":
			targets.append_array(_P(_opp(card.owner)).field)
		_:
			var oc: Array = _P(_opp(card.owner)).field.duplicate()
			oc.sort_custom(func(a, b): return a.base_power() > b.base_power())
			if not oc.is_empty():
				targets.append(oc[0])
	for t in targets:
		t.cost_bonus += amount
		_turn_bonuses.append({"card": t, "amount": amount, "dur": dur, "owner": card.owner, "kind": "cost"})

func _apply_protect(card: MtMatchCard, opts: Dictionary) -> void:
	var frm := String(opts.get("from", "all"))
	if frm == "effects":
		card.cannot_ko_effects = true
	else:
		card.cannot_ko_all = true
	_turn_bonuses.append({"card": card, "amount": 0, "dur": String(opts.get("dur", "turn")),
		"owner": card.owner, "kind": "protect"})

func _resolve_actions(card: MtMatchCard, actions: Array, _ctx: Dictionary) -> void:
	_effect_depth += 1
	if _effect_depth == 1:
		_effect_did = false
	var i := 0
	while i < actions.size():
		var act = actions[i]
		var kind: String = act[0]
		if act.size() > 1 and act[1] is Dictionary and not _check_cond(card, act[1]):
			i += 1
			continue
		match kind:
			MtEffectParser.TOK_PAY:
				var paid := _pay_activation(card, act[1], actions, i)
				if _halt_for_choice(card, actions, i):
					return
				if not paid:
					_effect_depth -= 1
					if _effect_depth == 0:
						_rule_process()
					return
			MtEffectParser.TOK_DRAW:
				var spec = act[1]
				if spec is Dictionary and int(spec.get("until", 0)) > 0:
					var psd := _P(card.owner)
					while psd.hand.size() < int(spec.get("until", 0)):
						if not draw_card(psd):
							break
				else:
					var n: int = spec if spec is int else int(spec.get("n", 1))
					for d in range(n):
						draw_card(_P(card.owner))
			MtEffectParser.TOK_ADD_DON:
				var spec = act[1]
				var add_n := int(spec) if spec is int else int(spec.get("n", 1))
				var rested_add := spec is Dictionary and bool(spec.get("rested", false))
				_add_active_don(_ps_of(card, spec), add_n, rested_add)
			MtEffectParser.TOK_DON_MINUS:
				var dps := _ps_of(card, act[1])
				if bool(act[1].get("until_opp", false)):
					var extra := maxi(0, dps.don_active - _P(_opp(dps.index)).don_active)
					_return_don_to_deck(dps, extra)
				else:
					_return_don_to_deck(dps, int(act[1].get("n", 1)))
			MtEffectParser.TOK_SET_DON_ACTIVE:
				_set_don_active(_ps_of(card, act[1]), int(act[1].get("n", 1)))
			MtEffectParser.TOK_REST_SELF:
				card.rested = true
				_note_rested(card)
			MtEffectParser.TOK_ATTACH_DON:
				_begin_give_don(card, act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_KO:
				_begin_pick(card, "ko", act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_POWER:
				var popts: Dictionary = (act[1] as Dictionary).duplicate()
				if _ctx.has("counter_host") and String(popts.get("who", "")) == "self":
					popts["who"] = "counter_host"
					popts["host"] = _ctx.get("counter_host")
				var who_p := String(popts.get("who", "self"))
				if not auto_resolve_choices and who_p in ["opp_char", "opp_any", "self_or_chosen"]:
					var pf := {"number": 1, "up_to": true, "zone": "field", "card_type": "Character",
						"amount": int(popts.get("amount", 0)), "dur": String(popts.get("dur", "turn")),
						"src_owner": card.owner}
					if who_p == "opp_any" or who_p == "opp_char":
						pf["player"] = "opp"
						if who_p == "opp_any":
							pf["include_leader"] = true
					else:
						pf["player"] = "self"
						pf["include_leader"] = true
					_begin_pick(card, "power", pf, actions, i)
					if pending_choice != null:
						_effect_depth -= 1
						return
				else:
					_apply_power_bonus(card, popts)
			MtEffectParser.TOK_CHAR_TO_LIFE:
				var cl := act[1] as Dictionary
				var cf := {"player": String(cl.get("player", "any")), "zone": "field", "card_type": "Character",
					"number": 1, "up_to": true, "face": String(cl.get("face", "")), "cond": cl.get("cond", {})}
				if int(cl.get("max_cost", 0)) > 0:
					cf["has_cost"] = true
					cf["cost"] = int(cl.get("max_cost", 0))
					cf["op"] = "<="
				if String(cf.get("player", "")) == "any":
					cf["player"] = "opp"
				_begin_pick(card, "char_to_life", cf, actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_REST_DON:
				var ropts: Dictionary = act[1]
				var rps := _P(card.owner) if String(ropts.get("player", "self")) == "self" else _P(_opp(card.owner))
				var rn: int = ropts.get("n", 1)
				var max_restable := rps.don_active - rps.get_attached_don_total()
				rps.don_rested = clamp(rps.don_rested + rn, 0, max_restable)
			MtEffectParser.TOK_TRASH_DECK:
				var topts: Dictionary = act[1]
				var tp := _P(card.owner) if topts.player == "self" else _P(_opp(card.owner))
				_trash_top_of_deck(tp, int(topts.get("n", 1)))
			MtEffectParser.TOK_TO_DECK:
				var dopts: Dictionary = act[1]
				if String(dopts.get("zone", "")) == "":
					_return_to_deck(card, dopts)
				else:
					_begin_pick(card, "to_deck", dopts, actions, i)
					if pending_choice != null:
						_effect_depth -= 1
						return
			MtEffectParser.TOK_SET_POWER:
				_apply_set_power(card, act[1])
			MtEffectParser.TOK_TRASH_TO_DECK:
				_trash_to_deck(_ps_of(card, act[1]), act[1])
			MtEffectParser.TOK_TRASH_HAND:
				var th: Dictionary = (act[1] as Dictionary).duplicate()
				th["zone"] = "hand"
				if String(th.get("player", "")) == "":
					th["player"] = "self"
				if not auto_resolve_choices:
					_begin_pick(card, "trash", th, actions, i)
					if pending_choice != null:
						_effect_depth -= 1
						return
				else:
					_trash_from_hand(_ps_of(card, th), int(th.get("n", 1)), th)
			MtEffectParser.TOK_HAND_TO_DECK:
				_hand_to_deck(_ps_of(card, act[1]), int(act[1].get("n", 1)), String(act[1].get("edge", "bottom")))
			MtEffectParser.TOK_LIFE_TO_HAND:
				_resolve_life_to_hand(card, act[1])
				if _halt_for_choice(card, actions, i):
					return
			MtEffectParser.TOK_DECK_TO_LIFE:
				var dlopts: Dictionary = act[1]
				var dp := _P(card.owner)
				var dn: int = dlopts.get("n", 1)
				if bool(dlopts.get("all", false)):
					dn = dp.deck.size()
				deck_to_life(dp, dn, String(dlopts.get("face", "")) != "up")
			MtEffectParser.TOK_HAND_TO_LIFE:
				var hlopts: Dictionary = act[1]
				if not auto_resolve_choices and not _P(card.owner).hand.is_empty():
					var hf := {"player": "self", "zone": "hand",
						"number": int(hlopts.get("n", 1)),
						"up_to": bool(hlopts.get("up_to", false)),
						"face": String(hlopts.get("face", ""))}
					if bool(hlopts.get("all", false)):
						hf["number"] = _P(card.owner).hand.size()
						hf["up_to"] = true
					_begin_pick(card, "hand_to_life", hf, actions, i)
					if _halt_for_choice(card, actions, i):
						return
				else:
					_resolve_hand_to_life(_P(card.owner), hlopts)
			MtEffectParser.TOK_TRASH_LIFE:
				var tlopts: Dictionary = act[1]
				var tlp := _P(card.owner) if String(tlopts.get("player", "self")) == "self" else _P(_opp(card.owner))
				var tn: int = tlopts.get("n", 1)
				if bool(tlopts.get("all", false)):
					tn = tlp.life.size()
				life_to_trash(tlp, tn)
			MtEffectParser.TOK_FACE_LIFE:
				_resolve_face_life(_P(card.owner), act[1], card)
				if _halt_for_choice(card, actions, i):
					return
			MtEffectParser.TOK_LOOK_LIFE:
				_resolve_look_life(_P(card.owner), act[1], card, actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_TRASH_FACEUP:
				var tfopts: Dictionary = act[1]
				var tfp := _P(card.owner) if String(tfopts.get("player", "self")) == "self" else _P(_opp(card.owner))
				life_trash_faceup(tfp)
			MtEffectParser.TOK_GRANT_KW:
				_grant_kw(card, act[1])
			MtEffectParser.TOK_PLAY:
				_begin_pick(card, "play", act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_BOUNCE:
				_begin_pick(card, "bounce", act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_REST_CHAR:
				_begin_pick(card, "rest", act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_LOOK_DECK:
				_look_deck(card, act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_COST:
				var copts: Dictionary = (act[1] as Dictionary).duplicate()
				copts["src_owner"] = card.owner
				if copts.has("set_to") or (not auto_resolve_choices and String(copts.get("who", "")) == "opp_char"):
					if not copts.has("zone"):
						copts["zone"] = "field"
						copts["player"] = "opp"
						copts["card_type"] = "Character"
						copts["number"] = 1
						copts["up_to"] = true
					_begin_pick(card, "cost", copts, actions, i)
					if pending_choice != null:
						_effect_depth -= 1
						return
				else:
					_apply_cost_bonus(card, copts)
			MtEffectParser.TOK_PROTECT:
				_apply_protect(card, act[1])
			MtEffectParser.TOK_SET_ACTIVE:
				_set_card_active(card, act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_SKIP_REFRESH:
				var sk: Dictionary = act[1] if act[1] is Dictionary else {}
				if sk.is_empty() or bool(sk.get("this_card", false)):
					card.skip_next_refresh = true
				else:
					_begin_pick(card, "skip_refresh", sk, actions, i)
					if pending_choice != null:
						_effect_depth -= 1
						return
			MtEffectParser.TOK_FIELD_TRASH:
				var ft: Dictionary = (act[1] as Dictionary).duplicate()
				ft["zone"] = "field"
				_begin_pick(card, "trash", ft, actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_DAMAGE:
				var dmg_n := int(act[1].get("n", 1))
				var dmg_ps := _P(_opp(card.owner)) if String(act[1].get("player", "opp")) == "opp" else _P(card.owner)
				for _di in range(dmg_n):
					_deal_leader_damage(dmg_ps, card)
			MtEffectParser.TOK_WIN:
				_over_loss(_opp(card.owner), "Effect")
			MtEffectParser.TOK_NO_LIFE_ADD:
				_P(card.owner).no_life_to_hand = true
				_log("P%d cannot add Life cards to their hand with their own effects." % card.owner)
			MtEffectParser.TOK_NO_BLOCK:
				_apply_block_seal(card, act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_SHUFFLE:
				_shuffle(_P(card.owner).deck)
			MtEffectParser.TOK_REMOVE:
				_begin_pick(card, "remove", act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_MUST_ATTACK:
				var nm := String(act[1].get("name", ""))
				if nm != "" and not card.granted_keywords.has("must_attack:%s" % nm):
					card.granted_keywords.append("must_attack:%s" % nm)
			MtEffectParser.TOK_TRASH_SELF:
				_move_to_trash(_P(card.owner), card)
				_effect_did = true
			MtEffectParser.TOK_REVEAL_HAND:
				if _reveal_hand_ok(card, act[1]):
					_log("P%d reveals the required card(s) from their hand." % card.owner)
					_effect_did = true
			MtEffectParser.TOK_OPP_CHOOSE:
				_opp_choose(card, act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_OPP_MAY:
				_opp_may(card, act[1], actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_CHOOSE:
				_begin_modal(card, act[1], actions, i, card.owner)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_TRASH_TO_HAND:
				var th2: Dictionary = (act[1] as Dictionary).duplicate()
				th2["zone"] = "trash"
				th2["player"] = "self"
				th2["src_owner"] = card.owner
				_begin_pick(card, "trash_to_hand", th2, actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_NEGATE:
				var ng: Dictionary = (act[1] as Dictionary).duplicate()
				ng["src_owner"] = card.owner
				_begin_pick(card, "negate", ng, actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_NO_ATTACK:
				var na: Dictionary = (act[1] as Dictionary).duplicate()
				na["src_owner"] = card.owner
				_begin_pick(card, "no_attack", na, actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_SWAP_POWER:
				var sw: Dictionary = (act[1] as Dictionary).duplicate()
				sw["src_owner"] = card.owner
				_begin_pick(card, "swap_power", sw, actions, i)
				if pending_choice != null:
					_effect_depth -= 1
					return
			MtEffectParser.TOK_NO_PLAY:
				_apply_no_play(_P(card.owner), act[1])
			MtEffectParser.TOK_HAND_COST:
				_P(card.owner).hand_cost_mods.append((act[1] as Dictionary).duplicate())
		i += 1
	_effect_depth -= 1
	if _effect_depth == 0:
		_rule_process()
		if pending_choice == null and not _start_turn_queue.is_empty():
			_drain_start_of_turn()

func _trash_top_of_deck(ps: MtPlayerState, n: int) -> int:
	var moved := 0
	for i in range(n):
		if ps.deck.is_empty():
			break
		var c: MtMatchCard = ps.deck.pop_front()
		c.zone = MtMatchCard.ZONE_TRASH
		c.face_down = false
		ps.trash.append(c)
		moved += 1
	if moved > 0:
		_log("P%d sends %d card(s) from the top of the deck to the Trash." % [ps.index, moved])
	if ps.deck.is_empty():
		_on_deck_empty(ps, false)
	return moved

func _place_on_deck(ps: MtPlayerState, card: MtMatchCard, edge: String) -> void:
	_finalize_move(card)
	card.zone = MtMatchCard.ZONE_DECK
	card.rested = false
	card.face_down = true
	if edge == "bottom":
		ps.deck.append(card)
		_log("%s is placed at the bottom of P%d's deck." % [card.card_name(), ps.index])
	else:
		ps.deck.push_front(card)
		_log("%s is placed on top of P%d's deck." % [card.card_name(), ps.index])

func _return_to_deck(card: MtMatchCard, opts: Dictionary) -> void:
	var ps := _P(card.owner)
	_place_on_deck(ps, card, String(opts.get("edge", "top")))

func _trash_to_deck(ps: MtPlayerState, opts: Dictionary) -> void:
	var n := int(opts.get("n", 1))
	var edge := String(opts.get("edge", "bottom"))
	for i in range(n):
		if ps.trash.is_empty():
			break
		var c: MtMatchCard = ps.trash.pop_back()
		_place_on_deck(ps, c, edge)

func _trash_from_hand(ps: MtPlayerState, n: int, spec: Dictionary = {}) -> void:
	var pool: Array = _matching_hand(ps, spec)
	var moved := 0
	for i in range(mini(n, pool.size())):
		_move_to_trash(ps, pool[i])
		moved += 1
	if moved > 0:
		_log("P%d trashes %d card(s) from hand." % [ps.index, moved])
		_effect_did = true

func _add_active_don(ps: MtPlayerState, n: int, rested: bool = false) -> void:
	var added := 0
	for i in range(n):
		if ps.don_in_deck > 0 and ps.don_active < ps.don_deck_size:
			ps.don_in_deck -= 1
			ps.don_active += 1
			if rested:
				ps.don_rested += 1
			added += 1
	if added > 0:
		_log("P%d adds %d DON!! to the Active Area%s." % [ps.index, added, " rested" if rested else ""])

func _set_don_active(ps: MtPlayerState, n: int) -> void:
	var amt := mini(n, ps.don_rested)
	ps.don_rested -= amt
	if amt > 0:
		_log("P%d sets %d DON!! as active." % [ps.index, amt])

func _return_don_to_deck(ps: MtPlayerState, n: int) -> int:
	var left := n
	# Cost-area Active first, then rested, then given DON!! on Leader/Characters.
	var free := ps.get_available_don()
	var take_free := mini(left, free)
	ps.don_active -= take_free
	ps.don_in_deck += take_free
	left -= take_free
	var take_rest := mini(left, ps.don_rested)
	ps.don_rested -= take_rest
	ps.don_active -= take_rest
	ps.don_in_deck += take_rest
	left -= take_rest
	if left > 0:
		var hosts: Array = []
		if ps.leader:
			hosts.append(ps.leader)
		hosts.append_array(ps.field)
		for host in hosts:
			while left > 0 and host.don_count() > 0:
				host.attached_don.pop_back()
				ps.don_active -= 1
				ps.don_in_deck += 1
				left -= 1
	var moved := n - left
	if moved > 0:
		_log("P%d returns %d DON!! to their DON!! deck." % [ps.index, moved])
		_fire_window(ps, "on_don_return", {"don_returned": moved})
	return moved

func _life_cost_ps(card: MtMatchCard, spec: Dictionary) -> MtPlayerState:
	if String(spec.get("player", "self")) == "opp":
		return _P(_opp(card.owner))
	return _P(card.owner)

func _halt_for_choice(card: MtMatchCard, actions: Array, i: int) -> bool:
	if pending_choice == null:
		return false
	if not pending_choice.has("rest_actions"):
		var rest: Array = []
		if i >= 0 and i + 1 < actions.size():
			rest = actions.slice(i + 1)
		pending_choice["rest_actions"] = rest
	if String(pending_choice.get("source_uid", "")) == "":
		pending_choice["source_uid"] = card.uid
	_effect_depth -= 1
	return true

func _pay_activation(card: MtMatchCard, spec: Dictionary, actions: Array = [], act_idx: int = -1) -> bool:
	var cost_acts: Array = spec.get("actions", [])
	var optional := bool(spec.get("optional", false))
	if cost_acts.is_empty():
		return true
	if not _can_pay_acts(card, cost_acts):
		return false
	if optional and not auto_resolve_choices:
		var rest: Array = []
		if act_idx >= 0 and act_idx + 1 < actions.size():
			rest = actions.slice(act_idx + 1)
		pending_choice = {
			"type": "pay_optional", "player": card.owner, "source_uid": card.uid,
			"pay": cost_acts, "rest_actions": rest,
		}
		_log("P%d may pay this cost." % card.owner)
		return false
	_pay_acts(card, cost_acts)
	_effect_did = true
	return true

func _can_pay_acts(card: MtMatchCard, cost_acts: Array) -> bool:
	for act in cost_acts:
		if not (act is Array) or act.is_empty():
			continue
		var kind: String = act[0]
		var spec = act[1] if act.size() > 1 else {}
		if kind == MtEffectParser.TOK_TRASH_HAND:
			var nneed := int(spec.get("n", 1) if spec is Dictionary else 1)
			if _matching_hand(_P(card.owner), spec if spec is Dictionary else {}).size() < nneed:
				return false
		elif kind == MtEffectParser.TOK_HAND_TO_DECK:
			if _P(card.owner).hand.size() < int(spec.get("n", 1) if spec is Dictionary else 1):
				return false
		elif kind == MtEffectParser.TOK_TRASH_TO_DECK:
			if _P(card.owner).trash.size() < int(spec.get("n", 1) if spec is Dictionary else 1):
				return false
		elif kind == MtEffectParser.TOK_DON_MINUS:
			var ps := _P(card.owner)
			var pool := ps.get_available_don() + ps.don_rested + ps.get_attached_don_total()
			if pool < int(spec.get("n", 1) if spec is Dictionary else 1):
				return false
		elif kind == MtEffectParser.TOK_REST_SELF:
			if card.rested:
				return false
		elif kind == MtEffectParser.TOK_TRASH_SELF:
			if not _in_field(_P(card.owner), card):
				return false
		elif kind == MtEffectParser.TOK_REVEAL_HAND:
			if not _reveal_hand_ok(card, spec if spec is Dictionary else {}):
				return false
		elif kind == MtEffectParser.TOK_LIFE_TO_HAND or kind == MtEffectParser.TOK_TRASH_LIFE or kind == MtEffectParser.TOK_FACE_LIFE:
			var lps := _life_cost_ps(card, spec if spec is Dictionary else {})
			var need := int(spec.get("n", 1) if spec is Dictionary else 1)
			if bool(spec.get("all", false) if spec is Dictionary else false):
				if lps.life.is_empty():
					return false
			elif kind == MtEffectParser.TOK_FACE_LIFE:
				if lps.life.is_empty():
					return false
			elif lps.life.size() < need:
				return false
	return true

func _pay_acts(card: MtMatchCard, cost_acts: Array) -> void:
	for act in cost_acts:
		if not (act is Array) or act.is_empty():
			continue
		var kind2: String = act[0]
		match kind2:
			MtEffectParser.TOK_TRASH_HAND:
				_trash_from_hand(_P(card.owner), int(act[1].get("n", 1)), act[1])
			MtEffectParser.TOK_HAND_TO_DECK:
				_hand_to_deck(_P(card.owner), int(act[1].get("n", 1)), String(act[1].get("edge", "bottom")))
			MtEffectParser.TOK_TRASH_TO_DECK:
				_trash_to_deck(_P(card.owner), act[1])
			MtEffectParser.TOK_DON_MINUS:
				_return_don_to_deck(_P(card.owner), int(act[1].get("n", 1)))
			MtEffectParser.TOK_REST_SELF:
				card.rested = true
			MtEffectParser.TOK_REST_DON:
				var rps := _P(card.owner)
				var rn: int = act[1].get("n", 1)
				var max_restable := rps.don_active - rps.get_attached_don_total()
				rps.don_rested = clamp(rps.don_rested + rn, 0, max_restable)
			MtEffectParser.TOK_TRASH_SELF:
				_move_to_trash(_P(card.owner), card)
			MtEffectParser.TOK_REVEAL_HAND:
				_log("P%d reveals the required card(s) from their hand." % card.owner)
			MtEffectParser.TOK_LIFE_TO_HAND:
				_resolve_life_to_hand(card, act[1])
				if pending_choice != null:
					return
			MtEffectParser.TOK_TRASH_LIFE:
				var tps := _life_cost_ps(card, act[1])
				var tn: int = act[1].get("n", 1)
				if bool(act[1].get("all", false)):
					tn = tps.life.size()
				life_to_trash(tps, tn)
			MtEffectParser.TOK_FACE_LIFE:
				_resolve_face_life(_life_cost_ps(card, act[1]), act[1], card)
				if pending_choice != null:
					return

func _reveal_hand_ok(card: MtMatchCard, opts: Dictionary) -> bool:
	var n := int(opts.get("number", opts.get("n", 1)))
	var who := _P(card.owner)
	if String(opts.get("player", "self")) == "opp":
		who = _P(_opp(card.owner))
	var found := 0
	for c in who.hand:
		if _filter_matches(c, opts, card):
			found += 1
	if String(opts.get("player", "self")) == "opp":
		_log("P%d reveals %d card(s) from P%d's hand." % [card.owner, mini(n, who.hand.size()), who.index])
		return who.hand.size() >= n
	return found >= n

func _opp_choose(card: MtMatchCard, spec: Dictionary, actions: Array, act_idx: int) -> void:
	var rest: Array = []
	if act_idx >= 0 and act_idx + 1 < actions.size():
		rest = actions.slice(act_idx + 1)
	var kind := String(spec.get("kind", "trash_hand"))
	if kind == "modal":
		_begin_modal(card, spec, actions, act_idx, _opp(card.owner))
		return
	var chooser := _opp(card.owner)
	if kind == "trash_hand":
		var whose := String(spec.get("whose", "controller"))
		var hp := card.owner if whose == "controller" else chooser
		var hand: Array = _P(hp).hand.duplicate()
		if hand.is_empty():
			return
		if auto_resolve_choices:
			_move_to_trash(_P(hp), hand[0])
			_effect_did = true
			return
		var uids: Array = []
		for c in hand:
			uids.append(c.uid)
		pending_choice = {
			"type": "pick", "kind": "trash", "player": chooser, "source_uid": card.uid,
			"max": 1, "up_to": false, "candidates": uids, "opts": {"owner": hp},
			"rest_actions": rest,
		}
		return
	if kind == "bounce":
		var filt: Dictionary = spec.get("filter", {})
		var cands := _collect_filter(card, filt)
		if cands.is_empty():
			return
		if auto_resolve_choices:
			_bounce_to_hand(cands[0])
			_effect_did = true
			return
		var uids2: Array = []
		for c2 in cands:
			uids2.append(c2.uid)
		pending_choice = {
			"type": "pick", "kind": "bounce", "player": chooser, "source_uid": card.uid,
			"max": 1, "up_to": false, "candidates": uids2, "opts": filt, "rest_actions": rest,
		}

func _begin_modal(card: MtMatchCard, spec: Dictionary, actions: Array, act_idx: int, chooser: int) -> void:
	var rest: Array = []
	if act_idx >= 0 and act_idx + 1 < actions.size():
		rest = actions.slice(act_idx + 1)
	var options: Array = spec.get("options", [])
	if options.is_empty():
		return
	if auto_resolve_choices:
		_resolve_actions(card, options[0], {})
		_effect_did = true
		return
	pending_choice = {
		"type": "modal", "player": chooser, "source_uid": card.uid,
		"options": options, "rest_actions": rest, "max": options.size() - 1, "up_to": true,
	}

func _ps_of(card: MtMatchCard, spec) -> MtPlayerState:
	if spec is Dictionary and String(spec.get("player", "self")) == "opp":
		return _P(_opp(card.owner))
	return _P(card.owner)

func _matching_hand(ps: MtPlayerState, spec: Dictionary) -> Array:
	var out: Array = []
	for c in ps.hand:
		if String(spec.get("card_type", "")) == "" or _filter_matches(c, spec, null):
			out.append(c)
	return out

func _hand_to_deck(ps: MtPlayerState, n: int, edge: String) -> void:
	for i in range(n):
		if ps.hand.is_empty():
			break
		_place_on_deck(ps, ps.hand[0], edge)

func _opp_may(card: MtMatchCard, spec: Dictionary, actions: Array, act_idx: int) -> void:
	var rest: Array = []
	if act_idx >= 0 and act_idx + 1 < actions.size():
		rest = actions.slice(act_idx + 1)
	var do_acts: Array = spec.get("do", [])
	var else_acts: Array = spec.get("else", [])
	if auto_resolve_choices:
		# Opponent takes the optional if they can pay/perform it.
		if not do_acts.is_empty():
			_resolve_actions(card, do_acts, {})
			if _effect_did:
				return
		_resolve_actions(card, else_acts, {})
		return
	pending_choice = {
		"type": "opp_may", "player": _opp(card.owner), "source_uid": card.uid,
		"do": do_acts, "else": else_acts, "rest_actions": rest, "max": 1, "up_to": true,
	}

func _auto_attach_target(ps: MtPlayerState, source: MtMatchCard) -> MtMatchCard:
	# Prefer the source card if it's a Character/Leader on field, else strongest.
	if source != null and _in_field(ps, source) and (source.is_character() or source.is_leader()):
		return source
	for c in ps.field:
		if c.is_character():
			return c
	return ps.leader

func _don_give_spec(raw) -> Dictionary:
	if raw is Dictionary:
		return {
			"n": int(raw.get("n", 1)),
			"up_to": bool(raw.get("up_to", true)),
			"from": String(raw.get("from", "rested")),
		}
	return {"n": int(raw), "up_to": true, "from": "rested"}

func _give_don_available(ps: MtPlayerState, from: String) -> int:
	if from == "active":
		return ps.get_available_don()
	return ps.don_rested

func _perform_give_don(ps: MtPlayerState, target: MtMatchCard, n: int, from: String) -> int:
	if target == null or n <= 0:
		return 0
	var amt := mini(n, _give_don_available(ps, from))
	if amt <= 0:
		return 0
	if from == "rested":
		ps.don_rested -= amt
	_attach_don_to(target, amt)
	if from == "rested":
		_log("P%d gives %d rested DON!! to %s." % [ps.index, amt, target.card_name()])
	else:
		_log("P%d gives %d DON!! to %s." % [ps.index, amt, target.card_name()])
	var gps := _P(target.owner)
	var gsrc: Array = []
	if gps.leader:
		gsrc.append(gps.leader)
	gsrc.append_array(gps.field)
	for c in gsrc:
		for tok in fx(c).get("on_give_don", []):
			var scope := String(tok.get("give_scope", ""))
			if scope == "any_own" or c == target:
				_resolve_actions(c, tok.get("actions", []), {})
	return amt

func _begin_give_don(card: MtMatchCard, raw, actions: Array, act_idx: int) -> void:
	var spec := _don_give_spec(raw)
	var ps := _P(card.owner)
	var maxn := mini(int(spec.n), _give_don_available(ps, spec.from))
	if maxn <= 0:
		return
	if auto_resolve_choices:
		var target := _auto_attach_target(ps, card)
		if target != null:
			_perform_give_don(ps, target, maxn, spec.from)
		return
	var rest: Array = []
	if act_idx >= 0 and act_idx + 1 < actions.size():
		rest = actions.slice(act_idx + 1)
	pending_choice = {
		"type": "give_don",
		"player": card.owner,
		"source_uid": card.uid,
		"max": maxn,
		"up_to": bool(spec.up_to),
		"from": spec.from,
		"rest_actions": rest,
	}
	_log("P%d must choose: give up to %d rested DON!! to their Leader or 1 Character." % [card.owner, maxn])

func _give_don_targets(ps: MtPlayerState) -> Array:
	var out: Array = []
	if ps.leader != null:
		out.append(ps.leader)
	for c in ps.field:
		if (c as MtMatchCard).is_character():
			out.append(c)
	out.sort_custom(func(a, b): return a.base_power() > b.base_power())
	return out

func _find_any_uid(uid: String) -> MtMatchCard:
	if uid.is_empty():
		return null
	for p in range(2):
		var c := _find_card_by_uid(p, uid)
		if c != null:
			return c
	return null

func _legal_choose_effect(action: Dictionary) -> Dictionary:
	if pending_choice == null:
		return _reject("no_choice", "No effect choice is pending.")
	var ptype := String(pending_choice.get("type", ""))
	if ptype == "pick":
		var cands: Array = pending_choice.get("candidates", [])
		var maxn := int(pending_choice.get("max", 1))
		var up_to := bool(pending_choice.get("up_to", true))
		var uids: Array = action.get("uids", [])
		if uids.is_empty() and String(action.get("target_uid", "")) != "":
			uids = [String(action.get("target_uid", ""))]
		if int(action.get("n", 1)) == 0 or uids.is_empty():
			if not up_to and maxn > 0:
				return _reject("must_pick", "This effect is not optional.")
			return _ok()
		if uids.size() > maxn:
			return _reject("too_many", "Choose at most %d card(s)." % maxn)
		for u in uids:
			if not cands.has(u) and not cands.has(String(u)):
				return _reject("bad_target", "That card is not a legal choice.")
		return _ok()
	if ptype == "replace_ko" or ptype == "opp_may":
		var n2 := int(action.get("n", 1))
		if n2 != 0 and n2 != 1:
			return _reject("bad_amount", "Choose yes or no.")
		return _ok()
	if ptype == "modal":
		if bool(action.get("skip", false)):
			return _ok()
		var opts: Array = pending_choice.get("options", [])
		var n3 := int(action.get("n", 0))
		if n3 < 0 or n3 >= opts.size():
			return _reject("bad_option", "Choose one of the listed options.")
		return _ok()
	if ptype == "look_order" or ptype == "start_turn":
		return _ok()
	if ptype == "pay_optional":
		var pn := int(action.get("n", 0))
		if pn != 0 and pn != 1:
			return _reject("bad_amount", "Pay the cost, or decline it.")
		return _ok()
	if ptype == "life_edge":
		var edge := String(action.get("edge", ""))
		if edge != "top" and edge != "bottom":
			return _reject("bad_edge", "Choose the top or the bottom.")
		return _ok()
	if ptype != "give_don":
		return _reject("no_choice", "No effect choice is pending.")
	var n := int(action.get("n", 0))
	var maxn := int(pending_choice.get("max", 0))
	var up_to := bool(pending_choice.get("up_to", true))
	if n < 0 or n > maxn:
		return _reject("bad_amount", "You may give up to %d DON!!." % maxn)
	if n == 0:
		if not up_to and maxn > 0:
			return _reject("must_give", "This effect is not optional.")
		return _ok()
	var player := int(pending_choice.get("player", 0))
	var target := _find_card_by_uid(player, String(action.get("target_uid", "")))
	if target == null or not _in_field(_P(player), target):
		return _reject("bad_target", "Choose your Leader or 1 of your Characters.")
	if not target.is_leader() and not target.is_character():
		return _reject("bad_target", "DON!! can only be given to a Leader or Character.")
	return _ok()

func _do_choose_effect(action: Dictionary) -> Dictionary:
	var pc: Dictionary = pending_choice
	if String(pc.get("type", "")) == "start_turn":
		pending_choice = null
		if int(action.get("n", 1)) <= 0 or bool(action.get("skip", false)):
			_start_turn_queue.clear()
			return _ok()
		_drain_start_of_turn()
		return _ok()
	if String(pc.get("type", "")) == "pay_optional":
		var pay_rest: Array = pc.get("rest_actions", [])
		var payer := _find_any_uid(String(pc.get("source_uid", "")))
		pending_choice = null
		if int(action.get("n", 0)) <= 0 or bool(action.get("skip", false)) or payer == null:
			return _ok()
		_pay_acts(payer, pc.get("pay", []))
		_effect_did = true
		if pending_choice != null:
			pending_choice["rest_actions"] = pay_rest
			if String(pending_choice.get("source_uid", "")) == "":
				pending_choice["source_uid"] = payer.uid
			return _ok()
		if not pay_rest.is_empty():
			_resolve_actions(payer, pay_rest, {})
		return _ok()
	if String(pc.get("type", "")) == "life_edge":
		var edge_rest: Array = pc.get("rest_actions", [])
		var edge_src := _find_any_uid(String(pc.get("source_uid", "")))
		var edge_opts: Dictionary = (pc.get("opts", {}) as Dictionary).duplicate()
		edge_opts["edge"] = String(action.get("edge", "top"))
		edge_opts["_edge_chosen"] = true
		var edge_mode := String(pc.get("mode", "to_hand"))
		var life_owner := int(pc.get("life_owner", edge_src.owner if edge_src != null else 0))
		pending_choice = null
		if edge_mode == "face":
			_resolve_face_life(_P(life_owner), edge_opts, edge_src)
		elif edge_src != null:
			_resolve_life_to_hand(edge_src, edge_opts)
		if edge_src != null and not edge_rest.is_empty() and pending_choice == null:
			_resolve_actions(edge_src, edge_rest, {})
		return _ok()
	if String(pc.get("type", "")) == "replace_ko":
		pending_choice = null
		var victim := _find_any_uid(String(pc.get("victim_uid", "")))
		var src := _find_any_uid(String(pc.get("source_uid", "")))
		if int(action.get("n", 1)) > 0 and src != null:
			_pay_acts(src, pc.get("pay", []))
			src.replace_ko_used = true
			if victim:
				_log("%s is not K.O.'d (replaced)." % victim.card_name())
			_effect_did = true
			return _ok()
		if victim:
			var fin := String(pc.get("finish", "ko"))
			if fin == "bounce":
				_commit_bounce(victim)
			elif fin == "remove":
				_commit_remove(_P(victim.owner), victim)
			else:
				_finish_ko(victim)
		return _ok()
	if String(pc.get("type", "")) == "opp_may":
		pending_choice = null
		var source := _find_any_uid(String(pc.get("source_uid", "")))
		if source == null:
			return _ok()
		if int(action.get("n", 1)) > 0:
			_resolve_actions(source, pc.get("do", []), {})
		else:
			_resolve_actions(source, pc.get("else", []), {})
		var rest_m: Array = pc.get("rest_actions", [])
		if not rest_m.is_empty():
			_resolve_actions(source, rest_m, {})
		return _ok()
	if String(pc.get("type", "")) == "modal":
		pending_choice = null
		var source2 := _find_any_uid(String(pc.get("source_uid", "")))
		var options: Array = pc.get("options", [])
		var idx := int(action.get("n", 0))
		if source2 != null and not bool(action.get("skip", false)) and idx >= 0 and idx < options.size():
			_resolve_actions(source2, options[idx], {})
			_effect_did = true
		if source2 != null:
			var rest2: Array = pc.get("rest_actions", [])
			if not rest2.is_empty():
				_resolve_actions(source2, rest2, {})
		return _ok()
	if String(pc.get("type", "")) == "look_order":
		return _apply_look_order(action, pc)
	if String(pc.get("type", "")) == "pick":
		var rest_actions: Array = pc.get("rest_actions", [])
		var source_uid := String(pc.get("source_uid", ""))
		var kind := String(pc.get("kind", ""))
		var opts: Dictionary = pc.get("opts", {})
		var maxn := int(pc.get("max", 1))
		var picked: Array = pc.get("picked", []).duplicate()
		var uids: Array = action.get("uids", [])
		if uids.is_empty() and String(action.get("target_uid", "")) != "":
			uids = [String(action.get("target_uid", ""))]
		if int(action.get("n", 1)) == 0:
			uids = []
		else:
			for u in uids:
				var us := String(u)
				if not picked.has(us):
					picked.append(us)
			if picked.size() < maxn:
				var left: Array = []
				for cu in pc.get("candidates", []):
					if not picked.has(String(cu)):
						left.append(cu)
				pending_choice = pc.duplicate()
				pending_choice["picked"] = picked
				pending_choice["candidates"] = left
				return _ok()
		pending_choice = null
		var cards: Array = []
		var use_uids: Array = picked if not picked.is_empty() else uids
		for u2 in use_uids:
			var c := _find_any_uid(String(u2))
			if c != null:
				cards.append(c)
		if kind == "look_deck":
			var taken: Array = []
			for tu in pc.get("taken_uids", []):
				var tc := _find_any_uid(String(tu))
				if tc != null:
					taken.append(tc)
			var chosen: MtMatchCard = null
			if not cards.is_empty():
				chosen = cards[0]
			if chosen != null:
				_finish_look_choice(chosen, opts)
				taken.erase(chosen)
			var src0 := _find_any_uid(source_uid)
			var ps := _P(int(pc.get("player", 0))) if src0 == null else _P(src0.owner)
			_return_look_rest(ps, taken, opts, src0, rest_actions)
			if pending_choice != null:
				return _ok()
		else:
			_apply_pick(kind, cards, opts)
		var source := _find_any_uid(source_uid)
		if source != null and not rest_actions.is_empty() and pending_choice == null:
			_resolve_actions(source, rest_actions, {})
		return _ok()
	var n := int(action.get("n", 0))
	var player := int(pc.get("player", 0))
	var from := String(pc.get("from", "rested"))
	var rest_actions2: Array = pc.get("rest_actions", [])
	var source_uid2 := String(pc.get("source_uid", ""))
	pending_choice = null
	if n > 0:
		var target := _find_card_by_uid(player, String(action.get("target_uid", "")))
		_perform_give_don(_P(player), target, n, from)
	else:
		_log("P%d gives 0 DON!!." % player)
	var source2 := _find_card_by_uid(player, source_uid2)
	if source2 != null and not rest_actions2.is_empty():
		_resolve_actions(source2, rest_actions2, {})
	return _ok()

func _apply_look_order(action: Dictionary, pc: Dictionary) -> Dictionary:
	var kind := String(pc.get("kind", "deck"))
	var skip := bool(action.get("skip", false)) or int(action.get("n", 1)) == 0
	var uids: Array = action.get("uids", [])
	if uids.is_empty() and String(action.get("target_uid", "")) != "":
		uids = [String(action.get("target_uid", ""))]
	var picked: Array = pc.get("picked", []).duplicate()
	if not skip:
		for u in uids:
			var us := String(u)
			if not picked.has(us):
				picked.append(us)
		var left: Array = []
		for cu in pc.get("candidates", []):
			if not picked.has(String(cu)):
				left.append(cu)
		if not left.is_empty():
			pending_choice = pc.duplicate()
			pending_choice["picked"] = picked
			pending_choice["candidates"] = left
			return _ok()
	pending_choice = null
	if String(action.get("rest", "")) != "":
		var opts2: Dictionary = (pc.get("opts", {}) as Dictionary).duplicate()
		opts2["rest"] = String(action.get("rest", "bottom"))
		pc = pc.duplicate()
		pc["opts"] = opts2
	if kind == "life":
		var who := _P(int(pc.get("owner", 0)))
		var ordered: Array = []
		for u3 in picked:
			var lc := _find_any_uid(String(u3))
			if lc != null:
				ordered.append(lc)
		if skip:
			for cu2 in pc.get("all_uids", pc.get("candidates", [])):
				var lc2 := _find_any_uid(String(cu2))
				if lc2 != null and not ordered.has(lc2):
					ordered.append(lc2)
		if ordered.size() == who.life.size():
			# First chosen is the top of Life (last index).
			ordered.reverse()
			who.life = ordered
			_log("P%d reorders their Life." % who.index)
	else:
		var pool: Array = pc.get("all_uids", pc.get("candidates", []))
		var taken: Array = []
		for u in pool:
			var tc := _find_any_uid(String(u))
			if tc != null:
				taken.append(tc)
		var ordered2: Array = []
		if not skip:
			for u5 in picked:
				var oc := _find_any_uid(String(u5))
				if oc != null and taken.has(oc):
					ordered2.append(oc)
					taken.erase(oc)
		ordered2.append_array(taken)
		if skip and bool((pc.get("opts", {}) as Dictionary).get("shuffle", false)):
			_shuffle(ordered2)
		var ps := _P(int(pc.get("owner", 0)))
		_place_look_rest_ordered(ps, ordered2, pc.get("opts", {}))
	var source := _find_any_uid(String(pc.get("source_uid", "")))
	var rest: Array = pc.get("rest_actions", [])
	if source != null and not rest.is_empty():
		_resolve_actions(source, rest, {})
	return _ok()

func _place_look_rest_ordered(ps: MtPlayerState, taken: Array, opts: Dictionary) -> void:
	var rest := String(opts.get("rest", "bottom"))
	if rest == "top":
		for i in range(taken.size() - 1, -1, -1):
			var c: MtMatchCard = taken[i]
			_limbo.erase(c)
			c.zone = MtMatchCard.ZONE_DECK
			c.face_down = true
			ps.deck.push_front(c)
		return
	_place_look_rest(ps, taken, opts)

func _do_cancel_choice(_action: Dictionary) -> Dictionary:
	if pending_choice == null:
		if in_battle():
			return _do_pass_battle({})
		return _reject("nothing_to_cancel", "Nothing to cancel.")
	var ptype := String(pending_choice.get("type", ""))
	if ptype == "life_trigger":
		return _do_trigger_no({"type": ACTION_TRIGGER_NO, "player": int(pending_choice.get("player", 0)),
			"card_uid": String(pending_choice.get("card_uid", ""))})
	if ptype == "pay_optional":
		return _do_choose_effect({"type": ACTION_CHOOSE_EFFECT, "n": 0, "skip": true})
	if ptype == "life_edge":
		return _do_choose_effect({"type": ACTION_CHOOSE_EFFECT, "edge": "top"})
	if ptype == "mulligan":
		return _do_keep_hand({"type": ACTION_KEEP_HAND, "player": int(pending_choice.get("player", 0))})
	if ptype == "modal":
		return _do_choose_effect({"type": ACTION_CHOOSE_EFFECT, "n": 0, "skip": true})
	if ptype == "start_turn":
		return _do_choose_effect({"type": ACTION_CHOOSE_EFFECT, "n": 0, "skip": true})
	if ptype == "look_order":
		return _do_choose_effect({"type": ACTION_CHOOSE_EFFECT, "n": 0, "skip": true, "uids": []})
	return _do_choose_effect({"type": ACTION_CHOOSE_EFFECT, "n": 0, "uids": [], "target_uid": ""})

func _attach_don_to(target: MtMatchCard, n: int) -> void:
	var cap := _P(target.owner).don_deck_size
	for i in range(n):
		if target.don_count() >= cap:
			break
		target.attached_don.append(_mk_don_matchcard(target.owner))
	# No active-area deduction: attach adds as-is from Active Area (already counted).

func _auto_ko(source: MtMatchCard, opts: Dictionary) -> void:
	if bool(opts.get("this_card", false)):
		_ko(source)
		return
	var ps := _P(source.owner)
	if String(opts.get("player", "opp")) == "opp":
		ps = _P(_opp(source.owner))
	var candidates: Array = []
	var pool: Array = []
	pool.append_array(ps.field)
	if bool(opts.get("include_leader", false)) and ps.leader != null:
		pool.append(ps.leader)
	for c in pool:
		if not c.is_character() and not (bool(opts.get("include_leader", false)) and c.is_leader()):
			continue
		if bool(opts.get("rested_only", false)) and not c.rested:
			continue
		if bool(opts.get("active_only", false)) and c.rested:
			continue
		var by_name := String(opts.get("by_name", ""))
		if by_name != "" and not c.card_name().contains(by_name) and String(c.card.get("name", "")) != by_name:
			continue
		var by_type := String(opts.get("by_type", ""))
		if by_type != "" and not c.traits().has(by_type):
			continue
		if opts.get("has_cost", false):
			var cost_ok := false
			if opts.op == "<=":
				cost_ok = c.cost_value() <= opts.cost
			elif opts.op == ">=":
				cost_ok = c.cost_value() >= opts.cost
			else:
				cost_ok = c.cost_value() == opts.cost
			if not cost_ok:
				continue
		if int(opts.get("by_power", 0)) > 0 and c.base_power() > int(opts.get("by_power", 0)):
			continue
		candidates.append(c)
	candidates.sort_custom(func(a, b): return a.base_power() > b.base_power())
	var num := opts.get("number", 1)
	if num <= 0:
		num = candidates.size()
	var targets := candidates.slice(0, num)
	for c in targets:
		_ko(c)

func _apply_power_bonus(card: MtMatchCard, popts: Dictionary) -> void:
	var who: String = popts.get("who", "self")
	var amount: int = popts.get("amount", 0)
	var dur := String(popts.get("dur", "turn"))
	var owner := card.owner
	var targets: Array = []
	match who:
		"all_self_chars":
			targets.append_array(_P(owner).field)
		"opp_char":
			var oc: Array = _P(_opp(owner)).field.duplicate()
			oc.sort_custom(func(a, b): return a.base_power() > b.base_power())
			if not oc.is_empty():
				targets.append(oc[0])
		"opp_any":
			var pool2: Array = _P(_opp(owner)).field.duplicate()
			if _P(_opp(owner)).leader:
				pool2.append(_P(_opp(owner)).leader)
			pool2.sort_custom(func(a, b): return a.base_power() > b.base_power())
			if not pool2.is_empty():
				targets.append(pool2[0])
		"self_or_chosen":
			targets.append(_auto_attach_target(_P(owner), card))
		"counter_host":
			var host = popts.get("host")
			if host != null:
				targets.append(host)
			elif not battle.is_empty() and battle.get("defender") != null:
				targets.append(battle.get("defender"))
		_:
			targets.append(card)
	for target in targets:
		if target == null:
			continue
		target.power_bonus += amount
		_turn_bonuses.append({"card": target, "amount": amount, "dur": dur, "owner": owner})

func _over_loss(player: int, reason: String) -> void:
	if over:
		return
	var winner_p := _opp(player)
	# Nami OP03-040 / P-117: "When your deck is reduced to 0, you win the game
	# instead of losing." -- only the deck-out loss condition reverses.
	if reason == "Deck is empty" and _leader_rules(_P(player)).get("deckout_is_win", false):
		winner_p = player
	over = true
	winner = winner_p
	win_reason = "%s: P%d loses (%s)" % [reason, player, reason]
	_log("GAME OVER. Winner P%d. %s" % [winner, reason])

func _check_win_on_block() -> void:
	var zero := false
	for p in players:
		if (p as MtPlayerState).life.is_empty():
			zero = true
			break
	if not zero:
		return
	for p in players:
		var src: Array = []
		if (p as MtPlayerState).leader:
			src.append((p as MtPlayerState).leader)
		src.append_array((p as MtPlayerState).field)
		for c in src:
			if bool(fx(c).get("win_on_block_zero_life", false)):
				winner = (c as MtMatchCard).owner
				over = true
				win_reason = "Blocker activated at 0 Life"
				_log("GAME OVER. Winner P%d. %s" % [winner, win_reason])
				return

# --- Legal move generation (adjudicator enumeration) ---
func get_legal_actions() -> Array:
	var out: Array = []
	if over:
		return out
	# A pending choice gates everything until answered.
	if pending_choice != null:
		var ptype: String = pending_choice.get("type", "")
		if ptype == "life_trigger":
			out.append({"type": ACTION_TRIGGER_YES, "player": pending_choice.get("player", 0),
				"card_uid": pending_choice.get("card_uid", "")})
			out.append({"type": ACTION_TRIGGER_NO, "player": pending_choice.get("player", 0),
				"card_uid": pending_choice.get("card_uid", "")})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "mulligan":
			out.append({"type": ACTION_KEEP_HAND, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_MULLIGAN, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "pay_optional":
			out.append({"type": ACTION_CHOOSE_EFFECT, "n": 1, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CHOOSE_EFFECT, "n": 0, "skip": true, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "life_edge":
			out.append({"type": ACTION_CHOOSE_EFFECT, "edge": "top", "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CHOOSE_EFFECT, "edge": "bottom", "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "give_don":
			var gp := int(pending_choice.get("player", 0))
			var gps := _P(gp)
			var maxn := int(pending_choice.get("max", 0))
			var up_to := bool(pending_choice.get("up_to", true))
			var from := String(pending_choice.get("from", "rested"))
			if maxn > 0:
				for t in _give_don_targets(gps):
					out.append({"type": ACTION_CHOOSE_EFFECT, "n": maxn,
						"target_uid": t.uid, "from": from})
			if up_to or maxn <= 0:
				out.append({"type": ACTION_CHOOSE_EFFECT, "n": 0, "target_uid": ""})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "pick":
			var maxn2 := int(pending_choice.get("max", 1))
			var up2 := bool(pending_choice.get("up_to", true))
			for uid in pending_choice.get("candidates", []):
				out.append({"type": ACTION_CHOOSE_EFFECT, "n": maxn2, "target_uid": uid,
					"uids": [uid]})
			if up2:
				out.append({"type": ACTION_CHOOSE_EFFECT, "n": 0, "target_uid": "", "uids": []})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "replace_ko" or ptype == "opp_may":
			out.append({"type": ACTION_CHOOSE_EFFECT, "n": 1, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CHOOSE_EFFECT, "n": 0, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "modal" or ptype == "look_order":
			var options: Array = pending_choice.get("options", [])
			for oi in range(options.size()):
				out.append({"type": ACTION_CHOOSE_EFFECT, "n": oi, "player": pending_choice.get("player", 0)})
			for uid2 in pending_choice.get("candidates", []):
				out.append({"type": ACTION_CHOOSE_EFFECT, "n": 1, "target_uid": uid2, "uids": [uid2]})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
		elif ptype == "start_turn":
			out.append({"type": ACTION_CHOOSE_EFFECT, "n": 1, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CHOOSE_EFFECT, "n": 0, "skip": true, "player": pending_choice.get("player", 0)})
			out.append({"type": ACTION_CANCEL_CHOICE})
			return out
	if in_battle():
		out = _battle_actions()
		out.append({"type": ACTION_CANCEL_CHOICE})
		return out
	if phase != Phase.MAIN:
		out.append({"type": ACTION_END_TURN})
		return out
	var ps := _P(active)
	# End turn
	out.append({"type": ACTION_END_TURN})
	# Play Characters / Stages
	for card in ps.hand:
		if card.card_type() == "Character":
			if ps.field.size() < 5:
				if _legal_play({"type": ACTION_PLAY, "card_uid": card.uid}).ok:
					out.append({"type": ACTION_PLAY, "card_uid": card.uid, "hand_idx": ps.hand.find(card)})
			else:
				for vic in ps.field:
					var ov := {"type": ACTION_PLAY, "card_uid": card.uid, "trash_uid": vic.uid}
					if _legal_play(ov).ok:
						out.append(ov)
		elif card.card_type() == "Stage" and _legal_play({"type": ACTION_PLAY, "card_uid": card.uid}).ok:
			out.append({"type": ACTION_PLAY, "card_uid": card.uid, "hand_idx": ps.hand.find(card)})
		if card.card_type() == "Event" and _legal_play_event({"type": ACTION_PLAY_EVENT, "card_uid": card.uid}).ok:
			out.append({"type": ACTION_PLAY_EVENT, "card_uid": card.uid})
	# Activate effects
	for c in ps.field:
		if _legal_activate({"type": ACTION_ACTIVATE, "card_uid": c.uid}).ok:
			out.append({"type": ACTION_ACTIVATE, "card_uid": c.uid})
	if ps.leader != null and _legal_activate({"type": ACTION_ACTIVATE, "card_uid": ps.leader.uid}).ok:
		out.append({"type": ACTION_ACTIVATE, "card_uid": ps.leader.uid})
	if ps.stage != null and _legal_activate({"type": ACTION_ACTIVATE, "card_uid": ps.stage.uid}).ok:
		out.append({"type": ACTION_ACTIVATE, "card_uid": ps.stage.uid})
	# Attach DON
	if ps.get_available_don() > 0:
		for target in ps.field:
			out.append({"type": ACTION_ATTACH_DON, "card_uid": target.uid})
		if ps.leader != null:
			out.append({"type": ACTION_ATTACH_DON, "card_uid": ps.leader.uid})
	# Attacks
	var ops := _P(_opp(active))
	for atk in [ps.leader] if ps.leader else []:
		if _legal_attack({"type": ACTION_ATTACK, "attacker": atk.uid, "target": _default_attack_target(ops).uid}).ok:
			out.append({"type": ACTION_ATTACK, "attacker": atk.uid, "target": _default_attack_target(ops).uid})
	for atk in ps.field:
		var targets := _attack_targets(atk)
		for tgt in targets:
			if _legal_attack({"type": ACTION_ATTACK, "attacker": atk.uid, "target": tgt.uid}).ok:
				out.append({"type": ACTION_ATTACK, "attacker": atk.uid, "target": tgt.uid})
	return out

func _default_attack_target(ops: MtPlayerState) -> MtMatchCard:
	for c in ops.field:
		if c.rested:
			return c
	return ops.leader

func _attack_targets(atk: MtMatchCard) -> Array:
	var ops := _P(_opp(active))
	var targets: Array = []
	for c in ops.field:
		if c.rested or _can_attack_active(atk):
			targets.append(c)
	if ops.leader != null:
		targets.append(ops.leader)
	return targets

func _battle_actions() -> Array:
	var out: Array = []
	var defender := _P(battle.defender_owner)
	var step: String = battle.get("step", "resolve")
	if step == "counter" or step == "counter2":
		for c in defender.hand:
			if _legal_counter({"type": ACTION_COUNTER, "card_uid": c.uid}).ok:
				out.append({"type": ACTION_COUNTER, "card_uid": c.uid})
	if step == "block":
		for c in defender.field:
			if _legal_block({"type": ACTION_BLOCK, "blocker": c.uid}).ok:
				out.append({"type": ACTION_BLOCK, "blocker": c.uid})
	out.append({"type": ACTION_PASS_BATTLE})
	return out

# --- Snapshot for UI ---
func snapshot(seer: int) -> Dictionary:
	var me := _P(seer)
	var foe := _P(_opp(seer))
	return {
		"turn": turn,
		"active": active,
		"phase": phase,
		"battle": battle_to_dict(),
		"over": over,
		"winner": winner,
		"win_reason": win_reason,
		"pending_choice": pending_choice,
		"me": _zone_dict(me),
		"foe": _zone_dict(foe),
	}

func _zone_dict(ps: MtPlayerState) -> Dictionary:
	var field_cards := []
	for c in ps.field:
		field_cards.append(card_to_dict(c))
	return {
		"hand": _cards(ps.hand),
		"deck": ps.deck.size(),
		"trash": _cards(ps.trash),
		"life": ps.life.size(),
		"field": field_cards,
		"stage": card_to_dict(ps.stage) if ps.stage else {},
		"leader": card_to_dict(ps.leader) if ps.leader else {},
		"don_active": ps.don_active,
		"don_rested": ps.don_rested,
		"don_deck": ps.don_in_deck,
	}

func _cards(arr: Array) -> Array:
	var out := []
	for c in arr:
		out.append(card_to_dict(c))
	return out

func card_to_dict(card: MtMatchCard) -> Dictionary:
	if card == null:
		return {}
	return {
		"uid": card.uid,
		"code": card.card_code(),
		"name": card.card_name(),
		"type": card.card_type(),
		"zone": card.zone,
		"rested": card.rested,
		"face_down": card.face_down,
		"power": card_power(card),
		"base_power": card.base_power(),
		"cost": play_cost(card) if card.zone == MtMatchCard.ZONE_HAND else card.cost_value(),
		"counter": card.counter_value(),
		"don": card.don_count(),
		"attacked": card.attacked_count,
		"played_this_turn": card.played_this_turn_value(),
		"activated_this_turn": card.activated_this_turn,
		"keywords": card.keywords(),
		"granted_keywords": card.granted_keywords.duplicate(),
		"owner": card.owner,
		"card": card,
	}

func battle_to_dict() -> Dictionary:
	if battle.is_empty():
		return {}
	return {
		"attacker": card_to_dict(battle.attacker) if battle.attacker else {},
		"defender": card_to_dict(battle.defender) if battle.defender else {},
		"target": card_to_dict(battle.target) if battle.target else {},
		"step": battle.step,
		"counter_bonus": battle.get("counter_bonus", 0),
	}
