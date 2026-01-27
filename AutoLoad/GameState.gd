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

const USER_LIBRARY_PATH := "user://PlayerLibrary.tres"
const DEFAULT_LIBRARY_PATH := "res://Resources/PlayerLibrary.tres"
const UNIT_DATABASE_PATH := "res://Resources/UnitDatabase.tres"
const LEVEL_DATABASE_PATH := "res://Resources/EnemyLevels.tres"
const SAVE_GAME_PATH := "user://savegame.cfg"
var current_slot: int = 1
func _slot(i: int = -1) -> int:
	var s = current_slot if i < 0 else i
	return clamp(s, 1, 3)
func _save_path(i: int = -1) -> String:
	return "user://savegame_slot_%d.cfg" % _slot(i)
func _library_path(i: int = -1) -> String:
	return "user://PlayerLibrary_slot_%d.tres" % _slot(i)

# --- 恢复逻辑 ---
func recover_all_injured_units():
	var path = _library_path()
	if not FileAccess.file_exists(path):
		return # 没有存档，不做处理
	
	var lib = ResourceLoader.load(path) as CardLibrary
	if not lib:
		return
		
	var changed = false
	for unit in lib.collected_cards:
		if unit and unit.is_injured:
			unit.is_injured = false
			changed = true
			
	if changed:
		ResourceSaver.save(lib, path)
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
	next_level_id_from_camp = level_id
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
	var lib_path := _library_path()
	
	var cache_mode = ResourceLoader.CACHE_MODE_REUSE
	if force_reload:
		cache_mode = ResourceLoader.CACHE_MODE_REPLACE

	if FileAccess.file_exists(lib_path):
		lib = ResourceLoader.load(lib_path, "", cache_mode)
	
	if not lib:
		lib = ResourceLoader.load(DEFAULT_LIBRARY_PATH, "", cache_mode) as CardLibrary
		
	# 如果库是空的（可能是默认库也没配置，或者新档），强制发放初始阵容
	if lib and lib.collected_cards.is_empty():
		_add_initial_roster(lib)
		
	return lib

func save_player_library(library: CardLibrary) -> int:
	# 将卡牌收集进度写入 user://，导出的 EXE 分发给其他用户也不会写到游戏目录。
	if not library:
		return ERR_INVALID_DATA
	return ResourceSaver.save(library, _library_path())

func save_progress() -> int:
	var config = ConfigFile.new()
	config.set_value("progress", "level_index", selected_level_index)
	config.set_value("progress", "current_rows", current_rows)
	config.set_value("progress", "current_cols", current_cols)
	config.set_value("progress", "run_gold", run_gold)
	config.set_value("progress", "run_manpower_bonus", run_manpower_bonus)
	config.set_value("progress", "next_level_id_from_camp", next_level_id_from_camp)
	return config.save(_save_path())

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

func clear_save() -> int:
	# 清空存档：重置关卡索引并清空已收集卡牌，然后回写 user:// 存档文件。
	selected_level_index = 0
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
	# 发放初始阵容：士兵x2，弓箭手x1，长矛手x1
	var starters = [
		"res://Resources/DataFiles/han_caiguan.tres",
		"res://Resources/DataFiles/camp.tres",
	]
	if has_upgrade("start_card_junguo_bing"):
		starters.append("res://Resources/DataFiles/junguo_bing.tres")
	for path in starters:
		if ResourceLoader.exists(path):
			var unit = load(path)
			if unit:
				# 必须复制，否则会修改原始资源，导致新存档继承旧状态
				library.collected_cards.append(unit.duplicate())

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
