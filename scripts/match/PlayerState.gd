# res://scripts/match/PlayerState.gd
# Per-player board state used by the Match engine.

extends RefCounted
class_name MtPlayerState

const DON_START := 10

var index: int = 0
var deck: Array = []        # MatchCard
var hand: Array = []        # MatchCard
var trash: Array = []       # MatchCard
var life: Array = []        # MatchCard (face_down true)
var field: Array = []       # MatchCard characters
var removed: Array = []     # MatchCard removed from the game ([Banish])
var stage: MtMatchCard = null # single stage
var leader: MtMatchCard = null
# DON resources: an external Don-Deck of DON_START + an Active Area (max DON_START)
var don_deck_size: int = DON_START # leader rule override (e.g. Enel = 6)
var don_in_deck: int = DON_START
var don_active: int = 0        # total DON currently in your Active Area (attached + free)
var don_rested: int = 0        # how many active DON are rested right now

var max_life: int = 4          # set from the Leader card at game start

var deckout_lose: bool = false
var deckout_pending: bool = false
var ko_instead: Array = []
var no_play_chars: bool = false
var no_play_hand: bool = false
var no_play_char_cost_gte: int = 0
var hand_trashed_this_turn: bool = false
var no_life_to_hand: bool = false
var hand_cost_mods: Array = []

func _init(p_index: int) -> void:
	index = p_index

# Deep copy for engine simulation. Card dicts are shared read-only; every
# MtMatchCard (incl. attached DON) is cloned with uid preserved, registered
# in `map` for cross-reference remapping.
func clone_mapped(map: Dictionary) -> MtPlayerState:
	var ps := MtPlayerState.new(index)
	for zone_arr in ["deck", "hand", "trash", "life", "field", "removed"]:
		var out: Array = []
		for c in get(zone_arr):
			out.append((c as MtMatchCard).clone(map))
		ps.set(zone_arr, out)
	if stage != null:
		ps.stage = stage.clone(map)
	if leader != null:
		ps.leader = leader.clone(map)
	ps.don_deck_size = don_deck_size
	ps.don_in_deck = don_in_deck
	ps.don_active = don_active
	ps.don_rested = don_rested
	ps.max_life = max_life
	ps.deckout_lose = deckout_lose
	ps.deckout_pending = deckout_pending
	ps.ko_instead = ko_instead.duplicate(true)
	ps.no_play_chars = no_play_chars
	ps.no_play_hand = no_play_hand
	ps.no_play_char_cost_gte = no_play_char_cost_gte
	ps.hand_trashed_this_turn = hand_trashed_this_turn
	ps.no_life_to_hand = no_life_to_hand
	ps.hand_cost_mods = hand_cost_mods.duplicate(true)
	return ps

# Number of un-rested (free-for-cost) DON in the Active Area.
# don_active counts every DON in play (free + attached); attached DON are
# inherently committed, so they are not free for costs.
func get_available_don() -> int:
	return don_active - get_attached_don_total() - don_rested

func get_attached_don_total() -> int:
	var total := 0
	for c in field:
		total += c.don_count()
	for c in ([leader] if leader else []):
		total += c.don_count()
	if stage and stage.don_count() > 0:
		total += stage.don_count()
	return total

func get_rested_don_total() -> int:
	var rested_total := 0
	for c in field:
		if c.rested:
			for _d in c.attached_don:
				rested_total += 1
	for l in ([leader] if leader else []):
		if l.rested:
			rested_total += l.don_count()
	return rested_total

func reset_don_refresh() -> void:
	# Refresh Phase (comprehensive rules 6-2):
	# 6-2-3 Return all given DON!! to the cost area (rested), then
	# 6-2-4 set every rested card in Leader / Character / Stage / cost areas as active.
	for c in field:
		c.attached_don.clear()
	if leader:
		leader.attached_don.clear()
	don_rested = 0
	for c in field:
		c.refresh()
	if leader:
		leader.refresh()
	if stage:
		stage.refresh()

func count_in_hand_typed(type_name: String) -> int:
	var n := 0
	for c in hand:
		if c.card_type() == type_name:
			n += 1
	return n

func all_zones_array() -> Array:
	var out: Array = []
	out.append_array(deck)
	out.append_array(hand)
	out.append_array(trash)
	out.append_array(life)
	out.append_array(field)
	out.append_array(removed)
	if leader:
		out.append(leader)
	if stage:
		out.append(stage)
	return out

func is_leader_color(color_name: String) -> bool:
	if leader == null:
		return false
	return String(leader.card.get("color", "")).split("/", false).has(color_name)