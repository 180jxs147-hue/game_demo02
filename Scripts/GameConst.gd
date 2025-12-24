class_name GameConst

const GRID_SIZE: int = 64
const GRID_PADDING: int = 4

# 战场配置（修改这里即可改变战场大小）
const MAP_COLUMNS: int = 4
const MAP_ROWS: int = 4

# 计算战场总像素宽度（用于战线判定与布局）
const BATTLE_FIELD_WIDTH: float = MAP_COLUMNS * GRID_SIZE

# 技能词条说明
const TAG_DESCRIPTIONS = {
	"sacrifice": "牺牲：队友阵亡时，冷却减少 30%（最低 0.2s）。",
	"medic": "医者：不进行攻击，而是治疗受伤最重的友军。",
	"last_stand": "亡语：阵亡时对随机敌人造成 300% 伤害。",
	"sniper": "狙击：距离越远伤害越高（每格约 +6%）。"
}

# 技能标签中文名映射
const TAG_CN_NAMES = {
	"sacrifice": "牺牲",
	"medic": "医者",
	"last_stand": "亡语",
	"sniper": "狙击"
}
