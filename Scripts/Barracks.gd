extends Control

## 图鉴/兵种总览界面。
## 页面：
## - 已收集：读取玩家存档库并按同卡堆叠显示
## - 全部兵种：读取 UnitDatabase 的权威列表
## - 标签：对 UnitDatabase 做 tag 过滤
## 右侧详情：
## - 始终用 UnitDatabase 兜底简介，确保导出 EXE 下也能稳定显示

@export var player_library: CardLibrary
@export var unit_database: UnitDatabase
@onready var page_header = $RootLayout/Content/ContentVBox/PageHeader

@onready var collected_page = $RootLayout/Content/ContentVBox/MainArea/Pages/CollectedPage
@onready var collected_search = $RootLayout/Content/ContentVBox/MainArea/Pages/CollectedPage/Toolbar/SearchLineEdit
@onready var collected_type = $RootLayout/Content/ContentVBox/MainArea/Pages/CollectedPage/Toolbar/TypeOptionButton
@onready var collected_grid = $RootLayout/Content/ContentVBox/MainArea/Pages/CollectedPage/ScrollContainer/GridContainer

@onready var all_page = $RootLayout/Content/ContentVBox/MainArea/Pages/AllPage
@onready var all_search = $RootLayout/Content/ContentVBox/MainArea/Pages/AllPage/Toolbar/SearchLineEdit
@onready var all_type = $RootLayout/Content/ContentVBox/MainArea/Pages/AllPage/Toolbar/TypeOptionButton
@onready var all_grid = $RootLayout/Content/ContentVBox/MainArea/Pages/AllPage/ScrollContainer/GridContainer

@onready var tags_page = $RootLayout/Content/ContentVBox/MainArea/Pages/TagsPage
@onready var tag_list = $RootLayout/Content/ContentVBox/MainArea/Pages/TagsPage/TagList
@onready var tags_grid = $RootLayout/Content/ContentVBox/MainArea/Pages/TagsPage/CardList/ScrollContainer/GridContainer

@onready var synergy_page = $RootLayout/Content/ContentVBox/MainArea/Pages/SynergyPage
@onready var synergy_list = $RootLayout/Content/ContentVBox/MainArea/Pages/SynergyPage/SynergyList
@onready var synergy_desc = $RootLayout/Content/ContentVBox/MainArea/Pages/SynergyPage/SynergyDesc

@onready var detail_name = $RootLayout/Content/ContentVBox/MainArea/Detail/DetailVBox/NameLabel
@onready var detail_count = $RootLayout/Content/ContentVBox/MainArea/Detail/DetailVBox/CountLabel
@onready var detail_shape = $RootLayout/Content/ContentVBox/MainArea/Detail/DetailVBox/ShapePreview
@onready var detail_tags = $RootLayout/Content/ContentVBox/MainArea/Detail/DetailVBox/TagsLabel
@onready var detail_story = $RootLayout/Content/ContentVBox/MainArea/Detail/DetailVBox/StoryLabel

var card_slot_scene = preload("res://Scenes/CardSlot.tscn")
var _all_units_cache: Array[UnitData] = []
var _tags_cache: Array[String] = []
var _current_tag: String = ""
enum UnitTypeFilter { ALL, CONSUME, PRODUCE }
var _selected_unit: UnitData

var _card_base_width: float = 280.0
var _card_base_height: float = 400.0
var _card_min_width: float = 220.0
var _target_columns: int = 4
var _current_card_width: float = 280.0
var _current_card_scale: float = 1.0


# Sorting
var sort_option_collected: OptionButton
var sort_option_all: OptionButton

func _ready():
	preload("res://Scripts/WarMenuSkin.gd").apply.call_deferred(self)
	# 图鉴数据有两部分来源：
	# 1) 玩家存档库：决定“已收集”页显示哪些卡、各卡数量（user://PlayerLibrary.tres）
	# 2) 单位数据库：决定“全部兵种/标签页”有哪些卡，以及用于补全导出时可能丢失的字段（例如简介）
	if GameState and GameState.has_method("load_player_library"):
		var loaded = GameState.load_player_library()
		if loaded:
			player_library = loaded
	
	# 单位数据库必须用“显式引用资源”的方式（UnitDatabase.tres 引用所有 UnitData），
	# 否则导出 EXE 后可能因资源未被打包而加载不全。
	if not unit_database:
		if GameState and GameState.has_method("get_unit_database"):
			unit_database = GameState.get_unit_database()
		if not unit_database:
			var loaded_db = load("res://Resources/UnitDatabase.tres")
			if loaded_db is UnitDatabase:
				unit_database = loaded_db
	_setup_filters()
	_switch_page("collected")
	_connect_signals()
	_refresh_all()
	_update_columns()
	_show_unit_detail(null)

