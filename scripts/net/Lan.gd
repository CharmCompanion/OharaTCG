# Host or join one duel. The duel host is seat 0 and the authority.
# LAN rooms are announced by UDP. A lobby on port 7780 relays public rooms.
extends Node

signal peer_ready
signal joined
signal throws_revealed(you: String, opp: String, winner_seat: int)
signal match_begin(deck_a: Dictionary, deck_b: Dictionary, first: int, seed_value: int)
var tourney_minutes := 0
var tourney_best := 0
var tag := false
var mates_here := 0
signal action_requested(action: Dictionary)
signal action_broadcast(action: Dictionary)
signal chat_received(channel: String, message: String)
signal rooms_updated
signal spectate_ready(deck_a: Dictionary, deck_b: Dictionary, first: int, seed_value: int, actions: Array)
signal room_opened
signal room_full
signal room_denied(reason: String)
signal lobby_connected
signal seated(seat: int)
signal mates_changed(count: int)

const PORT := 7777
const LOBBY_PORT := 7780
const BEACON_PORT := 7778

var active := false
var is_host := false
var relay := false
var lobby_client := false
var role := "play"
var peer_name := "Opponent"
var local_deck: Dictionary = {}
var remote_deck: Dictionary = {}
var room_id := 0
var _throw_local := ""
var _throw_remote := ""
var _opponent_id := 0
var _watchers: Array = []
var _match_live := false
var _catchup: Dictionary = {}
var _advertise_port := PORT
var _beacon: PacketPeerUDP
var _listen: PacketPeerUDP
var _beacon_cd := 0.0
var _seen: Dictionary = {}
var _lobby_rooms: Array = []
var _rooms: Dictionary = {}
var _peer_room: Dictionary = {}
var _next_room := 1
var _intent_open := false
var _invite := ""
var _mates: Array = []
var _deck_waiting := false

func _ready() -> void:
	_hook_net()

func _process(delta: float) -> void:
	if is_host and not relay:
		_beacon_cd += delta
		if _beacon_cd >= 1.0:
			_beacon_cd = 0.0
			_send_beacon()
	_poll_beacons()

func host_game() -> int:
	return _host_on(PORT)

func host_public() -> int:
	return _host_on(LOBBY_PORT)

func serve_relay() -> int:
	close()
	_hook_net()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(LOBBY_PORT, 64)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	relay = true
	active = true
	return OK

func join_game(ip: String, as_watch: bool = false, port: int = -1, as_mate: bool = false) -> int:
	close()
	_hook_net()
	if as_mate:
		role = "mate"
	elif as_watch:
		role = "watch"
	else:
		role = "play"
	var use_port := PORT if port <= 0 else port
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip if ip != "" else "127.0.0.1", use_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	_bind_connect(false)
	return OK

func connect_lobby(ip: String, open_room_after: bool) -> int:
	ip = ip.strip_edges()
	if ip == "":
		return ERR_CANT_CONNECT
	close()
	_hook_net()
	_intent_open = open_room_after
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, LOBBY_PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	_bind_connect(true)
	return OK

func reach_lobby(ip: String, open_room_after: bool) -> int:
	if active and not is_host and not relay and multiplayer.multiplayer_peer != null:
		_intent_open = open_room_after
		if open_room_after:
			open_room()
		else:
			ask_rooms()
		return OK
	return connect_lobby(ip, open_room_after)

func hello_direct(as_watch: bool, as_mate: bool = false) -> void:
	if as_mate:
		role = "mate"
	elif as_watch:
		role = "watch"
	else:
		role = "play"
	is_host = false
	lobby_client = false
	_rpc_hello.rpc_id(1, role, _local_name(), _crew_name(), _invite)
	if role == "play":
		joined.emit()

func _bind_connect(lobby: bool) -> void:
	if multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.disconnect(_on_connected)
	if multiplayer.connected_to_server.is_connected(_on_lobby_connected):
		multiplayer.connected_to_server.disconnect(_on_lobby_connected)
	if lobby:
		multiplayer.connected_to_server.connect(_on_lobby_connected)
	else:
		multiplayer.connected_to_server.connect(_on_connected)

