# Friends, crews, room access, and the conduct record.
# Match chat is not stored here. It is written into the replay.
# Every other channel and every report is appended under user://conduct,
# and a connected lobby keeps its own copy.
extends Node

const SOCIAL_PATH := "user://social.json"
const CONDUCT_DIR := "user://conduct"

var friends: Array = []
var crew := {"name": "", "owner": "", "members": []}
var tournament := {"code": "", "minutes": 50, "best_of": 3, "rules": "", "format": "swiss", "entrants": [], "bracket": [], "scores": {}}
var inbox: Array = []
var notice := ""
var room_kind := "public"
var room_access := "anyone"
var match_chat: Array = []
var mat_path := ""
var sleeve_path := ""
var _seen := {}

signal social_changed

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONDUCT_DIR))
	_load()
	touch_self()

func crew_name() -> String:
	return String(crew.get("name", ""))

func set_room(kind: String, access: String) -> void:
	room_kind = kind
	room_access = access
	_save()

func room_policy() -> Dictionary:
	return {
		"kind": room_kind,
		"access": room_access,
		"friends": _names(friends),
		"crew": crew_name(),
		"members": _names(crew.get("members", [])),
		"code": String(tournament.get("code", "")),
		"minutes": int(tournament.get("minutes", 50)),
		"best_of": int(tournament.get("best_of", 3)),
		"rules": String(tournament.get("rules", "")),
	}

func admits(policy: Dictionary, who: String, who_crew: String, invite: String = "") -> bool:
	if policy.is_empty():
		return true
	var kind := String(policy.get("kind", "public"))
	var access := String(policy.get("access", "anyone"))
	if kind == "public":
		return true
	if kind == "tournament":
		var code := String(policy.get("code", "")).strip_edges()
		return code != "" and invite.strip_edges().to_upper() == code.to_upper()
	if access == "none":
		return false
	if access == "friends":
		return who in policy.get("friends", [])
	if access == "crew":
		var cname := String(policy.get("crew", ""))
		return cname != "" and who_crew == cname and who in policy.get("members", [])
	return false

func ago(when: int) -> String:
	if when <= 0:
		return "no login yet"
	var delta := int(Time.get_unix_time_from_system()) - when
	if delta < 60:
		return "just now"
	if delta < 3600:
		return "%dm" % int(delta / 60)
	if delta < 86400:
		return "%dh" % int(delta / 3600)
	return "%dd" % int(delta / 86400)

func friend_line(row) -> String:
	var person := _person(row)
	return "%s · %s" % [person.get("name", ""), ago(int(person.get("last_seen", 0)))]

func crew_line(row) -> String:
	var person := _person(row)
	var rank := String(person.get("rank", ""))
	var role := String(person.get("role", "Member"))
	var title := role if rank == "" else "%s %s" % [role, rank]
	return "%s · %s · %s" % [person.get("name", ""), title, ago(int(person.get("last_seen", 0)))]

func touch_self() -> void:
	var now := int(Time.get_unix_time_from_system())
	var profile := get_node_or_null("/root/ProfileManager")
	if profile != null and profile.has_method("touch_login"):
		profile.touch_login()
		now = int(profile.last_login)
	note_seen(_me(), now)

func note_seen(who: String, when: int) -> void:
	who = who.strip_edges()
	if who == "" or when <= 0:
		return
	var changed := false
	for i in range(friends.size()):
		var person := _person(friends[i])
		if String(person.get("name", "")) != who or int(person.get("last_seen", 0)) == when:
			continue
		person["last_seen"] = when
		friends[i] = person
		changed = true
	var members: Array = crew.get("members", [])
	for i in range(members.size()):
		var person := _person(members[i])
		if String(person.get("name", "")) != who or int(person.get("last_seen", 0)) == when:
			continue
		person["last_seen"] = when
		members[i] = person
		changed = true
	if changed:
		crew["members"] = members
		_save()
		social_changed.emit()

func note_from_chat(message: String) -> void:
	var open_at := message.find("][")
	if open_at < 0:
		return
	var close_at := message.find("]", open_at + 2)
	if close_at < 0:
		return
	note_seen(message.substr(open_at + 2, close_at - open_at - 2), int(Time.get_unix_time_from_system()))

func add_friend(who: String) -> void:
	who = who.strip_edges()
	if who == "" or _has_name(friends, who):
		return
	friends.append({"name": who, "last_seen": 0})
	_save()
	social_changed.emit()

