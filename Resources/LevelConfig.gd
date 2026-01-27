class_name LevelConfig extends Resource

@export var level_id: String = ""
@export var level_name: String = "Level"
@export var grid_width: int = 4
@export var grid_height: int = 4
@export var position_offset: Vector2 = Vector2.ZERO
@export var enemy_units: Array[UnitSpawn] = []
@export var reward_pool_id: String = ""
@export var shop_pool_id: String = ""
@export var allow_camp: bool = true
