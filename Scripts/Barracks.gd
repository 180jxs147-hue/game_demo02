extends Control

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
var _tag_desc: Dictionary = {
	"sacrifice": "牺牲：以自身为代价换取更强的战果。"
}
var _selected_unit: UnitData
var _unit_lookup_by_path: Dictionary = {}
var _unit_lookup_by_name: Dictionary = {}
var _story_cache_by_path: Dictionary = {}
var _logged_story_issue_by_path: Dictionary = {}

func _ready():
	if GameState and GameState.has_method("load_player_library"):
		var loaded = GameState.load_player_library()
		if loaded:
			player_library = loaded
	if not unit_database:
		var loaded_db = load("res://Resources/UnitDatabase.tres")
		if loaded_db is UnitDatabase:
			unit_database = loaded_db
	_build_unit_lookups()
	_setup_filters()
	_switch_page("collected")
	_connect_signals()
	_refresh_all()
	_update_columns()
	_show_unit_detail(null)

func _build_unit_lookups():
	_unit_lookup_by_path.clear()
	_unit_lookup_by_name.clear()
	_story_cache_by_path.clear()
	if not unit_database:
		return
	for u in unit_database.get_units():
		if not u:
			continue
		if not u.resource_path.is_empty():
			_unit_lookup_by_path[u.resource_path] = u
		if not u.name.is_empty() and not _unit_lookup_by_name.has(u.name):
			_unit_lookup_by_name[u.name] = u

func _resolve_unit_data(data: UnitData) -> UnitData:
	if not data:
		return null
	if not data.resource_path.is_empty() and _unit_lookup_by_path.has(data.resource_path):
		return _unit_lookup_by_path[data.resource_path]
	if not data.name.is_empty() and _unit_lookup_by_name.has(data.name):
		return _unit_lookup_by_name[data.name]
	return data

func _get_story_text(data: UnitData) -> String:
	if not data:
		return ""
	var s := data.story
	if not s.strip_edges().is_empty():
		return _normalize_story_text(s)
	if unit_database and unit_database.has_method("get_story_for"):
		var ds: String = unit_database.get_story_for(data)
		if not ds.strip_edges().is_empty():
			return _normalize_story_text(ds)
	var p := data.resource_path
	if p.is_empty():
		return ""
	if _story_cache_by_path.has(p):
		return _normalize_story_text(str(_story_cache_by_path[p]))
	var reloaded = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
	if reloaded is UnitData:
		var rs: String = reloaded.story
		if not rs.strip_edges().is_empty():
			_story_cache_by_path[p] = rs
			return _normalize_story_text(rs)
	var fallback := _read_story_from_tres(p)
	_story_cache_by_path[p] = fallback
	if fallback.strip_edges().is_empty():
		_log_story_issue(p, data, reloaded)
	return _normalize_story_text(fallback)

func _normalize_story_text(text: String) -> String:
	return text.replace("\\n", "\n").replace("/n", "\n").replace("\\t", "\t")

func _read_story_from_tres(resource_path: String) -> String:
	if resource_path.is_empty():
		return ""
	var f := FileAccess.open(resource_path, FileAccess.READ)
	if not f:
		return ""
	var text := f.get_as_text()
	var key := "\nstory = \""
	var start := text.find(key)
	if start == -1:
		if text.begins_with("story = \""):
			start = 0
		else:
			return ""
	var i := start + (key.length() if start != 0 else "story = \"".length())
	var out := ""
	while i < text.length():
		var ch := text[i]
		if ch == "\"":
			break
		if ch == "\\" and i + 1 < text.length():
			var n := text[i + 1]
			if n == "n":
				out += "\n"
				i += 2
				continue
			if n == "t":
				out += "\t"
				i += 2
				continue
			out += n
			i += 2
			continue
		out += ch
		i += 1
	return out

func _log_story_issue(resource_path: String, data: UnitData, reloaded: Resource) -> void:
	if _logged_story_issue_by_path.has(resource_path):
		return
	_logged_story_issue_by_path[resource_path] = true
	var f := FileAccess.open("user://story_debug.log", FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open("user://story_debug.log", FileAccess.WRITE)
	if not f:
		return
	f.seek_end()
	var exists := ResourceLoader.exists(resource_path)
	var can_open := FileAccess.open(resource_path, FileAccess.READ) != null
	var data_story_len := 0
	if data:
		data_story_len = data.story.length()
	var reloaded_story_len := -1
	if reloaded is UnitData:
		reloaded_story_len = (reloaded as UnitData).story.length()
	var line := "%s | exists=%s | can_open=%s | data_story_len=%d | reloaded_story_len=%d\n" % [
		resource_path, str(exists), str(can_open), data_story_len, reloaded_story_len
	]
	f.store_string(line)

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
		tag_list.add_item(t)
	if tags.is_empty():
		_current_tag = ""
		_fill_grid(tags_grid, [])
		return
	if _current_tag.is_empty():
		_current_tag = tags[0]
	var idx := tags.find(_current_tag)
	if idx < 0:
		idx = 0
		_current_tag = tags[0]
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
	for child in grid.get_children():
		child.queue_free()
	for u in units:
		u = _resolve_unit_data(u)
		var slot = card_slot_scene.instantiate()
		grid.add_child(slot)
		slot.setup(u)
		slot.pressed.connect(_on_card_pressed)

func _get_stacked_collected() -> Array[Dictionary]:
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
	if not _all_units_cache.is_empty():
		return _all_units_cache
	var result: Array[UnitData] = []
	if unit_database:
		for u in unit_database.get_units():
			if u:
				result.append(u)
		_all_units_cache = result
		return _all_units_cache
	var dir = DirAccess.open("res://Resources/DataFiles")
	if dir:
		dir.list_dir_begin()
		while true:
			var file_name = dir.get_next()
			if file_name == "":
				break
			if dir.current_is_dir():
				continue
			if not file_name.ends_with(".tres"):
				continue
			var path = "res://Resources/DataFiles/%s" % file_name
			var res = load(path)
			if res is UnitData:
				result.append(res)
		dir.list_dir_end()
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
	var cols: int = clampi(int(content_w / 160.0), 2, 8)
	collected_grid.columns = cols
	all_grid.columns = cols
	tags_grid.columns = cols

func _switch_page(page: String):
	collected_page.visible = page == "collected"
	all_page.visible = page == "all"
	tags_page.visible = page == "tags"
	if page == "collected":
		page_header.text = "已收集"
	elif page == "all":
		page_header.text = "全部兵种"
	elif page == "tags":
		page_header.text = "标签"
	else:
		page_header.text = ""

func _on_tag_selected(index: int):
	var tags = _get_all_tags()
	if index < 0 or index >= tags.size():
		return
	_current_tag = tags[index]
	_refresh_tag_units()

func _on_card_pressed(data: UnitData):
	_selected_unit = _resolve_unit_data(data)
	_show_unit_detail(_selected_unit)

func _show_unit_detail(data: UnitData):
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
	for t in data.tags:
		var desc = _tag_desc.get(t, "")
		if desc == "":
			tag_lines.append("• %s" % t)
		else:
			tag_lines.append("• %s：%s" % [t, desc])
	var tags_text := "\n".join(tag_lines)
	if detail_tags is RichTextLabel:
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
