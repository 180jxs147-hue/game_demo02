class_name Tutorial_1_0_1 extends Node

var battle_manager: BattleManager
var current_tip: PanelContainer
var current_target_node: Node

# 阶段枚举
enum Phase {
	INTRO_BENCH,      # 介绍备战区
	INTRO_FIELD,      # 介绍部署区
	DRAG_UNIT,        # 引导拖拽
	EXPLAIN_MANPOWER, # 介绍民力
	WAIT_START,       # 等待开始
	STARTED           # 战斗开始
}

var phase: Phase = Phase.INTRO_BENCH

func start(bm: BattleManager):
	print("[Tutorial_1_0_1] Tutorial started")
	battle_manager = bm
	
	battle_manager.log_message("新手教程: 欢迎来到历史搅拌机！请部署您的单位。", Color.GREEN)
	
	# 连接信号
	GridManager.unit_placed.connect(_on_unit_placed)
	
	# 确保开始按钮被监控
	var start_btn = battle_manager.get_node_or_null("CanvasLayer/HUD/StartButton")
	if start_btn:
		start_btn.pressed.connect(_on_start_pressed)
	
	# 启动教程序列
	# 延迟一点显示，等待 UI 布局完成
	get_tree().create_timer(1.0).timeout.connect(_start_sequence)

signal step_finished

# Wait for either timer or user click
var _wait_index = 0
func _wait_for_step(duration: float):
	_wait_index += 1
	var current_index = _wait_index
	
	var t = get_tree().create_timer(duration)
	t.timeout.connect(func(): 
		if _wait_index == current_index:
			step_finished.emit()
	)
	
	await step_finished
	# Invalidate the timer if it hasn't fired yet
	_wait_index += 1

func _start_sequence():
	# Step 1: 介绍备战区
	phase = Phase.INTRO_BENCH
	var bench = battle_manager.get_node_or_null("CanvasLayer/HUD/BenchPanel")
	if bench:
		_show_tip("这是备战区，您的可用单位都在这里。", bench, Vector2(0, -50), 3.0)
		await _wait_for_step(3.5)
	
	# Step 2: 介绍部署区
	phase = Phase.INTRO_FIELD
	var field = battle_manager.get_node_or_null("Battlefield/FriendlyField")
	if field:
		# 临时把提示框放在战场中央大概位置
		# 由于 FriendlyField 很大，我们尝试找个中心点提示
		var center_offset = Vector2(200, 150) 
		# 这里没有很好的 Control 节点做锚点，FriendlyField 是 Node2D
		# 我们可以用 GridVisualizer 如果它是 Control，但它也是 Node2D
		# 暂时用 bench 做锚点，向上指
		_show_tip("请将单位拖拽到战场网格上进行部署。", bench, Vector2(0, -300), 3.0)
		await _wait_for_step(3.5)
	
	# Step 3: 引导拖拽
	phase = Phase.DRAG_UNIT
	if bench:
		_show_tip("请注意将汉家材官拖拽到营帐前方，以抵挡敌人攻击。", bench, Vector2(0, -50))

var current_indicator: Control

