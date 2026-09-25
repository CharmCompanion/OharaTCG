# res://scripts/match/ai/MctsAi.gd
# Monte-Carlo Tree Search opponent (Phase 2, advanced). No LLM at runtime.
#   - PUCT selection with learned move priors (default 0.5 when unknown).
#   - Opening book consult at the root (tournament + self-play games).
#   - Learned logistic eval (offline trainer) with hand-tuned fallback.
#   - Single-observer determinization per iteration; trigger YES/NO are moves.
#   - Dynamic time: full budget when behind on Life, 60% when ahead by 2+.
# Same pick_action interface as MtDummyAI. last_source reports how the move
# was chosen: "single" (one legal move), "book", or "search".

class_name MtMctsAi

extends RefCounted

var iterations := 300
var time_budget_ms := 250
var explore_c := 1.41421356
var rollout_cap := 400
var rng := RandomNumberGenerator.new()
var last_iterations := 0
var last_visits := 0
var last_source := ""
# Learned data (empty = disabled): move_priors {code: p}, eval_weights
# {bias,life,power,hand,don,meta}, book {poskey: {mover, moves:{canon:[w,n]}}}.
var move_priors := {}
var eval_weights := {}
var book := {}
var book_min_plays := 3
# RAVE: persistent all-moves-as-first table across moves in a game
# (subtree reuse is pointless here — the opponent always moves between our
# searches — so cross-move learning lives in this table instead).
# canon action -> [wins, plays]. Cleared per game via new_game().
var amaf := {}
var rave_k := 500.0
# Meta priors (tournament inclusion) feed the fallback eval only.
var card_weights := {}
var weight_scale := 0.004

var _rollout_policy := MtDummyAI.new()

func _init() -> void:
	rng.seed = Time.get_ticks_usec()

func new_game() -> void:
	amaf.clear()
	last_iterations = 0
	last_visits = 0
	last_source = ""

func pick_action(engine: Object, viewer: int = 1) -> Dictionary:
	var root_acts: Array = engine.get_legal_actions()
	if root_acts.is_empty():
		return {}
	if root_acts.size() == 1:
		last_source = "single"
		return root_acts[0]
	var booked := _book_move(engine, root_acts)
	if not booked.is_empty():
		last_source = "book"
		return booked
	last_source = "search"
	var root := {"action": {}, "parent": -1, "children": [], "visits": 0,
		"value": 0.0, "untried": root_acts.duplicate()}
	var nodes := [root]
	var budget := time_budget_ms
	if not eval_weights.is_empty():
		budget = _dynamic_budget(engine, viewer)
	var deadline := Time.get_ticks_msec() + budget
	var done := 0
	while done < iterations:
		var sim: MtMatch = engine.clone()
		sim.determinize(viewer)
		var traj: Array = [] # {node, action} applied in tree descent
		var idx := 0
		while (nodes[idx]["untried"] as Array).is_empty() and not (nodes[idx]["children"] as Array).is_empty() and not sim.over:
			idx = _select(nodes, idx)
			traj.append({"node": idx, "action": nodes[idx]["action"]})
			sim.apply(nodes[idx]["action"])
		if not sim.over and not (nodes[idx]["untried"] as Array).is_empty():
			var a: Dictionary = (nodes[idx]["untried"] as Array).pop_back()
			var res: Dictionary = sim.apply(a)
			if res.get("ok", false):
				var child := {"action": a, "parent": idx, "children": [], "visits": 0,
					"value": 0.0, "untried": sim.get_legal_actions(),
					"prior": _prior_for(sim, a)}
				nodes.append(child)
				(nodes[idx]["children"] as Array).append(nodes.size() - 1)
				traj.append({"node": nodes.size() - 1, "action": a})
				idx = nodes.size() - 1
		var rollout_acts: Array = []
		var steps := 0
		while not sim.over and steps < rollout_cap:
			var ra := _rollout_policy.pick_action(sim)
			if ra.is_empty():
				break
			var rres: Dictionary = sim.apply(ra)
			if not rres.get("ok", false):
				break
			rollout_acts.append(ra)
			steps += 1
		var reward := _reward(sim, viewer)
		var b := idx
		while b >= 0:
			nodes[b]["visits"] = int(nodes[b]["visits"]) + 1
			nodes[b]["value"] = float(nodes[b]["value"]) + reward
			b = int(nodes[b]["parent"])
		_rave_update(traj, rollout_acts, reward)
		done += 1
		if done % 16 == 0 and Time.get_ticks_msec() >= deadline:
			break
	last_iterations = done
	var best := {}
	var best_v := -1
	for ci in (root["children"] as Array):
		var v := int(nodes[int(ci)]["visits"])
		if v > best_v:
			best_v = v
			best = nodes[int(ci)]["action"]
	last_visits = best_v
	if (best as Dictionary).is_empty():
		return root_acts[0]
	return best