func remove_friend(who: String) -> void:
	_drop_name(friends, who)
	_save()
	social_changed.emit()

func create_crew(crew_title: String) -> void:
	crew_title = crew_title.strip_edges()
	if crew_title == "":
		return
	var me := _me()
	crew = {"name": crew_title, "owner": me, "members": [_crew_row(me, "Captain", "")]}
	_save()
	social_changed.emit()

func invite_to_crew(who: String) -> void:
	who = who.strip_edges()
	if crew_name() == "" or who == "" or not _is_captain():
		return
	var members: Array = crew.get("members", [])
	if not _has_name(members, who):
		members.append(_crew_row(who, "Member", ""))
	crew["members"] = members
	_save()
	post_invite("crew", who, {"crew": crew_name()})
	social_changed.emit()

func kick_member(who: String) -> void:
	who = who.strip_edges()
	if who == "" or who == String(crew.get("owner", "")):
		return
	var mine := _role_of(_me())
	var theirs := _role_of(who)
	var allowed := mine == "Captain" or (mine == "Officer" and theirs == "Member")
	if not allowed:
		return
	var members: Array = crew.get("members", [])
	_drop_name(members, who)
	crew["members"] = members
	_save()
	social_changed.emit()

func set_crew_standing(who: String, role: String, rank: String) -> void:
	if not _is_captain():
		return
	var members: Array = crew.get("members", [])
	for i in range(members.size()):
		var person := _person(members[i])
		if String(person.get("name", "")) != who.strip_edges():
			continue
		if role != "Captain":
			person["role"] = role if role in ["Officer", "Member", "Captain"] else "Member"
		person["rank"] = rank.strip_edges()
		members[i] = person
	crew["members"] = members
	_save()
	social_changed.emit()

func save_tournament(minutes: int, best_of: int, rules: String, format: String) -> String:
	var code := "%s%d" % [_me().substr(0, 1), randi() % 1000000]
	code = code.sha256_text().substr(0, 6).to_upper()
	var best := 1
	if best_of >= 5:
		best = 5
	elif best_of >= 3:
		best = 3
	var names: Array = [_me()]
	tournament = {
		"code": code,
		"minutes": clampi(minutes, 10, 120),
		"best_of": best,
		"rules": rules.strip_edges(),
		"format": format if format in ["swiss", "round_robin", "single", "double", "swiss_cut"] else "swiss",
		"entrants": names,
		"checked": [],
		"bracket": [],
		"scores": {},
	}
	room_kind = "tournament"
	room_access = "invite"
	_save()
	social_changed.emit()
	return code

func add_entrant(who: String) -> void:
	who = who.strip_edges()
	if who == "":
		return
	var names: Array = tournament.get("entrants", [])
	if who not in names:
		names.append(who)
	tournament["entrants"] = names
	_save()
	social_changed.emit()

func generate_bracket() -> Array:
	var names: Array = tournament.get("entrants", [])
	if names.size() < 2:
		return []
	var rounds := _make_rounds(names, String(tournament.get("format", "swiss")))
	tournament["bracket"] = rounds
	var scores := {}
	for name in names:
		scores[name] = 0
	_score_byes(rounds, scores)
	tournament["scores"] = scores
	_save()
	social_changed.emit()
	return rounds

func record_win(who: String) -> void:
	who = who.strip_edges()
	var rounds: Array = tournament.get("bracket", [])
	for rnd in rounds:
		if not rnd is Dictionary:
			continue
		var pairs: Array = rnd.get("pairs", [])
		for mi in range(pairs.size()):
			var pair = pairs[mi]
			if not pair is Dictionary or String(pair.get("winner", "")) != "":
				continue
			if String(pair.get("a", "")) != who and String(pair.get("b", "")) != who:
				continue
			pair["winner"] = who
			var scores: Dictionary = tournament.get("scores", {})
			scores[who] = int(scores.get(who, 0)) + 1
			tournament["scores"] = scores
			var slot := "winner r%d m%d" % [int(rnd.get("round", 1)), mi + 1]
			_fill_slot(rounds, slot, who)
			_save()
			social_changed.emit()
			return

