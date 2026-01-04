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
	
	var fill = unit_data.color
	fill.a = 0.85
	var border = unit_data.color.darkened(0.4)
	border.a = 0.95
	for off in unit_data.grid_shape:
		var rect = Rect2(base_offset.x + off.x * cell_size, base_offset.y + off.y * cell_size, cell_size, cell_size)
		draw_rect(rect.grow(-1.0), fill, true)
		draw_rect(rect.grow(-1.0), border, false, 2.0)
	
	var anchor_rect = Rect2(base_offset.x, base_offset.y, cell_size, cell_size)
	draw_rect(anchor_rect.grow(-2.0), Color(1, 1, 1, 0.12), false, 2.0)
