extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var parent = get_parent()
	if parent == null or not parent.has_method("get_outline_colors"):
		return
	var colors = parent.get_outline_colors()
	if colors.size() == 0:
		return
	var col_a: Color = colors[0]
	var col_b: Color = col_a
	if colors.size() > 1:
		col_b = colors[1]

	var size_rect = Rect2(Vector2.ZERO, size)
	if size_rect.size.x <= 0.0 or size_rect.size.y <= 0.0:
		return

	var outer: Rect2 = size_rect.grow(-2)
	var border_w: float = 4.0
	var r: float = 18.0
	r = min(r, outer.size.x * 0.5, outer.size.y * 0.5)

	# Two-color split border: top/left use col_a, bottom/right use col_b.
	var p_tl: Vector2 = outer.position
	var p_tr: Vector2 = outer.position + Vector2(outer.size.x, 0)
	var p_bl: Vector2 = outer.position + Vector2(0, outer.size.y)
	var p_br: Vector2 = outer.position + outer.size

	# Sides
	draw_line(Vector2(p_tl.x + r, p_tl.y), Vector2(p_tr.x - r, p_tr.y), col_a, border_w, true)
	draw_line(Vector2(p_tl.x, p_tl.y + r), Vector2(p_bl.x, p_bl.y - r), col_a, border_w, true)
	draw_line(Vector2(p_tr.x, p_tr.y + r), Vector2(p_br.x, p_br.y - r), col_b, border_w, true)
	draw_line(Vector2(p_bl.x + r, p_bl.y), Vector2(p_br.x - r, p_br.y), col_b, border_w, true)

	# Rounded corners
	var steps: int = 24
	draw_arc(p_tl + Vector2(r, r), r, PI, PI * 1.5, steps, col_a, border_w, true) # TL
	draw_arc(p_tr + Vector2(-r, r), r, PI * 1.5, TAU, steps, col_b, border_w, true) # TR
	draw_arc(p_br + Vector2(-r, -r), r, 0.0, PI * 0.5, steps, col_b, border_w, true) # BR
	draw_arc(p_bl + Vector2(r, -r), r, PI * 0.5, PI, steps, col_a, border_w, true) # BL
