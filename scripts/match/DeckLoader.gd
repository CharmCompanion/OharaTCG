extends RefCounted
class_name MtDeckLoader

# Loads decks saved by the deck editor (res://data/decks/*.json, format:
# {"leader": "<code>", "main": ["<code>", ...]}) into the engine's input
# shape: {"leader": <card_dict>, "main": [<card_dict> ...]}.
# The engine generates its own 10 DON!! internally, so saved DON decks are
# ignored here.

const DECK_SAVE_DIR := "res://data/decks/"

static func available_deck_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DECK_SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".json") or file_name.ends_with(".deck")):
			out.append(DECK_SAVE_DIR + file_name)
		file_name = dir.get_next()
	out.sort()
	return out

static func default_deck_path() -> String:
	var paths := available_deck_paths()
	if paths.is_empty():
		return ""
	return paths[0]

static func load_deck_file(path: String, lookup: Callable) -> Dictionary:
	var deck := {"leader": {}, "main": []}
	if path.is_empty() or not FileAccess.file_exists(path):
		return deck
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return deck
	var stripped := raw.strip_edges()
	if stripped.begins_with("{") or stripped.begins_with("["):
		var parsed = JSON.parse_string(stripped)
		if parsed is Dictionary:
			var leader_id := String(parsed.get("leader", ""))
			if not leader_id.is_empty():
				deck.leader = lookup.call(leader_id)
			var main_ids: Array = parsed.get("main", [])
			for card_id in main_ids:
				var card_info := lookup.call(String(card_id))
				if not card_info.is_empty():
					deck.main.append(card_info)
			return deck
		if parsed is Array:
			for entry in parsed:
				if not (entry is Dictionary):
					continue
				var cid := String(entry.get("id", entry.get("card_code", "")))
				var count := int(entry.get("count", 1))
				var info = lookup.call(cid)
				if info.is_empty():
					continue
				if String(info.get("type", "")) == "Leader" and deck.leader.is_empty():
					deck.leader = info
					count = maxi(0, count - 1)
				for i in range(count):
					if String(info.get("type", "")) != "Leader":
						deck.main.append(info)
			return deck
	# .deck / line formats: first non-empty line can be a lone leader code.
	var lines := raw.split("\n")
	for line in lines:
		var t := line.strip_edges()
		if t.is_empty() or t.begins_with("["):
			continue
		var sim := _sim_line(t)
		if not sim.is_empty():
			var info := lookup.call(sim[1])
			if info.is_empty():
				continue
			if deck.leader.is_empty() and String(info.get("type", "")) == "Leader":
				deck.leader = info
			else:
				for i in range(int(sim[0])):
					if String(info.get("type", "")) != "Leader":
						deck.main.append(info)
			continue
		var code := t.to_upper()
		var info2 = lookup.call(code)
		if info2.is_empty():
			continue
		if String(info2.get("type", "")) == "Leader" and deck.leader.is_empty():
			deck.leader = info2
		elif String(info2.get("type", "")) != "Leader" and String(info2.get("type", "")) != "DON!!":
			deck.main.append(info2)
	return deck

static func _sim_line(t: String) -> Array:
	# Returns [copies, code] or [].
	var re := RegEx.new()
	re.compile(r"(?i)^(\d+)x([A-Z]+\d+-\d+\w*)$")
	var m := re.search(t.strip_edges().to_upper())
	if m == null:
		return []
	return [int(m.get_string(1)), m.get_string(2)]

static func build_from_lists(leader_code: String, main_codes: Array, lookup: Callable) -> Dictionary:
	var deck := {"leader": {}, "main": []}
	var leader_info := lookup.call(leader_code)
	if not leader_info.is_empty():
		deck.leader = leader_info
	for code in main_codes:
		var card_info := lookup.call(String(code))
		if not card_info.is_empty():
			deck.main.append(card_info)
	return deck