func _show_tip(text: String, target_node: Node, offset: Vector2 = Vector2.ZERO, duration: float = 0.0):
	if current_tip:
		current_tip.queue_free()
		current_tip = null
	if current_indicator:
		current_indicator.queue_free()
		current_indicator = null
		
	# 允许 target_node 为 null (仅显示文字，不跟随)
	current_target_node = target_node

	# --- 1. 创建提示文本框 ---
	var panel = PanelContainer.new()
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_right", 16)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(label)
	
	var hint = Label.new()
	hint.text = "(点击继续)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hint)
	
	panel.add_child(margin)
	
	# 设置文本框样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.1, 0.2, 0.8) # Deep Blue
	panel.add_theme_stylebox_override("panel", style)
	
	# 确保不遮挡鼠标交互
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			step_finished.emit()
	)
	
	var hud = battle_manager.get_node("CanvasLayer/HUD")
	hud.add_child(panel)
	current_tip = panel
	panel.visible = false # 先隐藏，等定位好再显示
	
	# --- 2. 创建目标指示器 (如果存在目标) ---
	if target_node:
		var indicator = Panel.new()
		indicator.visible = false # 先隐藏
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ind_style = StyleBoxFlat.new()
		ind_style.bg_color = Color(0, 0, 0, 0) # 透明背景
		ind_style.border_width_left = 4
		ind_style.border_width_top = 4
		ind_style.border_width_right = 4
		ind_style.border_width_bottom = 4
		ind_style.border_color = Color(0.1, 0.2, 0.8, 0.8) # Deep Blue Transparent
		ind_style.set_corner_radius_all(4)
		indicator.add_theme_stylebox_override("panel", ind_style)
		
		hud.add_child(indicator)
		current_indicator = indicator
		
		# 指示器闪烁动画
		var ind_tween = indicator.create_tween()
		ind_tween.set_loops()
		ind_tween.tween_property(indicator, "modulate:a", 0.3, 0.8).set_trans(Tween.TRANS_SINE)
		ind_tween.tween_property(indicator, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	# --- 3. 定位逻辑 ---
	await get_tree().process_frame
	if not is_instance_valid(panel): return
	
	var target_rect = Rect2()
	
	if target_node:
		if not is_instance_valid(target_node): 
			current_tip.queue_free()
			if current_indicator: current_indicator.queue_free()
			return
			
		target_rect = _get_screen_rect(target_node)
		
		# 更新指示器位置和大小
		if current_indicator:
			current_indicator.position = target_rect.position - Vector2(5, 5) # 外扩一点
			current_indicator.size = target_rect.size + Vector2(10, 10)
	else:
		# 如果没有目标，默认显示在屏幕上方中央
		var vp_size = get_viewport().get_visible_rect().size
		target_rect = Rect2(vp_size.x / 2, vp_size.y / 3, 0, 0)

	# 更新文本框位置
	# 默认显示在目标正上方，如果空间不足则显示在下方
	var tip_pos = target_rect.position + Vector2(target_rect.size.x / 2 - panel.size.x / 2, -panel.size.y - 20) + offset
	
	# 屏幕边界检查 (防止超出屏幕)
	var vp_size = get_viewport().get_visible_rect().size
	
	# 1. 上边界检查
	if tip_pos.y < 10:
		tip_pos.y = target_rect.end.y + 20
	
	# 2. 下边界检查
	if tip_pos.y + panel.size.y > vp_size.y - 10:
		tip_pos.y = vp_size.y - panel.size.y - 10
		# 如果调整后上边界又超了 (屏幕太小)，优先保证上边界在屏幕内，或者垂直居中
		if tip_pos.y < 10: tip_pos.y = 10
	
	# 3. 左边界检查
	if tip_pos.x < 10:
		tip_pos.x = 10
	
	# 4. 右边界检查
	if tip_pos.x + panel.size.x > vp_size.x - 10:
		tip_pos.x = vp_size.x - panel.size.x - 10
		
	panel.position = tip_pos
	
	# 显示
	panel.visible = true
	if current_indicator:
		current_indicator.visible = true
	
	# 文本框弹跳动画
	var tween = panel.create_tween()
	tween.set_loops()
	tween.tween_property(panel, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
	
	if duration > 0:
		get_tree().create_timer(duration).timeout.connect(func():
			if is_instance_valid(panel) and current_tip == panel:
				panel.queue_free()
				current_tip = null
			if is_instance_valid(current_indicator) and current_indicator == current_indicator:
				current_indicator.queue_free()
				current_indicator = null
		)

func _get_screen_rect(node: Node) -> Rect2:
	if node is Control:
		return node.get_global_rect()
	elif node is Node2D:
		# 获取 CanvasTransform (考虑 Camera 和 缩放)
		var canvas_transform = node.get_canvas_transform()
		var screen_pos = canvas_transform * node.global_position
		
		# 估算大小 (尝试获取 Sprite 子节点，或者用默认值)
		var size = Vector2(100, 100) # 默认 100x100
		var sprite = _find_visual_node(node)
		if sprite:
			if sprite is Sprite2D:
				var tex = sprite.texture
				if tex:
					size = tex.get_size() * sprite.global_scale
			elif sprite is ColorRect:
				size = sprite.size * sprite.global_scale
				
		# Node2D 的 position 通常是中心或左上角，取决于实现。
		# 假设 Unit 的 position 是脚下中心，或者中心。
		# 我们假设是中心，所以 rect 的起点要偏移
		return Rect2(screen_pos - size / 2, size)
	
	return Rect2(0, 0, 0, 0)

func _find_visual_node(root: Node) -> Node:
	# 尝试找到用于显示的子节点来估算大小
	for child in root.get_children():
		if child is Sprite2D or child is AnimatedSprite2D or child is ColorRect:
			return child
	return null


func _on_unit_placed(unit, _pos):
	# 检查是否是我方单位
	if not ("faction" in unit and unit.faction == 0): # Friendly
		return

	if phase == Phase.DRAG_UNIT:
		_start_phase_explain_manpower()

func _start_phase_explain_manpower():
	phase = Phase.EXPLAIN_MANPOWER
	var manpower_label = battle_manager.manpower_label
	if manpower_label:
		_show_tip("注意左上角的民力值。\n大部分单位攻击时会消耗民力，需要靠营帐等单位回复民力。\n(等待几秒自动继续...)", manpower_label, Vector2(0, 10), 4.0)
		
		await _wait_for_step(4.5)
		_start_phase_wait_start()
	else:
		_start_phase_wait_start()

func _start_phase_wait_start():
	phase = Phase.WAIT_START
	var btn = battle_manager.get_node_or_null("CanvasLayer/HUD/StartButton")
	if btn:
		_show_tip("一切就绪！\n点击这里开始战斗！", btn, Vector2(0, 0))

func _on_start_pressed():
	if phase == Phase.WAIT_START or phase == Phase.EXPLAIN_MANPOWER:
		phase = Phase.STARTED
		if current_tip:
			current_tip.queue_free()
			current_tip = null
		
		# 教程完成，自动销毁
		queue_free()

func _exit_tree():
	if current_tip:
		current_tip.queue_free()
		current_tip = null
	if current_indicator:
		current_indicator.queue_free()
		current_indicator = null
