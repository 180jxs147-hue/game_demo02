extends Node2D

var override_cols: int = -1
var override_rows: int = -1

const GOLD := Color("c5a369")

func _draw():
	var enemy := get_parent().name == "EnemyField"
	var line_color := Color(0.86, 0.42, 0.36, 0.62) if enemy else Color(0.48, 0.82, 0.60, 0.62)
	
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
	
	var cell := float(GameConst.GRID_SIZE)
	var area := Rect2(0, 0, cols * cell, rows * cell)

	# 底色：压暗背景但让战场背景图透出来
	draw_rect(area, Color(0.06, 0.045, 0.03, 0.30))

	# 格内只保留很轻的玻璃质感，避免出现双重粗框。
	var inset_line := line_color
	inset_line.a = 0.16
	for y in range(rows):
		for x in range(cols):
			var fill := Color(line_color.r, line_color.g, line_color.b, 0.035 if (x + y) % 2 == 0 else 0.018)
			draw_rect(Rect2(Vector2(x, y) * cell + Vector2(1, 1), Vector2.ONE * (cell - 2)), fill, true)
			draw_rect(Rect2(Vector2(x, y) * cell + Vector2(2, 2), Vector2.ONE * (cell - 4)), inset_line, false, 1.0)

	# 主网格线
	for x in range(cols + 1):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, area.size.y), line_color, 1.5)
	for y in range(rows + 1):
		draw_line(Vector2(0, y * cell), Vector2(area.size.x, y * cell), line_color, 1.5)

	# 外框描金
	draw_rect(area, Color(GOLD.r, GOLD.g, GOLD.b, 0.72), false, 2.0)

	# 四角包角：L 形金件 + 端头方块
	_draw_corners(area)

func _draw_corners(area: Rect2):
	var len := 16.0
	var w := 2.5
	var pad := 2.0
	var gold := Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
	var corners := [
		[area.position, Vector2.RIGHT, Vector2.DOWN],
		[Vector2(area.end.x, area.position.y), Vector2.LEFT, Vector2.DOWN],
		[Vector2(area.position.x, area.end.y), Vector2.RIGHT, Vector2.UP],
		[area.end, Vector2.LEFT, Vector2.UP],
	]
	for c in corners:
		var p: Vector2 = c[0]
		var dx: Vector2 = c[1]
		var dy: Vector2 = c[2]
		draw_line(p + dx * pad, p + dx * (len + pad), gold, w)
		draw_line(p + dy * pad, p + dy * (len + pad), gold, w)
		draw_rect(Rect2(p - Vector2.ONE * (w * 0.5), Vector2.ONE * w), gold)

func _ready():
	queue_redraw()