static func validate_deck(deck: Dictionary, banlist: Dictionary = {}, format: Dictionary = {}, blocks: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	var leader: Dictionary = deck.get("leader", {})
	if leader.is_empty():
		errors.append("A Leader card is required (exactly 1).")
	elif String(leader.get("type", "")) != "Leader":
		errors.append("The Leader slot must be a Leader card.")
	var lead_rules: Dictionary = {}
	if not leader.is_empty():
		lead_rules = MtEffectParser.parse(leader).get("rules", {})
	var main: Array = deck.get("main", [])
	if main.size() != 50:
		errors.append("Main deck must contain exactly 50 cards (found %d)." % main.size())
	var don_n := int(lead_rules.get("don_deck_size", 10))
	if deck.has("don"):
		var don_arr: Array = deck.get("don", [])
		if don_arr.size() != don_n:
			errors.append("DON!! deck must contain exactly %d cards (found %d)." % [don_n, don_arr.size()])
	var counts: Dictionary = {}
	var by_code: Dictionary = {}
	var color_noted: Dictionary = {}
	for card in main:
		var ctype := String((card as Dictionary).get("type", ""))
		var code := String((card as Dictionary).get("card_code", ""))
		if ctype == "Leader":
			errors.append("%s is a Leader and cannot be in the main deck (Leader is max 1, in the Leader slot)." % code)
		if ctype == "DON!!":
			errors.append("DON!! cards are not part of the 50-card main deck (DON!! deck is exactly %d)." % don_n)
		if not matches_leader_color(leader, card) and not color_noted.has(code):
			color_noted[code] = true
			errors.append("%s is %s and this Leader is %s (every color on a card must be a Leader color)." % [code, _color_label(card), _color_label(leader)])
		counts[code] = int(counts.get(code, 0)) + 1
		by_code[code] = card
		if int(lead_rules.get("deck_max_cost", 99)) < 99 and int((card as Dictionary).get("cost", 0)) > int(lead_rules.get("deck_max_cost", 99)):
			errors.append("%s exceeds this Leader's deck cost cap of %d." % [code, int(lead_rules.get("deck_max_cost", 99))])
		if ctype == "Event" and lead_rules.has("event_max_cost") and int((card as Dictionary).get("cost", 0)) > int(lead_rules.get("event_max_cost", 99)):
			errors.append("%s is an Event above this Leader's Event cost cap of %d." % [code, int(lead_rules.get("event_max_cost", 99))])
		var only_trait := String(lead_rules.get("deck_only_trait", ""))
		if only_trait != "" and not _card_has_trait(card, only_trait):
			errors.append("%s is not {%s} (this Leader can only include that type)." % [code, only_trait])
	for code in counts:
		var cap := 4
		var sample: Dictionary = by_code.get(code, {})
		if not sample.is_empty():
			var crules: Dictionary = MtEffectParser.parse(sample).get("rules", {})
			if bool(crules.get("any_number", false)):
				cap = 99
		if int(counts[code]) > cap:
			errors.append("%s exceeds the %d-copy limit (found %d)." % [code, cap if cap < 99 else 4, counts[code]])
	var all_counts: Dictionary = counts.duplicate()
	var lb := String(leader.get("card_code", ""))
	if lb != "":
		all_counts[lb] = int(all_counts.get(lb, 0)) + 1
	if not format.is_empty() and not (format.get("allowed_blocks", []) as Array).is_empty():
		var allowed: Array = []
		for b in (format.get("allowed_blocks", []) as Array):
			allowed.append(int(b))
		var checked: Array = [leader]
		checked.append_array(main)
		var block_noted: Dictionary = {}
		for card in checked:
			if not (card is Dictionary) or (card as Dictionary).is_empty():
				continue
			var ccode := String((card as Dictionary).get("card_code", ""))
			if ccode.is_empty():
				continue
			var b := card_block(card as Dictionary, blocks)
			if b < 0:
				continue
			if not allowed.has(b) and not block_noted.has(ccode):
				block_noted[ccode] = true
				errors.append("%s is Block %d (not legal in %s)." % [ccode, b, format.get("id", "format")])
	if not banlist.is_empty():
		var banned: Array = banlist.get("banned", [])
		var restricted: Dictionary = _restricted_map(banlist)
		for b in banned:
			if int(all_counts.get(String(b), 0)) > 0:
				errors.append("%s is banned (%s)." % [b, banlist.get("name", "banlist")])
		for r in restricted:
			var limit := int(restricted[r])
			if int(all_counts.get(String(r), 0)) > limit:
				if limit <= 0:
					errors.append("%s is banned (%s)." % [r, banlist.get("name", "banlist")])
				else:
					errors.append("%s is restricted to %d (%s)." % [r, limit, banlist.get("name", "banlist")])
		for pair in banlist.get("pairs", []):
			var pa: Array = pair
			if pa.size() >= 2 and int(all_counts.get(String(pa[0]), 0)) > 0 and int(all_counts.get(String(pa[1]), 0)) > 0:
				errors.append("Banned pair: %s + %s cannot share a deck (%s)." % [pa[0], pa[1], banlist.get("name", "banlist")])
	return errors

# Printed Block icon on the card, else the set map in blocks.json. -1 = unknown (allowed).
static func card_block(card: Dictionary, blocks: Dictionary = {}) -> int:
	var printed := int(card.get("block_number", 0))
	if printed > 0:
		return printed
	var ccode := String(card.get("card_code", ""))
	var cards_map: Dictionary = blocks.get("cards", {})
	if cards_map.has(ccode):
		return int(cards_map[ccode])
	var sets: Dictionary = blocks.get("sets", {})
	var prefix := ccode.split("-")[0]
	if sets.has(prefix):
		return int(sets[prefix])
	return -1

static func _restricted_map(banlist: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	_absorb_restricted(out, banlist.get("restricted", {}))
	_absorb_restricted(out, banlist.get("limited", {}))
	return out

static func _absorb_restricted(out: Dictionary, raw) -> void:
	if raw is Dictionary:
		for k in raw:
			if String(k).is_empty():
				continue
			out[String(k)] = int(raw[k])
	elif raw is Array:
		for entry in raw:
			if entry is Dictionary:
				var id := String(entry.get("card_id", entry.get("code", "")))
				if id.is_empty():
					continue
				out[id] = int(entry.get("limit", 1))
			else:
				out[String(entry)] = 1

# Empty string when one more copy of card may join main. Size is the caller's job.
static func why_not_add(leader: Dictionary, card: Dictionary, main: Array, banlist: Dictionary = {}, format: Dictionary = {}, blocks: Dictionary = {}) -> String:
	var trial: Array = main.duplicate()
	trial.append(card)
	var code := String(card.get("card_code", ""))
	var lines: PackedStringArray = PackedStringArray()
	for e in validate_deck({"leader": leader, "main": trial}, banlist, format, blocks):
		var s := String(e)
		if s.begins_with("Main deck must contain"):
			continue
		if code == "" or s.contains(code):
			lines.append(s)
	return "\n".join(lines)

static func card_colors(card: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var raw = card.get("color", "")
	if raw is Array:
		for c in raw:
			var piece := String(c).strip_edges()
			if piece != "":
				out.append(piece)
		return out
	for part in String(raw).split("/", false):
		var piece := part.strip_edges()
		if piece != "":
			out.append(piece)
	return out

# A card is deck-legal when every color printed on it is also on the Leader.
# Red/Green may play Red, Green, and Red/Green. It may not play Red/Blue.
static func matches_leader_color(leader: Dictionary, card: Dictionary) -> bool:
	if leader.is_empty():
		return true
	var lead := card_colors(leader)
	if lead.is_empty():
		return true
	var cols := card_colors(card)
	if cols.is_empty():
		return true
	for c in cols:
		if not lead.has(c):
			return false
	return true

static func _color_label(card: Dictionary) -> String:
	var cols := card_colors(card)
	if cols.is_empty():
		return "colorless"
	return "/".join(cols)

static func copy_limit(code: String, banlist: Dictionary = {}) -> int:
	if banlist.is_empty():
		return 4
	if (banlist.get("banned", []) as Array).has(code):
		return 0
	var restricted := _restricted_map(banlist)
	if restricted.has(code):
		return int(restricted[code])
	return 4

static func _card_has_trait(card: Dictionary, trait_name: String) -> bool:
	var traits = card.get("traits", [])
	if not (traits is Array):
		return false
	for t in traits:
		if String(t) == trait_name:
			return true
	return false

static func load_banlist(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func load_format(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func load_blocks() -> Dictionary:
	return load_format("res://data/blocks.json")

static func opening_hand(main: Array) -> Array:
	var pool: Array = main.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	if pool.size() <= 5:
		return pool
	return pool.slice(0, 5)

static func list_formats() -> Array:
	var out: Array = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/formats.json"))
	if parsed is Dictionary:
		for f in parsed.get("formats", []):
			out.append(f)
	return out