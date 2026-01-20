extends Node2D

const DraggableBlock = preload("res://Scripts/Editor/DraggableBlock.gd")

var grid_pos: Vector2i
var unit_data: Resource
var is_preview: bool = false
var color: Color = Color.WHITE

func setup(pos: Vector2i, data: Resource, preview: bool = false):
	grid_pos = pos
	unit_data = data
	is_preview = preview
	_build_visuals()

func _build_visuals():
	for child in get_children():
		child.queue_free()
		
	if not unit_data: return

	# Calculate bounds
	var min_x := 0
	var min_y := 0
	var width_grids := 1
	var height_grids := 1
	var shapes = unit_data.grid_shape
	if shapes.is_empty():
		shapes = [Vector2i(0,0)]
		
	if not shapes.is_empty():
		min_x = int(shapes[0].x)
		min_y = int(shapes[0].y)
		var max_x := min_x
		var max_y := min_y
		for p in shapes:
			min_x = min(min_x, int(p.x))
			min_y = min(min_y, int(p.y))
			max_x = max(max_x, int(p.x))
			max_y = max(max_y, int(p.y))
		width_grids = max_x - min_x + 1
		height_grids = max_y - min_y + 1

	var base_color = unit_data.color
	if color != Color.WHITE:
		base_color = color
	
	# Icon calculations
	var crop_uv_pos := Vector2(0.0, 0.0)
	var crop_uv_size := Vector2(1.0, 1.0)
	if unit_data.icon:
		var tw := float(unit_data.icon.get_width())
		var th := float(unit_data.icon.get_height())
		if tw > 0.0 and th > 0.0:
			var icon_aspect: float = tw / th
			var target_aspect: float = float(width_grids) / maxf(1.0, float(height_grids))
			if icon_aspect > target_aspect:
				var sub_w := target_aspect / icon_aspect
				crop_uv_pos.x = (1.0 - sub_w) * 0.5
				crop_uv_size.x = sub_w
			elif icon_aspect < target_aspect:
				var sub_h := icon_aspect / target_aspect
				crop_uv_pos.y = (1.0 - sub_h) * 0.5
				crop_uv_size.y = sub_h

	# Shader code
	var shader_code = """
	shader_type canvas_item;
	uniform float progress : hint_range(0.0, 1.0) = 1.0;
	uniform sampler2D icon_tex;
	uniform bool use_icon = false;
	uniform vec2 uv_scale = vec2(1.0, 1.0);
	uniform vec2 uv_offset = vec2(0.0, 0.0);
	uniform vec4 main_color : source_color;
	
	void fragment() {
		vec4 c = main_color;
		if (use_icon) {
			vec2 u = uv_offset + UV * uv_scale;
			c = texture(icon_tex, u);
		}
		COLOR = c;
	}
	"""
	var shader = Shader.new()
	shader.code = shader_code

	for pos in shapes:
		var block = DraggableBlock.new()
		block.parent_visual = self
		block.grid_offset = pos
		
		var size_val = GameConst.GRID_SIZE - GameConst.GRID_PADDING
		block.size = Vector2(size_val, size_val)
		block.color = base_color
		
		# Offset relative to anchor (0,0)
		var offset = Vector2(pos) * GameConst.GRID_SIZE
		var padding = Vector2(GameConst.GRID_PADDING, GameConst.GRID_PADDING) / 2.0
		block.position = offset + padding
		
		# Shader setup
		var mat = ShaderMaterial.new()
		mat.shader = shader
		block.material = mat
		mat.set_shader_parameter("main_color", base_color)
		
		if unit_data.icon:
			mat.set_shader_parameter("use_icon", true)
			mat.set_shader_parameter("icon_tex", unit_data.icon)
			
			var rel_x := int(pos.x) - min_x
			var rel_y := int(pos.y) - min_y
			var u_off = Vector2(float(rel_x) / float(width_grids), float(rel_y) / float(height_grids))
			var u_scl = Vector2(1.0 / float(width_grids), 1.0 / float(height_grids))
			u_off = crop_uv_pos + Vector2(u_off.x * crop_uv_size.x, u_off.y * crop_uv_size.y)
			u_scl = Vector2(u_scl.x * crop_uv_size.x, u_scl.y * crop_uv_size.y)
			
			mat.set_shader_parameter("uv_offset", u_off)
			mat.set_shader_parameter("uv_scale", u_scl)
		else:
			mat.set_shader_parameter("use_icon", false)
			
		add_child(block)
		
	# Add Label
	if not is_preview:
		var lbl = Label.new()
		lbl.text = unit_data.name if unit_data.get("name") else unit_data.resource_path.get_file()
		var center_x = (min_x + width_grids/2.0) * GameConst.GRID_SIZE
		var top_y = min_y * GameConst.GRID_SIZE
		lbl.position = Vector2(center_x, top_y) - Vector2(lbl.size.x/2, 20)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.z_index = 10
		add_child(lbl)

func _get_drag_data_from_block(block):
	var data = {
		"type": "unit_move",
		"grid_pos": grid_pos,
		"unit_data": unit_data,
		"source": self,
		"grid_offset": block.grid_offset
	}
	
	# Create Preview
	var preview_root = Control.new()
	var vis = load("res://Scripts/Editor/DraggableUnitVisual.gd").new()
	vis.setup(Vector2i.ZERO, unit_data, true)
	preview_root.add_child(vis)
	
	# Center the clicked block on the mouse
	# The block's position in visual is block.position
	# We want block center to be at mouse (0,0 in preview context)
	vis.position = -block.position - block.size/2
	
	block.set_drag_preview(preview_root)
	return data

func _on_right_click():
	# Traverse up to find LevelEditor
	var p = get_parent()
	while p:
		if p.has_method("_remove_unit"):
			p._remove_unit(grid_pos)
			break
		p = p.get_parent()
