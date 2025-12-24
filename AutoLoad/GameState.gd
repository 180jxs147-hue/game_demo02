extends Node

## 全局运行态与存档入口。
## 约定：
## - res:// 下的资源用于“默认配置/默认卡牌库”（随包分发，不能修改）
## - user:// 下的资源用于“玩家存档”（每台机器/每个系统用户独立，可读写）

var selected_level_index: int = 0
var current_rows: int = 3
var current_cols: int = 3

const USER_LIBRARY_PATH := "user://PlayerLibrary.tres"
const DEFAULT_LIBRARY_PATH := "res://Resources/PlayerLibrary.tres"
const UNIT_DATABASE_PATH := "res://Resources/UnitDatabase.tres"
const LEVEL_DATABASE_PATH := "res://Resources/EnemyLevels.tres"
const SAVE_GAME_PATH := "user://savegame.cfg"

var _cached_unit_database: UnitDatabase
var _cached_level_database: LevelDatabase

func load_player_library() -> CardLibrary:
	# 存档策略：
	# - 优先加载 user:// 下的玩家存档（每台机器/每个用户独立）
	# - 如果第一次运行或存档不存在，则回退到 res:// 的默认库
	var lib: CardLibrary = null
	if FileAccess.file_exists(USER_LIBRARY_PATH):
		lib = load(USER_LIBRARY_PATH)
	
	if not lib:
		lib = load(DEFAULT_LIBRARY_PATH) as CardLibrary
		
	# 如果库是空的（可能是默认库也没配置，或者新档），强制发放初始阵容
	if lib and lib.collected_cards.is_empty():
		_add_initial_roster(lib)
		
	return lib

func save_player_library(library: CardLibrary) -> int:
	# 将卡牌收集进度写入 user://，导出的 EXE 分发给其他用户也不会写到游戏目录。
	if not library:
		return ERR_INVALID_DATA
	return ResourceSaver.save(library, USER_LIBRARY_PATH)

func save_progress():
	var config = ConfigFile.new()
	config.set_value("progress", "level_index", selected_level_index)
	config.set_value("progress", "current_rows", current_rows)
	config.set_value("progress", "current_cols", current_cols)
	config.save(SAVE_GAME_PATH)

func load_progress():
	var config = ConfigFile.new()
	var err = config.load(SAVE_GAME_PATH)
	if err == OK:
		selected_level_index = config.get_value("progress", "level_index", 0)
		current_rows = config.get_value("progress", "current_rows", 4)
		current_cols = config.get_value("progress", "current_cols", 4)
	else:
		selected_level_index = 0
		current_rows = 4
		current_cols = 4

func clear_save() -> int:
	# 清空存档：重置关卡索引并清空已收集卡牌，然后回写 user:// 存档文件。
	selected_level_index = 0
	current_rows = 4
	current_cols = 4
	save_progress() # 清空进度文件
	
	var lib = load_player_library()
	if not lib:
		return ERR_CANT_OPEN
	lib.collected_cards.clear()
	_add_initial_roster(lib) # 发放初始阵容
	return save_player_library(lib)

func _add_initial_roster(library: CardLibrary):
	# 发放初始阵容：士兵x2，弓箭手x1，长矛手x1
	var starters = [
		"res://Resources/DataFiles/soldier.tres",
		"res://Resources/DataFiles/soldier.tres",
		"res://Resources/DataFiles/archer.tres",
		"res://Resources/DataFiles/spear.tres",
		"res://Resources/DataFiles/camp.tres",
		"res://Resources/DataFiles/camp.tres"
	]
	for path in starters:
		if ResourceLoader.exists(path):
			var unit = load(path)
			if unit:
				library.collected_cards.append(unit)

func get_unit_database() -> UnitDatabase:
	# 单位数据库用于：
	# - 提供“全部兵种”的权威列表（显式引用，保证导出打包）
	# - 兜底导出环境下可能缺失的字段（如简介）
	if _cached_unit_database:
		return _cached_unit_database
	var db = load(UNIT_DATABASE_PATH)
	if db is UnitDatabase:
		_cached_unit_database = db
	return _cached_unit_database

func get_level_database() -> LevelDatabase:
	# 关卡配置数据库（敌军配置/HP 等）
	if _cached_level_database:
		return _cached_level_database
	var db = load(LEVEL_DATABASE_PATH)
	if db is LevelDatabase:
		_cached_level_database = db
	return _cached_level_database

func unlock_all_cards():
	var db = get_unit_database()
	var lib = load_player_library()
	if db and lib:
		lib.collected_cards.clear()
		lib.collected_cards.append_array(db.units)
		save_player_library(lib)
