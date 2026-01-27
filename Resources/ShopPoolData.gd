class_name ShopPoolData extends Resource

@export var pool_id: String = ""
@export var display_name: String = ""
@export var refresh_cost: int = 1
@export var base_card_cost: int = 3
# entries 结构: { "unit": UnitData, "prob": float, "cost": int (optional), "min_level": int, "tags": Array[String] }
@export var entries: Array[Dictionary] = []
