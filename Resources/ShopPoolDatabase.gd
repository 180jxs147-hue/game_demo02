class_name ShopPoolDatabase extends Resource

@export var pools: Array[ShopPoolData] = []

func get_pool_by_id(id: String) -> ShopPoolData:
	for p in pools:
		if p and p.pool_id == id:
			return p
	return null