# Canonical action string: sorted keys, compact (trainer uses the same form).
static func canon(a: Dictionary) -> String:
	var keys := a.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		var v = a[k]
		if v is String:
			parts.append('"%s":"%s"' % [k, v])
		else:
			parts.append('"%s":%s' % [k, str(v)])
	return "{" + ",".join(parts) + "}"

func _book_move(engine: Object, root_acts: Array) -> Dictionary:
	if book.is_empty():
		return {}
	var entry: Dictionary = book.get(String(engine.position_key()), {})
	if entry.is_empty() or int(entry.get("mover", -1)) != engine.mover():
		return {}
	var legal := {}
	for a in root_acts:
		legal[MtMctsAi.canon(a)] = a
	var best := {}
	var best_wr := -1.0
	for ck in (entry.get("moves", {}) as Dictionary):
		if not legal.has(ck):
			continue
		var wn: Array = (entry.get("moves", {}) as Dictionary)[ck]
		if int(wn[1]) < book_min_plays:
			continue
		var wr := float(wn[0]) / float(maxi(1, int(wn[1])))
		if wr > best_wr:
			best_wr = wr
			best = legal[ck]
	return best

func _select(nodes: Array, idx: int) -> int:
	var parent_visits := maxi(1, int(nodes[idx]["visits"]))
	var best_i := -1
	var best_s := -1.0
	for ci in (nodes[idx]["children"] as Array):
		var c: Dictionary = nodes[int(ci)]
		var n := int(c["visits"])
		if n <= 0:
			return int(ci)
		var q := float(c["value"]) / float(n)
		var p := float(c.get("prior", 0.5))
		var puct := q + explore_c * p * sqrt(float(parent_visits)) / (1.0 + float(n))
		# RAVE blend: beta decays with node visits (Schaeffer form).
		var beta := rave_k / (3.0 * float(n) + rave_k)
		var ck := MtMctsAi.canon(c["action"])
		var aw: Array = amaf.get(ck, [p, 1.0])
		var q_amaf := float(aw[0]) / float(maxi(1, int(aw[1])))
		var s := (1.0 - beta) * puct + beta * q_amaf
		if s > best_s:
			best_s = s
			best_i = int(ci)
	if best_i < 0:
		return idx
	return best_i

func _rave_update(traj: Array, rollout_acts: Array, reward: float) -> void:
	# Every action played at-or-after a node counts as-first for that node.
	var later: Array = []
	for t in traj:
		later.append((t as Dictionary)["action"])
	later.append_array(rollout_acts)
	for i in range(traj.size()):
		var seen := {}
		for j in range(i, later.size()):
			var ck := MtMctsAi.canon(later[j])
			if seen.has(ck):
				continue
			seen[ck] = true
			var st: Array = amaf.get(ck, [0.0, 0])
			st[0] = float(st[0]) + reward
			st[1] = int(st[1]) + 1
			amaf[ck] = st

func _prior_for(sim: MtMatch, a: Dictionary) -> float:
	var t := String(a.get("type", ""))
	if t == "trigger_yes":
		return 0.6
	if t == "trigger_no":
		return 0.4
	if t == "end_turn":
		return 0.4
	var uid := String(a.get("card_uid", a.get("attacker", a.get("blocker", ""))))
	if uid.is_empty() or move_priors.is_empty():
		return 0.5
	return clampf(float(move_priors.get(_find_code(sim, uid), 0.5)), 0.05, 0.95)

