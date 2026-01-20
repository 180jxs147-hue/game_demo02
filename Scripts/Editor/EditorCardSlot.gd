extends "res://Scripts/CardSlot.gd"

const DraggableUnitVisual = preload("res://Scripts/Editor/DraggableUnitVisual.gd")

func _ready():
	super._ready()
	if click_button:
		# Disable the button's input handling so the Panel can receive drag events
		click_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Set cursor shape to indicate clickability
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Handle selection click manually since we disabled the button
			pressed.emit(_unit_data)
			accept_event()

func _get_drag_data(_at_position: Vector2):
	if not _unit_data:
		return null
		
	var data = {
		"type": "unit_card",
		"unit_data": _unit_data,
		"path": _unit_data.resource_path,
		"source": self
	}
	
	# Create Preview
	var preview_root = Control.new()
	var vis = DraggableUnitVisual.new()
	vis.setup(Vector2i.ZERO, _unit_data, true)
	preview_root.add_child(vis)
	
	# Center the anchor block on mouse
	# Assuming GameConst is globally available or we need to load it
	# But DraggableUnitVisual uses GameConst so it should be fine.
	var grid_size = 64 # Default fallback
	if ClassDB.class_exists("GameConst"):
		# Dynamic access if needed, or just use hardcoded 64 if GameConst is not a class_name
		# Actually GameConst is a class_name in this project
		grid_size = GameConst.GRID_SIZE
		
	var anchor_center = Vector2(grid_size, grid_size) / 2.0
	vis.position = -anchor_center
	
	set_drag_preview(preview_root)
	
	return data
