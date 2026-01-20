extends ColorRect

var parent_visual: Node
var grid_offset: Vector2i = Vector2i.ZERO

func _get_drag_data(_at_position: Vector2):
	if parent_visual and parent_visual.has_method("_get_drag_data_from_block"):
		return parent_visual._get_drag_data_from_block(self)
	return null

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if parent_visual and parent_visual.has_method("_on_right_click"):
				parent_visual._on_right_click()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# Pass left click too if needed
			pass
