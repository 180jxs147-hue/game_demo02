extends Node
## Shared, deliberately small tutorial UI and input flow for the opening levels.

signal _step_finished
signal closed

var battle_manager: Node
var current_panel: PanelContainer
var current_indicator: Panel
var current_target_node: Node
var _step_done: bool = false
var _action_waiting: bool = false
var _tutorial_skipped: bool = false

const GOLD: Color = Color("c5a369")
const PANEL_COLOR: Color = Color(0.055, 0.045, 0.035, 0.98)

func initialize(bm: Node, lesson_name: String) -> void:
	battle_manager = bm
	if is_instance_valid(battle_manager) and battle_manager.has_method("log_message"):
		battle_manager.log_message("新手引导：" + lesson_name, Color(0.86, 0.72, 0.43))
	var start_button: Button = battle_manager.get_node_or_null("CanvasLayer/HUD/StartButton") as Button
	if start_button and not start_button.pressed.is_connected(_on_battle_started):
		start_button.pressed.connect(_on_battle_started)

func _process(_delta: float) -> void:
	if not is_instance_valid(current_panel) or not current_panel.visible:
		return
	if not is_instance_valid(current_target_node):
		return
	_update_target_position()

func show_info_step(step: int, total: int, title: String, message: String, target_path: Variant, continue_text: String = "继续") -> void:
	_step_done = false
	_action_waiting = false
	await _create_prompt(step, total, "战术讲解", title, message, target_path, true, continue_text)
	while not _step_done and not _tutorial_skipped and is_inside_tree():
		await _step_finished
	_clear_prompt()

func show_action_step(step: int, total: int, title: String, message: String, target_path: Variant) -> void:
	_step_done = false
	_action_waiting = true
	await _create_prompt(step, total, "轮到你操作", title, message, target_path, false, "")
	while not _step_done and not _tutorial_skipped and is_inside_tree():
		await _step_finished
	_action_waiting = false
	_clear_prompt()

func complete_action_step() -> void:
	if not _action_waiting or _step_done:
		return
	_step_done = true
	_step_finished.emit()

func _create_prompt(step: int, total: int, category: String, title: String, message: String, target_path: Variant, can_continue: bool, continue_text: String) -> void:
	_clear_prompt()
	if not is_instance_valid(battle_manager):
		_step_done = true
		return
	var hud: Control = battle_manager.get_node_or_null("CanvasLayer/HUD") as Control
	if not hud:
		_step_done = true
		return
	var target: Node = null
	if target_path is Node:
		target = target_path
	elif target_path is NodePath or (target_path is String and not target_path.is_empty()):
		target = battle_manager.get_node_or_null(NodePath(target_path))
	current_target_node = target

	var panel: PanelContainer = PanelContainer.new()
	var viewport_size: Vector2 = hud.size
	var card_width: float = maxf(250.0, minf(390.0, viewport_size.x * 0.42))
	panel.custom_minimum_size = Vector2(card_width, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if can_continue else Control.MOUSE_FILTER_IGNORE
	panel.z_index = 2
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
	panel_style.set_corner_radius_all(8)
	panel_style.shadow_color = Color(0, 0, 0, 0.48)
	panel_style.shadow_size = 9
	panel_style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(panel)
	current_panel = panel

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	column.add_child(top_row)
	var category_label: Label = Label.new()
	category_label.text = category
	category_label.add_theme_color_override("font_color", Color(GOLD.r, GOLD.g, GOLD.b, 1))
	category_label.add_theme_font_size_override("font_size", 15)
	top_row.add_child(category_label)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	var step_label: Label = Label.new()
	step_label.text = "%02d / %02d" % [step, total]
	step_label.add_theme_color_override("font_color", Color(0.78, 0.73, 0.64))
	step_label.add_theme_font_size_override("font_size", 14)
	top_row.add_child(step_label)

	var title_label: Label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.72))
	title_label.add_theme_font_size_override("font_size", 22)
	column.add_child(title_label)

	var body_label: Label = Label.new()
	body_label.text = message
	body_label.custom_minimum_size.x = card_width - 44.0
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_color_override("font_color", Color(0.93, 0.91, 0.85))
	body_label.add_theme_font_size_override("font_size", 18)
	column.add_child(body_label)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)
	if can_continue:
		var continue_button: Button = _make_button(continue_text, true)
		continue_button.pressed.connect(_advance_step)
		footer.add_child(continue_button)
		continue_button.grab_focus.call_deferred()
	else:
		var action_hint: Label = Label.new()
		action_hint.text = "完成操作后自动继续"
		action_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_hint.add_theme_color_override("font_color", Color(0.78, 0.73, 0.64))
		action_hint.add_theme_font_size_override("font_size", 14)
		footer.add_child(action_hint)
	var skip_button: Button = _make_button("跳过引导", false)
	skip_button.pressed.connect(_skip_tutorial)
	footer.add_child(skip_button)

	if target:
		current_indicator = Panel.new()
		current_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		current_indicator.z_index = 1
		var indicator_style: StyleBoxFlat = StyleBoxFlat.new()
		indicator_style.bg_color = Color(0, 0, 0, 0)
		indicator_style.set_border_width_all(2)
		indicator_style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.9)
		indicator_style.set_corner_radius_all(5)
		current_indicator.add_theme_stylebox_override("panel", indicator_style)
		hud.add_child(current_indicator)

	await get_tree().process_frame
	if not is_instance_valid(panel) or _tutorial_skipped:
		return
	if target and is_instance_valid(target):
		_update_target_position()
	else:
		panel.position = Vector2((viewport_size.x - panel.size.x) * 0.5, viewport_size.y * 0.28)
	if not can_continue:
		_set_mouse_filter_recursive(panel, Control.MOUSE_FILTER_IGNORE)
		# Keep the explicit skip button clickable while allowing the player to drag units through the callout.
		skip_button.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = true

