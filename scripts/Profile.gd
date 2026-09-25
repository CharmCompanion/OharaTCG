extends Control

const POSTER_DIR := "res://assets/profiles/posters/"
const SYMBOL_DIR := "res://assets/profiles/symbols/"
const PFP_DIR := "res://assets/profiles/pfps/"

# Shared with tools/generate_profile_assets.py (poster-local pixel space)
const POSTER_W := 450
const POSTER_H := 640
const CUTOUT := Rect2(90, 170, 360 - 90, 460 - 170)  # x=90,y=170,w=270,h=290

var poster_base_height := 560.0

var pfp_layer: TextureRect
var poster_layer: TextureRect
var symbol_row: HBoxContainer
var name_label: Label
var bounty_label: Label
var tier_label: Label
var stats_label: Label
var _friend_label: Label
var _crew_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	build_ui()
	ProfileManager.profile_changed.connect(_refresh)

func build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	row.add_child(_build_poster())
	row.add_child(_build_panel())

func _build_poster() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(poster_base_height * POSTER_W / POSTER_H, poster_base_height)

	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(holder)

	# Layer 0 - profile picture (shows through the poster cutout)
	pfp_layer = TextureRect.new()
	pfp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pfp_layer)

	# Layer 1 - poster background (transparent in the cutout area)
	poster_layer = TextureRect.new()
	poster_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	poster_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(poster_layer)

	# Tier symbol row (under the WANTED ribbon)
	symbol_row = HBoxContainer.new()
	symbol_row.add_theme_constant_override("separation", 4)
	holder.add_child(symbol_row)

	# Labels (name inside the pfp window, bounty + tier in the footer zone)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(name_label)

	bounty_label = Label.new()
	bounty_label.add_theme_font_size_override("font_size", 26)
	bounty_label.add_theme_color_override("font_color", Color.WHITE)
	bounty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bounty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bounty_label)

	tier_label = Label.new()
	tier_label.add_theme_font_size_override("font_size", 18)
	tier_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tier_label)

	return wrap

func _layout_poster() -> void:
	var w := poster_layer.size.x
	if w <= 0.0: w = poster_base_height * POSTER_W / POSTER_H
	var f := w / POSTER_W

	# pfp inside cutout
	pfp_layer.position = Vector2(CUTOUT.position.x * f, CUTOUT.position.y * f)
	pfp_layer.size = Vector2(CUTOUT.size.x * f, CUTOUT.size.y * f)
	pfp_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pfp_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	# tier symbols centered, ribbon->cutout gap
	symbol_row.position = Vector2(w * 0.5 - symbol_row.size.x * 0.5, 128.0 * f)
	symbol_row.custom_minimum_size.y = 26 * f

	# name label in footer
	name_label.position = Vector2(36.0 * f, 528.0 * f)
	name_label.size = Vector2(w - 72.0 * f, 30.0 * f)

	bounty_label.position = Vector2(36.0 * f, 556.0 * f)
	bounty_label.size = Vector2(w - 72.0 * f, 34.0 * f)

	tier_label.position = Vector2(36.0 * f, 578.0 * f)
	tier_label.size = Vector2(w - 72.0 * f, 26.0 * f)

func _refresh() -> void:
	# poster art by tier
	var tier := ProfileManager.get_tier()
	var poster_path = POSTER_DIR + "poster_%s.png" % tier.id
	var poster_tex = load(poster_path)
	if poster_tex is Texture2D:
		poster_layer.texture = poster_tex

	# pfp
	var pfp_tex = load(ProfileManager.avatar_path)
	if pfp_tex is Texture2D:
		pfp_layer.texture = pfp_tex

	# symbols
	for child in symbol_row.get_children():
		child.queue_free()
	var symbol_count := int(tier.symbols)
	for i in range(symbol_count):
		var sym := TextureRect.new()
		sym.custom_minimum_size = Vector2(26, 26)
		sym.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sym.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sym.texture = load(SYMBOL_DIR + "symbol_%d.png" % (i + 1))
		symbol_row.add_child(sym)

	if is_inside_tree():
		_layout_poster()

	name_label.text = ProfileManager.username
	bounty_label.text = ProfileManager.format_bounty()
	tier_label.text = "%s Tier" % tier.name
	stats_label.text = "Wins: %d   Losses: %d" % [ProfileManager.wins, ProfileManager.losses]

func _paint_social() -> void:
	if _friend_label != null:
		var friends: Array = []
		for row in Social.friends:
			friends.append(Social.friend_line(row))
		_friend_label.text = "Friends: %s" % ("—" if friends.is_empty() else "\n".join(friends))
	if _crew_label != null:
		var members: Array = []
		for row in Social.crew.get("members", []):
			members.append(Social.crew_line(row))
		var title := Social.crew_name() if Social.crew_name() != "" else "none"
		_crew_label.text = "Crew %s\n%s" % [title, "\n".join(members)]

