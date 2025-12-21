class_name GameConst

const GRID_SIZE: int = 64
const GRID_PADDING: int = 4

# 战场配置（修改这里即可改变战场大小）
const MAP_COLUMNS: int = 6
const MAP_ROWS: int = 5

# 计算战场总像素宽度（用于战线判定与布局）
const BATTLE_FIELD_WIDTH: float = MAP_COLUMNS * GRID_SIZE
