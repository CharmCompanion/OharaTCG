extends Node

var channels := {
	"general": [],
	"ranked": [],
}

func _ready():
	print("ChatManager loaded. Not auto-loading ChatUI in _ready()")

func post_message(channel: String, message: String):
	if not channels.has(channel):
		channels[channel] = []
	channels[channel].append(message)
