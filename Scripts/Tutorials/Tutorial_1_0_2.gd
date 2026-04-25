class_name Tutorial_1_0_2 extends Node

var battle_manager: BattleManager
var current_tip: PanelContainer
var current_target_node: Node
var current_tip_offset: Vector2 = Vector2.ZERO

# 阶段枚举
enum Phase {
	INTRO_STRATEGY,   # 介绍策略：弓兵后置
	EXPLAIN_RANGE,    # 介绍射程
	WAIT_START,       # 等待开始
	STARTED           # 战斗开始
}

var phase: Phase = Phase.INTRO_STRATEGY

func start(bm: BattleManager):
	print("[Tutorial_1_0_2] Tutorial started")
	battle_manager = bm
	
	battle_manager.log_message("新手教程: 远程单位的使用技巧。", Color.GREEN)
	
	# 连接信号
	var start_btn = battle_manager.get_node_or_null("CanvasLayer/HUD/StartButton")
	if start_btn:
		start_btn.pressed.connect(_on_start_pressed)
	
	# 启动教程序列
	get_tree().create_timer(1.0).timeout.connect(_start_sequence)

signal step_finished
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
	_wait_index += 1

func _start_sequence():
	# Step 1: 介绍弓兵站位
	phase = Phase.INTRO_STRATEGY
	var bench = battle_manager.get_node_or_null("CanvasLayer/HUD/BenchPanel")
	if bench:
		_show_tip("汉家材官皮糙肉厚，适合抗线。\n请将弓箭手放在材官身后，提供安全的输出环境。", bench, Vector2(0, -50), 4.0)
		await _wait_for_step(4.5)
	
	# Step 2: 介绍射程
	phase = Phase.EXPLAIN_RANGE
	var field = battle_manager.get_node_or_null("Battlefield/FriendlyField")
	if field:
		_show_tip("每个单位都有攻击距离。\n如果前方有太多友军阻挡，可能会无法攻击到敌人（卡射程）。\n请合理安排站位！", bench, Vector2(0, -300), 4.0)
		# Add a wait here if needed, or proceed to WAIT_START
		await _wait_for_step(4.5)


	_start_phase_wait_start()

func _start_phase_wait_start():
	phase = Phase.WAIT_START
	var btn = battle_manager.get_node_or_null("CanvasLayer/HUD/StartButton")
	if btn:
		_show_tip("准备好后，点击开始战斗！", btn, Vector2(0, -10))

func _on_start_pressed():
	if phase == Phase.WAIT_START or phase == Phase.EXPLAIN_RANGE or phase == Phase.INTRO_STRATEGY:
		phase = Phase.STARTED
		if current_tip:
			current_tip.queue_free()
			current_tip = null
		
		queue_free()

func _show_tip(text: String, target_node: Node, offset: Vector2 = Vector2.ZERO, duration: float = 0.0):
	if current_tip:
		current_tip.queue_free()
		current_tip = null
		
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
	panel.add_theme_stylebox_override("panel", style)
	
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			step_finished.emit()
	)
	
	battle_manager.get_node("CanvasLayer/HUD").add_child(panel)
	current_tip = panel
	current_tip_offset = offset
	panel.visible = false
	
	# --- 2. 定位逻辑 ---
	call_deferred("_update_tip_position")
	
	# 自动销毁
	if duration > 0:
		get_tree().create_timer(duration).timeout.connect(func():
			if is_instance_valid(panel) and panel == current_tip:
				panel.queue_free()
				current_tip = null
		)

func _process(_delta):
	if current_tip and is_instance_valid(current_target_node):
		# 如果需要跟随移动，可以在这里更新位置
		# 目前只在创建时定位一次，如果需要实时跟随，取消下面注释并传入 offset
		# _update_tip_position(Vector2.ZERO) 
		pass

func _update_tip_position():
	if not current_tip or not is_instance_valid(current_target_node):
		return

	var target_rect = Rect2()
	if current_target_node is Control:
		target_rect = current_target_node.get_global_rect()
	elif current_target_node is Node2D:
		var target_pos = current_target_node.get_global_transform_with_canvas().origin
		target_rect = Rect2(target_pos, Vector2.ZERO)

	var viewport_size = get_viewport().get_visible_rect().size
	var tip_size = current_tip.size
	var tip_pos = target_rect.position + Vector2(
		target_rect.size.x / 2.0 - tip_size.x / 2.0,
		-tip_size.y - 20
	) + current_tip_offset

	if tip_pos.y < 10:
		tip_pos.y = target_rect.end.y + 20
	if tip_pos.y + tip_size.y > viewport_size.y - 10:
		tip_pos.y = max(10.0, viewport_size.y - tip_size.y - 10.0)
	if tip_pos.x < 10:
		tip_pos.x = 10
	if tip_pos.x + tip_size.x > viewport_size.x - 10:
		tip_pos.x = viewport_size.x - tip_size.x - 10

	current_tip.position = tip_pos
	current_tip.visible = true

func _exit_tree():
	if current_tip:
		current_tip.queue_free()
		current_tip = null
