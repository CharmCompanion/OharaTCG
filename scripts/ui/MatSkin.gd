# res://scripts/ui/MatSkin.gd
# Play-mat skins keyed by leader color. Resolution order per color:
#   1. res://assets/mats/Custom/<color>.png  (player drops real art here)
#   2. res://assets/mats/<color>.png         (shipped set, when it exists)
#   3. Procedural felt: dark per-color diagonal gradient (always works,
#      including headless/tests).
# Multi-color leaders use their FIRST color (documented simplification).
# Drop real <color>.png files in to override with zero code changes.

extends RefCounted
class_name MtMatSkin

const COLORS := ["Red", "Green", "Blue", "Purple", "Black", "Yellow", "Default"]

const TINTS := {
	"Red": [Color(0.28, 0.05, 0.06), Color(0.10, 0.03, 0.03)],
	"Green": [Color(0.05, 0.22, 0.08), Color(0.02, 0.08, 0.03)],
	"Blue": [Color(0.05, 0.12, 0.30), Color(0.02, 0.05, 0.12)],
	"Purple": [Color(0.16, 0.06, 0.28), Color(0.07, 0.03, 0.12)],
	"Black": [Color(0.10, 0.10, 0.12), Color(0.03, 0.03, 0.04)],
	"Yellow": [Color(0.30, 0.22, 0.05), Color(0.12, 0.09, 0.02)],
	"Default": [Color(0.14, 0.12, 0.10), Color(0.05, 0.04, 0.03)],
}

static var _cache := {}

static func primary(colors: Array) -> String:
	for c in colors:
		var s := String(c).capitalize()
		if TINTS.has(s):
			return s
	return "Default"

const RANK := ["Red", "Green", "Blue", "Purple", "Black", "Yellow"]

# Pair-aware key: [Green, Red] -> "RedGreen" (their sim ships pair mats like
# RedGreen.png in RANK order). Falls back to the primary single color.
static func pair_key(colors: Array) -> String:
	var seen: Array = []
	for c in colors:
		var s := String(c).capitalize()
		if TINTS.has(s) and not seen.has(s):
			seen.append(s)
	seen.sort_custom(func(a, b): return RANK.find(a) < RANK.find(b))
	if seen.size() >= 2:
		return "".join(seen.slice(0, 2))
	if seen.size() == 1:
		return String(seen[0])
	return "Default"

static func art_for(colors: Array) -> Texture2D:
	var key := pair_key(colors)
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	for path in ["res://assets/mats/Custom/%s.png" % key.to_lower(),
			"res://assets/mats/%s.png" % key.to_lower()]:
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			if tex != null:
				break
	if tex == null:
		tex = _felt(primary(colors))
	_cache[key] = tex
	return tex

static func _felt(key: String) -> GradientTexture2D:
	var cols: Array = TINTS.get(key, TINTS["Default"])
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([cols[0], cols[1]])
	var t := GradientTexture2D.new()
	t.gradient = grad
	t.fill_from = Vector2(0.15, 0.0)
	t.fill_to = Vector2(0.85, 1.0)
	t.width = 256
	t.height = 256
	return t
