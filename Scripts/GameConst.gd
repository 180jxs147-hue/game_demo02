class_name GameConst

const GRID_SIZE: int = 64
const GRID_PADDING: int = 4

# 战场配置 (可扩展性：修改这里即可改变战场大小)
const MAP_COLUMNS: int = 4 # 宽 12 格
const MAP_ROWS: int = 2     # 高 8 格

# 计算战场总像素宽度 (用于战线判定)
const BATTLE_FIELD_WIDTH: float = MAP_COLUMNS * GRID_SIZE
