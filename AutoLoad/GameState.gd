extends Node

## 全局运行态与存档入口。
## 约定：
## - res:// 下的资源用于“默认配置/默认卡牌库”（随包分发，不能修改）
## - user:// 下的资源用于“玩家存档”（每台机器/每个系统用户独立，可读写）

var selected_level_index: int = 0
var current_rows: int = 3
var current_cols: int = 2
var slot_select_mode: String = "new"
var skip_intro: bool = false
var use_autosave_library: bool = false

const USER_LIBRARY_PATH := "user://PlayerLibrary.tres"
const DEFAULT_LIBRARY_PATH := "res://Resources/PlayerLibrary.tres"
const UNIT_DATABASE_PATH := "res://Resources/UnitDatabase.tres"
const LEVEL_DATABASE_PATH := "res://Resources/EnemyLevels.tres"
const GAME_CONFIG_PATH := "res://Resources/GameConfig.tres"
const SAVE_GAME_PATH := "user://savegame.cfg"
const AUTO_SAVE_PROGRESS_PATH := "user://autosave_progress.cfg"
const AUTO_LIBRARY_PATH := "user://Autosave_PlayerLibrary.tres"
var current_slot: int = 1

# Caches for price configuration
var _rarity_buy_prices: Dictionary = {}
var _rarity_sell_prices: Dictionary = {}

func _ready():
	_load_price_config()
	load_all()
	# Optional: Apply initial prestige if starting fresh
	var config_res = load(GAME_CONFIG_PATH) as GameConfig
	if config_res and config_res.initial_prestige > 0 and meta_currency == 0:
		meta_currency = config_res.initial_prestige
		save_meta()

func _load_price_config():
	var config_res = load(GAME_CONFIG_PATH) as GameConfig
	if config_res:
		_rarity_buy_prices = config_res.rarity_buy_prices
		_rarity_sell_prices = config_res.rarity_sell_prices
	else:
		# Fallback defaults if config missing
		_rarity_buy_prices = {
			"common": 3, "uncommon": 5, "rare": 8, "epic": 12, "legendary": 20
		}
		_rarity_sell_prices = {
			"common": 1, "uncommon": 2, "rare": 4, "epic": 6, "legendary": 10
		}

func get_card_buy_price(rarity: String) -> int:
	return _rarity_buy_prices.get(rarity.to_lower(), 3)

func get_card_sell_price(rarity: String) -> int:
	return _rarity_sell_prices.get(rarity.to_lower(), 1)

func _slot(i: int = -1) -> int:
	var s = current_slot if i < 0 else i
	return clamp(s, 1, 3)
func _save_path(i: int = -1) -> String:
	return "user://savegame_slot_%d.cfg" % _slot(i)
func _library_path(i: int = -1) -> String:
	return "user://PlayerLibrary_slot_%d.tres" % _slot(i)

# --- 恢复逻辑 ---
func recover_all_injured_units():
	# Use standard load function which handles new/old formats
	var lib = load_player_library()
	if not lib:
		return
		
	var changed = false
	for unit in lib.collected_cards:
		if unit and unit.is_injured:
			unit.is_injured = false
			changed = true
			
	if changed:
		# save_player_library now updates the ConfigFile safely
		save_player_library(lib)
		print("All units recovered and saved.")

# --- UI 样式常量与缓存 ---
const UI_COLOR_BG_DARK = Color("1a1a1d")
const UI_COLOR_BG_PANEL = Color("2d2d30")
const UI_COLOR_ACCENT_GOLD = Color("f0a500")
const UI_COLOR_ACCENT_BLUE = Color("00adb5")
const UI_COLOR_TEXT_PRIMARY = Color("eeeeee")
const UI_COLOR_TEXT_SECONDARY = Color("cf7500")

var _ui_style_cache = {}

func _crop_center_to_aspect(tex: Texture2D, target_aspect: float) -> Texture2D:
	if not tex:
		return null
	if target_aspect <= 0.0:
		return tex
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	if w <= 0.0 or h <= 0.0:
		return tex
	var region_w := w
	var region_h := w / target_aspect
	if region_h > h:
		region_h = h
		region_w = h * target_aspect
	region_w = clampf(region_w, 1.0, w)
	region_h = clampf(region_h, 1.0, h)
	var x := (w - region_w) * 0.5
	var y := (h - region_h) * 0.5
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(x, y, region_w, region_h)
	return atlas

