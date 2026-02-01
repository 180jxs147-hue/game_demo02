class_name Tutorial_1_0_2 extends Node

var battle_manager: BattleManager
var current_tip: PanelContainer
var current_target_node: Node

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

func _start_sequence():
	# Step 1: 介绍弓兵站位
	phase = Phase.INTRO_STRATEGY
	var bench = battle_manager.get_node_or_null("CanvasLayer/HUD/BenchPanel")
	if bench:
		_show_tip("汉家材官皮糙肉厚，适合抗线。\n请将弓箭手放在材官身后，提供安全的输出环境。", bench, Vector2(0, -50), 4.0)
		await get_tree().create_timer(4.5).timeout
	
	# Step 2: 介绍射程
	phase = Phase.EXPLAIN_RANGE
	var field = battle_manager.get_node_or_null("Battlefield/FriendlyField")
	if field:
		_show_tip("每个单位都有攻击距离。\n如果前方有太多友军阻挡，可能会无法攻击到敌人（卡射程）。\n请合理安排站位！", bench, Vector2(0, -300), 4.0)
		await get_tree().create_timer(4.5).timeout

	_start_phase_wait_start()

func _start_phase_wait_start():
	phase = Phase.WAIT_START
	var btn = battle_manager.get_node_or_null("CanvasLayer/HUD/StartButton")
	if btn:
		_show_tip("准备好后，点击开始战斗！", btn, Vector2(0, 0))

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
	
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 24)
	
	margin.add_child(label)
	panel.add_child(margin)
	
	# 设置文本框样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	panel.add_theme_stylebox_override("panel", style)
	
	battle_manager.get_node("CanvasLayer/HUD").add_child(panel)
	current_tip = panel
	
	# --- 2. 定位逻辑 ---
	_update_tip_position(offset)
	
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

func _update_tip_position(offset: Vector2):
	if not current_tip or not is_instance_valid(current_target_node):
		return
		
	var target_pos = Vector2.ZERO
	if current_target_node is Control:
		target_pos = current_target_node.get_global_rect().position
	elif current_target_node is Node2D:
		target_pos = current_target_node.get_global_transform_with_canvas().origin
		
	current_tip.global_position = target_pos + offset

func _exit_tree():
	if current_tip:
		current_tip.queue_free()
		current_tip = null
