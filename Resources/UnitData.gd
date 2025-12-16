class_name UnitData extends Resource

@export_group("基础信息")
@export var name: String = "未命名"
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
