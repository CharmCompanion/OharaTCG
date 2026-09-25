# One inbox for friend, crew, duel, and tournament invites.
extends VBoxContainer

var _list: VBoxContainer

func _ready() -> void:
	var title := Label.new()
	title.text = "Invites"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	_list = VBoxContainer.new()
	add_child(_list)
	var social := get_node_or_null("/root/Social")
	if social != null and not social.social_changed.is_connected(_rebuild):
		social.social_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var social := get_node_or_null("/root/Social")
	if social == null:
		return
	var me := ""
	var profile := get_node_or_null("/root/ProfileManager")
	if profile != null:
		me = String(profile.username)
	var any := false
	for row in social.inbox:
		if not row is Dictionary:
			continue
		any = true
		_list.add_child(_row(social, row, me))
	if not any:
		var empty := Label.new()
		empty.text = "No invites."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty)

func _row(social: Node, row: Dictionary, me: String) -> HBoxContainer:
	var kind := String(row.get("kind", ""))
	var from := String(row.get("from", ""))
	var target := String(row.get("target", ""))
	var detail: Dictionary = row.get("detail", {})
	var line := "%s from %s" % [kind, from]
	if from == me:
		line = "Sent %s to %s" % [kind, target]
	elif kind == "friend":
		line = "%s wants to be friends" % from
	elif kind == "crew":
		line = "%s invited you to %s" % [from, detail.get("crew", "a crew")]
	elif kind == "duel":
		line = "%s invited you to a duel" % from
	elif kind == "tournament":
		line = "%s invited you (%s, best of %s, code %s)" % [from, detail.get("format", ""), detail.get("best_of", ""), detail.get("code", "")]
	var box := HBoxContainer.new()
	var lab := Label.new()
	lab.text = line
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(lab)
	if from != me:
		var id := String(row.get("id", ""))
		var ok := Button.new()
		ok.text = "Accept"
		ok.pressed.connect(_accept.bind(social, id))
		box.add_child(ok)
		var no := Button.new()
		no.text = "Decline"
		no.pressed.connect(_decline.bind(social, id))
		box.add_child(no)
	return box

func _accept(social: Node, id: String) -> void:
	if social != null and social.has_method("accept_invite"):
		social.accept_invite(id)

func _decline(social: Node, id: String) -> void:
	if social != null and social.has_method("decline_invite"):
		social.decline_invite(id)