func _setup_sort_option(parent: Node) -> OptionButton:
	var opt = OptionButton.new()
	opt.add_item("名称 (A-Z)", 0)
	opt.add_item("稀有度 (高到低)", 1)
	opt.add_item("费用 (高到低)", 2)
	opt.add_item("费用 (低到高)", 3)
	parent.add_child(opt)
	# 调整顺序：放在 TypeOptionButton 后面
	parent.move_child(opt, parent.get_child_count() - 1)
	return opt

func _get_rarity_score(r: String) -> int:
	match r:
		"legendary": return 5
		"epic": return 4
		"rare": return 3
		"uncommon": return 2
		_: return 1

func _sort_list(list: Array, sort_mode: int):
	list.sort_custom(func(a, b):
		var da = a if a is UnitData else a["data"]
		var db = b if b is UnitData else b["data"]
		
		match sort_mode:
			1: # Rarity Desc
				var ra = _get_rarity_score(da.rarity)
				var rb = _get_rarity_score(db.rarity)
				if ra != rb: return ra > rb
				return da.name < db.name
			2: # Cost Desc
				if da.manpower_cost != db.manpower_cost: return da.manpower_cost > db.manpower_cost
				return da.name < db.name
			3: # Cost Asc
				if da.manpower_cost != db.manpower_cost: return da.manpower_cost < db.manpower_cost
				return da.name < db.name
			_: # Name
				return da.name < db.name
	)

func _resolve_unit_data(data: UnitData) -> UnitData:
	if not data:
		return null
	if unit_database and unit_database.has_method("resolve_unit"):
		return unit_database.resolve_unit(data)
	return data

func _get_story_text(data: UnitData) -> String:
	if not data:
		return ""
	# 导出后如果 UnitData 的某些字段（例如 story）加载为空，这里会走 UnitDatabase 的兜底表。
	if unit_database and unit_database.has_method("get_story_for"):
		return unit_database.get_story_for(data)
	return data.story

func _setup_filters():
	_setup_type_option(collected_type)
	_setup_type_option(all_type)
	
	if collected_type:
		sort_option_collected = _setup_sort_option(collected_type.get_parent())
	if all_type:
		sort_option_all = _setup_sort_option(all_type.get_parent())

func _setup_type_option(option: OptionButton):
	option.clear()
	option.add_item("全部", UnitTypeFilter.ALL)
	option.add_item("消耗", UnitTypeFilter.CONSUME)
	option.add_item("产出", UnitTypeFilter.PRODUCE)

func _connect_signals():
	resized.connect(_update_columns)
	for grid in [collected_grid, all_grid, tags_grid]:
		grid.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		grid.get_parent().resized.connect(_update_columns)
	collected_search.text_changed.connect(func(_t): _refresh_collected())
	all_search.text_changed.connect(func(_t): _refresh_all_units())
	collected_type.item_selected.connect(func(_i): _refresh_collected())
	all_type.item_selected.connect(func(_i): _refresh_all_units())
	
	if sort_option_collected:
		sort_option_collected.item_selected.connect(func(_i): _refresh_collected())
	if sort_option_all:
		sort_option_all.item_selected.connect(func(_i): _refresh_all_units())
		
	tag_list.item_selected.connect(_on_tag_selected)

func _refresh_all():
	_refresh_collected()
	_refresh_all_units()
	_refresh_tags()
	_refresh_synergy_list()

func _refresh_collected():
	var entries = _get_stacked_collected()
	var filtered = _filter_stacked_entries(entries, collected_search.text, collected_type.get_selected_id())
	
	if sort_option_collected:
		_sort_list(filtered, sort_option_collected.get_selected_id())
	else:
		_sort_list(filtered, 0)
		
	_fill_grid_stacked(collected_grid, filtered)
	if not filtered.is_empty():
		_show_unit_detail(filtered[0]["data"])
	else:
		_show_unit_detail(null)