func next_swiss_round() -> void:
	var fmt := String(tournament.get("format", ""))
	if fmt != "swiss" and fmt != "swiss_cut":
		return
	var scores: Dictionary = tournament.get("scores", {})
	var names: Array = scores.keys()
	names.sort_custom(func(a, b): return int(scores.get(a, 0)) > int(scores.get(b, 0)))
	var rounds: Array = tournament.get("bracket", [])
	var at := rounds.size()
	if not rounds.is_empty() and rounds.back() is Dictionary and String(rounds.back().get("label", "")) == "Top 4":
		at = rounds.size() - 1
	var round_no := 1
	for rnd in rounds:
		if rnd is Dictionary and String(rnd.get("label", "")) == "Swiss":
			round_no += 1
	rounds.insert(at, {"round": round_no, "label": "Swiss", "pairs": _pairs_of(names)})
	_score_byes(rounds, scores)
	tournament["scores"] = scores
	tournament["bracket"] = rounds
	_save()
	social_changed.emit()

func wins_needed(best_of: int) -> int:
	if best_of >= 5:
		return 3
	if best_of <= 1 and best_of > 0:
		return 1
	return 2

func check_in(who: String) -> void:
	who = who.strip_edges()
	if who == "":
		return
	var present: Array = tournament.get("checked", [])
	if who not in present:
		present.append(who)
	tournament["checked"] = present
	add_entrant(who)

func bracket_text() -> String:
	var lines: Array = []
	var fmt := String(tournament.get("format", "swiss"))
	lines.append("%s · best of %d · %d min" % [fmt, int(tournament.get("best_of", 1)), int(tournament.get("minutes", 0))])
	for rnd in tournament.get("bracket", []):
		if not rnd is Dictionary:
			continue
		lines.append("Round %s · %s" % [str(rnd.get("round", "")), rnd.get("label", "")])
		for pair in rnd.get("pairs", []):
			if not pair is Dictionary:
				continue
			var win := String(pair.get("winner", ""))
			var mark := "" if win == "" else " -> %s" % win
			lines.append("%s vs %s%s" % [pair.get("a", ""), pair.get("b", ""), mark])
	var present: Array = tournament.get("checked", [])
	if not present.is_empty():
		lines.append("Checked in: %s" % ", ".join(present))
	var scores: Dictionary = tournament.get("scores", {})
	if not scores.is_empty():
		var names: Array = scores.keys()
		names.sort_custom(func(a, b): return int(scores.get(a, 0)) > int(scores.get(b, 0)))
		lines.append("Standings")
		for name in names:
			lines.append("%s  %d" % [name, int(scores.get(name, 0))])
	return "\n".join(lines)

func post_invite(kind: String, target: String, detail: Dictionary) -> void:
	target = target.strip_edges()
	if target == "" or target == _me():
		return
	var row := {
		"id": "%s-%s-%d" % [kind, target, int(Time.get_unix_time_from_system())],
		"kind": kind,
		"from": _me(),
		"target": target,
		"detail": detail,
		"t": int(Time.get_unix_time_from_system()),
	}
	if kind != "friend_ok":
		inbox.append(row)
		_save()
		social_changed.emit()
	var net := get_node_or_null("/root/Lan")
	if net != null and net.active and net.has_method("send_invite"):
		net.send_invite(row)

func receive_invite(row: Dictionary) -> void:
	if String(row.get("target", "")) != _me():
		return
	if String(row.get("from", "")) == _me():
		return
	if String(row.get("kind", "")) == "friend_ok":
		add_friend(String(row.get("from", "")))
		return
	for have in inbox:
		if have is Dictionary and String(have.get("id", "")) == String(row.get("id", "")):
			return
	inbox.append(row)
	_save()
	social_changed.emit()

func accept_invite(id: String) -> void:
	var row := _take_invite(id)
	if row.is_empty():
		return
	var kind := String(row.get("kind", ""))
	var from := String(row.get("from", ""))
	var detail: Dictionary = row.get("detail", {})
	if kind == "friend":
		add_friend(from)
		notice = "%s is a friend." % from
		post_invite("friend_ok", from, {})
	elif kind == "crew" and crew_name() == "":
		crew = {"name": String(detail.get("crew", "")), "owner": from, "members": [_crew_row(_me(), "Member", "")]}
		notice = "Joined %s." % crew_name()
	elif kind == "duel":
		notice = "Duel with %s." % from
	elif kind == "tournament":
		tournament["code"] = String(detail.get("code", tournament.get("code", "")))
		notice = "Tournament code %s." % String(tournament.get("code", ""))
	_save()
	social_changed.emit()

func decline_invite(id: String) -> void:
	_take_invite(id)
	_save()
	social_changed.emit()

func request_friend(who: String) -> void:
	post_invite("friend", who, {})

