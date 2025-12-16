extends Node2D

func _draw():
	var color = Color(1, 1, 1, 0.1) # 半透明白线
	
	# 画竖线
	for x in range(GameConst.MAP_COLUMNS + 1):
		var start = Vector2(x * GameConst.GRID_SIZE, 0)
		var end = Vector2(x * GameConst.GRID_SIZE, GameConst.MAP_ROWS * GameConst.GRID_SIZE)
		draw_line(start, end, color)
		
	# 画横线
	for y in range(GameConst.MAP_ROWS + 1):
		var start = Vector2(0, y * GameConst.GRID_SIZE)
		var end = Vector2(GameConst.MAP_COLUMNS * GameConst.GRID_SIZE, y * GameConst.GRID_SIZE)
		draw_line(start, end, color)

func _ready():
	queue_redraw()
