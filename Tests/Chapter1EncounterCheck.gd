extends SceneTree

const STORY_UNITS := {
	"1_1_2": "马元义", "1_1_4": "波才", "1_1_5": "彭脱",
	"1_1_8": "张梁", "1_1_9": "张宝", "1_1_10": "张角",
	"1_2_3": "黄巾叛首", "1_2_4": "刘备", "1_2_5": "曹操", "1_2_8": "皇甫嵩",
}

func _initialize() -> void:
	var failures := 0
	for route in ["1_0_", "1_1_", "1_2_"]:
		for file in DirAccess.get_files_at("res://Resources/Levels"):
			if not file.begins_with(route) or not file.ends_with(".tres"):
				continue
			var level = load("res://Resources/Levels/" + file) as LevelConfig
			if level == null:
				printerr("Failed to load: ", file)
				failures += 1
				continue
			var occupied := {}
			var net_spend: float = -level.enemy_manpower_regen
			var unit_names := []
			var cols: int = maxi(6, level.grid_width)
			var rows: int = maxi(6, level.grid_height)
			for spawn in level.enemy_units:
				if spawn == null or spawn.unit_data == null:
					printerr("Missing unit: ", file)
					failures += 1
					continue
				net_spend += spawn.unit_data.manpower_cost / maxf(spawn.unit_data.cooldown, 0.1)
				unit_names.append(spawn.unit_data.name)
				for offset in spawn.unit_data.grid_shape:
					var cell: Vector2i = spawn.grid_pos + offset
					if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows or occupied.has(cell):
						printerr("Invalid cell: ", file, " ", spawn.unit_data.name, " ", cell)
						failures += 1
					occupied[cell] = true
			if STORY_UNITS.has(level.level_id):
				var found_story_unit := false
				for unit_name in unit_names:
					if unit_name.begins_with(STORY_UNITS[level.level_id]):
						found_story_unit = true
				if not found_story_unit:
					printerr("Story unit missing: ", file, " ", STORY_UNITS[level.level_id])
					failures += 1
			if route != "1_0_" and net_spend > 2.6:
				printerr("Enemy supply too short: ", file, " ", net_spend)
				failures += 1
			print(file, " | ", level.enemy_units.size(), " units | ", occupied.size(), " cells | regen ", level.enemy_manpower_regen, " | net spend/s ", snappedf(net_spend, 0.01))
	quit(1 if failures else 0)