func _make_texture_style(path: String, margins: Vector4, target_aspect: float = 0.0) -> StyleBoxTexture:
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if not tex:
		return null
	tex = _crop_center_to_aspect(tex, target_aspect)
	var s = StyleBoxTexture.new()
	s.texture = tex
	s.content_margin_left = margins.x
	s.content_margin_top = margins.y
	s.content_margin_right = margins.z
	s.content_margin_bottom = margins.w
	return s

func get_ui_style(name: String) -> StyleBox:
	if _ui_style_cache.has(name):
		return _ui_style_cache[name]
		
	var style = null
	match name:
		"panel":
			style = _make_texture_style("res://Assets/UI/panel_bg.png", Vector4(20, 16, 20, 16))
			if not style:
				var f = StyleBoxFlat.new()
				f.bg_color = UI_COLOR_BG_PANEL
				f.corner_radius_top_left = 8
				f.corner_radius_top_right = 8
				f.corner_radius_bottom_left = 8
				f.corner_radius_bottom_right = 8
				f.border_width_left = 2
				f.border_width_top = 2
				f.border_width_right = 2
				f.border_width_bottom = 2
				f.border_color = Color("3e3e42")
				style = f
		"button_normal":
			style = _make_texture_style("res://Assets/UI/button_normal.png", Vector4(12, 8, 12, 8), 3.2)
			if not style:
				var f = StyleBoxFlat.new()
				f.bg_color = Color("393e46")
				f.border_width_bottom = 4
				f.border_color = Color("222831")
				f.set_corner_radius_all(4)
				f.content_margin_left = 12
				f.content_margin_right = 12
				f.content_margin_top = 8
				f.content_margin_bottom = 8
				style = f
		"button_hover":
			style = get_ui_style("button_normal").duplicate()
		"button_pressed":
			style = get_ui_style("button_normal").duplicate()
		"level_card_bg":
			style = _make_texture_style("res://Assets/UI/level_card_bg.png", Vector4(18, 14, 18, 14), 5.5)
			if not style:
				var f = StyleBoxFlat.new()
				f.bg_color = Color("252526")
				f.border_width_left = 1
				f.border_width_top = 1
				f.border_width_right = 1
				f.border_width_bottom = 3
				f.border_color = Color("333333")
				f.set_corner_radius_all(6)
				f.shadow_color = Color(0, 0, 0, 0.3)
				f.shadow_size = 4
				f.shadow_offset = Vector2(0, 2)
				style = f
		"reward_card_bg":
			style = _make_texture_style("res://Assets/UI/reward_card_bg.png", Vector4(12, 12, 12, 12), 0.7)
			if not style:
				var f = get_ui_style("level_card_bg").duplicate()
				style = f
		"card_bg":
			style = get_ui_style("reward_card_bg")
			
	_ui_style_cache[name] = style
	return style

func apply_button_style(btn: Button):
	if not btn: return
	var base_style: StyleBox = get_ui_style("button_normal")
	btn.add_theme_stylebox_override("normal", base_style)
	btn.add_theme_stylebox_override("hover", base_style)
	btn.add_theme_stylebox_override("pressed", base_style)
	btn.add_theme_stylebox_override("focus", base_style)
	btn.add_theme_stylebox_override("disabled", base_style)
	btn.add_theme_color_override("font_color", UI_COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.GRAY)

var _cached_unit_database: UnitDatabase
var _cached_level_database: LevelDatabase
const METASHOP_SAVE_PATH := "user://metashop.cfg"
var meta_currency: int = 0
var purchased_upgrades: Dictionary = {}

# --- Run Currency (军资) ---
# This is valid for the current run only
var run_gold: int = 0
var run_manpower_bonus: int = 0
var next_level_id_from_camp: String = ""
var next_shop_pool_id: String = ""
	
func enter_camp_then_level(level_id: String):
	print("GameState: enter_camp_then_level called with ", level_id)
	next_level_id_from_camp = level_id
	skip_intro = true
	get_tree().paused = false # Safety unpause
	get_tree().change_scene_to_file("res://Scenes/CampShop.tscn")

func set_next_shop_pool(pool_id: String):
	next_shop_pool_id = pool_id

func add_run_gold(amount: int):
	run_gold += amount
	# We might want to save this if we support mid-run saving
	save_progress()

