# tests/test_don_drag_drop.gd
extends SceneTree

var _tb: Control
var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_tb = load("res://scripts/ui/TestBoard.gd").new()
		root.add_child(_tb)
		_tb._ready()
		_tb.build_ui()
		_tb._start_game()
		return false
	if _frame == 3:
		_run()
		quit(0)
	return false

func _run() -> void:
	var tb: Control = _tb
	var engine = tb.engine
	var me = engine.players[0]
	print("Initial available DON: ", me.get_available_don(), " active: ", me.don_active)
	
	# Give P0 active DON
	me.don_active = 5
	tb._rebuild()
	
	# Check leader widget position
	var lead_widget = tb._widget_for(me.leader.uid)
	var lead_zone = tb._playfield.get_zone(0, "leader")
	print("Leader zone rect: ", lead_zone.get_global_rect())
	if lead_widget != null:
		print("Leader widget rect: ", lead_widget.get_global_rect(), " center: ", lead_widget.get_global_transform() * (lead_widget.size / 2.0))
	
	# Simulate dropping DON on leader zone center
	var lead_center = lead_zone.get_global_rect().get_center()
	print("Dropping DON at leader center: ", lead_center)
	tb._handle_card_drop("don", "don", lead_center)
	print("Leader attached DON count: ", me.leader.don_count(), " status: '", tb._status.text, "'")
	
	# Now play a character
	var chopper_dict = {
		"card_code": "ST01-006", "name": "Tony Tony.Chopper", "type": "Character",
		"power": 1000, "cost": 1, "counter": 0, "effect": "[Blocker]",
		"color": "Red", "rarity": "Common"
	}
	var chopper = engine._mk(chopper_dict, 0, MtMatchCard.ZONE_FIELD)
	me.field.append(chopper)
	tb._rebuild()
	
	var char_widget = tb._widget_for(chopper.uid)
	print("Chopper widget: ", char_widget)
	if char_widget != null:
		var c_center = char_widget.get_global_transform() * (char_widget.size / 2.0)
		print("Chopper widget rect: ", char_widget.get_global_rect(), " center: ", c_center)
		print("Dropping DON at Chopper center: ", c_center)
		tb._handle_card_drop("don", "don", c_center)
		print("Chopper attached DON count: ", chopper.don_count(), " status: '", tb._status.text, "'")
		
		# Also test dropping slightly off center (e.g. 25px off)
		tb._handle_card_drop("don", "don", c_center + Vector2(25, 30))
		print("After off-center drop, Chopper attached DON: ", chopper.don_count(), " status: '", tb._status.text, "'")
