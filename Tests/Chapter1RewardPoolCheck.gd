extends SceneTree

const CHAPTER_TWO_CARDS := [
	"BlackPrince", "DismountedFrenchKnight", "EnglishBillman",
	"FrenchHandgonner", "Hobilar", "JoanOfArc", "joan",
	"JohnChandos", "LaHire", "Routier", "Ribauldequin", "RoyalCulverin",
]

func _initialize() -> void:
	var reward_db := load("res://Resources/RewardPoolDatabase.tres") as RewardPoolDatabase
	var failures := 0
	for file in DirAccess.get_files_at("res://Resources/Levels"):
		if not file.begins_with("1_") or not file.ends_with(".tres"):
			continue
		var level := load("res://Resources/Levels/" + file) as LevelConfig
		if not level:
			printerr("Missing level: ", file)
			failures += 1
			continue
		var pool: RewardPoolData = reward_db.get_pool_by_id(level.reward_pool_id) if reward_db else null
		if not pool or pool.entries.is_empty():
			printerr("Missing chapter one reward pool: ", file, " -> ", level.reward_pool_id)
			failures += 1
			continue
		var boss_card_found := false
		var high_tier_han_cards := 0
		for entry in pool.entries:
			var unit := entry.get("unit") as UnitData
			if not unit:
				continue
			var card_file := unit.resource_path.get_file().get_basename()
			if level.level_id == "1_1_10":
				if card_file == "zhang_jiao":
					boss_card_found = true
				elif unit.civilization == "dynasty" and unit.rarity == "legendary":
					high_tier_han_cards += 1
			if card_file in CHAPTER_TWO_CARDS:
				printerr("Chapter two card in chapter one pool: ", file, " -> ", card_file)
				failures += 1
		if level.level_id == "1_1_10" and (level.reward_pool_id != "han_boss" or pool.entries.size() != 3 or not boss_card_found or high_tier_han_cards < 2):
			printerr("Invalid Han boss reward choices: ", level.reward_pool_id)
			failures += 1
		print(file, " -> ", level.reward_pool_id, " (", pool.entries.size(), " entries)")
	quit(1 if failures else 0)