func ask_rooms() -> void:
	if active:
		_rpc_ask_rooms.rpc_id(1)

func open_room() -> void:
	lobby_client = true
	is_host = true
	_rpc_open_room.rpc_id(1, _local_name(), _room_policy())

func enter_room(rid: int, as_watch: bool, as_mate: bool = false) -> void:
	if as_mate:
		role = "mate"
	elif as_watch:
		role = "watch"
	else:
		role = "play"
	is_host = false
	lobby_client = true
	_rpc_enter_room.rpc_id(1, rid, role, _local_name(), _crew_name(), _invite)

func listen_rooms() -> void:
	if _listen != null:
		return
	var udp := PacketPeerUDP.new()
	if udp.bind(BEACON_PORT) != OK:
		return
	_listen = udp

func lan_rooms() -> Array:
	var now := Time.get_ticks_msec()
	var out: Array = []
	var drop: Array = []
	for ip in _seen.keys():
		var row: Dictionary = _seen[ip]
		if now - int(row.get("t", 0)) > 4000:
			drop.append(ip)
			continue
		out.append(row)
	for ip in drop:
		_seen.erase(ip)
	for row in _lobby_rooms:
		out.append(row)
	return out

func note_beacon(ip: String, pkt: PackedByteArray) -> void:
	var data = JSON.parse_string(pkt.get_string_from_utf8())
	if not data is Dictionary or String(data.get("game", "")) != "ohara":
		return
	if is_host and String(data.get("name", "")) == _local_name() and int(data.get("port", 0)) == _advertise_port:
		return
	_seen[ip] = {
		"kind": "lan", "id": 0, "ip": ip,
		"name": String(data.get("name", "Room")),
		"port": int(data.get("port", PORT)),
		"players": int(data.get("players", 1)),
		"live": bool(data.get("live", false)),
		"mode": String(data.get("mode", "public")),
		"access": String(data.get("access", "anyone")),
		"t": Time.get_ticks_msec(),
	}
	rooms_updated.emit()

func close() -> void:
	active = false
	is_host = false
	relay = false
	lobby_client = false
	role = "play"
	room_id = 0
	_opponent_id = 0
	_mates.clear()
	mates_here = 0
	_deck_waiting = false
	_watchers.clear()
	_match_live = false
	_throw_local = ""
	_throw_remote = ""
	_intent_open = false
	_lobby_rooms.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func send_deck(deck: Dictionary, who: String) -> void:
	local_deck = deck
	peer_name = who
	if is_host:
		return
	if lobby_client:
		_rpc_relay.rpc_id(1, "deck", {"deck": deck, "who": who}, 0)
		return
	_rpc_deck.rpc_id(1, deck, who)

func send_throw(hand: String) -> void:
	_throw_local = hand
	if is_host:
		_consider_throws()
	elif lobby_client:
		_rpc_relay.rpc_id(1, "throw", {"hand": hand}, 0)
	else:
		_rpc_throw.rpc_id(1, hand)

func send_first(first: int) -> void:
	if is_host:
		_begin(first)
	elif lobby_client:
		_rpc_relay.rpc_id(1, "first", {"first": first}, 0)
	else:
		_rpc_first.rpc_id(1, first)

func request_action(action: Dictionary) -> void:
	if lobby_client:
		_rpc_relay.rpc_id(1, "request", {"action": action}, 0)
		return
	_rpc_request.rpc_id(1, action)

func broadcast_action(action: Dictionary) -> void:
	if is_host:
		var acts: Array = _catchup.get("actions", [])
		acts.append(action.duplicate())
		_catchup["actions"] = acts
	if lobby_client:
		_rpc_relay.rpc_id(1, "broadcast", {"action": action}, 0)
		return
	_rpc_broadcast.rpc(action)