func invite_duel(who: String) -> void:
	post_invite("duel", who, {})

func invite_tournament(who: String) -> void:
	if String(tournament.get("code", "")) == "":
		return
	post_invite("tournament", who, {
		"code": tournament.get("code", ""),
		"format": tournament.get("format", "swiss"),
		"minutes": tournament.get("minutes", 50),
		"best_of": tournament.get("best_of", 1),
	})

func clear_match_chat() -> void:
	match_chat.clear()

func add_match_line(message: String) -> void:
	match_chat.append({"t": int(Time.get_unix_time_from_system()), "text": message})

func archive_chat(channel: String, message: String) -> void:
	if channel == "match":
		return
	_append_unique("chat.jsonl", {
		"t": int(Time.get_unix_time_from_system()),
		"channel": channel,
		"message": message,
	}, "chat|%s|%s" % [channel, message])

func file_report(kind: String, target: String, note: String, evidence: Dictionary) -> void:
	var row := {
		"id": "%s-%d-%s" % [_me(), int(Time.get_unix_time_from_system()), kind],
		"t": int(Time.get_unix_time_from_system()),
		"reporter": _me(),
		"kind": kind,
		"target": target,
		"note": note.strip_edges(),
		"evidence": evidence,
	}
	store_report(row)
	var net := get_node_or_null("/root/Lan")
	if net != null and net.active and net.has_method("send_report"):
		net.send_report(row)
		return
	var accounts := get_node_or_null("/root/Accounts")
	if accounts != null:
		accounts.enqueue(row)

func store_report(row: Dictionary) -> void:
	_append_unique("reports.jsonl", row, "report|%s" % String(row.get("id", "")))

func appearance() -> Dictionary:
	var avatar := ""
	var profile := get_node_or_null("/root/ProfileManager")
	if profile != null:
		avatar = String(profile.avatar_path)
	return {"avatar": avatar, "mat": mat_path, "sleeve": sleeve_path, "name": _me()}

func _append_unique(file_name: String, row: Dictionary, key: String) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONDUCT_DIR))
	var path := CONDUCT_DIR.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(row))

func _me() -> String:
	var profile := get_node_or_null("/root/ProfileManager")
	if profile != null and String(profile.username).strip_edges() != "":
		return String(profile.username)
	return "Player"

func _save() -> void:
	var f := FileAccess.open(SOCIAL_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"friends": friends,
		"crew": crew,
		"tournament": tournament,
		"inbox": inbox,
		"room_kind": room_kind,
		"room_access": room_access,
	}))

func _load() -> void:
	if not FileAccess.file_exists(SOCIAL_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SOCIAL_PATH))
	if not data is Dictionary:
		return
	friends = _people(data.get("friends", []))
	var saved = data.get("crew", {})
	if saved is Dictionary:
		crew = saved
		crew["members"] = _crew_people(saved.get("members", []), String(saved.get("owner", "")))
	var event = data.get("tournament", {})
	if event is Dictionary:
		tournament = event
	var box = data.get("inbox", [])
	if box is Array:
		inbox = box
	room_kind = String(data.get("room_kind", room_kind))
	room_access = String(data.get("room_access", room_access))

func _people(rows) -> Array:
	var out: Array = []
	if not rows is Array:
		return out
	for row in rows:
		out.append(_person(row))
	return out

func _crew_people(rows, owner: String) -> Array:
	var out: Array = []
	if not rows is Array:
		return out
	for row in rows:
		var person := _person(row)
		if String(person.get("role", "")) == "":
			person["role"] = "Captain" if String(person.get("name", "")) == owner else "Member"
		out.append(person)
	return out

func _person(row) -> Dictionary:
	if row is Dictionary:
		return {
			"name": String(row.get("name", "")),
			"role": String(row.get("role", "")),
			"rank": String(row.get("rank", "")),
			"last_seen": int(row.get("last_seen", 0)),
		}
	return {"name": String(row), "role": "", "rank": "", "last_seen": 0}

func _crew_row(who: String, role: String, rank: String) -> Dictionary:
	return {"name": who, "role": role, "rank": rank, "last_seen": 0 if who != _me() else int(Time.get_unix_time_from_system())}

func _names(rows) -> Array:
	var out: Array = []
	if not rows is Array:
		return out
	for row in rows:
		var name := String(_person(row).get("name", ""))
		if name != "":
			out.append(name)
	return out

func _has_name(rows, who: String) -> bool:
	return who in _names(rows)

