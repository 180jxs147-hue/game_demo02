class_name RewardPoolDatabase extends Resource

@export var pools: Array[RewardPoolData] = []

func get_pool_by_id(id: String) -> RewardPoolData:
	for p in pools:
		if p and p.pool_id == id:
			return p
	return null

