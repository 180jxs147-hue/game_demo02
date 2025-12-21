extends Node2D

func _draw():
	var color = Color(1, 1, 1, 0.1) # 半透明白线
	
	# 画竖线
	for x in range(GameConst.MAP_COLUMNS + 1):
		var start = Vector2(x * GameConst.GRID_SIZE, 0)
		var end = Vector2(x * GameConst.GRID_SIZE, GameConst.MAP_ROWS * GameConst.GRID_SIZE)
		
		if x > GridManager.playable_columns:
			# 锁定区域画红叉或者暗色
			draw_line(start, end, Color(0.3, 0, 0, 0.3))
		else:
			draw_line(start, end, color)
		
	# 画横线
	for y in range(GameConst.MAP_ROWS + 1):
		var start = Vector2(0, y * GameConst.GRID_SIZE)
		var end = Vector2(GameConst.MAP_COLUMNS * GameConst.GRID_SIZE, y * GameConst.GRID_SIZE)
		draw_line(start, end, color)
		
	# 画锁定区域遮罩
	if GridManager.playable_columns < GameConst.MAP_COLUMNS:
		var locked_x = GridManager.playable_columns * GameConst.GRID_SIZE
		var locked_w = (GameConst.MAP_COLUMNS - GridManager.playable_columns) * GameConst.GRID_SIZE
		var rect = Rect2(locked_x, 0, locked_w, GameConst.MAP_ROWS * GameConst.GRID_SIZE)
		draw_rect(rect, Color(0, 0, 0, 0.4))

func _ready():
	queue_redraw()
