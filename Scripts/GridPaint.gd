extends Node2D

var override_cols: int = -1
var override_rows: int = -1

func _draw():
	# 改为深色半透明线，增加宽度，以便在黄色/亮色背景上更清晰
	var enemy := get_parent().name == "EnemyField"
	var color := Color(0.80, 0.39, 0.31, 0.48) if enemy else Color(0.49, 0.72, 0.56, 0.48) 
	var line_width = 2.0
	
	# 确定绘制范围
	var cols = GameConst.MAP_COLUMNS
	var rows = GameConst.MAP_ROWS
	
	# 优先使用重写值（如果已设置）
	if override_cols > 0:
		cols = override_cols
	elif GridManager and GridManager.playable_columns > 0:
		cols = GridManager.playable_columns
		
	if override_rows > 0:
		rows = override_rows
	elif GridManager and GridManager.playable_rows > 0:
		rows = GridManager.playable_rows
	
	var area := Rect2(0, 0, cols * GameConst.GRID_SIZE, rows * GameConst.GRID_SIZE)
	draw_rect(area, Color(0.10, 0.075, 0.065, 0.64))
	draw_rect(area, color.lightened(0.2), false, 2.0)
	# 画竖线
	for x in range(cols + 1):
		var start = Vector2(x * GameConst.GRID_SIZE, 0)
		var end = Vector2(x * GameConst.GRID_SIZE, rows * GameConst.GRID_SIZE)
		draw_line(start, end, color, line_width)
		
	# 画横线
	for y in range(rows + 1):
		var start = Vector2(0, y * GameConst.GRID_SIZE)
		var end = Vector2(cols * GameConst.GRID_SIZE, y * GameConst.GRID_SIZE)
		draw_line(start, end, color, line_width)
		
	# 不再绘制锁定区域的遮罩，因为现在直接不画那部分的网格了

func _ready():
	queue_redraw()
