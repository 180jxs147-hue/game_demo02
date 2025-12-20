class_name LevelDatabase extends Resource

@export var levels: Array[LevelConfig] = []

func get_level(index: int) -> LevelConfig:
	if levels.is_empty():
		return null
	return levels[clampi(index, 0, levels.size() - 1)]