func spend_run_gold(amount: int) -> bool:
	if run_gold >= amount:
		run_gold -= amount
		save_progress()
		return true
	return false

func get_run_gold() -> int:
	return run_gold

func add_run_manpower_bonus(amount: int):
	run_manpower_bonus += amount
	save_progress()

func get_run_manpower_bonus() -> int:
	return run_manpower_bonus

func load_player_library(force_reload: bool = false) -> CardLibrary:
	# 存档策略：
	# - 优先加载 user:// 下的玩家存档（每台机器/每个用户独立）
	# - 如果第一次运行或存档不存在，则回退到 res:// 的默认库
	var lib: CardLibrary = null
	# 注意：现在统一使用 ConfigFile (.cfg) 存储 Library
	var save_path := AUTO_SAVE_PROGRESS_PATH if use_autosave_library else _save_path()
	var legacy_lib_path := AUTO_LIBRARY_PATH if use_autosave_library else _library_path()
	
	# 1. 尝试从 ConfigFile 加载 (新格式)
	var config = ConfigFile.new()
	var err = config.load(save_path)
	if err == OK:
		var data = config.get_value("library", "data", null)
		if data is Dictionary:
			lib = _deserialize_library(data)
			print("GameState: Loaded library from ConfigFile: ", save_path)

	# 2. 如果 ConfigFile 中没有 Library 数据 (可能是旧存档迁移)，尝试加载 .tres (旧格式)
	if not lib and FileAccess.file_exists(legacy_lib_path):
		var cache_mode = ResourceLoader.CACHE_MODE_REUSE
		if force_reload or use_autosave_library:
			cache_mode = ResourceLoader.CACHE_MODE_REPLACE
		lib = ResourceLoader.load(legacy_lib_path, "", cache_mode)
		print("GameState: Loaded library from Legacy .tres: ", legacy_lib_path)
	
	# 3. 尝试回退到默认库
	if not lib:
		# 尝试回退到默认库
		var cache_mode = ResourceLoader.CACHE_MODE_REUSE
		if force_reload:
			cache_mode = ResourceLoader.CACHE_MODE_REPLACE
		lib = ResourceLoader.load(DEFAULT_LIBRARY_PATH, "", cache_mode) as CardLibrary
		print("GameState: Loaded default library")
		
	# 如果库是空的（可能是默认库也没配置，或者新档），强制发放初始阵容
	if lib and lib.collected_cards.is_empty():
		_add_initial_roster(lib)
		
	return lib

func save_player_library(library: CardLibrary) -> int:
	# 将卡牌收集进度写入当前槽位文件（或自动存档）
	if not library:
		return ERR_INVALID_DATA
	var path = AUTO_SAVE_PROGRESS_PATH if use_autosave_library else _save_path()
	
	var config = ConfigFile.new()
	# 尝试加载现有文件以保留其他数据（如进度）
	config.load(path)
	
	var lib_data = _serialize_library(library)
	config.set_value("library", "data", lib_data)
	
	return config.save(path)

func save_autosave_library(library: CardLibrary) -> int:
	# 将卡牌收集进度写入自动存档文件
	if not library:
		return ERR_INVALID_DATA
	var path = AUTO_SAVE_PROGRESS_PATH
	
	var config = ConfigFile.new()
	config.load(path)
	
	var lib_data = _serialize_library(library)
	config.set_value("library", "data", lib_data)
	
	return config.save(path)

func save_progress() -> int:
	var path = AUTO_SAVE_PROGRESS_PATH if use_autosave_library else _save_path()
	var config = ConfigFile.new()
	config.load(path) # 保留 Library 数据
	
	config.set_value("progress", "level_index", selected_level_index)
	config.set_value("progress", "current_rows", current_rows)
	config.set_value("progress", "current_cols", current_cols)
	config.set_value("progress", "run_gold", run_gold)
	config.set_value("progress", "run_manpower_bonus", run_manpower_bonus)
	config.set_value("progress", "next_level_id_from_camp", next_level_id_from_camp)
	
	return config.save(path)

func save_autosave_progress() -> int:
	var path = AUTO_SAVE_PROGRESS_PATH
	var config = ConfigFile.new()
	config.load(path)
	
	config.set_value("progress", "level_index", selected_level_index)
	config.set_value("progress", "current_rows", current_rows)
	config.set_value("progress", "current_cols", current_cols)
	config.set_value("progress", "run_gold", run_gold)
	config.set_value("progress", "run_manpower_bonus", run_manpower_bonus)
	config.set_value("progress", "next_level_id_from_camp", next_level_id_from_camp)
	
	return config.save(path)

