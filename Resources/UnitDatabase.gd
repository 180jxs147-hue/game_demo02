class_name UnitDatabase extends Resource

@export var units: Array[UnitData] = []
@export var story_by_path: Dictionary = {}

func get_units() -> Array[UnitData]:
	return units

func get_story_for(unit: UnitData) -> String:
	if not unit:
		return ""
	if unit.resource_path.is_empty():
		return ""
	if story_by_path.has(unit.resource_path):
		return _normalize_story_text(str(story_by_path[unit.resource_path]))
	return ""

func _normalize_story_text(text: String) -> String:
	return text.replace("\\n", "\n").replace("/n", "\n").replace("\\t", "\t")