func say(channel: String, message: String) -> void:
	if not active:
		return
	if lobby_client:
		_rpc_relay.rpc_id(1, "chat", {"channel": channel, "message": message}, 0)
		return
	_rpc_chat.rpc(channel, message)

func _host_on(port: int) -> int:
	close()
	_hook_net()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 6)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	role = "play"
	_advertise_port = port
	_catchup = {"actions": []}
	return OK

func _hook_net() -> void:
	if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
		multiplayer.peer_disconnected.connect(_on_peer_left)

func _on_connected() -> void:
	_rpc_hello.rpc_id(1, role, _local_name(), _crew_name(), _invite)
	if role == "play":
		joined.emit()

func _on_lobby_connected() -> void:
	lobby_connected.emit()
	if _intent_open:
		open_room()
	else:
		ask_rooms()

func _on_peer_left(id: int) -> void:
	if id == _opponent_id:
		_opponent_id = 0
	_mates.erase(id)
	mates_here = _mates.size()
	_watchers.erase(id)
	if not relay:
		return
	var rid := int(_peer_room.get(id, 0))
	_peer_room.erase(id)
	if not _rooms.has(rid):
		return
	var room: Dictionary = _rooms[rid]
	if int(room.get("host", 0)) == id:
		_rooms.erase(rid)
		return
	if int(room.get("guest", 0)) == id:
		room["guest"] = 0
	if int(room.get("mate0", 0)) == id:
		room["mate0"] = 0
	if int(room.get("mate1", 0)) == id:
		room["mate1"] = 0
	var watch: Array = room.get("watch", [])
	watch.erase(id)
	room["watch"] = watch

func set_invite(code: String) -> void:
	_invite = code.strip_edges()

func _crew_name() -> String:
	var social := get_node_or_null("/root/Social")
	if social != null and social.has_method("crew_name"):
		return String(social.crew_name())
	return ""

func _room_policy() -> Dictionary:
	var social := get_node_or_null("/root/Social")
	if social != null and social.has_method("room_policy"):
		return social.room_policy()
	return {}

func _admits(policy: Dictionary, who: String, who_crew: String, invite: String) -> bool:
	var social := get_node_or_null("/root/Social")
	if social != null and social.has_method("admits"):
		return bool(social.admits(policy, who, who_crew, invite))
	return true

func _local_name() -> String:
	var profile := get_node_or_null("/root/ProfileManager")
	if profile != null and String(profile.username).strip_edges() != "":
		return String(profile.username)
	return "Player"

func _send_beacon() -> void:
	var sock := _listen
	if sock == null:
		if _beacon == null:
			_beacon = PacketPeerUDP.new()
			_beacon.set_broadcast_enabled(true)
		sock = _beacon
	var body := JSON.stringify({
		"game": "ohara",
		"name": _local_name(),
		"port": _advertise_port,
		"players": 1 if _opponent_id == 0 else 2,
		"live": _match_live,
		"mode": String(_room_policy().get("kind", "public")),
		"access": String(_room_policy().get("access", "anyone")),
	})
	var bytes := body.to_utf8_buffer()
	sock.set_broadcast_enabled(true)
	sock.set_dest_address("255.255.255.255", BEACON_PORT)
	sock.put_packet(bytes)
	sock.set_dest_address("127.0.0.1", BEACON_PORT)
	sock.put_packet(bytes)

func _poll_beacons() -> void:
	if _listen == null:
		return
	var got := false
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		note_beacon(ip, pkt)
		got = true
	if got:
		return
	var now := Time.get_ticks_msec()
	for ip in _seen.keys():
		if now - int((_seen[ip] as Dictionary).get("t", 0)) > 4000:
			_seen.erase(ip)
			rooms_updated.emit()
			return

func _rps(a: String, b: String) -> int:
	if a == b:
		return -1
	if (a == "Rock" and b == "Scissors") or (a == "Scissors" and b == "Paper") or (a == "Paper" and b == "Rock"):
		return 0
	return 1

