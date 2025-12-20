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
	var cell_w := size.x / float(cols)
	var cell_h := size.y / float(rows)
	var grid_color := Color(1, 1, 1, 0.08)
	
	for x in range(cols + 1):
		var p1 = Vector2(x * cell_w, 0)
		var p2 = Vector2(x * cell_w, rows * cell_h)
		draw_line(p1, p2, grid_color, 1.0)
	for y in range(rows + 1):
		var p1 = Vector2(0, y * cell_h)
		var p2 = Vector2(cols * cell_w, y * cell_h)
		draw_line(p1, p2, grid_color, 1.0)
	
	var fill = unit_data.color
	fill.a = 0.85
	var border = unit_data.color.darkened(0.4)
	border.a = 0.95
	for off in unit_data.grid_shape:
		var rect = Rect2(off.x * cell_w, off.y * cell_h, cell_w, cell_h)
		draw_rect(rect.grow(-1.0), fill, true)
		draw_rect(rect.grow(-1.0), border, false, 2.0)
	
	var anchor_rect = Rect2(0, 0, cell_w, cell_h)
	draw_rect(anchor_rect.grow(-2.0), Color(1, 1, 1, 0.12), false, 2.0)
