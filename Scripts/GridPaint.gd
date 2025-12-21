extends Node2D

func _draw():
	var color = Color(1, 1, 1, 0.1) # 半透明白线
	
	# 确定绘制范围
	var cols = GameConst.MAP_COLUMNS
	var rows = GameConst.MAP_ROWS
	
	# 判断是否是我方战场 (通过父节点名字)
	var parent_name = get_parent().name
	if parent_name == "FriendlyField":
		cols = GridManager.playable_columns
		rows = GridManager.playable_rows
	
	# 画竖线
	for x in range(cols + 1):
		var start = Vector2(x * GameConst.GRID_SIZE, 0)
		var end = Vector2(x * GameConst.GRID_SIZE, rows * GameConst.GRID_SIZE)
		draw_line(start, end, color)
		
	# 画横线
	for y in range(rows + 1):
		var start = Vector2(0, y * GameConst.GRID_SIZE)
		var end = Vector2(cols * GameConst.GRID_SIZE, y * GameConst.GRID_SIZE)
		draw_line(start, end, color)
		
	# 不再绘制锁定区域的遮罩，因为现在直接不画那部分的网格了

func _ready():
	queue_redraw()