# --- Serialization Helpers ---
func _serialize_library(lib: CardLibrary) -> Dictionary:
	var data = { "collected_cards": [] }
	for unit in lib.collected_cards:
		if unit:
			data.collected_cards.append(_serialize_unit(unit))
	return data

func _deserialize_library(data: Dictionary) -> CardLibrary:
	var lib = CardLibrary.new()
	var cards = data.get("collected_cards", [])
	if cards is Array:
		for unit_data in cards:
			if unit_data is Dictionary:
				var unit = _deserialize_unit(unit_data)
				if unit:
					lib.collected_cards.append(unit)
	return lib

func _serialize_unit(unit: UnitData) -> Dictionary:
	var dict = {}
	# 显式保存关键字段，确保版本兼容性
	dict["name"] = unit.name
	dict["max_hp"] = unit.max_hp
	dict["manpower_cost"] = unit.manpower_cost
	dict["cooldown"] = unit.cooldown
	dict["attack_damage"] = unit.attack_damage
	dict["defense"] = unit.defense
	dict["attack_range"] = unit.attack_range
	dict["is_injured"] = unit.is_injured
	dict["charge_count"] = unit.charge_count
	dict["unit_class"] = unit.unit_class
	dict["civilization"] = unit.civilization
	dict["rarity"] = unit.rarity
	dict["tags"] = unit.tags
	dict["grid_shape"] = unit.grid_shape
	dict["adjacency_rules"] = unit.adjacency_rules
	dict["story"] = unit.story
	
	# 保存资源路径以便恢复引用（如 Icon）
	if unit.icon and unit.icon.resource_path != "":
		dict["icon_path"] = unit.icon.resource_path
		
	# 尝试保存原始资源路径（如果是从文件加载的）
	# 注意：Duplicate 的资源没有 path，所以我们可能需要依靠 name 来查找原始资源？
	# 或者我们假设 icon_path 指向了原始文件所在位置附近？
	# 目前只能尽力而为。如果 name 对应文件名，可以恢复。
	
	return dict

func _deserialize_unit(data: Dictionary) -> UnitData:
	var unit = UnitData.new()
	unit.name = data.get("name", "Unknown")
	unit.max_hp = data.get("max_hp", 100.0)
	unit.manpower_cost = data.get("manpower_cost", 1.0)
	unit.cooldown = data.get("cooldown", 2.0)
	unit.attack_damage = data.get("attack_damage", 10.0)
	unit.defense = data.get("defense", 0.0)
	unit.attack_range = data.get("attack_range", 1)
	unit.is_injured = data.get("is_injured", false)
	unit.charge_count = data.get("charge_count", 0)
	unit.unit_class = data.get("unit_class", "infantry")
	unit.civilization = data.get("civilization", "neutral")
	unit.rarity = data.get("rarity", "common")
	unit.tags = data.get("tags", [])
	
	# 恢复 grid_shape (Array[Vector2i] 可能会被存为 Array[String] via ConfigFile?)
	# ConfigFile 支持 Vector2i，所以应该没问题。
	var shape = data.get("grid_shape", [])
	if shape is Array:
		var typed_shape: Array[Vector2i] = []
		for p in shape:
			if p is Vector2i: typed_shape.append(p)
			elif p is Vector2: typed_shape.append(Vector2i(p))
		unit.grid_shape = typed_shape
	
	unit.adjacency_rules = data.get("adjacency_rules", [])
	unit.story = data.get("story", "")
	
	if data.has("icon_path"):
		var path = data["icon_path"]
		if ResourceLoader.exists(path):
			unit.icon = load(path)
			
	return unit

func trigger_autosave() -> int:
	# 触发自动存档：保存进度和卡牌库到自动存档路径
	var rc1 = save_autosave_progress()
	var rc2 = OK
	# 注意：这里我们重新加载当前的库（可能是槽位的，也可能是自动存档的）
	# 然后将其保存到自动存档位置。
	# 为了确保一致性，我们应该保存内存中当前正在使用的状态。
	# 由于 GameState 不持有 library 实例，我们必须 load 一次。
	# 但 load 会根据 use_autosave_library 决定路径。
	# 如果当前在玩槽位1，use_autosave_library=false，load 返回槽位1的库。
	# 我们把这个库保存到 Autosave。这正是自动存档的定义：保存当前游玩状态。
	var lib = load_player_library() 
	if lib:
		rc2 = save_autosave_library(lib)
	
	print("Autosave triggered.")
	return rc1 if rc1 != OK else rc2


