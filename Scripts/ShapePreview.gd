extends Control

@export var unit_data: UnitData

func set_unit_data(data: UnitData):
	unit_data = data
	queue_redraw()

func _draw():
	if not unit_data:
		return
	var cols := GameConst.MAP_COLUMNS
	var rows := GameConst.MAP_ROWS
	var size := Vector2(maxf(1.0, self.size.x), maxf(1.0, self.size.y))
	
	# 计算正方形网格大小
	var cell_size = min(size.x / float(cols), size.y / float(rows))
	
	# 居中偏移
	var grid_w = cell_size * cols
	var grid_h = cell_size * rows
	var offset_x = (size.x - grid_w) / 2.0
	var offset_y = (size.y - grid_h) / 2.0
	var base_offset = Vector2(offset_x, offset_y)
	
	var grid_color := Color(1, 1, 1, 0.08)
	
	for x in range(cols + 1):
		var p1 = base_offset + Vector2(x * cell_size, 0)
		var p2 = base_offset + Vector2(x * cell_size, grid_h)
		draw_line(p1, p2, grid_color, 1.0)
	for y in range(rows + 1):
		var p1 = base_offset + Vector2(0, y * cell_size)
		var p2 = base_offset + Vector2(grid_w, y * cell_size)
		draw_line(p1, p2, grid_color, 1.0)
	
	var base_color := unit_data.color
	if "civilization" in unit_data:
		base_color = _get_civ_color(String(unit_data.civilization).to_lower(), unit_data.color)
	var fill := base_color
	fill.a = 0.85
	var border := base_color.darkened(0.4)
	border.a = 0.95
	var icon: Texture2D = unit_data.icon
	var has_icon := icon != null
	var bounds := _get_shape_bounds(unit_data.grid_shape)
	var target_aspect := bounds.size.x / maxf(1.0, bounds.size.y)
	var crop_src := Rect2(0, 0, 1, 1)
	if has_icon:
		crop_src = _get_center_crop_src(icon, target_aspect)
	for off in unit_data.grid_shape:
		var dest = Rect2(base_offset.x + off.x * cell_size, base_offset.y + off.y * cell_size, cell_size, cell_size)
		draw_rect(dest.grow(-1.0), fill, true)
		if has_icon:
			var rel = Vector2(off.x - bounds.position.x, off.y - bounds.position.y)
			var u_off := Vector2(rel.x / bounds.size.x, rel.y / bounds.size.y)
			var u_scl := Vector2(1.0 / bounds.size.x, 1.0 / bounds.size.y)
			var src_pos := crop_src.position + Vector2(u_off.x * crop_src.size.x, u_off.y * crop_src.size.y)
			var src_size := Vector2(u_scl.x * crop_src.size.x, u_scl.y * crop_src.size.y)
			var src_rect := Rect2(src_pos, src_size)
			draw_texture_rect_region(icon, dest.grow(-1.0), src_rect, Color.WHITE)
		draw_rect(dest.grow(-1.0), border, false, 2.0)
	
	var anchor_rect = Rect2(base_offset.x, base_offset.y, cell_size, cell_size)
	draw_rect(anchor_rect.grow(-2.0), Color(1, 1, 1, 0.12), false, 2.0)

func _get_shape_bounds(shape: Array) -> Rect2:
	if shape.is_empty():
		return Rect2(0, 0, 1, 1)
	var min_x := int(shape[0].x)
	var min_y := int(shape[0].y)
	var max_x := int(shape[0].x)
	var max_y := int(shape[0].y)
	for p in shape:
		min_x = min(min_x, int(p.x))
		min_y = min(min_y, int(p.y))
		max_x = max(max_x, int(p.x))
		max_y = max(max_y, int(p.y))
	return Rect2(min_x, min_y, (max_x - min_x + 1), (max_y - min_y + 1))

func _get_center_crop_src(tex: Texture2D, target_aspect: float) -> Rect2:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw <= 0.0 or th <= 0.0 or target_aspect <= 0.0:
		return Rect2(0, 0, tw, th)
	var src_w := tw
	var src_h := tw / target_aspect
	if src_h > th:
		src_h = th
		src_w = th * target_aspect
	var x := (tw - src_w) * 0.5
	var y := (th - src_h) * 0.5
	return Rect2(x, y, src_w, src_h)

func _get_civ_color(civ_key: String, fallback: Color) -> Color:
	match civ_key:
		"han":
			return Color("c83f2b")
		"roman":
			return Color("3b1b5a")
		"greek":
			return Color("1b5ea8")
		"french":
			return Color("234aa5")
		"huangjin":
			return Color("d1a322")
		_:
			return fallback