func _refresh_all_units():
	var base = _get_all_units()
	var filtered = _filter_units(base, all_search.text, all_type.get_selected_id(), "")
	
	if sort_option_all:
		_sort_list(filtered, sort_option_all.get_selected_id())
	else:
		_sort_list(filtered, 0)
		
	_fill_grid(all_grid, filtered)
	if not filtered.is_empty():
		_show_unit_detail(filtered[0])
	else:
		_show_unit_detail(null)

func _refresh_tags():
	var tags = _get_all_tags()
	tag_list.clear()
	for t in tags:
		var cn_name = TagManager.get_tag_name(t)
		tag_list.add_item(cn_name)
		# 将原始 tag key 存入 metadata
		tag_list.set_item_metadata(tag_list.get_item_count() - 1, t)
		
	if tags.is_empty():
		_current_tag = ""
		_fill_grid(tags_grid, [])
		return
	if _current_tag.is_empty():
		_current_tag = tags[0]
	
	# 选中当前 tag 对应的项
	var idx = -1
	for i in range(tag_list.get_item_count()):
		if tag_list.get_item_metadata(i) == _current_tag:
			idx = i
			break
			
	if idx < 0:
		idx = 0
		if not tags.is_empty():
			_current_tag = tags[0]
			
	if tag_list.get_item_count() > 0:
		tag_list.select(idx)
		
	_refresh_tag_units()

func _refresh_tag_units():
	if _current_tag.is_empty():
		_fill_grid(tags_grid, [])
		_show_unit_detail(null)
		return
	var base = _get_all_units()
	var filtered = _filter_units(base, "", UnitTypeFilter.ALL, _current_tag)
	
	# Default sort by name for tags page
	_sort_list(filtered, 0)
	
	_fill_grid(tags_grid, filtered)
	if _selected_unit and filtered.has(_selected_unit):
		_show_unit_detail(_selected_unit)
	else:
		_show_tag_detail(_current_tag)

func _filter_units(units: Array[UnitData], query: String, type_filter_id: int, tag: String) -> Array[UnitData]:
	var q = query.strip_edges().to_lower()
	var out: Array[UnitData] = []
	for u in units:
		if not u:
			continue
		if not q.is_empty() and u.name.to_lower().find(q) == -1:
			continue
		if tag != "" and (not u.tags.has(tag)):
			continue
		if type_filter_id == UnitTypeFilter.CONSUME and u.manpower_cost <= 0:
			continue
		if type_filter_id == UnitTypeFilter.PRODUCE and u.manpower_cost >= 0:
			continue
		out.append(u)
	return out

func _fill_grid(grid: GridContainer, units: Array[UnitData]):
	# 将单位数组渲染为一组卡牌槽位（不堆叠）。
	# 这里会先用 UnitDatabase 将 UnitData 解析回“权威实例”，避免导出后字段缺失/资源引用不一致。
	for child in grid.get_children():
		child.queue_free()
	var target_w := _current_card_width
	var target_h := _card_base_height * _current_card_scale
	for u in units:
		u = _resolve_unit_data(u)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(target_w, target_h)
		grid.add_child(wrapper)
		
		var slot = card_slot_scene.instantiate()
		slot.scale = Vector2(_current_card_scale, _current_card_scale)
		var card_w := _card_base_width * _current_card_scale
		var card_h := _card_base_height * _current_card_scale
		slot.position = Vector2((target_w - card_w) * 0.5, (target_h - card_h) * 0.5)
		wrapper.add_child(slot)
		
		slot.setup(u)
		slot.pressed.connect(_on_card_pressed)
	_update_columns.call_deferred()

func _get_stacked_collected() -> Array[Dictionary]:
	# “已收集”页需要把同名/同资源的卡牌堆叠显示（xN），所以先按 key 聚合计数。
	# key 优先用 resource_path（导出更稳定），否则退回 name。
	var counts: Dictionary = {}
	var rep: Dictionary = {}
	if player_library:
		for d in player_library.collected_cards:
			if not (d is UnitData):
				continue
			var k = _unit_key(d)
			counts[k] = int(counts.get(k, 0)) + 1
			if not rep.has(k):
				rep[k] = d
	var out: Array[Dictionary] = []
	for k in counts.keys():
		out.append({"key": k, "data": rep[k], "count": counts[k]})
	return out