func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _build_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(300, 0)

	var header := Label.new()
	header.text = "Crew Profile"
	header.add_theme_font_size_override("font_size", 28)
	panel.add_child(header)

	# username
	panel.add_child(_lbl("Bounty Hunter Name:"))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_edit.text = ProfileManager.username
	name_edit.text_submitted.connect(func(_t): ProfileManager.set_username(name_edit.text))
	panel.add_child(name_edit)

	# bounty editor
	panel.add_child(_lbl("Set Bounty (Berries):"))
	var bounty_row := HBoxContainer.new()
	var bounty_edit := LineEdit.new()
	bounty_edit.placeholder_text = "30000000"
	bounty_edit.text = str(ProfileManager.bounty)
	bounty_edit.custom_minimum_size.x = 180
	bounty_row.add_child(bounty_edit)
	var set_btn := Button.new()
	set_btn.text = "Set"
	set_btn.pressed.connect(func(): ProfileManager.set_bounty(int(bounty_edit.text)))
	bounty_row.add_child(set_btn)
	panel.add_child(bounty_row)

	# progression buttons
	var win_btn := Button.new()
	win_btn.text = "+ Win  (+%s Berries)" % Formatter.number_text(ProfileManager.BOUNTY_PER_WIN)
	win_btn.pressed.connect(ProfileManager.register_win)
	panel.add_child(win_btn)

	var loss_btn := Button.new()
	loss_btn.text = "Register Loss"
	loss_btn.pressed.connect(ProfileManager.register_loss)
	panel.add_child(loss_btn)

	stats_label = Label.new()
	stats_label.text = "Wins: 0   Losses: 0"
	panel.add_child(stats_label)

	# avatar picker
	panel.add_child(_lbl("Select Profile Picture:"))
	var avatar_grid := HFlowContainer.new()
	avatar_grid.add_theme_constant_override("h_separation", 6)
	avatar_grid.add_theme_constant_override("v_separation", 6)
	avatar_grid.custom_minimum_size.y = 120
	panel.add_child(avatar_grid)

	var dir := DirAccess.open(PFP_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") or file_name.ends_with(".jpg"):
				var path := PFP_DIR + file_name
				var btn := TextureButton.new()
				btn.custom_minimum_size = Vector2(56, 56)
				btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
				btn.texture_normal = load(path)
				btn.pressed.connect(func():
					ProfileManager.set_avatar(path))
				avatar_grid.add_child(btn)
			file_name = dir.get_next()

	panel.add_child(_lbl("Drop your own images into assets/profiles/pfps/"))
	var report_pic := Button.new()
	report_pic.text = "Report this picture"
	report_pic.pressed.connect(func() -> void:
		var social := get_node_or_null("/root/Social")
		if social != null:
			social.file_report("avatar", ProfileManager.username, "Reported a profile picture.", {"avatar": ProfileManager.avatar_path}))
	panel.add_child(report_pic)
	panel.add_child(_lbl("Friend"))
	var friend_row := HBoxContainer.new()
	var friend_edit := LineEdit.new()
	friend_edit.placeholder_text = "Name"
	friend_edit.custom_minimum_size.x = 140
	friend_row.add_child(friend_edit)
	var add_friend := Button.new()
	add_friend.text = "Invite friend"
	add_friend.pressed.connect(func() -> void:
		var social := get_node_or_null("/root/Social")
		if social != null:
			social.request_friend(friend_edit.text))
	friend_row.add_child(add_friend)
	panel.add_child(friend_row)
	_friend_label = Label.new()
	_friend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_friend_label)
	panel.add_child(_lbl("Crew"))
	var crew_row := HBoxContainer.new()
	var crew_edit := LineEdit.new()
	crew_edit.placeholder_text = "Crew name"
	crew_edit.custom_minimum_size.x = 140
	crew_row.add_child(crew_edit)
	var make_crew := Button.new()
	make_crew.text = "Create"
	make_crew.pressed.connect(func() -> void:
		var social := get_node_or_null("/root/Social")
		if social != null:
			social.create_crew(crew_edit.text))
	crew_row.add_child(make_crew)
	panel.add_child(crew_row)
	var invite_row := HBoxContainer.new()
	var invite_edit := LineEdit.new()
	invite_edit.placeholder_text = "Crew member"
	invite_edit.custom_minimum_size.x = 140
	invite_row.add_child(invite_edit)
	var invite_b := Button.new()
	invite_b.text = "Invite"
	invite_b.pressed.connect(func() -> void:
		var social := get_node_or_null("/root/Social")
		if social != null:
			social.invite_to_crew(invite_edit.text))
	invite_row.add_child(invite_b)
	panel.add_child(invite_row)
	var stand_row := HBoxContainer.new()
	var stand_name := LineEdit.new()
	stand_name.placeholder_text = "Member"
	stand_name.custom_minimum_size.x = 100
	stand_row.add_child(stand_name)
	var stand_role := OptionButton.new()
	stand_role.add_item("Member")
	stand_role.add_item("Officer")
	stand_row.add_child(stand_role)
	var stand_rank := LineEdit.new()
	stand_rank.placeholder_text = "Rank"
	stand_rank.custom_minimum_size.x = 80
	stand_row.add_child(stand_rank)
	var stand_b := Button.new()
	stand_b.text = "Set"
	stand_b.tooltip_text = "Only the captain can set a role or a rank."
	stand_b.pressed.connect(func() -> void:
		var social := get_node_or_null("/root/Social")
		if social != null:
			social.set_crew_standing(stand_name.text, stand_role.get_item_text(stand_role.selected), stand_rank.text))
	stand_row.add_child(stand_b)
	var kick_b := Button.new()
	kick_b.text = "Kick"
	kick_b.tooltip_text = "Officers can remove members. The captain can remove anyone else."
	kick_b.pressed.connect(func() -> void:
		var social := get_node_or_null("/root/Social")
		if social != null:
			social.kick_member(stand_name.text))
	stand_row.add_child(kick_b)
	panel.add_child(stand_row)
	panel.add_child(load("res://scripts/ui/InviteBox.gd").new())
	_crew_label = Label.new()
	_crew_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_crew_label)
	if not Social.social_changed.is_connected(_paint_social):
		Social.social_changed.connect(_paint_social)
	_paint_social()

	# back
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		var ui = get_parent()
		if ui and ui.has_method("switch_scene"):
			ui.switch_scene("res://scenes/ui/PostLogin.tscn"))
	panel.add_child(back_btn)

	return panel

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_poster()