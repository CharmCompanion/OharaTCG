# Spend bounty on a 5-card pack. Cards are marked owned in the local collection.
extends Control

const PACK_COST := 5_000_000
const PACK_SIZE := 5
const BACK_SCENE := "res://scenes/ui/PostLogin.tscn"

var _status: Label
var _list: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -260
	box.offset_top = -220
	box.offset_right = 260
	box.offset_bottom = 220
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "SHOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var bounty := Label.new()
	bounty.text = "Bounty %s" % ProfileManager.format_bounty()
	bounty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(bounty)
	var buy := Button.new()
	buy.text = "Buy a pack (5 cards)"
	buy.pressed.connect(_on_buy)
	box.add_child(buy)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_list = Label.new()
	_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_list)
	var back := Button.new()
	back.text = "< Back"
	back.pressed.connect(_on_back)
	box.add_child(back)

func _on_buy() -> void:
	if ProfileManager.bounty < PACK_COST:
		_status.text = "You need %d berries. Wins add bounty." % PACK_COST
		return
	var cdb := get_node_or_null("/root/CardDatabase")
	if cdb == null:
		return
	var pool: Array = cdb.get_base_cards_as_array()
	if pool.is_empty():
		_status.text = "Card data is still loading."
		return
	var pulled: Array = []
	for i in range(PACK_SIZE):
		var card: Dictionary = pool[randi() % pool.size()]
		var code := String(card.get("card_code", ""))
		if code == "":
			continue
		pulled.append("%s %s" % [code, String(card.get("name", ""))])
		CollectionManager.add_owned(code)
	ProfileManager.set_bounty(ProfileManager.bounty - PACK_COST)
	_status.text = "Pack opened. Bounty %s." % ProfileManager.format_bounty()
	_list.text = "\n".join(pulled)

func _on_back() -> void:
	var parent := get_parent()
	if parent and parent.has_method("switch_scene"):
		parent.switch_scene(BACK_SCENE)
	else:
		queue_free()
