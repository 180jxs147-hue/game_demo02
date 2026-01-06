@tool
extends EditorScript

func _run():
	print("--- Checking Resources ---")
	
	var db_path = "res://Resources/EnemyLevels.tres"
	var db = load(db_path)
	if not db:
		print("ERROR: Failed to load ", db_path)
	else:
		print("SUCCESS: Loaded ", db_path)
		print("Levels count: ", db.levels.size())
		for i in range(db.levels.size()):
			var lvl = db.levels[i]
			if not lvl:
				print("ERROR: Level at index ", i, " is null!")
			else:
				print("Level ", i, ": ", lvl.level_id if "level_id" in lvl else "NO_ID", " - ", lvl.resource_path)
				# Check enemy units
				if "enemy_units" in lvl:
					print("  Enemy units: ", lvl.enemy_units.size())
					for j in range(lvl.enemy_units.size()):
						var spawn = lvl.enemy_units[j]
						if not spawn:
							print("  ERROR: Spawn at ", j, " is null!")
						elif not spawn.unit_data:
							print("  ERROR: Spawn at ", j, " has no unit_data!")

	print("--- Check Complete ---")