func save_meta() -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "currency", meta_currency)
	cfg.set_value("meta", "upgrades", purchased_upgrades)
	return cfg.save(METASHOP_SAVE_PATH)

func load_meta():
	var cfg := ConfigFile.new()
	var err = cfg.load(METASHOP_SAVE_PATH)
	if err == OK:
		meta_currency = int(cfg.get_value("meta", "currency", 0))
		var up = cfg.get_value("meta", "upgrades", {})
		if up is Dictionary:
			purchased_upgrades = up
	else:
		meta_currency = 0
		purchased_upgrades = {}

func save_all() -> int:
	var rc1 = save_progress()
	var rc2 = OK
	var lib = load_player_library()
	if lib:
		rc2 = save_player_library(lib)
	var rc3 = save_meta()
	return rc1 if rc1 != OK else (rc2 if rc2 != OK else rc3)

func load_all():
	# Reset transient flags to prevent state leakage
	next_level_id_from_camp = ""
	skip_intro = false
	
	load_progress()
	load_meta()

func load_progress():
	var config = ConfigFile.new()
	var err = config.load(_save_path())
	if err == OK:
		selected_level_index = config.get_value("progress", "level_index", 0)
		current_rows = config.get_value("progress", "current_rows", 3)
		current_cols = config.get_value("progress", "current_cols", 2)
		run_gold = config.get_value("progress", "run_gold", 0)
		run_manpower_bonus = config.get_value("progress", "run_manpower_bonus", 0)
		next_level_id_from_camp = config.get_value("progress", "next_level_id_from_camp", "")
	else:
		selected_level_index = 0
		current_rows = 3
		current_cols = 2
		run_gold = 0
		run_manpower_bonus = 0
		next_level_id_from_camp = ""

func load_autosave_progress():
	var config = ConfigFile.new()
	var err = config.load(AUTO_SAVE_PROGRESS_PATH)
	if err == OK:
		selected_level_index = config.get_value("progress", "level_index", 0)
		current_rows = config.get_value("progress", "current_rows", 3)
		current_cols = config.get_value("progress", "current_cols", 2)
		run_gold = config.get_value("progress", "run_gold", 0)
		run_manpower_bonus = config.get_value("progress", "run_manpower_bonus", 0)
		next_level_id_from_camp = config.get_value("progress", "next_level_id_from_camp", "")
	else:
		selected_level_index = 0
		current_rows = 3
		current_cols = 2
		run_gold = 0
		run_manpower_bonus = 0
		next_level_id_from_camp = ""

func load_from_slot_and_init_autosave(slot_idx: int):
	# 1. 临时设置环境以读取指定的 Slot 文件
	current_slot = slot_idx
	use_autosave_library = false 
	
	# 2. 读取该槽位的所有数据到内存 (Progress + Library + Meta)
	# load_all() 内部会调用 load_progress() 和 load_player_library()
	# 它们会根据 use_autosave_library=false 读取 _save_path(slot_idx)
	load_all()
	
	print("GameState: Loaded data from Slot ", slot_idx, " into memory.")
	
	# 3. 立即切换到 Autosave 模式
	use_autosave_library = true
	
	# 4. 将内存中的数据写入 Autosave 文件
	# 这样后续的游戏进程将基于 Autosave 文件进行读写，而不会影响原始 Slot 文件
	save_autosave_progress()
	
	# 注意：Library 数据现在也是通过 save_autosave_progress (如果是单文件) 
	# 或者我们需要显式保存 Library？
	# 在新架构下，save_autosave_progress() 只保存 progress 字典。
	# Library 是通过 save_autosave_library 保存的。
	# 为了确保完整性，我们调用 trigger_autosave() 或者手动调用两者。
	# trigger_autosave() 会保存 progress 和 library 到 autosave 路径。
	trigger_autosave()
	
	print("GameState: Initialized Autosave from Slot ", slot_idx)

