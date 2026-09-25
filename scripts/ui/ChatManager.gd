extends Node

signal message_received(channel: String, message: String)

const SAVE_PATH := "user://chat.json"

var channels := {
	"general": [],
	"ranked": [],
}

func _ready():
	_load()
	print("ChatManager loaded. Not auto-loading ChatUI in _ready()")
	var net := get_node_or_null("/root/Lan")
	if net != null:
		net.chat_received.connect(_on_net_chat)

func post_message(channel: String, message: String, broadcast: bool = true):
	var social := get_node_or_null("/root/Social")
	if channel == "match":
		if social != null:
			social.add_match_line(message)
			social.note_from_chat(message)
		if broadcast:
			var net := get_node_or_null("/root/Lan")
			if net != null and net.active:
				net.say(channel, message)
		message_received.emit(channel, message)
		return
	if not channels.has(channel):
		channels[channel] = []
	channels[channel].append(message)
	_save()
	if social != null:
		social.archive_chat(channel, message)
		social.note_from_chat(message)
	if broadcast:
		var net := get_node_or_null("/root/Lan")
		if net != null and net.active:
			net.say(channel, message)
	message_received.emit(channel, message)

func _on_net_chat(channel: String, message: String) -> void:
	post_message(channel, message, false)

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(channels))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		for key in data.keys():
			channels[key] = data[key]