func _consider_throws() -> void:
	if _throw_local == "" or _throw_remote == "":
		return
	var mine := _throw_local
	var theirs := _throw_remote
	var winner := _rps(_throw_local, _throw_remote)
	_throw_local = ""
	_throw_remote = ""
	if lobby_client:
		_rpc_relay.rpc_id(1, "reveal", {"mine": mine, "theirs": theirs, "winner": winner}, 0)
	else:
		_rpc_reveal.rpc(mine, theirs, winner)
	throws_revealed.emit(mine, theirs, winner)

func _begin(first: int) -> void:
	var seed_value := randi()
	tourney_minutes = _clock_minutes()
	tourney_best = _series_best()
	_catchup = {
		"deck_a": local_deck, "deck_b": remote_deck,
		"first": first, "seed": seed_value, "actions": [],
		"minutes": tourney_minutes,
		"best": tourney_best,
	}
	_match_live = true
	if lobby_client:
		_rpc_relay.rpc_id(1, "begin", _catchup, 0)
	else:
		_rpc_begin.rpc(local_deck, remote_deck, first, seed_value, tourney_minutes, tourney_best)
	match_begin.emit(local_deck, remote_deck, first, seed_value)

func _series_best() -> int:
	var social := get_node_or_null("/root/Social")
	if social == null or String(social.room_kind) != "tournament":
		return 3
	return int(social.tournament.get("best_of", 3))

func _banned(who: String) -> bool:
	var accounts := get_node_or_null("/root/Accounts")
	return accounts != null and accounts.is_banned(who)

func _note_guest_deck(deck: Dictionary, who: String) -> void:
	remote_deck = deck
	peer_name = who
	if tag and mates_here < 2:
		_deck_waiting = true
		return
	_open_guest()

func _open_guest() -> void:
	_deck_waiting = false
	peer_ready.emit()
	if lobby_client:
		_rpc_relay.rpc_id(1, "deck_ok", {}, 0)
	elif is_host and not relay:
		_rpc_deck_ok.rpc()

func _add_mate(id: int) -> int:
	if id in _mates:
		return 0 if _mates.find(id) == 0 else 1
	if _mates.size() >= 2:
		return -1
	_mates.append(id)
	mates_here = _mates.size()
	mates_changed.emit(mates_here)
	if _deck_waiting and mates_here >= 2:
		_open_guest()
	return 0 if _mates.size() == 1 else 1

func _clock_minutes() -> int:
	var social := get_node_or_null("/root/Social")
	if social == null or String(social.room_kind) != "tournament":
		return 0
	return int(social.tournament.get("minutes", 0))

func _take_begin(deck_a: Dictionary, deck_b: Dictionary, first: int, seed_value: int, actions: Array) -> void:
	if role == "watch":
		spectate_ready.emit(deck_a, deck_b, first, seed_value, actions)
		return
	local_deck = deck_b
	remote_deck = deck_a
	match_begin.emit(deck_a, deck_b, first, seed_value)

func _room_of(peer_id: int) -> Dictionary:
	var rid := int(_peer_room.get(peer_id, 0))
	if rid == 0 or not _rooms.has(rid):
		return {}
	return _rooms[rid]

func _others(room: Dictionary, except: int) -> Array:
	var out: Array = []
	for key in ["host", "guest", "mate0", "mate1"]:
		var pid := int(room.get(key, 0))
		if pid > 0 and pid != except:
			out.append(pid)
	for w in room.get("watch", []):
		if int(w) != except:
			out.append(int(w))
	return out

