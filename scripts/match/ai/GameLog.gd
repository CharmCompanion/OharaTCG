# res://scripts/match/ai/GameLog.gd
# Self-play game recorder. Drives the learning loop: games recorded here feed
# tools/train_eval.py (offline), which writes the book + move priors +
# learned eval weights that Pro consults at runtime.
# Log entry: {seed, decks, first, winner, turns, steps, plies:[{action, mover, turn}]}.

class_name MtGameLog

extends RefCounted

static func play(p0, p1, deck_a: Dictionary, deck_b: Dictionary, seed: int,
		turn_cap: int = 40, step_cap: int = 1500) -> Dictionary:
	var mt := MtMatch.new()
	mt.rng.seed = seed
	mt.auto_resolve_choices = true
	mt.quiet = true
	mt.start(deck_a, deck_b, 0)
	var meta_w := MtAiLevels.load_weights()
	var plies: Array = []
	var steps := 0
	var bad := 0
	while not mt.over and mt.turn <= turn_cap and steps < step_cap:
		var mover := mt.mover()
		# Learnable snapshot BEFORE the move: book key + eval features.
		var key := mt.position_key()
		var feat := features(mt, meta_w)
		var a := {}
		if mover == 0:
			a = p0.pick_action(mt, 0)
		else:
			a = p1.pick_action(mt, 1)
		if (a as Dictionary).is_empty():
			break
		var res := mt.apply(a)
		if not res.get("ok", false):
			bad += 1
			if bad > 2:
				break
			continue
		plies.append({"action": a, "mover": mover, "turn": mt.turn,
			"key": key, "feat": feat})
		steps += 1
	return {"seed": seed, "deck_a": deck_a, "deck_b": deck_b, "first": 0,
		"winner": mt.winner if mt.over else -1, "turns": mt.turn,
		"steps": steps, "plies": plies}

# Raw eval features from P0's perspective (trainer standardizes):
# [life_diff, power_diff, hand_diff, don_diff, meta_diff].
static func features(mt: MtMatch, meta_w: Dictionary) -> Array:
	var a: MtPlayerState = mt.players[0]
	var b: MtPlayerState = mt.players[1]
	return [a.life.size() - b.life.size(), _power(mt, a) - _power(mt, b),
		a.hand.size() - b.hand.size(), a.don_active - b.don_active,
		_meta_raw(a, meta_w) - _meta_raw(b, meta_w)]

static func _power(mt: MtMatch, ps: MtPlayerState) -> int:
	var total := 0
	if ps.leader != null:
		total += mt.card_power(ps.leader)
	for c in ps.field:
		total += mt.card_power(c)
	return total

static func _meta_raw(ps: MtPlayerState, meta_w: Dictionary) -> float:
	if meta_w.is_empty():
		return 0.0
	var total := 0.0
	for c in ps.field:
		total += float(meta_w.get((c as MtMatchCard).card_code(), 0.0))
	for c in ps.hand:
		total += float(meta_w.get((c as MtMatchCard).card_code(), 0.0)) * 0.5
	if ps.leader != null:
		total += float(meta_w.get(ps.leader.card_code(), 0.0))
	return total

static func append_jsonl(path: String, entry: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return false
	file.seek_end()
	file.store_string(JSON.stringify(_sanitize(entry)) + "\n")
	file.flush()
	file.close()
	return true

# Same control-char scrub as the puzzle pack (Python-tolerated ≠ Godot-valid).
static func _sanitize(v):
	if v is String:
		var s := ""
		for i in range((v as String).length()):
			var code := (v as String).unicode_at(i)
			s += " " if code < 32 else (v as String)[i]
		return s
	if v is Array:
		var out := []
		for e in v:
			out.append(_sanitize(e))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _sanitize(v[k])
		return d
	return v
