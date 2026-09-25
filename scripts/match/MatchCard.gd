# res://scripts/match/MatchCard.gd
# Runtime in-match card instance. Pure data + computed stats, no scene tree.

extends RefCounted
class_name MtMatchCard

# Zones
const ZONE_LEADER := "leader"
const ZONE_HAND := "hand"
const ZONE_DECK := "deck"
const ZONE_TRASH := "trash"
const ZONE_LIFE := "life"
const ZONE_FIELD := "field"
const ZONE_STAGE := "stage"
const ZONE_DON := "don"          # DON cards are tracked as counters, not instances
const ZONE_REMOVED := "removed"  # cards removed from game

var uid: String = ""
var card: Dictionary = {}
var owner: int = 0
var zone: String = ZONE_DECK
var face_down: bool = false
var rested: bool = false

# Power adjustments: base_power_override (replaces) and power_bonus (adds)
var power_override: int = -1
var power_bonus: int = 0

var attacked_count: int = 0        # attacks declared this turn (Double Attack)
var activated_this_turn: bool = false
var played_this_turn: bool = false
var granted_keywords: Array = []
var attached_don: Array = []       # list of MatchCard DON instances attached
var removed_forever: bool = false
var cost_bonus: int = 0
var cannot_ko_effects: bool = false
var cannot_ko_all: bool = false
var skip_next_refresh: bool = false
var activated_this_game: bool = false
var replace_ko_used: bool = false
var effects_negated: bool = false
var no_attack: bool = false
var window_once: Dictionary = {}
var cannot_leave_effects: bool = false

var _turn_played: int = -1

func _init(p_uid: String = "", p_card: Dictionary = {}, p_owner: int = 0) -> void:
	uid = p_uid
	card = p_card
	owner = p_owner

# Deep copy for engine simulation (MCTS). `map` fills uid -> clone so the
# match can remap cross-references (battle, turn bonuses). The static card
# dict is shared read-only.
func clone(map: Dictionary) -> MtMatchCard:
	var c := MtMatchCard.new(uid, card, owner)
	c.zone = zone
	c.face_down = face_down
	c.rested = rested
	c.power_override = power_override
	c.power_bonus = power_bonus
	c.attacked_count = attacked_count
	c.activated_this_turn = activated_this_turn
	c.played_this_turn = played_this_turn
	c.removed_forever = removed_forever
	c.cost_bonus = cost_bonus
	c.cannot_ko_effects = cannot_ko_effects
	c.cannot_ko_all = cannot_ko_all
	c.skip_next_refresh = skip_next_refresh
	c.activated_this_game = activated_this_game
	c.replace_ko_used = replace_ko_used
	c.effects_negated = effects_negated
	c.no_attack = no_attack
	c.window_once = window_once.duplicate()
	c.cannot_leave_effects = cannot_leave_effects
	c._turn_played = _turn_played
	c.granted_keywords = granted_keywords.duplicate()
	for d in attached_don:
		c.attached_don.append((d as MtMatchCard).clone(map))
	map[uid] = c
	return c

# --- Type helpers ---
func card_type() -> String:
	return String(card.get("type", ""))

func is_leader() -> bool: return card_type() == "Leader"
func is_character() -> bool: return card_type() == "Character"
func is_event() -> bool: return card_type() == "Event"
func is_stage() -> bool: return card_type() == "Stage"
func is_don() -> bool: return card_type() == "DON!!"

func card_code() -> String:
	return String(card.get("card_code", ""))

func card_name() -> String:
	return String(card.get("name", "DON!!"))

# Base printed power (0 for anything without power)
func base_power() -> int:
	if power_override >= 0:
		return power_override
	return int(card.get("power", 0))

# Counter value printed on the card (used from hand as a Counter)
func counter_value() -> int:
	return int(card.get("counter", 0))

func cost_value() -> int:
	return maxi(0, int(card.get("cost", 0)) + cost_bonus)

func colors() -> Array:
	return String(card.get("color", "")).split("/", false)

# DON attachment straddles turns; caller decides whose turn power is computed on.
func don_count() -> int:
	return attached_don.size()

func refresh() -> void:
	if skip_next_refresh:
		skip_next_refresh = false
		attacked_count = 0
		activated_this_turn = false
		played_this_turn = false
		granted_keywords.clear()
		replace_ko_used = false
		window_once.clear()
		return
	rested = false
	attacked_count = 0
	activated_this_turn = false
	played_this_turn = false
	granted_keywords.clear()
	replace_ko_used = false
	window_once.clear()

func mark_played(turn_number: int) -> void:
	played_this_turn = true
	_turn_played = turn_number

func played_this_turn_value() -> bool:
	return played_this_turn

func profile() -> Dictionary:
	return MtCardProfile.from_dict(card)

func life_value() -> int:
	return int(card.get("life", 0))

func attribute_value() -> String:
	return String(card.get("attribute", ""))

func traits() -> Array:
	var t = card.get("traits", [])
	return t if t is Array else []

func keywords() -> Array:
	return MtEffectParser.parse(card).get("keywords", [])

# Snapshot for UI / log
func summary() -> String:
	return "%s (%s) [%s]" % [card_name(), card_code(), zone]