@rpc("any_peer", "reliable")
func _rpc_hello(want: String, who: String, who_crew: String, invite_code: String) -> void:
	if relay or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _banned(who):
		_rpc_denied.rpc_id(id, "This account is banned.")
		return
	if not _admits(_room_policy(), who, who_crew, invite_code):
		_rpc_denied.rpc_id(id, "This room is not open to you.")
		return
	if want == "watch":
		if id not in _watchers:
			_watchers.append(id)
		if _match_live:
			_rpc_catchup.rpc_id(id, _catchup)
		return
	if want == "mate":
		if not tag:
			_rpc_denied.rpc_id(id, "This room is not a tag duel.")
			return
		var seat := _add_mate(id)
		if seat < 0:
			_rpc_full.rpc_id(id)
			return
		_rpc_seated.rpc_id(id, seat)
		return
	if _opponent_id != 0 and _opponent_id != id:
		_rpc_full.rpc_id(id)
		return
	_opponent_id = id

@rpc("any_peer", "reliable")
func _rpc_deck(deck: Dictionary, who: String) -> void:
	if relay or not multiplayer.is_server():
		return
	remote_deck = deck
	peer_name = who
	_note_guest_deck(deck, who)

@rpc("authority", "reliable")
func _rpc_deck_ok() -> void:
	if not multiplayer.is_server():
		peer_ready.emit()

@rpc("any_peer", "reliable")
func _rpc_throw(hand: String) -> void:
	if relay or not multiplayer.is_server():
		return
	_throw_remote = hand
	_consider_throws()

@rpc("any_peer", "reliable")
func _rpc_first(first: int) -> void:
	if multiplayer.is_server() and not relay:
		_begin(first)

@rpc("any_peer", "reliable")
func _rpc_request(action: Dictionary) -> void:
	if multiplayer.is_server() and not relay:
		action_requested.emit(action)

@rpc("authority", "reliable")
func _rpc_broadcast(action: Dictionary) -> void:
	if not multiplayer.is_server():
		action_broadcast.emit(action)

@rpc("any_peer", "reliable")
func _rpc_chat(channel: String, message: String) -> void:
	if multiplayer.get_remote_sender_id() == multiplayer.get_unique_id():
		return
	chat_received.emit(channel, message)

@rpc("authority", "reliable")
func _rpc_reveal(host_throw: String, client_throw: String, winner_seat: int) -> void:
	if multiplayer.is_server():
		return
	throws_revealed.emit(client_throw, host_throw, winner_seat)

@rpc("authority", "reliable")
func _rpc_begin(deck_a: Dictionary, deck_b: Dictionary, first: int, seed_value: int, minutes: int, best: int) -> void:
	if multiplayer.is_server():
		return
	tourney_minutes = minutes
	tourney_best = best
	_take_begin(deck_a, deck_b, first, seed_value, [])

@rpc("authority", "reliable")
func _rpc_catchup(data: Dictionary) -> void:
	tourney_minutes = int(data.get("minutes", 0))
	tourney_best = int(data.get("best", 0))
	_take_begin(
		data.get("deck_a", {}), data.get("deck_b", {}),
		int(data.get("first", 0)), int(data.get("seed", 0)),
		data.get("actions", []))

@rpc("authority", "reliable")
func _rpc_full() -> void:
	room_full.emit()

@rpc("authority", "reliable")
func _rpc_denied(reason: String) -> void:
	room_denied.emit(reason)
	close()

func send_invite(row: Dictionary) -> void:
	if not active:
		return
	if lobby_client:
		_rpc_relay.rpc_id(1, "invite", row, 0)
		return
	_rpc_invite.rpc(row)

@rpc("any_peer", "reliable")
func _rpc_invite(row: Dictionary) -> void:
	var from := multiplayer.get_remote_sender_id()
	if from == multiplayer.get_unique_id():
		return
	if is_host:
		for dest in multiplayer.get_peers():
			if int(dest) == from:
				continue
			_rpc_invite.rpc_id(int(dest), row)
	var social := get_node_or_null("/root/Social")
	if social != null:
		social.receive_invite(row)

func send_report(row: Dictionary) -> void:
	if not active:
		return
	if lobby_client:
		_rpc_relay.rpc_id(1, "report", row, 0)
		return
	_rpc_report.rpc(row)

