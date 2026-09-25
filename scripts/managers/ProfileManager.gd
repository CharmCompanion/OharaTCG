# res://scripts/managers/ProfileManager.gd
# Wanted-poster progression: bounty, wins/losses, tier unlocks and avatar.
extends Node

signal profile_changed

const SAVE_PATH := "user://profile.json"

# Tier thresholds (bounty in Berries). Crossing a threshold upgrades the poster
# + tier symbols shown on the wanted poster.
const TIERS := [
	{ "min": 0,          "id": "rookie",      "name": "Rookie",          "symbols": 0 },
	{ "min": 30_000_000, "id": "supernova",   "name": "Supernova",       "symbols": 1 },
	{ "min": 100_000_000, "id": "warlord",    "name": "Warlord",         "symbols": 2 },
	{ "min": 500_000_000, "id": "emperor",    "name": "Emperor",         "symbols": 3 },
	{ "min": 1_500_000_000, "id": "pirateking", "name": "Pirate King",   "symbols": 4 },
]

const BOUNTY_PER_WIN := 10_000_000

var username: String = "Mugiwara"
var avatar_path: String = "res://assets/profiles/pfps/avatar_1.png"
var bounty: int = 0
var wins: int = 0
var losses: int = 0
var last_login: int = 0
var role: String = "player"

func _ready() -> void:
	_load()

# --- Tier logic ---
func get_tier_index() -> int:
	var index: int = 0
	for i in range(TIERS.size()):
		if bounty >= TIERS[i].min:
			index = i
	return index

func get_tier() -> Dictionary:
	return TIERS[get_tier_index()]

func get_next_tier() -> Dictionary:
	var idx := get_tier_index()
	if idx + 1 < TIERS.size():
		return TIERS[idx + 1]
	return TIERS[idx]

# --- Mutators ---
func register_win() -> void:
	wins += 1
	bounty += BOUNTY_PER_WIN
	profile_changed.emit()
	_save()

func register_loss() -> void:
	losses += 1
	profile_changed.emit()
	_save()

func set_bounty(value: int) -> void:
	bounty = maxi(0, value)
	profile_changed.emit()
	_save()

func set_avatar(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	avatar_path = path
	profile_changed.emit()
	_save()

func set_username(value: String) -> void:
	username = value.strip_edges()
	profile_changed.emit()
	_save()

func set_role(value: String) -> void:
	role = value if value == "admin" else "player"
	profile_changed.emit()
	_save()

func touch_login() -> void:
	last_login = int(Time.get_unix_time_from_system())
	_save()

func format_bounty() -> String:
	return Formatter.bounty_text(bounty)

# --- Persistence ---
func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"username": username,
			"avatar_path": avatar_path,
			"bounty": bounty,
			"wins": wins,
			"losses": losses,
			"last_login": last_login,
			"role": role,
		}))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return
	username = data.get("username", username)
	avatar_path = data.get("avatar_path", avatar_path)
	bounty = int(data.get("bounty", 0))
	wins = int(data.get("wins", 0))
	losses = int(data.get("losses", 0))
	last_login = int(data.get("last_login", 0))
	role = String(data.get("role", "player"))
	profile_changed.emit()