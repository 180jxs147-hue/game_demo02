class_name LevelDatabase extends Resource

@export var levels: Array[LevelConfig] = []

func get_level(index: int) -> LevelConfig:
	if levels.is_empty():
		return null
	return levels[clampi(index, 0, levels.size() - 1)]

func get_level_by_id(id: String) -> LevelConfig:
	for l in levels:
		if "level_id" in l and l.level_id == id:
			return l
	return null

func get_index_by_id(id: String) -> int:
	for i in range(levels.size()):
		var l = levels[i]
		if "level_id" in l and l.level_id == id:
			return i
	return -1