@rpc("any_peer", "reliable")
func _rpc_report(row: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() == multiplayer.get_unique_id():
		return
	var social := get_node_or_null("/root/Social")
	if social != null:
		social.store_report(row)

@rpc("any_peer", "reliable")
func _rpc_open_room(room_name: String, policy: Dictionary) -> void:
	if not relay or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var rid := _next_room
	_next_room += 1
	_rooms[rid] = {"host": id, "guest": 0, "mate0": 0, "mate1": 0, "watch": [], "name": room_name, "policy": policy}
	_peer_room[id] = rid
	_rpc_room_opened.rpc_id(id, rid)

@rpc("authority", "reliable")
func _rpc_room_opened(rid: int) -> void:
	room_id = rid
	is_host = true
	lobby_client = true
	room_opened.emit()

@rpc("any_peer", "reliable")
func _rpc_enter_room(rid: int, want: String, who: String, who_crew: String, invite_code: String) -> void:
	if not relay or not multiplayer.is_server() or not _rooms.has(rid):
		return
	var id := multiplayer.get_remote_sender_id()
	var room: Dictionary = _rooms[rid]
	if _banned(who):
		_rpc_denied.rpc_id(id, "This account is banned.")
		return
	if not _admits(room.get("policy", {}), who, who_crew, invite_code):
		_rpc_denied.rpc_id(id, "This room is not open to you.")
		return
	if want == "watch":
		var watch: Array = room.get("watch", [])
		watch.append(id)
		room["watch"] = watch
		_peer_room[id] = rid
		_rpc_entered.rpc_id(id, "watch")
		_rpc_inbox.rpc_id(int(room.get("host", 0)), "watcher", {"id": id, "who": who})
		return
	if want == "mate":
		var policy: Dictionary = room.get("policy", {})
		if String(policy.get("kind", "")) != "tag":
			_rpc_denied.rpc_id(id, "This room is not a tag duel.")
			return
		var seat := -1
		if int(room.get("mate0", 0)) == 0:
			room["mate0"] = id
			seat = 0
		elif int(room.get("mate1", 0)) == 0:
			room["mate1"] = id
			seat = 1
		if seat < 0:
			_rpc_full.rpc_id(id)
			return
		_peer_room[id] = rid
		_rpc_entered.rpc_id(id, "mate%d" % seat)
		_rpc_inbox.rpc_id(int(room.get("host", 0)), "mate", {"seat": seat})
		return
	if int(room.get("guest", 0)) != 0:
		_rpc_full.rpc_id(id)
		return
	room["guest"] = id
	_peer_room[id] = rid
	_rpc_entered.rpc_id(id, "play")
	_rpc_inbox.rpc_id(int(room.get("host", 0)), "guest", {"who": who})

@rpc("authority", "reliable")
func _rpc_entered(want: String) -> void:
	lobby_client = true
	if want.begins_with("mate"):
		role = "play"
		seated.emit(int(want.substr(4)))
		return
	role = want
	if want == "play":
		joined.emit()

@rpc("authority", "reliable")
func _rpc_seated(seat: int) -> void:
	role = "play"
	is_host = false
	seated.emit(seat)

@rpc("any_peer", "reliable")
func _rpc_ask_rooms() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var list: Array = []
	if relay:
		for rid in _rooms.keys():
			var room: Dictionary = _rooms[rid]
			var players := 1
			if int(room.get("guest", 0)) != 0:
				players += 1
			if int(room.get("mate0", 0)) != 0:
				players += 1
			if int(room.get("mate1", 0)) != 0:
				players += 1
			var policy: Dictionary = room.get("policy", {})
			list.append({
				"kind": "lobby", "id": int(rid), "ip": "",
				"name": String(room.get("name", "Room")),
				"port": LOBBY_PORT, "players": players, "live": false,
				"mode": String(policy.get("kind", "public")),
				"access": String(policy.get("access", "anyone")),
			})
	elif is_host:
		var policy := _room_policy()
		list.append({
			"kind": "lobby", "id": 0, "ip": "",
			"name": _local_name(), "port": _advertise_port,
			"players": 1 if _opponent_id == 0 else 2, "live": _match_live,
			"mode": String(policy.get("kind", "public")),
			"access": String(policy.get("access", "anyone")),
		})
	_rpc_rooms.rpc_id(id, list)

@rpc("authority", "reliable")
func _rpc_rooms(list: Array) -> void:
	_lobby_rooms = list
	var direct := false
	for row in list:
		if int((row as Dictionary).get("id", 0)) == 0:
			direct = true
	if direct:
		lobby_client = false
	rooms_updated.emit()

@rpc("any_peer", "reliable")
func _rpc_relay(kind: String, payload: Dictionary, target: int) -> void:
	if not relay or not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	if kind == "invite":
		for dest in multiplayer.get_peers():
			if int(dest) == from:
				continue
			_rpc_inbox.rpc_id(int(dest), "invite", payload)
		return
	var room := _room_of(from)
	if room.is_empty():
		return
	_keep_conduct(kind, payload)
	var dests: Array = []
	if target > 0:
		dests = [target]
	else:
		dests = _others(room, from)
	for dest in dests:
		_rpc_inbox.rpc_id(int(dest), kind, payload)

@rpc("authority", "reliable")
func _rpc_inbox(kind: String, payload: Dictionary) -> void:
	if multiplayer.is_server() and relay:
		return
	match kind:
		"deck":
			if is_host:
				_note_guest_deck(payload.get("deck", {}), String(payload.get("who", "Opponent")))
		"mate":
			mates_here += 1
			mates_changed.emit(mates_here)
			if _deck_waiting and mates_here >= 2:
				_open_guest()
		"deck_ok":
			if not is_host:
				peer_ready.emit()
		"throw":
			if is_host:
				_throw_remote = String(payload.get("hand", ""))
				_consider_throws()
		"reveal":
			if not is_host:
				throws_revealed.emit(String(payload.get("theirs", "")), String(payload.get("mine", "")), int(payload.get("winner", -1)))
		"first":
			if is_host:
				_begin(int(payload.get("first", 0)))
		"begin":
			tourney_minutes = int(payload.get("minutes", 0))
			tourney_best = int(payload.get("best", 3))
			_take_begin(payload.get("deck_a", {}), payload.get("deck_b", {}), int(payload.get("first", 0)), int(payload.get("seed", 0)), payload.get("actions", []))
		"request":
			if is_host:
				action_requested.emit(payload.get("action", {}))
		"broadcast":
			if not is_host:
				action_broadcast.emit(payload.get("action", {}))
		"catchup":
			tourney_minutes = int(payload.get("minutes", 0))
			tourney_best = int(payload.get("best", 3))
			_take_begin(payload.get("deck_a", {}), payload.get("deck_b", {}), int(payload.get("first", 0)), int(payload.get("seed", 0)), payload.get("actions", []))
		"watcher":
			if is_host and _match_live:
				_rpc_relay.rpc_id(1, "catchup", _catchup, int(payload.get("id", 0)))
		"chat":
			chat_received.emit(String(payload.get("channel", "")), String(payload.get("message", "")))
		"report":
			var social := get_node_or_null("/root/Social")
			if social != null:
				social.store_report(payload)
		"invite":
			var social_box := get_node_or_null("/root/Social")
			if social_box != null:
				social_box.receive_invite(payload)

func _keep_conduct(kind: String, payload: Dictionary) -> void:
	var social := get_node_or_null("/root/Social")
	if social == null:
		return
	if kind == "chat" and String(payload.get("channel", "")) != "match":
		social.archive_chat(String(payload.get("channel", "")), String(payload.get("message", "")))
	elif kind == "report":
		social.store_report(payload)
		var accounts := get_node_or_null("/root/Accounts")
		if accounts != null:
			accounts.enqueue(payload)
