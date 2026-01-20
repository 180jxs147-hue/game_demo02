extends Button
class_name UnitCard

const DraggableUnitVisual = preload("res://Scripts/Editor/DraggableUnitVisual.gd")

var unit_data: Resource
var unit_path: String

func setup(data: Resource, path: String):
	unit_data = data
	unit_path = path
	
	custom_minimum_size = Vector2(120, 160)
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	expand_icon = true
	clip_text = true
	
	if unit_data.get("icon"):
		icon = unit_data.icon
	
	text = unit_data.name if unit_data.get("name") else path.get_file()

func _get_drag_data(_at_position: Vector2):
	var data = {
		"type": "unit_card",
		"unit_data": unit_data,
		"path": unit_path,
		"source": self
	}
	
	# Create Preview
	var preview_root = Control.new()
	var vis = DraggableUnitVisual.new()
	vis.setup(Vector2i.ZERO, unit_data, true)
	preview_root.add_child(vis)
	
	# Center the anchor block on mouse
	var anchor_center = Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE) / 2.0
	vis.position = -anchor_center
	
	set_drag_preview(preview_root)
	
	return data
