class_name UnitData extends Resource

@export_group("基础信息")
@export var name: String = "未命名"
@export var icon: Texture2D
@export var rarity: String = "common"
@export var civilization: String = "neutral" # 文明：dynasty, rebel, warlord, predator
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
@export var attack_damage: float = 10.0
@export var defense: float = 0.0 # 防御力 (0-3)
@export var attack_range: int = 1 # 射程 (1: 前方无队友; 2: 前方<1队友)
@export var is_injured: bool = false # 是否受伤
@export var charge_count: int = 0 # 冲锋次数：前 X 次攻击造成双倍伤害
@export var fear_count: float = 0.0 # 恐惧强度：降低周围敌军攻击力的数值
@export var plunder_count: float = 0.0 # 掠夺强度：每次攻击掠夺的民力
@export var berserk_count: float = 0.0 # 狂暴强度：生命值越低时的最大额外伤害百分比

@export_group("Adjacency Bonuses")
## Adjacency Rules:
## Each dictionary should look like:
## {
##   "type": "give" | "receive", 
##   "req_type": "tag" | "class" | "civ" | "all",
##   "req_value": "shield" | "warlord" | ... (ignored if "all"),
##   "effect_stat": "attack_damage" | "max_hp" | "cooldown_speed",
##   "effect_value": 5.0
## }
@export var adjacency_rules: Array[Dictionary] = []

@export_group("背景故事")
@export var story: String = ""
