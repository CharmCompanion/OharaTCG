# res://scripts/match/ai/Puzzles.gd
# "Win this turn" (lethal) puzzle pipeline. Fully automatic — no game
# knowledge needed to author puzzles:
#   1. RECORD a Pro-vs-New AI game (seed + decks + per-action mover/turn).
#   2. MINE candidate positions from the winner's final-turn run-up.
#   3. VERIFY: deep MCTS on both sides still wins same-turn (forced win
#      approximation; true proof would need exhaustive search).
#   4. EMIT puzzle JSON {title, seed, decks, first, prefix, winner, turn}.
# Puzzles replay deterministically: same seed + prefix reproduces identical
# uids, so no state serialization is required. Human always plays the
# winner's side (TestBoard human is P0, so only winner==0 games are mined).

class_name MtPuzzles

extends RefCounted

# Replay prefix actions on a fresh engine. Returns null on any illegal step.
static func replay(seed: int, deck_a: Dictionary, deck_b: Dictionary,
		first: int, prefix: Array) -> MtMatch:
	var mt := MtMatch.new()
	mt.rng.seed = seed
	mt.auto_resolve_choices = true
	mt.start(deck_a, deck_b, first)
	for a in prefix:
		var res := mt.apply(a)
		if not res.get("ok", false):
			return null
	return mt

# Candidates: last `window` plies where the eventual winner is to move and
# the game is not over. Log entries: {action, mover, turn}.
static func mine(log: Array, winner: int, window: int = 12) -> Array:
	var out: Array = []
	var start := maxi(0, log.size() - window)
	for i in range(start, log.size()):
		var e: Dictionary = log[i]
		if int(e.get("mover", -1)) == winner and not bool(e.get("over", false)):
			out.append({"index": i, "turn": int(e.get("turn", 0))})
	return out

# Verify candidate: from the prefix, play Pro-vs-Pro (deep MCTS both sides);
# puzzle holds if the winner still wins WITHOUT the turn advancing.
static func verify(seed: int, deck_a: Dictionary, deck_b: Dictionary,
		first: int, prefix: Array, winner: int, turn: int,
		iters: int, seeds: int) -> bool:
	for s in range(seeds):
		var mt := replay(seed, deck_a, deck_b, first, prefix)
		if mt == null or mt.over:
			return false
		var pro_w := MtMctsAi.new()
		pro_w.iterations = iters
		pro_w.time_budget_ms = 60000
		pro_w.rng.seed = 1000 + s
		var pro_o := MtMctsAi.new()
		pro_o.iterations = maxi(20, iters / 4)
		pro_o.time_budget_ms = 60000
		pro_o.rng.seed = 2000 + s
		var steps := 0
		var bad := 0
		while not mt.over and steps < 400:
			var mover := mt.get_active_player() if not mt.in_battle() else int(mt.battle.get("defender_owner", 0))
			var a := {}
			if mover == winner:
				a = pro_w.pick_action(mt, mover)
			else:
				a = pro_o.pick_action(mt, mover)
			if (a as Dictionary).is_empty():
				return false
			var res := mt.apply(a)
			if not res.get("ok", false):
				bad += 1
				if bad > 2:
					return false
				continue
			steps += 1
			if mt.turn != turn:
				return false # survived the turn: not a this-turn forced win
		if not (mt.over and mt.winner == winner and mt.turn == turn):
			return false
	return true

static func emit_puzzle(title: String, seed: int, deck_a: Dictionary,
		deck_b: Dictionary, first: int, prefix: Array, winner: int,
		turn: int, par: int) -> Dictionary:
	return {"title": title, "seed": seed, "deck_a": deck_a, "deck_b": deck_b,
		"first": first, "prefix": prefix, "winner": winner, "turn": turn,
		"par": par}