func save_to_slot(i: int):
	# 显式保存当前状态到指定槽位
	# 这通常是玩家手动点击“保存”时调用
	
	var target_slot = i
	var target_path = _save_path(target_slot)
	
	# 1. 获取当前内存中的 Library (可能是 Autosave 的，也可能是刚加载的)
	# 我们直接从内存获取吗？GameState 不持有 Library 实例。
	# 所以我们必须 load_player_library()。
	# 此时 use_autosave_library 应该是 true (如果我们正在玩游戏)。
	var current_lib = load_player_library()
	
	# 2. 保存到目标槽位文件
	var config = ConfigFile.new()
	# 尝试加载目标文件以保留可能的其他元数据（虽然我们其实是覆盖模式）
	config.load(target_path)
	
	# 写入 Progress
	config.set_value("progress", "level_index", selected_level_index)
	config.set_value("progress", "current_rows", current_rows)
	config.set_value("progress", "current_cols", current_cols)
	config.set_value("progress", "run_gold", run_gold)
	config.set_value("progress", "run_manpower_bonus", run_manpower_bonus)
	config.set_value("progress", "next_level_id_from_camp", next_level_id_from_camp)
	
	# 写入 Library
	if current_lib:
		var lib_data = _serialize_library(current_lib)
		config.set_value("library", "data", lib_data)
		
	var rc = config.save(target_path)
	
	# 3. 保存 Meta (Meta 是全局的，不需要区分槽位，但 save_to_slot 原始逻辑也保存了它)
	save_meta()
	
	print("GameState: Manual Save to Slot ", target_slot, " completed. RC: ", rc)
	return rc


func load_autosave_all():
	use_autosave_library = true
	load_autosave_progress()
	load_meta()

func clear_save() -> int:
	# 清空存档：重置关卡索引并清空已收集卡牌，然后回写 user:// 存档文件。
	selected_level_index = 0
	
	# Load GameConfig for initial values
	var config_res = load(GAME_CONFIG_PATH) as GameConfig
	if config_res:
		current_rows = config_res.initial_grid_rows
		current_cols = config_res.initial_grid_cols
		run_gold = config_res.initial_gold
		run_manpower_bonus = config_res.initial_manpower_bonus
	else:
		current_rows = 3
		current_cols = 2
		run_gold = 0
		run_manpower_bonus = 0
		
	next_level_id_from_camp = ""
	save_progress() # 清空进度文件（当前槽位）
	
	var lib = load_player_library()
	if not lib:
		return ERR_CANT_OPEN
	lib.collected_cards.clear()
	_add_initial_roster(lib) # 发放初始阵容
	return save_player_library(lib)

func add_meta_currency(amount: int):
	meta_currency = max(0, meta_currency + amount)
	save_meta()

func get_meta_currency() -> int:
	return meta_currency

func purchase_upgrade(key: String, cost: int) -> bool:
	if purchased_upgrades.get(key, false):
		return false
	if meta_currency < cost:
		return false
	meta_currency -= cost
	purchased_upgrades[key] = true
	save_meta()
	return true

func has_upgrade(key: String) -> bool:
	return bool(purchased_upgrades.get(key, false))

func get_max_manpower_bonus() -> int:
	var bonus := 0
	if has_upgrade("max_manpower_plus_10"):
		bonus += 10
	return bonus

func get_bench_columns_bonus() -> int:
	return 1 if has_upgrade("bench_columns_plus_1") else 0

func _add_initial_roster(library: CardLibrary):
	# 发放初始阵容
	var config_res = load(GAME_CONFIG_PATH) as GameConfig
	
	if config_res and not config_res.initial_cards.is_empty():
		for card_data in config_res.initial_cards:
			if card_data:
				library.collected_cards.append(card_data.duplicate())
	else:
		# Fallback to hardcoded if config is missing or empty
		var starters = [
			"res://Resources/DataFiles/han_caiguan.tres",
			"res://Resources/DataFiles/camp.tres",
		]
		for path in starters:
			if ResourceLoader.exists(path):
				var unit = load(path)
				if unit:
					library.collected_cards.append(unit.duplicate())

	# Meta upgrades (append extra)
	if has_upgrade("start_card_junguo_bing"):
		var p = "res://Resources/DataFiles/junguo_bing.tres"
		if ResourceLoader.exists(p):
			var u = load(p)
			if u: library.collected_cards.append(u.duplicate())

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
