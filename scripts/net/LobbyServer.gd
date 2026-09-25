extends SceneTree

# Public account server and room relay. Run this on the machine named in
# res://data/server.cfg, not on a player's PC:
#   godot --headless --path <OharaTCG> --script res://scripts/net/LobbyServer.gd

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var lan := get_root().get_node_or_null("Lan")
	if lan == null or not lan.has_method("serve_relay"):
		push_error("Lobby: Lan autoload is missing.")
		quit(1)
		return
	var code: int = lan.serve_relay()
	if code != OK:
		push_error("Lobby: could not listen on port 7780 (%d)." % code)
		quit(1)
		return
	print("Ohara lobby listening on port 7780.")
	var ip := await _external_ip()
	var accounts := get_root().get_node_or_null("Accounts")
	if accounts != null and ip != "":
		accounts.publish(ip)
		print("Ohara lobby address: %s" % ip)
	elif accounts != null:
		accounts.publish("")
		var mark := FileAccess.open("user://server_local.cfg", FileAccess.WRITE)
		if mark != null:
			mark.store_string("1\n")
		print("Ohara lobby: forward UDP 7780 to this PC.")

func _external_ip() -> String:
	var mapped := _map_port()
	if mapped != "":
		return mapped
	return await _lookup_ip()

func _map_port() -> String:
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	if err != OK:
		print("Ohara lobby: router did not map the port (%d)." % err)
		return ""
	upnp.add_port_mapping(7780, 7780, "OharaTCG", "UDP")
	return upnp.query_external_address().strip_edges()

func _lookup_ip() -> String:
	var http := HTTPRequest.new()
	get_root().add_child(http)
	var err := http.request("https://api.ipify.org")
	if err != OK:
		http.queue_free()
		return ""
	var result = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		return ""
	var body := PackedByteArray(result[3]).get_string_from_utf8().strip_edges()
	if body.is_valid_ip_address():
		return body
	return ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://server_local.cfg"))
