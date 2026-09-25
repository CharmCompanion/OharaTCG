# res://scripts/match/ai/DummyAI.gd
# Deck-aware policy. Easy plays this directly and sometimes blunders.
# Medium and Pro use it as the MCTS rollout, so search follows the same plan:
# develop the hand, spend DON on a swing that connects, attack for Life or a
# K.O., counter only when it saves the battle, block a Life hit on the leader.
class_name MtDummyAI

extends RefCounted

# Easy blunders: with probability epsilon, play a uniform-random legal move.
var epsilon := 0.0
var rng := RandomNumberGenerator.new()
# Tournament inclusion, copies/4. Empty until a level loads card_weights.json.
var card_weights := {}

func _init() -> void:
	rng.seed = Time.get_ticks_usec()

func pick_action(engine: Object, _viewer: int = 1) -> Dictionary:
	var actions: Array = engine.get_legal_actions()
	if actions.is_empty():
		return {}
	if epsilon > 0.0 and rng.randf() < epsilon:
		return actions[rng.randi_range(0, actions.size() - 1)]
	var best: Dictionary = actions[0]
	var best_s := -1e9
	for a in actions:
		var s := _score(engine, a)
		if s > best_s:
			best_s = s
			best = a
	return best

func _score(engine: Object, a: Dictionary) -> float:
	var mt := engine as MtMatch
	var t := String(a.get("type", ""))
	if t == mt.ACTION_CANCEL_CHOICE:
		return -1000.0
	if t == mt.ACTION_TRIGGER_YES:
		return 500.0
	if t == mt.ACTION_TRIGGER_NO:
		return 10.0
	if t == mt.ACTION_KEEP_HAND:
		return _mulligan_score(mt, false)
	if t == mt.ACTION_MULLIGAN:
		return _mulligan_score(mt, true)
	if t == mt.ACTION_CHOOSE_EFFECT:
		return _score_choose(mt, a)
	if mt.in_battle():
		return _score_battle(mt, a)
	return _score_main(mt, a)

func _mulligan_score(mt: MtMatch, redraw: bool) -> float:
	var keep := _keep_names(mt)
	if keep.is_empty():
		return 30.0 if redraw else 80.0
	var hits := 0
	var who := mt.get_active_player()
	if mt.pending_choice != null:
		who = int(mt.pending_choice.get("player", who))
	var me: MtPlayerState = mt.players[who]
	for c in me.hand:
		for name in keep:
			if _name_hit(c.card_name(), name):
				hits += 1
				break
	if hits > 0:
		return 20.0 if redraw else 120.0
	return 90.0 if redraw else 40.0

func _keep_names(mt: MtMatch) -> Array:
	var data := MtAiLevels.load_json("res://data/ai/matchup_notes.json")
	var me: MtPlayerState = mt.players[mt.get_active_player()]
	var foe: MtPlayerState = mt.players[1 - me.index]
	if me.leader == null or foe.leader == null:
		return []
	var mine := me.leader.card_name().to_lower()
	var opp := foe.leader.card_name().to_lower()
	var out: Array = []
	for n in data.get("notes", []):
		if not (n is Dictionary):
			continue
		var s := String(n.get("self", "")).to_lower()
		var o := String(n.get("opp", "")).to_lower()
		if s.length() < 3 or o.length() < 3:
			continue
		if MtAiLevels.names_line_up(mine, s) and MtAiLevels.names_line_up(opp, o):
			out.append_array(n.get("keep", []))
	return out

func _name_hit(card_name: String, keep_entry: String) -> bool:
	var have := card_name.to_lower()
	for part in keep_entry.split(" "):
		var bit := part.to_lower()
		if bit.length() >= 4 and have.contains(bit):
			return true
		if bit.ends_with("s") and bit.length() >= 5 and have.contains(bit.substr(0, bit.length() - 1)):
			return true
	return false

func _score_choose(mt: MtMatch, a: Dictionary) -> float:
	if bool(a.get("skip", false)) or int(a.get("n", 1)) <= 0:
		return 20.0
	if String(a.get("edge", "")) == "bottom":
		return 40.0
	if String(a.get("edge", "")) == "top":
		return 60.0
	var uid := String(a.get("target_uid", a.get("card_uid", "")))
	if uid == "":
		var uids: Array = a.get("uids", [])
		if not uids.is_empty():
			uid = String(uids[0])
	var card := _find(mt, uid)
	if card == null:
		return 70.0
	return 100.0 + float(mt.card_power(card)) / 50.0 + float(card.cost_value())