func _filter_stacked_entries(entries: Array[Dictionary], query: String, type_filter_id: int) -> Array[Dictionary]:
	var q = query.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for e in entries:
		var u: UnitData = e["data"]
		if not u:
			continue
		if not q.is_empty() and u.name.to_lower().find(q) == -1:
			continue
		if type_filter_id == UnitTypeFilter.CONSUME and u.manpower_cost <= 0:
			continue
		if type_filter_id == UnitTypeFilter.PRODUCE and u.manpower_cost >= 0:
			continue
		out.append(e)
	return out

func _fill_grid_stacked(grid: GridContainer, entries: Array[Dictionary]):
	# 渲染“已收集”页的堆叠卡牌（slot.setup_stacked 会显示 xN）。
	for child in grid.get_children():
		child.queue_free()
	var target_w := _current_card_width
	var target_h := _card_base_height * _current_card_scale
	for e in entries:
		var u: UnitData = _resolve_unit_data(e["data"])
		var c: int = int(e["count"])
		
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(target_w, target_h)
		grid.add_child(wrapper)
		
		var slot = card_slot_scene.instantiate()
		slot.scale = Vector2(_current_card_scale, _current_card_scale)
		var card_w := _card_base_width * _current_card_scale
		var card_h := _card_base_height * _current_card_scale
		slot.position = Vector2((target_w - card_w) * 0.5, (target_h - card_h) * 0.5)
		wrapper.add_child(slot)
		
		if slot.has_method("setup_stacked"):
			slot.setup_stacked(u, c)
		else:
			slot.setup(u)
		slot.pressed.connect(_on_card_pressed)
	_update_columns.call_deferred()

func _get_all_units() -> Array[UnitData]:
	# “全部兵种/标签”页的候选单位列表。
	# 正常情况下应来自 UnitDatabase（导出时保证资源被打包）。
	if not _all_units_cache.is_empty():
		return _all_units_cache
	var result: Array[UnitData] = []
	if unit_database:
		for u in unit_database.get_units():
			if u:
				result.append(u)
		_all_units_cache = result
		return _all_units_cache
	_all_units_cache = result
	return _all_units_cache

func _get_all_tags() -> Array[String]:
	if not _tags_cache.is_empty():
		return _tags_cache
	var set: Dictionary = {}
	for u in _get_all_units():
		for t in u.tags:
			set[t] = true
	var tags: Array[String] = []
	for k in set.keys():
		tags.append(str(k))
	tags.sort()
	_tags_cache = tags
	return _tags_cache

func _update_columns():
	# Measure the scroll area rather than subtracting guessed sidebar widths.
	for grid in [collected_grid, all_grid, tags_grid]:
		var available: float = maxf(220.0, grid.get_parent().size.x - 12.0)
		var gap: float = float(grid.get_theme_constant("h_separation"))
		var cols := clampi(int((available + gap) / (_card_min_width + gap)), 1, _target_columns)
		var width := minf(_card_base_width, floorf((available - gap * (cols - 1)) / cols))
		var card_scale := width / _card_base_width
		grid.columns = cols
		if grid == collected_grid:
			_current_card_width = width
			_current_card_scale = card_scale
		for wrapper in grid.get_children():
			if wrapper.is_queued_for_deletion(): continue
			wrapper.custom_minimum_size = Vector2(width, _card_base_height * card_scale)
			if wrapper.get_child_count() > 0:
				var slot: Control = wrapper.get_child(0)
				slot.scale = Vector2(card_scale, card_scale)
				slot.position = Vector2.ZERO

