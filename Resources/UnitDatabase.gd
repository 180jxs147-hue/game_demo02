class_name UnitDatabase extends Resource

@export var units: Array[UnitData] = []
@export var story_by_path: Dictionary = {}

var _index_ready: bool = false
var _unit_by_path: Dictionary = {}
var _unit_by_name: Dictionary = {}

# 维护约定：
# - units：必须显式包含所有 UnitData（保证导出能打包）
# - story_by_path：用于导出环境下 story 字段失效时的兜底，key 为 UnitData.resource_path

func get_units() -> Array[UnitData]:
	# 返回“全部兵种”的权威列表。
	# 之所以做成显式列表而不是扫描目录，是为了保证导出 EXE 时资源能被打包进 PCK。
	_ensure_index()
	return units

func resolve_unit(candidate: UnitData) -> UnitData:
	# 由于玩家存档里保存的是 UnitData 引用，导出后可能出现：
	# - 引用指向的资源不在导出包里（目录扫描/未被引用导致未打包）
	# - 或者脚本导出模式下字段反序列化不一致
	# 所以这里尽量把“存档中的 UnitData”映射回数据库里那份 UnitData 实例。
	_ensure_index()
	if not candidate:
		return null
	if not candidate.resource_path.is_empty() and _unit_by_path.has(candidate.resource_path):
		return _unit_by_path[candidate.resource_path]
	if not candidate.name.is_empty() and _unit_by_name.has(candidate.name):
		return _unit_by_name[candidate.name]
	return candidate

func get_story_for(candidate: UnitData) -> String:
	# 图鉴简介的统一入口：
	# 1) 优先用 UnitData.story（编辑器里写的原始字段）
	# 2) 如果导出后该字段为空，则用 story_by_path 兜底（导出更稳定）
	_ensure_index()
	if not candidate:
		return ""
	var unit := resolve_unit(candidate)
	if unit and not unit.story.strip_edges().is_empty():
		return _normalize_story_text(unit.story)
	if unit and not unit.resource_path.is_empty() and story_by_path.has(unit.resource_path):
		return _normalize_story_text(str(story_by_path[unit.resource_path]))
	if not candidate.resource_path.is_empty() and story_by_path.has(candidate.resource_path):
		return _normalize_story_text(str(story_by_path[candidate.resource_path]))
	return ""

func _ensure_index() -> void:
	# 建立两个索引：
	# - resource_path -> UnitData（稳定、唯一）
	# - name -> UnitData（编辑器可读，但不保证唯一，仅作为回退）
	if _index_ready:
		return
	_index_ready = true
	_unit_by_path.clear()
	_unit_by_name.clear()
	for u in units:
		if not u:
			continue
		if not u.resource_path.is_empty():
			_unit_by_path[u.resource_path] = u
		if not u.name.is_empty() and not _unit_by_name.has(u.name):
			_unit_by_name[u.name] = u

func _normalize_story_text(text: String) -> String:
	# 兼容历史数据：
	# - "\\n" / "/n" 这类“字面换行”转成真正的换行
	# - "\\t" 转成制表符
	var t := text
	t = t.replace("\\n", "\n")
	t = t.replace("/n", "\n")
	t = t.replace("\\t", "\t")
	return t
