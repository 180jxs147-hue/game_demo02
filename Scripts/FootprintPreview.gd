extends Control

@export var unit_data: UnitData

func set_unit_data(data: UnitData):
	unit_data = data
	queue_redraw()

func _draw():
	if not unit_data:
		return
	if unit_data.grid_shape.is_empty():
		return

	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for p in unit_data.grid_shape:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)

	var w_cells := int(max_x - min_x + 1)
	var h_cells := int(max_y - min_y + 1)
	if w_cells <= 0 or h_cells <= 0:
		return

	var pad: float = 3.0
	var avail_w: float = maxf(1.0, size.x - pad * 2.0)
	var avail_h: float = maxf(1.0, size.y - pad * 2.0)
	var cell: float = floor(minf(avail_w / float(w_cells), avail_h / float(h_cells)))
	cell = maxf(2.0, cell)

	var grid_w: float = cell * float(w_cells)
	var grid_h: float = cell * float(h_cells)
	var origin: Vector2 = Vector2((size.x - grid_w) * 0.5, (size.y - grid_h) * 0.5)

	var bg := Color(1, 1, 1, 0.06)
	var line := Color(1, 1, 1, 0.12)
	var base := unit_data.color
	if "civilization" in unit_data:
		base = _get_civ_color(String(unit_data.civilization).to_lower())
	var fill := base
	fill.a = 0.85
	var border := base.darkened(0.45)
	border.a = 0.95

	draw_rect(Rect2(origin.x, origin.y, grid_w, grid_h), bg, true)
	for x in range(w_cells + 1):
		var p1 := origin + Vector2(x * cell, 0)
		var p2 := origin + Vector2(x * cell, grid_h)
		draw_line(p1, p2, line, 1.0)
	for y in range(h_cells + 1):
		var p1 := origin + Vector2(0, y * cell)
		var p2 := origin + Vector2(grid_w, y * cell)
		draw_line(p1, p2, line, 1.0)

	for off in unit_data.grid_shape:
		var x := int(off.x - min_x)
		var y := int(off.y - min_y)
		var r := Rect2(origin.x + x * cell, origin.y + y * cell, cell, cell)
		draw_rect(r.grow(-1.0), fill, true)
		draw_rect(r.grow(-1.0), border, false, 2.0)

	var ax := int(0 - min_x)
	var ay := int(0 - min_y)
	if ax >= 0 and ax < w_cells and ay >= 0 and ay < h_cells:
		var a := Rect2(origin.x + ax * cell, origin.y + ay * cell, cell, cell)
		draw_rect(a.grow(-2.0), Color(1, 1, 1, 0.18), false, 2.0)

func _get_civ_color(civ_key: String) -> Color:
	match civ_key:
		"han":
			return Color("c83f2b")
		"roman":
			return Color("3b1b5a")
		"greek":
			return Color("1b5ea8")
		"french":
			return Color("234aa5")
		_:
			return unit_data.color