func _switch_page(page: String):
	var nav := {"CollectedButton": "collected", "AllUnitsButton": "all", "TagsButton": "tags", "SynergyButton": "synergy"}
	for button_name in nav:
		var button: Button = $RootLayout/Sidebar/SidebarVBox.get_node(button_name)
		button.theme_type_variation = "CommandButton" if page == nav[button_name] else ""
	_update_columns.call_deferred()
	collected_page.visible = page == "collected"
	all_page.visible = page == "all"
	tags_page.visible = page == "tags"
	synergy_page.visible = page == "synergy"
	if page == "collected":
		page_header.text = "已收集"
		if sort_option_collected: sort_option_collected.show()
		if sort_option_all: sort_option_all.hide()
	elif page == "all":
		page_header.text = "全部卡牌"
		if sort_option_all: sort_option_all.show()
		if sort_option_collected: sort_option_collected.hide()
	elif page == "tags":
		page_header.text = "标签分类"
		if sort_option_all: sort_option_all.hide()
		if sort_option_collected: sort_option_collected.hide()
	elif page == "synergy":
		page_header.text = "羁绊效果"
		if sort_option_all: sort_option_all.hide()
		if sort_option_collected: sort_option_collected.hide()
	else:
		page_header.text = ""
		if sort_option_collected: sort_option_collected.hide()
		if sort_option_all: sort_option_all.hide()

func _on_tag_selected(index: int):
	if index < 0 or index >= tag_list.get_item_count():
		return
	var t = tag_list.get_item_metadata(index)
	if t:
		_current_tag = t
		_selected_unit = null
		_refresh_tag_units()

func _on_card_pressed(data: UnitData):
	_selected_unit = _resolve_unit_data(data)
	_show_unit_detail(_selected_unit)

func _get_adjacency_desc(data: UnitData) -> String:
	if not data or not ("adjacency_rules" in data) or data.adjacency_rules.is_empty():
		return ""
	
	var lines: Array[String] = []
	
	var civ_map = {
		"han": "汉", "roman": "罗马", "greek": "希腊", "neutral": "中立", "french": "法兰西", "huangjin": "黄巾",
		"dynasty": "王朝", "warlord": "诸侯", "rebel": "义军", "predator": "虎狼"
	}
	var cls_map = {"infantry": "步兵", "archer": "弓兵", "cavalry": "骑兵", "shield": "盾兵", "support": "辅助", "building": "建筑", "spear": "长柄", "civilian": "平民", "siege": "攻城", "equipment": "装备"}

	for rule in data.adjacency_rules:
		# 解析类型
		var type_str = ""
		if rule.get("type") == "give":
			type_str = "给予"
		elif rule.get("type") == "receive":
			type_str = "自身获得"
		else:
			continue
			
		# 解析条件
		var req_str = ""
		var rt = rule.get("req_type", "all")
		var rv = rule.get("req_value", "")
		
		if rt == "all":
			req_str = "周围所有友军"
		elif rt == "tag":
			# 尝试翻译 tag
			var tag_name = TagManager.get_tag_name(rv)
			req_str = "周围[%s]" % tag_name
		elif rt == "class":
			var c_name = cls_map.get(rv, rv)
			req_str = "周围[%s]" % c_name
		elif rt == "civ":
			var c_name = civ_map.get(rv, rv)
			req_str = "周围[%s]" % c_name
			
		# 解析效果
		var stat_str = ""
		var es = rule.get("effect_stat", "")
		if es == "max_hp":
			stat_str = "生命上限"
		elif es == "attack_damage":
			stat_str = "攻击力"
		elif es == "cooldown_speed":
			stat_str = "冷却速度"
		else:
			stat_str = es
			
		var val = rule.get("effect_value", 0)
		var val_str = "+%s" % val if val >= 0 else "%s" % val
		
		# 组合句子: "给予 周围所有友军 生命上限 +10"
		# 或者 "自身获得 周围[步兵] 攻击力 +5" (这个逻辑稍微有点不同，receive通常是每有一个加多少)
		
		if rule.get("type") == "give":
			lines.append("• %s %s %s %s" % [type_str, req_str, stat_str, val_str])
		elif rule.get("type") == "receive":
			lines.append("• %s: 每个%s 提供 %s %s" % [type_str, req_str, stat_str, val_str])
			
	return "\n".join(lines)

