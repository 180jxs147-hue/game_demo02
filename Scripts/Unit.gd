extends Node2D

@export var data: UnitData

# 引用状态机节点
@onready var state_chart = $StateChart
@onready var timer = $Timer

# 动态属性
var current_cooldown: float
var visual_blocks: Array[ColorRect] = []
var _processed_death_ids: Dictionary = {}

# --- 拖拽相关变量 ---
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO # 记录拖拽前的位置，放不下去要弹回

# 引用新的 Label 节点
@onready var status_label = $StatusLabel # 记得在场景里改名
@onready var name_label = $NameLabel     # 新加的 Label

func _ready():
	if not data: return
	
	# 1. 显示名字
	if name_label:
		name_label.text = data.name
		# 将名字居中显示在形状上方
		name_label.position = Vector2(0, -20) 
	
	current_cooldown = data.cooldown
	_build_visuals()
	
	# 确保计时器没自动开始
	timer.stop()
	
	# 信号连接
	EventBus.unit_died.connect(_on_ally_died)
	timer.timeout.connect(_on_timer_timeout)
	
	# 3. 连接状态机信号
	# 请确保你的 StateChart 节点路径正确
	var alive_state = $StateChart/Root/Alive
	
	alive_state.get_node("Cooldown").state_entered.connect(_on_cooldown_entered)
	alive_state.get_node("Ready").state_entered.connect(_on_ready_entered)
	alive_state.get_node("Action").state_entered.connect(_on_action_entered)
	$StateChart/Root/Dead.state_entered.connect(_on_dead_entered)
	
	# 4. 初始化 Timer 信号 (用于驱动 Cooldown 状态)
	# 初始时，先不启动 Timer (只有战斗开始才启动)
	timer.stop() 
	# 或者让状态机处于 "Preparation" 状态

# --- 状态机逻辑 ---

# 状态 1: 进入冷却
func _on_cooldown_entered():
	status_label.text = "CD..."
	timer.start(current_cooldown)

# Timer 跑完了 -> 告诉状态机 "CD结束了"
func _on_timer_timeout():
	state_chart.send_event("cd_finished")

# 状态 2: 准备就绪 (判定民力)
func _on_ready_entered():
	_check_condition()

func _check_condition():
	# A. 产出类单位
	if data.manpower_cost < 0:
		state_chart.send_event("act")
		return

	# B. 消耗类单位
	var manager = get_parent().get_parent()
	if manager.current_manpower >= data.manpower_cost:
		state_chart.send_event("act")
	else:
		# 缺气，等待 0.5s 后重试 (停留在 Ready 状态)
		status_label.text = "缺气"
		get_tree().create_timer(0.5).timeout.connect(_check_condition)

# 状态 3: 执行动作
func _on_action_entered():
	if data.manpower_cost < 0:
		_produce()
	else:
		_attack()
	# 状态机会根据 Delay 自动跳回 Cooldown

# 状态 4: 死亡
func _on_dead_entered():
	timer.stop()
	status_label.text = "X"
	modulate = Color(0.3, 0.3, 0.3)
	EventBus.unit_died.emit(self, global_position.x)

# --- 业务逻辑 ---

func _produce():
	var manager = get_parent().get_parent()
	var amount = absf(data.manpower_cost)
	manager.modify_manpower(amount)
	_pop_text("+%.1f" % amount)

func _attack():
	var manager = get_parent().get_parent()
	manager.modify_manpower(-data.manpower_cost)
	var dmg = data.attack_damage if "attack_damage" in data else 10.0
	manager.deal_damage_to_enemy(dmg)
	_pop_text("ATK!")

# --- 外部调用与辅助函数 (之前缺失的部分) ---

# 战线判定 (由 BattleManager 调用)
func check_burn(line_x: float):
	# 视觉变灰逻辑
	for i in range(visual_blocks.size()):
		var block = visual_blocks[i]
		var relative_pos = data.grid_shape[i]
		var block_world_x = global_position.x + (relative_pos.x * GameConst.GRID_SIZE)
		
		# 红线从右往左烧，如果方块X > 红线X，说明在红线右边
		if block_world_x > line_x:
			block.color = Color(0.2, 0.2, 0.2)
	
	# 死亡判定 (发送事件给状态机)
	if global_position.x > line_x:
		state_chart.send_event("die")

