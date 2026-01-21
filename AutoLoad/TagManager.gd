extends Node

# Autoload to manage tags.
# Registered as "TagManager" in Project Settings.

var _tags: Dictionary = {} # id -> TagDefinition
var _path: String = "res://Resources/Tags/"

func _ready():
	_load_tags()

func _load_tags():
	var dir = DirAccess.open(_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var full_path = _path + file_name
				var res = load(full_path)
				if res is TagDefinition:
					var id = res.id
					if id == "":
						id = file_name.get_basename()
					_tags[id] = res
			file_name = dir.get_next()
	else:
		push_error("TagManager: Failed to open tags directory: " + _path)

func get_tag_info(tag_id: String) -> TagDefinition:
	return _tags.get(tag_id)

func get_all_tags() -> Array:
	return _tags.values()

func get_tag_name(tag_id: String) -> String:
	var info = get_tag_info(tag_id)
	return info.name if info else tag_id

func get_tag_description(tag_id: String) -> String:
	var info = get_tag_info(tag_id)
	return info.description if info else ""