func _make_button(text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(112 if primary else 96, 36)
	button.focus_mode = Control.FOCUS_NONE
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.31, 0.20, 0.10, 1) if primary else Color(0.12, 0.10, 0.08, 1)
	normal.set_border_width_all(1)
	normal.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.9 if primary else 0.55)
	normal.set_corner_radius_all(5)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.42, 0.29, 0.14, 1) if primary else Color(0.21, 0.17, 0.12, 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	button.add_theme_font_size_override("font_size", 15)
	return button

func _advance_step() -> void:
	if _step_done:
		return
	_step_done = true
	_step_finished.emit()

func _skip_tutorial() -> void:
	_tutorial_skipped = true
	_action_waiting = false
	closed.emit()
	queue_free()

func _on_battle_started() -> void:
	_tutorial_skipped = true
	_action_waiting = false
	closed.emit()
	queue_free()

func _clear_prompt() -> void:
	if is_instance_valid(current_panel):
		current_panel.queue_free()
	current_panel = null
	if is_instance_valid(current_indicator):
		current_indicator.queue_free()
	current_indicator = null
	current_target_node = null

func _update_target_position() -> void:
	if not is_instance_valid(current_panel) or not is_instance_valid(current_target_node):
		return
	var target_rect: Rect2 = _get_target_rect(current_target_node)
	if is_instance_valid(current_indicator):
		current_indicator.position = target_rect.position - Vector2(5, 5)
		current_indicator.size = target_rect.size + Vector2(10, 10)
		current_indicator.visible = true
	var viewport_size: Vector2 = (current_panel.get_parent() as Control).size
	current_panel.position = _place_target_panel(target_rect, current_panel.size, viewport_size)

func _place_target_panel(target: Rect2, panel_size: Vector2, viewport_size: Vector2) -> Vector2:
	const GAP: float = 16.0
	const SAFE_TOP: float = 92.0
	const SAFE_BOTTOM: float = 100.0
	var candidates: Array[Vector2] = [
		Vector2(target.position.x - panel_size.x - GAP, target.position.y + (target.size.y - panel_size.y) * 0.5),
		Vector2(target.end.x + GAP, target.position.y + (target.size.y - panel_size.y) * 0.5),
		Vector2(target.position.x + (target.size.x - panel_size.x) * 0.5, target.position.y - panel_size.y - GAP),
		Vector2(target.position.x + (target.size.x - panel_size.x) * 0.5, target.end.y + GAP)
	]
	var best: Vector2 = Vector2(SAFE_TOP, SAFE_TOP)
	var best_score: float = INF
	for candidate in candidates:
		var clamped: Vector2 = Vector2(
			clampf(candidate.x, GAP, maxf(GAP, viewport_size.x - panel_size.x - GAP)),
			clampf(candidate.y, SAFE_TOP, maxf(SAFE_TOP, viewport_size.y - panel_size.y - SAFE_BOTTOM))
		)
		var panel_rect: Rect2 = Rect2(clamped, panel_size)
		var overlap: float = panel_rect.intersection(target).get_area() if panel_rect.intersects(target) else 0.0
		var distance: float = clamped.distance_to(candidate) * 0.1
		var score: float = overlap * 100.0 + distance
		if score < best_score:
			best_score = score
			best = clamped
	return best

func _get_target_rect(node: Node) -> Rect2:
	if node is Control:
		return _rect_in_hud(node as CanvasItem, Rect2(Vector2.ZERO, (node as Control).size))
	if node is Node2D:
		if node.name == "GridVisualizer":
			var cols: int = int(node.get("override_cols"))
			var rows: int = int(node.get("override_rows"))
			if cols <= 0:
				cols = GridManager.playable_columns
			if rows <= 0:
				rows = GridManager.playable_rows
			var grid_size := Vector2(cols, rows) * GameConst.GRID_SIZE
			return _rect_in_hud(node as CanvasItem, Rect2(Vector2.ZERO, grid_size))
		if node.has_method("_calculate_visual_bounds"):
			var bounds: Rect2 = node.call("_calculate_visual_bounds")
			return _rect_in_hud(node as CanvasItem, bounds)
		if node is Sprite2D:
			return _rect_in_hud(node as CanvasItem, (node as Sprite2D).get_rect())
		for child in node.get_children():
			if child is Sprite2D and child.texture:
				return _rect_in_hud(child as CanvasItem, (child as Sprite2D).get_rect())
		return _rect_in_hud(node as CanvasItem, Rect2(Vector2(-56, -56), Vector2(112, 112)))
	return Rect2()

func _rect_in_hud(item: CanvasItem, local_rect: Rect2) -> Rect2:
	var hud: Control = current_panel.get_parent() as Control
	var to_hud: Transform2D = hud.get_global_transform_with_canvas().affine_inverse() * item.get_global_transform_with_canvas()
	var top_left: Vector2 = to_hud * local_rect.position
	var top_right: Vector2 = to_hud * Vector2(local_rect.end.x, local_rect.position.y)
	var bottom_left: Vector2 = to_hud * Vector2(local_rect.position.x, local_rect.end.y)
	var bottom_right: Vector2 = to_hud * local_rect.end
	return Rect2(top_left, Vector2.ZERO).expand(top_right).expand(bottom_left).expand(bottom_right)

func _set_mouse_filter_recursive(control: Control, filter: int) -> void:
	control.mouse_filter = filter
	for child in control.get_children():
		if child is Control:
			_set_mouse_filter_recursive(child, filter)

func _exit_tree() -> void:
	_clear_prompt()