# 皮洛士机制
func _on_ally_died(unit, _pos):
	if unit == self:
		return
	var id = unit.get_instance_id()
	if _processed_death_ids.has(id):
		return
	_processed_death_ids[id] = true
	if not timer.is_stopped():
		if "sacrifice" in data.tags:
			current_cooldown = max(0.2, current_cooldown * 0.7)
			if timer.time_left > current_cooldown:
				timer.start(current_cooldown)
			status_label.modulate = Color.RED

# 构建视觉方块 (之前缺失的函数!)
func _build_visuals():
	for grid_pos in data.grid_shape:
		var block = ColorRect.new()
		var size_val = GameConst.GRID_SIZE - GameConst.GRID_PADDING
		
		block.size = Vector2(size_val, size_val)
		block.color = data.color
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var offset = Vector2(grid_pos) * GameConst.GRID_SIZE
		var padding = Vector2(GameConst.GRID_PADDING, GameConst.GRID_PADDING) / 2.0
		block.position = offset + padding
		
		add_child(block)
		visual_blocks.append(block)

func _pop_text(txt):
	status_label.text = txt
	var t = create_tween()
	# 让状态文字跳动，不要遮挡名字
	t.tween_property(status_label, "position:y", -50.0, 0.1)
	t.tween_property(status_label, "position:y", -40.0, 0.1)

	
#  --- 输入处理 (实现拖拽) ---
func _unhandled_input(event):
	# 如果战斗已经开始，禁止拖拽
	if BattleManager.is_battle_started: return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_start_drag()
			elif is_dragging:
				_end_drag()
	
	elif event is InputEventMouseMotion and is_dragging:
		# 跟随鼠标，并应用偏移
		global_position = get_global_mouse_position() - drag_offset

func _try_start_drag():
	# 简单的点击检测：鼠标是否在我的“锚点”附近 (粗略检测，实际建议用Area2D)
	# 这里为了演示简单，假设点击任何属于该单位的格子都算
	var mouse_pos = get_global_mouse_position()
	var my_rect = Rect2(global_position, Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE))
	
	# 检测是否点击到了本单位的任何一部分
	var clicked_on_me = false
	for grid_pos in data.grid_shape:
		var part_pos = global_position + Vector2(grid_pos) * GameConst.GRID_SIZE
		var part_rect = Rect2(part_pos, Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE))
		if part_rect.has_point(mouse_pos):
			clicked_on_me = true
			break
			
	if clicked_on_me:
		is_dragging = true
		original_position = global_position
		drag_offset = mouse_pos - global_position
		z_index = 100 # 拖拽时显示在最上层
		
		# 拖起时，告诉 GridManager 释放我原来的位置
		GridManager.clear_unit(self)

func _end_drag():
	is_dragging = false
	z_index = 0
	
	# 1. 计算吸附位置
	# 获取鼠标当前的格子坐标
	var drop_grid_pos = GridManager.world_to_grid(global_position)
	
	# 2. 询问 GridManager 能不能放
	if GridManager.can_place_unit(data, drop_grid_pos):
		# A. 可以放置：吸附并注册
		global_position = GridManager.grid_to_world(drop_grid_pos)
		GridManager.place_unit(self, drop_grid_pos)
		# 播放一个放置音效
	else:
		# B. 不能放置：弹回原位 (并重新注册原位)
		var tween = create_tween()
		tween.tween_property(self, "global_position", original_position, 0.2).set_trans(Tween.TRANS_CUBIC)
		# 记得把原位置重新占回去
		var old_grid_pos = GridManager.world_to_grid(original_position)
		GridManager.place_unit(self, old_grid_pos)
func start_battle():
	# 也可以发送事件给 StateChart
	state_chart.send_event("battle_started")
