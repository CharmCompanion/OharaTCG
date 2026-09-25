# Accounts live on the lobby process (port 7780), not on each player's PC.
# The address every client uses is res://data/server.cfg.
extends Node

const PATH := "user://server_accounts.json"
const WEBHOOK := "user://discord.cfg"
const SERVER_CFG := "res://data/server.cfg"

signal session(ok: bool, note: String)
signal queue_changed

var role := "player"
var users: Dictionary = {}
var queue: Array = []
var _peers: Dictionary = {}
var _pending_user := ""
var _pending_digest := ""

func _ready() -> void:
	_load()
	var net := get_node_or_null("/root/Lan")
	if net != null and not net.lobby_connected.is_connected(_on_lobby):
		net.lobby_connected.connect(_on_lobby)

func host() -> String:
	if not FileAccess.file_exists(SERVER_CFG):
		return ""
	var text := FileAccess.get_file_as_string(SERVER_CFG)
	for line in text.split("\n"):
		var raw := line.strip_edges()
		if raw == "" or raw.begins_with("#"):
			continue
		if raw.begins_with("host="):
			return raw.substr(5).strip_edges()
	return ""

func dial() -> String:
	if host() != "" and FileAccess.file_exists("user://server_local.cfg"):
		return "127.0.0.1"
	return host()

func publish(ip: String) -> void:
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		return
	var cfg := FileAccess.open(SERVER_CFG, FileAccess.WRITE)
	if cfg != null:
		cfg.store_string("host=%s\n" % ip)
	var mark := FileAccess.open("user://server_local.cfg", FileAccess.WRITE)
	if mark != null:
		mark.store_string("1\n")

func webhook_text() -> String:
	if not FileAccess.file_exists(WEBHOOK):
		return ""
	return FileAccess.get_file_as_string(WEBHOOK).strip_edges()

func set_webhook(url: String) -> void:
	var f := FileAccess.open(WEBHOOK, FileAccess.WRITE)
	if f != null:
		f.store_string(url.strip_edges())

func admit_local(user: String, digest: String) -> String:
	var note := _admit(user, digest)
	if note == "":
		role = String(users[user].get("role", "player"))
	return note

func begin_remote(ip: String, user: String, digest: String) -> String:
	var net := get_node_or_null("/root/Lan")
	if net == null:
		return "The lobby is not available."
	_pending_user = user
	_pending_digest = digest
	var code: int = net.connect_lobby(ip, false)
	if code != OK:
		return "Could not reach the account server (%d)." % code
	return ""

func is_banned(user: String) -> bool:
	var row = users.get(user, {})
	return row is Dictionary and bool(row.get("banned", false))

func enqueue(row: Dictionary) -> void:
	var id := String(row.get("id", ""))
	if id == "":
		return
	for have in queue:
		if have is Dictionary and String(have.get("id", "")) == id:
			return
	queue.append(row)
	_save()
	queue_changed.emit()
	_discord("Report from %s about %s (%s). %s" % [
		row.get("reporter", ""), row.get("target", ""), row.get("kind", ""), row.get("note", "")])

func ask_queue() -> void:
	if _is_server():
		queue_changed.emit()
		return
	_rpc_ask_queue.rpc_id(1)

func add_admin(who: String) -> String:
	if role != "admin":
		return "Only an admin can add an admin."
	if _is_server() or not _remote():
		return _grant_admin(who)
	_rpc_add_admin.rpc_id(1, who.strip_edges())
	return ""

func decide(id: String, ban: bool) -> void:
	if role != "admin":
		return
	if _is_server() or not _remote():
		_decide(id, ban, "admin")
		return
	_rpc_decide.rpc_id(1, id, ban)

func _on_lobby() -> void:
	if _pending_user == "":
		return
	_rpc_auth.rpc_id(1, _pending_user, _pending_digest)

func _remote() -> bool:
	var net := get_node_or_null("/root/Lan")
	return net != null and net.lobby_client and net.active

func _is_server() -> bool:
	var net := get_node_or_null("/root/Lan")
	return net != null and net.relay and multiplayer.is_server()