func _score_battle(mt: MtMatch, a: Dictionary) -> float:
	var t := String(a.get("type", ""))
	var atk: MtMatchCard = mt.battle.get("attacker", null)
	var tgt: MtMatchCard = mt.battle.get("defender", null)
	if atk == null or tgt == null:
		return 10.0 if t == mt.ACTION_PASS_BATTLE else 0.0
	var atk_p := mt.card_power(atk)
	var def_p := mt.card_power(tgt) + int(mt.battle.get("counter_bonus", 0))
	var hits := atk_p >= def_p
	var on_leader := tgt.is_leader()
	if t == mt.ACTION_COUNTER:
		var card := _find(mt, String(a.get("card_uid", "")))
		var bonus := 0 if card == null else card.counter_value()
		if atk_p >= def_p and def_p + bonus > atk_p:
			return 500.0 - float(bonus) / 100.0
		return 5.0
	if t == mt.ACTION_BLOCK:
		if on_leader and hits:
			var blocker := _find(mt, String(a.get("blocker", "")))
			var p := 0 if blocker == null else mt.card_power(blocker)
			return 450.0 + (12000.0 - float(p)) / 100.0
		return 15.0
	# Pass.
	if on_leader and hits:
		return 40.0
	return 120.0

func _score_main(mt: MtMatch, a: Dictionary) -> float:
	var t := String(a.get("type", ""))
	var me: MtPlayerState = mt.players[mt.get_active_player()]
	var foe: MtPlayerState = mt.players[1 - me.index]
	var plan := _swing_plan(mt, me, foe)
	if t == mt.ACTION_END_TURN:
		return 35.0
	if t == mt.ACTION_PLAY or t == mt.ACTION_PLAY_EVENT:
		if plan == 2:
			return 50.0
		var card := _find(mt, String(a.get("card_uid", "")))
		if card == null:
			return 200.0
		var s := 380.0 + float(mt.card_power(card)) / 40.0
		if card.is_event():
			s += 30.0
		if mt.has_keyword(card, "Blocker"):
			s += 25.0
		if mt.has_keyword(card, "Rush"):
			s += 40.0
		s += float(card_weights.get(card.card_code(), 0.0)) * 36.0
		return s
	if t == mt.ACTION_ACTIVATE:
		return 40.0 if plan == 2 else 360.0
	if t == mt.ACTION_ATTACH_DON:
		return _score_attach(mt, me, foe, String(a.get("card_uid", "")), plan)
	if t == mt.ACTION_ATTACK:
		return _score_attack(mt, foe, a)
	return 1.0

# 0 = no Life this turn, 1 = a swing already connects, 2 = that swing is the last Life.
func _swing_plan(mt: MtMatch, me: MtPlayerState, foe: MtPlayerState) -> int:
	if foe.leader == null or (mt.turn == 1 and mt.active == mt.first_player_idx):
		return 0
	var lp := mt.card_power(foe.leader)
	var best := 0
	for atk in _attackers(mt, me):
		var p := mt.card_power(atk)
		if p >= lp:
			best = maxi(best, 2 if foe.life.size() <= 1 else 1)
		elif p + 1000 >= lp and me.get_available_don() > 0 and foe.life.size() <= 1:
			best = maxi(best, 2)
	return best

func _attackers(mt: MtMatch, me: MtPlayerState) -> Array:
	var out: Array = []
	var pool: Array = []
	if me.leader != null:
		pool.append(me.leader)
	pool.append_array(me.field)
	for c in pool:
		var card := c as MtMatchCard
		if card.rested:
			continue
		if card.played_this_turn and not mt.can_attack_turn_played(card):
			continue
		out.append(card)
	return out

func _score_attach(mt: MtMatch, me: MtPlayerState, foe: MtPlayerState, uid: String, plan: int) -> float:
	var card := _find(mt, uid)
	if card == null or foe.leader == null:
		return 20.0
	if card.rested or (card.played_this_turn and not mt.can_attack_turn_played(card)):
		return 25.0
	if plan == 2 and mt.card_power(card) >= mt.card_power(foe.leader):
		return 30.0
	var now := mt.card_power(card)
	var nxt := now + 1000
	var lp := mt.card_power(foe.leader)
	if now < lp and nxt >= lp:
		return 1700.0 if foe.life.size() <= 1 else 340.0
	for body in foe.field:
		var bp := mt.card_power(body)
		if now < bp and nxt >= bp:
			return 300.0
	return 140.0

func _score_attack(mt: MtMatch, foe: MtPlayerState, a: Dictionary) -> float:
	var atk := _find(mt, String(a.get("attacker", "")))
	var tgt := _find(mt, String(a.get("target", "")))
	if atk == null or tgt == null:
		return 10.0
	var ap := mt.card_power(atk)
	var tp := mt.card_power(tgt)
	if ap < tp:
		return 8.0
	if tgt.is_leader():
		if foe.life.size() <= 1:
			return 2000.0
		return 320.0 + float(ap - tp) / 100.0
	return 260.0 + float(tgt.cost_value()) * 8.0 + float(tp) / 200.0

func _find(mt: MtMatch, uid: String) -> MtMatchCard:
	if uid == "":
		return null
	for pi in [0, 1]:
		var ps: MtPlayerState = mt.players[pi]
		if ps.leader != null and ps.leader.uid == uid:
			return ps.leader
		if ps.stage != null and ps.stage.uid == uid:
			return ps.stage
		for zone in [ps.hand, ps.field, ps.life, ps.deck, ps.trash]:
			for c in zone:
				if (c as MtMatchCard).uid == uid:
					return c
	return null
