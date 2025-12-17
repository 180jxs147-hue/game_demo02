extends Node

# 存储格子占用情况: { Vector2i(x,y): UnitNode }
var grid_occupancy: Dictionary = {}

# 检查一个单位是否可以放在目标格子 (target_grid_pos 是锚点坐标)
func can_place_unit(unit_data: UnitData, target_grid_pos: Vector2i) -> bool:
	for offset in unit_data.grid_shape:
		var check_pos = target_grid_pos + offset
		
		# 1. 检查边界 (是否超出地图)
		if check_pos.x < 0 or check_pos.x >= GameConst.MAP_COLUMNS:
			return false
		if check_pos.y < 0 or check_pos.y >= GameConst.MAP_ROWS:
			return false
			
		# 2. 检查重叠 (是否已有单位)
		if grid_occupancy.has(check_pos):
			return false
			
	return true

# 将单位注册到格子上
func place_unit(unit: Node2D, target_grid_pos: Vector2i):
	# 先清除该单位之前占用的格子(如果有)
	clear_unit(unit)
	
	# 注册新位置
	for offset in unit.data.grid_shape:
		var final_pos = target_grid_pos + offset
		grid_occupancy[final_pos] = unit

# 移除单位的占用记录
func clear_unit(unit: Node2D):
	# 遍历字典，把值等于该 unit 的 key 删掉
	# (性能优化：实际项目中单位应该自己记住自己占了哪些格，直接删即可)
	var keys_to_erase = []
	for key in grid_occupancy:
		if grid_occupancy[key] == unit:
			keys_to_erase.append(key)
	
	for key in keys_to_erase:
		grid_occupancy.erase(key)

# 辅助：世界坐标 -> 网格坐标
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(world_pos / GameConst.GRID_SIZE)

# 这里返回的也是相对坐标
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos) * GameConst.GRID_SIZE
