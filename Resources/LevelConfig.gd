class_name LevelConfig extends Resource

@export var level_id: String = ""
@export var level_name: String = "Level"
@export var grid_width: int = 4
@export var grid_height: int = 4
@export var position_offset: Vector2 = Vector2.ZERO ## 手动调整该关卡敌阵的位置偏移 (相对于标准右上角基准)
@export var enemy_units: Array[UnitSpawn] = []
