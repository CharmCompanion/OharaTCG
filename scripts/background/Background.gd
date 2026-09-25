extends Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	get_viewport().size_changed.connect(_adjust_scale)
	_adjust_scale()

func _adjust_scale() -> void:
	var vp_size := get_viewport_rect().size
	if vp_size == Vector2.ZERO:
		vp_size = Vector2(1920, 1080)
	
	# The background textures (Ocean_1/4.png, etc.) are 2304 x 1296 (16:9).
	var s_x := vp_size.x / 2304.0
	var s_y := vp_size.y / 1296.0
	var s := maxf(s_x, s_y)
	
	var ocean = get_node_or_null("Background/Layer_Ocean")
	if ocean != null:
		ocean.scale = Vector2(s, s)
	
	var shading_layer: ParallaxLayer = get_node_or_null("Background/ParallaxLayerShading")
	if shading_layer != null:
		shading_layer.motion_mirroring = Vector2(2304.0 * s, 0)
		var shading = shading_layer.get_node_or_null("Layer_Shading")
		if shading != null:
			shading.scale = Vector2(s, s)
			
	var clouds_layer: ParallaxLayer = get_node_or_null("Background/ParallaxLayerClouds")
	if clouds_layer != null:
		clouds_layer.motion_mirroring = Vector2(2304.0 * s, 0)
		var clouds = clouds_layer.get_node_or_null("Layer_Clouds")
		if clouds != null:
			clouds.scale = Vector2(s, s)
			
	var ship = get_node_or_null("Background/Layer_Ship")
	if ship != null:
		ship.scale = Vector2(s, s)