func _drop_name(rows: Array, who: String) -> void:
	for i in range(rows.size() - 1, -1, -1):
		if String(_person(rows[i]).get("name", "")) == who:
			rows.remove_at(i)

func _is_captain() -> bool:
	return crew_name() != "" and String(crew.get("owner", "")) == _me()

func _score_byes(rounds: Array, scores: Dictionary) -> void:
	for rnd in rounds:
		if not rnd is Dictionary:
			continue
		for pair in rnd.get("pairs", []):
			if not pair is Dictionary or String(pair.get("b", "")) != "bye":
				continue
			if String(pair.get("scored", "")) == "yes":
				continue
			var win := String(pair.get("winner", ""))
			if win == "":
				continue
			scores[win] = int(scores.get(win, 0)) + 1
			pair["scored"] = "yes"

func _fill_slot(rounds: Array, slot: String, who: String) -> void:
	for rnd in rounds:
		if not rnd is Dictionary:
			continue
		for pair in rnd.get("pairs", []):
			if not pair is Dictionary:
				continue
			if String(pair.get("a", "")) == slot:
				pair["a"] = who
			if String(pair.get("b", "")) == slot:
				pair["b"] = who

func _role_of(who: String) -> String:
	if who == String(crew.get("owner", "")):
		return "Captain"
	for row in crew.get("members", []):
		var person := _person(row)
		if String(person.get("name", "")) == who:
			return String(person.get("role", "Member"))
	return ""

func _take_invite(id: String) -> Dictionary:
	for i in range(inbox.size() - 1, -1, -1):
		var row = inbox[i]
		if row is Dictionary and String(row.get("id", "")) == id:
			inbox.remove_at(i)
			return row
	return {}

func _make_rounds(names: Array, format: String) -> Array:
	var field: Array = names.duplicate()
	field.shuffle()
	if format == "round_robin":
		var pairs: Array = []
		for i in range(field.size()):
			for j in range(i + 1, field.size()):
				pairs.append({"a": field[i], "b": field[j], "winner": ""})
		return [{"round": 1, "label": "Round robin", "pairs": pairs}]
	if format == "single":
		return _elim_rounds(field, "Knockout")
	if format == "double":
		var winners := _elim_rounds(field, "Winners")
		var losers: Array = []
		var first: Dictionary = winners[0] if not winners.is_empty() else {}
		var lnames: Array = []
		for pair in first.get("pairs", []):
			lnames.append("loser %s/%s" % [pair.get("a", ""), pair.get("b", "")])
		if lnames.size() >= 2:
			losers = _elim_rounds(lnames, "Losers")
		return winners + losers
	if format == "swiss_cut":
		var swiss := [{"round": 1, "label": "Swiss", "pairs": _pairs_of(field)}]
		swiss.append({"round": 2, "label": "Top 4", "pairs": [
			{"a": "1st", "b": "4th", "winner": ""},
			{"a": "2nd", "b": "3rd", "winner": ""},
		]})
		return swiss
	return [{"round": 1, "label": "Swiss", "pairs": _pairs_of(field)}]

func _pairs_of(field: Array) -> Array:
	var pool: Array = field.duplicate()
	var pairs: Array = []
	if pool.size() % 2 == 1:
		var bye = pool.pop_back()
		pairs.append({"a": bye, "b": "bye", "winner": bye})
	for i in range(0, pool.size(), 2):
		pairs.append({"a": pool[i], "b": pool[i + 1], "winner": ""})
	return pairs

func _elim_rounds(field: Array, label: String) -> Array:
	var size := 1
	while size < field.size():
		size *= 2
	var seeded: Array = field.duplicate()
	while seeded.size() < size:
		seeded.append("bye")
	var rounds: Array = []
	var current: Array = seeded
	var round_no := 1
	while current.size() >= 2:
		var pairs: Array = []
		var nxt: Array = []
		for i in range(0, current.size(), 2):
			var a = current[i]
			var b = current[i + 1]
			var winner := ""
			if String(b) == "bye":
				winner = String(a)
			elif String(a) == "bye":
				winner = String(b)
			pairs.append({"a": a, "b": b, "winner": winner})
			nxt.append(winner if winner != "" else "winner r%d m%d" % [round_no, pairs.size()])
		rounds.append({"round": round_no, "label": label, "pairs": pairs})
		if nxt.size() < 2:
			break
		current = nxt
		round_no += 1
	return rounds