func _show_unit_detail(data: UnitData):
	# 右侧详情面板渲染入口。
	# 这里会统一解析 UnitData 与 story，保证 Debug/导出两种环境显示一致。
	data = _resolve_unit_data(data)
	if not data:
		detail_name.text = "未选择"
		detail_count.text = ""
		detail_tags.text = ""
		detail_story.text = ""
		if detail_shape and detail_shape.has_method("set_unit_data"):
			detail_shape.set_unit_data(null)
		return
	
	detail_name.text = data.name
	var count := _get_collected_count(data)
	detail_count.text = "拥有：%d" % count if count > 0 else "未收集"
	if detail_shape and detail_shape.has_method("set_unit_data"):
		detail_shape.set_unit_data(data)
	
	var tag_lines: Array[String] = []
	
	# 1. 基础属性
	tag_lines.append("[基础属性]")
	tag_lines.append("• 攻击力: %s" % data.attack_damage)
	if "defense" in data and data.defense > 0:
		tag_lines.append("• 防御力: %s" % data.defense)
	
	tag_lines.append("• 生命值: %s" % data.max_hp)
	tag_lines.append("• 冷却: %s秒" % data.cooldown)
	tag_lines.append("• 民力消耗: %s" % data.manpower_cost)
	
	if "attack_range" in data:
		var r_desc = ""
		if data.attack_range == 1: r_desc = "近战 (前方无友军)"
		elif data.attack_range == 2: r_desc = "中距 (前方<1友军)"
		elif data.attack_range >= 3: r_desc = "远距 (前方<%d友军)" % (data.attack_range - 1)
		tag_lines.append("• 射程: %d - %s" % [data.attack_range, r_desc])
	
	tag_lines.append("")

	# 2. 标签/技能
	tag_lines.append("[特性]")
	for t in data.tags:
		# 阵营/阵营羁绊标志不在这里重复展开说明
		if t in ["dynasty", "rebel", "warlord", "predator", "french", "han", "roman", "greek", "huangjin"]:
			continue
		var t_name = TagManager.get_tag_name(t)
		var t_desc = TagManager.get_tag_description(t)
		
		# 特殊处理：圣女贞德的医者标签
		if data.name == "圣女贞德" and t == "medic":
			t_desc = "不再主动治疗，而是通过光环辅助队友。"
		
		# Format description if it has placeholders (like charge / fear / plunder / berserk)
		if t == "charge" and "charge_count" in data:
			if "%d" in t_desc:
				t_desc = t_desc % data.charge_count
			elif "{X}" in t_desc:
				t_desc = t_desc.replace("{X}", str(data.charge_count))
		elif t == "fear" and "fear_count" in data:
			if "%d" in t_desc:
				t_desc = t_desc % int(data.fear_count)
			elif "{X}" in t_desc:
				t_desc = t_desc.replace("{X}", str(data.fear_count))
		elif t == "plunder" and "plunder_count" in data:
			if "%d" in t_desc:
				t_desc = t_desc % int(data.plunder_count)
			elif "{X}" in t_desc:
				t_desc = t_desc.replace("{X}", str(data.plunder_count))
		elif t == "berserk" and "berserk_count" in data:
			if "%d" in t_desc:
				t_desc = t_desc % int(data.berserk_count)
			elif "{X}" in t_desc:
				t_desc = t_desc.replace("{X}", str(data.berserk_count))
		
		if t_desc != "":
			tag_lines.append("• %s：%s" % [t_name, t_desc])
		else:
			tag_lines.append("• %s" % t_name)

	
	# 4. 邻近加成
	var adj_text = _get_adjacency_desc(data)
	if not adj_text.is_empty():
		tag_lines.append("")
		tag_lines.append("[阵型羁绊]") # 或者叫 "邻近加成"
		tag_lines.append(adj_text)

	var tags_text := "\n".join(tag_lines)
	if detail_tags is RichTextLabel:
		# RichTextLabel 用 clear/append_text 更新更稳定，避免某些导出环境刷新异常。
		detail_tags.clear()
		detail_tags.append_text(tags_text)
	else:
		detail_tags.text = tags_text
	var story_text: String = _get_story_text(data)
	if story_text.strip_edges().is_empty():
		story_text = "（暂无简介）"
	if detail_story is RichTextLabel:
		detail_story.clear()
		detail_story.append_text(story_text)
	else:
		detail_story.text = story_text

