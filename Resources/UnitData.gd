class_name UnitData extends Resource

@export_group("基础信息")
@export var name: String = "未命名"
@export var icon: Texture2D
@export var rarity: String = "common"
@export var civilization: String = "neutral" # 文明：han, roman, greek
@export var unit_class: String = "infantry"  # 兵种：infantry, archer, cavalry, shield
@export var color: Color = Color.WHITE
@export var tags: Array[String] = [] 

@export_group("军阵形态")
# 形状定义：(0,0)为锚点
@export var grid_shape: Array[Vector2i] = [Vector2i(0, 0)]

@export_group("战斗数值")
@export var max_hp: float = 100.0
# 修改：改为 float 类型，支持 0.5 或 1.5 这样的消耗
@export var manpower_cost: float = 1.0 
@export var cooldown: float = 2.0
@export var attack_damage: float = 10.0 # <--- 新增：攻击力
@export var is_injured: bool = false # 是否受伤

@export_group("Adjacency Bonuses")
## Adjacency Rules:
## Each dictionary should look like:
## {
##   "type": "give" | "receive", 
##   "req_type": "tag" | "class" | "civ" | "all",
##   "req_value": "shield" | "roman" | ... (ignored if "all"),
##   "effect_stat": "attack_damage" | "max_hp" | "cooldown_speed",
##   "effect_value": 5.0
## }
@export var adjacency_rules: Array[Dictionary] = []

@export_group("背景故事")
@export var story: String = ""
