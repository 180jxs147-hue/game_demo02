extends Node2D

func _draw():
	var color = Color(1, 1, 1, 0.1) # 半透明白线
	
	# 确定绘制范围
	var cols = GameConst.MAP_COLUMNS
	var rows = GameConst.MAP_ROWS
	
	# 判断是否需要动态调整行列
	if GridManager:
		# 无论是 FriendlyField 还是 EnemyField，都暂时跟随 GridManager 的动态行列
		# 这样能保证视觉上的一致性，且如果 EnemyGrid 需要扩充，也能通过 GridManager 控制
		# (未来如果需要敌我不同步，可以再加判定)
		if GridManager.playable_columns > 0:
			cols = GridManager.playable_columns
		if GridManager.playable_rows > 0:
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