func _show_tag_detail(tag_id: String):
	# 标签分类页面下，右侧默认展示标签本身的效果说明。
	var t_name := tag_id
	var t_desc := ""
	if TagManager:
		t_name = TagManager.get_tag_name(tag_id)
		t_desc = TagManager.get_tag_description(tag_id)
	if t_desc == "" and GameConst.TAG_DESCRIPTIONS.has(tag_id):
		t_desc = GameConst.TAG_DESCRIPTIONS[tag_id]
	# 冲锋标签在标签界面中使用“前N次攻击造成双倍伤害”的描述
	if tag_id == "charge":
		t_desc = "前N次攻击造成双倍伤害。"
	
	detail_name.text = t_name
	detail_count.text = "标签效果"
	if detail_shape and detail_shape.has_method("set_unit_data"):
		detail_shape.set_unit_data(null)
	
	var lines: Array[String] = []
	lines.append("[标签效果]")
	if not t_desc.is_empty():
		lines.append("• %s" % t_desc)
	else:
		lines.append("• 暂无描述")
	
	var tags_text := "\n".join(lines)
	if detail_tags is RichTextLabel:
		detail_tags.clear()
		detail_tags.append_text(tags_text)
	else:
		detail_tags.text = tags_text
	
	# 右侧下方区域简单列出若干典型单位名称，帮助玩家理解标签归属
	var story_text := ""
	var units := _filter_units(_get_all_units(), "", UnitTypeFilter.ALL, tag_id)
	if not units.is_empty():
		var names: Array[String] = []
		for i in range(min(6, units.size())):
			names.append(units[i].name)
		story_text = "典型单位：\n" + ", ".join(names)
	
	if detail_story is RichTextLabel:
		detail_story.clear()
		detail_story.append_text(story_text)
	else:
		detail_story.text = story_text

func _get_collected_count(data: UnitData) -> int:
	if not player_library:
		return 0
	var key = _unit_key(data)
	var c := 0
	for d in player_library.collected_cards:
		if d is UnitData and _unit_key(d) == key:
			c += 1
	return c

func _unit_key(data: UnitData) -> String:
	# 用于“堆叠统计/拥有数量”的稳定 key。
	# resource_path 在导出后更可靠；如果对象来自内存/临时创建，可能为空，则用 name 回退。
	if not data:
		return ""
	if not data.resource_path.is_empty():
		return data.resource_path
	return data.name

func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_collected_button_pressed():
	_switch_page("collected")
	_refresh_collected()

func _on_all_units_button_pressed():
	_switch_page("all")
	_refresh_all_units()

func _on_tags_button_pressed():
	_switch_page("tags")
	_refresh_tags()

func _on_synergy_button_pressed():
	_switch_page("synergy")
	_refresh_synergy_list()

func _refresh_synergy_list():
	if not synergy_list:
		return
	synergy_list.clear()
	# 这里硬编码一些羁绊数据用于展示
	# 实际项目中建议从 BattleManager 或单独的配置表读取
	var synergies = [
		{"name": "王朝 (Dynasty)", "desc": "2: 全体+2攻\n4: 全体+5攻"},
		{"name": "诸侯 (Warlord)", "desc": "2: 全体+20血\n4: 全体+50血"},
		{"name": "义军 (Rebel)", "desc": "2: 全体-0.2s CD\n4: 全体-0.5s CD"},
		{"name": "虎狼 (Predator)", "desc": "2: 全体+3攻\n4: 全体+8攻"},
		{"name": "步兵 (Infantry)", "desc": "2: 步兵+10血\n4: 步兵+30血"},
		{"name": "骑兵 (Cavalry)", "desc": "2: 骑兵+2攻+5血"},
		{"name": "弓手 (Archer)", "desc": "2: 弓兵+2攻"},
		{"name": "盾兵 (Shield)", "desc": "2: 盾兵+20血"},
		{"name": "辅助 (Support)", "desc": "2: 辅助+10血"}
	]
	
	for s in synergies:
		synergy_list.add_item(s.name)
		# 将描述存储在 item metadata 中，方便点击时获取
		synergy_list.set_item_metadata(synergy_list.get_item_count() - 1, s.desc)
	
	# 如果有列表项，默认选中第一个
	if synergy_list.get_item_count() > 0:
		synergy_list.select(0)
		_on_synergy_selected(0)
	
	# 确保信号连接（如果在 _ready 中未连接）
	if not synergy_list.item_selected.is_connected(_on_synergy_selected):
		synergy_list.item_selected.connect(_on_synergy_selected)

func _on_synergy_selected(index: int):
	if not synergy_desc:
		return
	var desc = synergy_list.get_item_metadata(index)
	synergy_desc.text = str(desc)
