# tests/context_menu_smoke.gd -- Test right-click context menu, player HUDs, Life backs, and DON alignment.
extends SceneTree

var _frame := 0
var _board: MtTestBoard
var _fail := 0

func _check(label: String, condition: bool, extra = "") -> void:
	if condition:
		print("  PASS: %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s (%s)" % [label, str(extra)])

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var script = load("res://scripts/ui/TestBoard.gd")
		_board = script.new()
		root.add_child(_board)
		return false

	if _frame == 10:
		_run_tests()
		print("CONTEXT MENU SMOKE: %s (%d failures)" % ["OK" if _fail == 0 else "FAIL", _fail])
		quit(0 if _fail == 0 else 1)
		return true

	return false

func _run_tests() -> void:
	print("--- Running Context Menu, Player HUD, and Layout Smoke Test ---")
	var board := _board
	_check("Board created", board != null)
	_check("Engine initialized", board.engine != null)

	var pf: MtPlayField = board.get_node_or_null("PlayField")
	_check("PlayField found", pf != null)
	if pf == null:
		return

	# 1. Verify Player HUD above deck
	var bot_mat: MtPlayerMat = pf._bot_mat
	var top_mat: MtPlayerMat = pf._top_mat
	_check("BottomMat HUD name exists", bot_mat.hud_name_label() != null)
	_check("BottomMat HUD life exists", bot_mat.hud_life_label() != null)
	_check("TopMat HUD name exists", top_mat.hud_name_label() != null)
	_check("TopMat HUD life exists", top_mat.hud_life_label() != null)

	# 2. Verify Life fan renders with sleeve art
	var life_zone: Control = bot_mat.get_zone("life")
	_check("Life zone exists", life_zone != null)
	var fan: Control = life_zone.get_node_or_null("Fan") if life_zone != null else null
	_check("Life Fan exists", fan != null)
	if fan != null and fan.get_child_count() > 0:
		var first_holder: Control = fan.get_child(0) as Control
		_check("Life holder has child", first_holder != null and first_holder.get_child_count() > 0)
		if first_holder != null and first_holder.get_child_count() > 0:
			var tr := first_holder.get_child(0) as TextureRect
			_check("Life card is TextureRect", tr != null)
			_check("Life card has sleeve texture", tr != null and tr.texture != null)

	# 3. Verify Hands centered
	var hand: HBoxContainer = board._hand
	var opp_hand: HBoxContainer = board._opp_hand
	_check("Hand is HBoxContainer", hand is HBoxContainer)
	_check("Hand alignment centered", hand.alignment == BoxContainer.ALIGNMENT_CENTER)
	_check("Opponent hand is HBoxContainer", opp_hand is HBoxContainer)
	_check("Opponent hand alignment centered", opp_hand.alignment == BoxContainer.ALIGNMENT_CENTER)

	# 4. Verify Context Menu on Hand Card
	var me = board.engine.players[0]
	var initial_hand_count: int = me.hand.size()
	var initial_deck_count: int = me.deck.size()
	_check("Hand has cards", initial_hand_count > 0)

	var hand_widget: MtMatCard = null
	for c in hand.get_children():
		if c is MtMatCard:
			hand_widget = c
			break
	_check("Hand widget found", hand_widget != null)

	if hand_widget != null:
		board._on_card_context_requested(hand_widget, Vector2(100, 100))
		_check("Context menu has items for hand card", board._context_menu.item_count > 0)
		_check("Context menu has Play option", board._context_menu.get_item_id(0) == board.CtxAction.HAND_PLAY)

	# 5. Verify Context Menu on Deck Zone (No cheat options allowed)
	board._on_zone_clicked(0, "deck", MOUSE_BUTTON_RIGHT, Vector2(200, 200))
	_check("Deck zone has no cheat context menu", board._context_menu.item_count == 0)

	# 6. Verify Context Menu on DON Deck Zone (No cheat options allowed)
	board._on_zone_clicked(0, "don_deck", MOUSE_BUTTON_RIGHT, Vector2(250, 250))
	_check("DON Deck zone has no cheat context menu", board._context_menu.item_count == 0)

	# 7. Verify Life Zone Context Menu (No cheat options allowed)
	board._on_zone_clicked(0, "life", MOUSE_BUTTON_RIGHT, Vector2(300, 300))
	_check("Life zone has no cheat context menu", board._context_menu.item_count == 0)

	# 8. Verify Trash Zone Context Menu (View Trash is legal)
	board._on_zone_clicked(0, "trash", MOUSE_BUTTON_RIGHT, Vector2(350, 350))
	_check("Trash context menu has items", board._context_menu.item_count > 0)
	_check("Trash has View Trash option", board._context_menu.get_item_id(0) == board.CtxAction.TRASH_VIEW)

	# 9. Verify Leader / Field card context menu (Legal actions only, no Stand/Rest cheat)
	var leader_card = me.leader
	_check("Leader exists", leader_card != null)
	if leader_card != null:
		var dummy_widget := MtMatCard.new()
		dummy_widget.uid = leader_card.uid
		dummy_widget.role = "my_leader"
		# Give active DON so Attach DON is available
		me.don_active = 2
		board.engine.phase = MtMatch.Phase.MAIN
		board._on_card_context_requested(dummy_widget, Vector2(400, 400))
		_check("Leader context menu has items", board._context_menu.item_count > 0)
		var has_stand_rest := false
		var has_attach_don := false
		for i in range(board._context_menu.item_count):
			if board._context_menu.get_item_id(i) == board.CtxAction.FIELD_REST_STAND:
				has_stand_rest = true
			if board._context_menu.get_item_id(i) == board.CtxAction.FIELD_ATTACH_DON:
				has_attach_don = true
		_check("Leader context menu has NO Stand/Rest cheat", not has_stand_rest)
		_check("Leader context menu has Attach 1 Active DON!!", has_attach_don)
		dummy_widget.queue_free()

	print("All context menu actions executed successfully!")
