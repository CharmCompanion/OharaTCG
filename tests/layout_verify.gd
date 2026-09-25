# tests/layout_verify.gd -- Verify geometry & node layouts for 1080p
extends SceneTree

var _frame := 0
var _mat: MtPlayerMat

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_mat = MtPlayerMat.new()
		_mat.size = Vector2(1920, 540)
		root.add_child(_mat)
		return false
	if _frame == 3:
		_run()
		quit(0)
	return false

func _run() -> void:
	var mat := _mat
	
	for zone in MtPlayerMat.ZONES:
		var node = mat.get_zone(zone)
		if node == null:
			printerr("FAIL: missing zone %s" % zone)
			quit(1)
			return
		var rect: Array = MtPlayerMat.ZONE_RECTS[zone]
		var w = (rect[2] - rect[0]) * 1920.0
		var h = (rect[3] - rect[1]) * 540.0
		print("Zone '%s': width=%.1f px, height=%.1f px" % [zone, w, h])
	
	# Check Character vs Cost
	var c_rect = MtPlayerMat.ZONE_RECTS["character"]
	var cost_rect = MtPlayerMat.ZONE_RECTS["cost"]
	var c_w = (c_rect[2] - c_rect[0]) * 1920.0
	var cost_w = (cost_rect[2] - cost_rect[0]) * 1920.0
	assert(abs(c_w - cost_w) < 0.1, "Character and Cost zone must have identical width!")
	assert(abs((c_rect[0] + c_rect[2]) - 1.0) < 0.001, "Character area must be horizontally centered/symmetric at 0.500!")

	# Check 1-card tall
	for zone in ["character", "leader", "stage", "deck", "don_deck", "cost", "trash", "event"]:
		var r = MtPlayerMat.ZONE_RECTS[zone]
		var zh = (r[3] - r[1]) * 540.0
		assert(abs(zh - 125.8) < 1.0, "Zone %s height %.1f should be ~126px (1 card tall)" % [zone, zh])

	# Check 1-card wide for single zones
	for zone in ["leader", "stage", "deck", "don_deck", "trash", "event"]:
		var r = MtPlayerMat.ZONE_RECTS[zone]
		var zw = (r[2] - r[0]) * 1920.0
		assert(abs(zw - 90.2) < 1.0, "Zone %s width %.1f should be ~90px (1 card wide)" % [zone, zw])

	# Check narrowed Life zone (~100px)
	var life_r = MtPlayerMat.ZONE_RECTS["life"]
	var life_w = (life_r[2] - life_r[0]) * 1920.0
	assert(abs(life_w - 99.8) < 1.0, "Life zone width %.1f should be ~100px" % life_w)
	
	# Check DON groups algorithm
	assert(MtPlayerMat.get_don_groups(1) == [1])
	assert(MtPlayerMat.get_don_groups(2) == [2])
	assert(MtPlayerMat.get_don_groups(3) == [3])
	assert(MtPlayerMat.get_don_groups(4) == [2, 2])
	assert(MtPlayerMat.get_don_groups(5) == [5])
	assert(MtPlayerMat.get_don_groups(6) == [3, 3])
	assert(MtPlayerMat.get_don_groups(7) == [5, 2])
	assert(MtPlayerMat.get_don_groups(8) == [5, 3])
	assert(MtPlayerMat.get_don_groups(9) == [3, 3, 3])
	assert(MtPlayerMat.get_don_groups(10) == [5, 5])
	print("DON grouping logic verified successfully for 1..10!")
	
	mat.queue_free()
	print("LAYOUT VERIFICATION OK: All zone proportions and dimensions verified!")
	quit(0)
