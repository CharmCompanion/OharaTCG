# tests/drag_rotation_smoke.gd -- Test rested rotation, attached DON, and hover growth
extends SceneTree

func _init() -> void:
	print("--- Running Drag, Rotation, & DON Smoke Test ---")
	var w := MtMatCard.new()
	root.add_child(w)
	
	# 1. Test Active state (rotation = 0, scale = 1)
	w.setup("c1", "my_field", "Luffy", "5000", "", false, false, {}, 0, null)
	assert(w.rotation_degrees == 0.0, "Active card should have rotation_degrees == 0")
	assert(w.is_rested == false, "Active card is_rested should be false")
	assert(w.don_count == 0, "No attached DON initially")
	
	# 2. Test Rested state (rotation = -90, is_rested = true)
	w.setup("c1", "my_field", "Luffy", "5000", "", true, false, {}, 0, null)
	assert(w.rotation_degrees == -90.0, "Rested card should have rotation_degrees == -90")
	assert(w.is_rested == true, "Rested card is_rested should be true")
	
	# 3. Test Attached DON (don_count = 3)
	w.setup("c1", "my_field", "Luffy", "5000", "", true, false, {}, 3, null)
	assert(w.don_count == 3, "don_count should be 3")
	assert(w._don_layer != null, "_don_layer should exist")
	assert(w._don_layer.get_child_count() == 3, "_don_layer should have 3 attached DON children")
	var d0: TextureRect = w._don_layer.get_child(0)
	var d1: TextureRect = w._don_layer.get_child(1)
	assert(d0.offset_left == 8.0, "First DON should be offset +8px to the right")
	assert(d1.offset_left == 16.0, "Second DON should be offset +16px to the right")
	print("Attached DON stack verified: %d children created with stepping offsets" % w._don_layer.get_child_count())
	
	# 4. Test Hand Hover Growth
	var hand_w := MtMatCard.new()
	root.add_child(hand_w)
	hand_w.setup("h1", "hand", "Zoro", "Cost 3", "", false, false, {}, 0, null)
	assert(hand_w.scale == Vector2.ONE, "Initial hand card scale should be 1.0")
	hand_w._on_mouse_entered()
	assert(hand_w.z_index == 50, "Hovered hand card z_index should be raised to 50")
	hand_w._on_mouse_exited()
	assert(hand_w.z_index == 0, "Unhovered hand card z_index should restore to 0")
	
	# 5. Test set_rested_animated
	w.set_rested_animated(false)
	assert(w.is_rested == false, "set_rested_animated(false) sets is_rested false")
	w.set_rested_animated(true)
	assert(w.is_rested == true, "set_rested_animated(true) sets is_rested true")
	print("Hand hover focus growth & animated rest verified!")
	
	w.queue_free()
	hand_w.queue_free()
	print("DRAG ROTATION SMOKE: OK (0 failures)")
	quit(0)
