extends Control

signal place_unit_requested(grid_pos: Vector2i, unit_data: Resource)
signal move_unit_requested(from_pos: Vector2i, to_pos: Vector2i)
signal remove_unit_requested(grid_pos: Vector2i)

signal grid_clicked(grid_pos: Vector2i, button_index: int)

const GRID_SIZE = 128
var grid_root: Node2D

func setup(root: Node2D):
	grid_root = root

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and (data.has("type") and (data.type == "unit_card" or data.type == "unit_move"))

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var grid_pos = _get_grid_pos(at_position)
	
	# Adjust for grid offset if present (e.g. dragging a multi-block unit by a non-anchor block)
	if data.has("grid_offset") and data.grid_offset is Vector2i:
		grid_pos -= data.grid_offset
	
	if data.type == "unit_card":
		place_unit_requested.emit(grid_pos, data.unit_data)
	elif data.type == "unit_move":
		if grid_pos != data.grid_pos:
			move_unit_requested.emit(data.grid_pos, grid_pos)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var grid_pos = _get_grid_pos(get_local_mouse_position())
		grid_clicked.emit(grid_pos, event.button_index)

func _get_grid_pos(local_pos: Vector2) -> Vector2i:
	var offset = Vector2.ZERO
	if grid_root:
		offset = grid_root.position
	
	var relative_pos = local_pos - offset
	return Vector2i((relative_pos / GameConst.GRID_SIZE).floor())