func _find_code(sim: MtMatch, uid: String) -> String:
	for pi in [0, 1]:
		var ps: MtPlayerState = sim.players[pi]
		for zone_arr in [ps.hand, ps.field, ps.deck, ps.trash, ps.life]:
			for c in zone_arr:
				if (c as MtMatchCard).uid == uid:
					return (c as MtMatchCard).card_code()
		if ps.leader != null and ps.leader.uid == uid:
			return ps.leader.card_code()
		if ps.stage != null and ps.stage.uid == uid:
			return ps.stage.card_code()
	return ""

func _dynamic_budget(engine: Object, viewer: int) -> int:
	var me: MtPlayerState = engine.players[viewer]
	var foe: MtPlayerState = engine.players[1 - viewer]
	var diff := me.life.size() - foe.life.size()
	if diff < 0:
		return time_budget_ms
	if diff >= 2:
		return int(time_budget_ms * 0.6)
	return int(time_budget_ms * 0.8)

func _reward(sim: MtMatch, viewer: int) -> float:
	if sim.over:
		return 1.0 if sim.winner == viewer else 0.0
	var me: MtPlayerState = sim.players[viewer]
	var foe: MtPlayerState = sim.players[1 - viewer]
	var life := float(me.life.size() - foe.life.size())
	var power := float(_field_power(sim, me) - _field_power(sim, foe))
	var hand := float(me.hand.size() - foe.hand.size())
	var don := float(me.don_active - foe.don_active)
	if eval_weights.is_empty():
		var score := life * 0.12 + power / 20000.0 + hand * 0.02 + don * 0.01
		score += _meta_score(me) - _meta_score(foe)
		return clampf(0.5 + score, 0.0, 1.0)
	# Learned logistic head: z = bias + Σ((x-mean)/std * w), same feature
	# order + standardization as tools/train_eval.py.
	var meta := _meta_raw(me) - _meta_raw(foe)
	var xs := [life, power, hand, don, meta]
	var mean: Array = eval_weights.get("mean", [0, 0, 0, 0, 0])
	var std: Array = eval_weights.get("std", [1, 1, 1, 1, 1])
	var w: Array = eval_weights.get("w", [0, 0, 0, 0, 0])
	var z := float(eval_weights.get("bias", 0.0))
	for i in range(5):
		var s := float(std[i] if i < std.size() else 1.0)
		if s <= 0.0:
			s = 1.0
		z += (float(xs[i]) - float(mean[i] if i < mean.size() else 0.0)) / s * float(w[i] if i < w.size() else 0.0)
	return 1.0 / (1.0 + exp(-z))

func _meta_raw(ps: MtPlayerState) -> float:
	if card_weights.is_empty():
		return 0.0
	var total := 0.0
	for c in ps.field:
		total += float(card_weights.get((c as MtMatchCard).card_code(), 0.0))
	for c in ps.hand:
		total += float(card_weights.get((c as MtMatchCard).card_code(), 0.0)) * 0.5
	if ps.leader != null:
		total += float(card_weights.get(ps.leader.card_code(), 0.0))
	return total

func _meta_score(ps: MtPlayerState) -> float:
	if card_weights.is_empty():
		return 0.0
	var total := 0.0
	for c in ps.field:
		total += float(card_weights.get((c as MtMatchCard).card_code(), 0.0))
	for c in ps.hand:
		total += float(card_weights.get((c as MtMatchCard).card_code(), 0.0)) * 0.5
	if ps.leader != null:
		total += float(card_weights.get(ps.leader.card_code(), 0.0))
	return total * weight_scale

func _field_power(sim: MtMatch, ps: MtPlayerState) -> int:
	var total := 0
	if ps.leader != null:
		total += sim.card_power(ps.leader)
	for c in ps.field:
		total += sim.card_power(c)
	return total