func _admit(user: String, digest: String) -> String:
	user = user.strip_edges()
	if user == "" or digest == "":
		return "Enter a username and a password."
	var row = users.get(user, {})
	if not row is Dictionary or row.is_empty():
		var rank := "admin" if users.is_empty() else "player"
		row = {"pass": digest, "role": rank, "banned": false}
		users[user] = row
		_save()
	elif bool(row.get("banned", false)):
		return "This account is banned."
	elif String(row.get("pass", "")) != digest:
		return "Wrong password."
	return ""

func _grant_admin(who: String) -> String:
	who = who.strip_edges()
	if not users.has(who):
		return "That account does not exist yet."
	var row: Dictionary = users[who]
	row["role"] = "admin"
	users[who] = row
	_save()
	_discord("%s is now an admin." % who)
	return ""

func _decide(id: String, ban: bool, by: String) -> void:
	var kept: Array = []
	var target := ""
	for row in queue:
		if row is Dictionary and String(row.get("id", "")) == id:
			target = String(row.get("target", ""))
			continue
		kept.append(row)
	queue = kept
	if ban and target != "":
		var row = users.get(target, {"pass": "", "role": "player", "banned": false})
		if not row is Dictionary:
			row = {"pass": "", "role": "player", "banned": false}
		row["banned"] = true
		users[target] = row
		_discord("%s banned %s." % [by, target])
	elif target != "":
		_discord("%s dismissed the report about %s." % [by, target])
	_save()
	queue_changed.emit()

func _discord(text: String) -> void:
	var url := webhook_text()
	if url == "" or not url.begins_with("https://"):
		return
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"content": text.substr(0, 1800)})
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())

func _caller_admin() -> bool:
	var id := multiplayer.get_remote_sender_id()
	var name := String(_peers.get(id, ""))
	var row = users.get(name, {})
	return row is Dictionary and String(row.get("role", "")) == "admin"

@rpc("any_peer", "reliable")
func _rpc_auth(user: String, digest: String) -> void:
	if not _is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var note := _admit(user, digest)
	var rank := "player"
	if note == "":
		_peers[from] = user
		rank = String(users[user].get("role", "player"))
	_rpc_session.rpc_id(from, note == "", note, rank)

@rpc("authority", "reliable")
func _rpc_session(ok: bool, note: String, rank: String) -> void:
	if ok:
		role = rank
		var profile := get_node_or_null("/root/ProfileManager")
		if profile != null:
			profile.set_username(_pending_user)
			profile.set_role(rank)
			profile.touch_login()
	_pending_user = ""
	_pending_digest = ""
	session.emit(ok, note)

@rpc("any_peer", "reliable")
func _rpc_ask_queue() -> void:
	if not _is_server() or not _caller_admin():
		return
	_rpc_queue.rpc_id(multiplayer.get_remote_sender_id(), queue)

@rpc("authority", "reliable")
func _rpc_queue(rows: Array) -> void:
	queue = rows
	queue_changed.emit()

@rpc("any_peer", "reliable")
func _rpc_add_admin(who: String) -> void:
	if not _is_server() or not _caller_admin():
		return
	var note := _grant_admin(who)
	_rpc_admin_note.rpc_id(multiplayer.get_remote_sender_id(), note)
	if note == "":
		_rpc_queue.rpc_id(multiplayer.get_remote_sender_id(), queue)

@rpc("authority", "reliable")
func _rpc_admin_note(note: String) -> void:
	session.emit(note == "", note if note != "" else "Admin added.")

@rpc("any_peer", "reliable")
func _rpc_decide(id: String, ban: bool) -> void:
	if not _is_server() or not _caller_admin():
		return
	var by := String(_peers.get(multiplayer.get_remote_sender_id(), "admin"))
	_decide(id, ban, by)
	_rpc_queue.rpc_id(multiplayer.get_remote_sender_id(), queue)

func _load() -> void:
	if not FileAccess.file_exists(PATH):
		_migrate_old()
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		return
	var found = data.get("users", {})
	if found is Dictionary:
		users = found
	var rows = data.get("queue", [])
	if rows is Array:
		queue = rows

func _migrate_old() -> void:
	var old_path := "user://accounts.json"
	if not FileAccess.file_exists(old_path):
		return
	var old = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	if not old is Dictionary:
		return
	var first := true
	for key in old.keys():
		users[String(key)] = {
			"pass": String(old[key]),
			"role": "admin" if first else "player",
			"banned": false,
		}
		first = false
	if not users.is_empty():
		_save()

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"users": users, "queue": queue}))
