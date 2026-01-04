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

func _ready():
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

func _setup_type_option(option: OptionButton):
	option.clear()
	option.add_item("全部", UnitTypeFilter.ALL)
	option.add_item("消耗", UnitTypeFilter.CONSUME)
	option.add_item("产出", UnitTypeFilter.PRODUCE)

func _connect_signals():
	resized.connect(_update_columns)
	collected_search.text_changed.connect(func(_t): _refresh_collected())
	all_search.text_changed.connect(func(_t): _refresh_all_units())
	collected_type.item_selected.connect(func(_i): _refresh_collected())
	all_type.item_selected.connect(func(_i): _refresh_all_units())
	tag_list.item_selected.connect(_on_tag_selected)

func _refresh_all():
	_refresh_collected()
	_refresh_all_units()
	_refresh_tags()
	_refresh_synergy_list()

func _refresh_collected():
	var entries = _get_stacked_collected()
	var filtered = _filter_stacked_entries(entries, collected_search.text, collected_type.get_selected_id())
	_fill_grid_stacked(collected_grid, filtered)
	if not filtered.is_empty():
		_show_unit_detail(filtered[0]["data"])
	else:
		_show_unit_detail(null)

func _refresh_all_units():
	var base = _get_all_units()
	var filtered = _filter_units(base, all_search.text, all_type.get_selected_id(), "")
	_fill_grid(all_grid, filtered)
	if not filtered.is_empty():
		_show_unit_detail(filtered[0])
	else:
		_show_unit_detail(null)

func _refresh_tags():
	var tags = _get_all_tags()
	tag_list.clear()
	for t in tags:
		var cn_name = GameConst.TAG_CN_NAMES.get(t, t)
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
	_fill_grid(tags_grid, filtered)
	if _selected_unit and filtered.has(_selected_unit):
		_show_unit_detail(_selected_unit)
	elif not filtered.is_empty():
		_show_unit_detail(filtered[0])
	else:
		_show_unit_detail(null)

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
	out.sort_custom(func(a: UnitData, b: UnitData): return a.name < b.name)
	return out

func _fill_grid(grid: GridContainer, units: Array[UnitData]):
	# 将单位数组渲染为一组卡牌槽位（不堆叠）。
	# 这里会先用 UnitDatabase 将 UnitData 解析回“权威实例”，避免导出后字段缺失/资源引用不一致。
	for child in grid.get_children():
		child.queue_free()
	for u in units:
		u = _resolve_unit_data(u)
		var slot = card_slot_scene.instantiate()
		grid.add_child(slot)
		slot.setup(u)
		slot.pressed.connect(_on_card_pressed)

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
	out.sort_custom(func(a: Dictionary, b: Dictionary):
		var an: String = a["data"].name
		var bn: String = b["data"].name
		return an < bn
	)
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
	for e in entries:
		var u: UnitData = _resolve_unit_data(e["data"])
		var c: int = int(e["count"])
		var slot = card_slot_scene.instantiate()
		grid.add_child(slot)
		if slot.has_method("setup_stacked"):
			slot.setup_stacked(u, c)
		else:
			slot.setup(u)
		slot.pressed.connect(_on_card_pressed)

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
	var viewport_w: float = get_viewport_rect().size.x
	var content_w: float = maxf(320.0, viewport_w - 320.0)
	# 卡牌改为 140宽，加上间距 16 -> 约 156/160
	var cols: int = clampi(int(content_w / 160.0), 2, 8)
	collected_grid.columns = cols
	all_grid.columns = cols
	tags_grid.columns = cols

func _switch_page(page: String):
	collected_page.visible = page == "collected"
	all_page.visible = page == "all"
	tags_page.visible = page == "tags"
	synergy_page.visible = page == "synergy"
	if page == "collected":
		page_header.text = "已收集"
	elif page == "all":
		page_header.text = "全部兵种"
	elif page == "tags":
		page_header.text = "标签"
	elif page == "synergy":
		page_header.text = "羁绊效果"
	else:
		page_header.text = ""

func _on_tag_selected(index: int):
	if index < 0 or index >= tag_list.get_item_count():
		return
	var t = tag_list.get_item_metadata(index)
	if t:
		_current_tag = t
		_refresh_tag_units()

func _on_card_pressed(data: UnitData):
	_selected_unit = _resolve_unit_data(data)
	_show_unit_detail(_selected_unit)

func _get_adjacency_desc(data: UnitData) -> String:
	if not data or not ("adjacency_rules" in data) or data.adjacency_rules.is_empty():
		return ""
	
	var lines: Array[String] = []
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
			var tag_name = GameConst.TAG_CN_NAMES.get(rv, rv)
			req_str = "周围[%s]" % tag_name
		elif rt == "class":
			req_str = "周围[%s]" % rv
		elif rt == "civ":
			req_str = "周围[%s]" % rv
			
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
	tag_lines.append("• 生命值: %s" % data.max_hp)
	tag_lines.append("• 冷却: %s秒" % data.cooldown)
	tag_lines.append("• 民力消耗: %s" % data.manpower_cost)
	tag_lines.append("")

	# 2. 标签/技能
	tag_lines.append("[特性]")
	for t in data.tags:
		var desc = ""
		# 特殊处理：贞德的医者标签
		if data.name == "圣女贞德" and t == "medic":
			desc = "医者(光环)：不再主动治疗，而是通过光环辅助队友。"
		else:
			desc = GameConst.TAG_DESCRIPTIONS.get(t, "")

		if desc == "":
			var cn = GameConst.TAG_CN_NAMES.get(t, t)
			tag_lines.append("• %s" % cn)
		else:
			tag_lines.append("• %s" % desc)
	
	# 3. 邻近加成
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
		{"name": "汉 (Han)", "desc": "2: 全体+2攻\n4: 全体+5攻"},
		{"name": "罗马 (Roman)", "desc": "2: 全体+20血"},
		{"name": "希腊 (Greek)", "desc": "2: 全体+1防\n4: 全体+3防"},
		{"name": "法兰西 (French)", "desc": "2: 全体移速+10%\n4: 全体移速+20%"},
		{"name": "步兵 (Infantry)", "desc": "2: 步兵+10血\n4: 步兵+30血"},
		{"name": "骑兵 (Cavalry)", "desc": "2: 骑兵+2攻\n4: 骑兵+5攻"},
		{"name": "弓手 (Archer)", "desc": "2: 射程+50\n4: 射程+100"}
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
