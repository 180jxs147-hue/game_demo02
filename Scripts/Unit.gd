extends Node2D

@export var data: UnitData

# 引用状态机节点
@onready var state_chart = $StateChart
@onready var timer = $Timer
@onready var label = $Label

# 动态属性
var current_cooldown: float
var visual_blocks: Array[ColorRect] = []

func _ready():
	if not data: return
	current_cooldown = data.cooldown
	
	# 1. 这里调用了函数，所以下面必须有定义
	_build_visuals()
	
	# 2. 连接队友死亡信号 (皮洛士机制)
	EventBus.unit_died.connect(_on_ally_died)
	
	# 3. 连接状态机信号
	# 请确保你的 StateChart 节点路径正确
	var alive_state = $StateChart/Root/Alive
	
	alive_state.get_node("Cooldown").state_entered.connect(_on_cooldown_entered)
	alive_state.get_node("Ready").state_entered.connect(_on_ready_entered)
	alive_state.get_node("Action").state_entered.connect(_on_action_entered)
	$StateChart/Root/Dead.state_entered.connect(_on_dead_entered)
	
	# 4. 初始化 Timer 信号 (用于驱动 Cooldown 状态)
	timer.timeout.connect(_on_timer_timeout)

# --- 状态机逻辑 ---

# 状态 1: 进入冷却
func _on_cooldown_entered():
	label.text = "CD..."
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
		label.text = "缺气"
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
	label.text = "X"
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
	if not timer.is_stopped(): # 只有活着且不在 Dead 状态才触发
		if "sacrifice" in data.tags:
			current_cooldown *= 0.9
			if timer.time_left > current_cooldown:
				timer.start(current_cooldown)
			label.modulate = Color.RED

# 构建视觉方块 (之前缺失的函数!)
func _build_visuals():
	for grid_pos in data.grid_shape:
		var block = ColorRect.new()
		var size_val = GameConst.GRID_SIZE - GameConst.GRID_PADDING
		
		block.size = Vector2(size_val, size_val)
		block.color = data.color
		
		var offset = Vector2(grid_pos) * GameConst.GRID_SIZE
		var padding = Vector2(GameConst.GRID_PADDING, GameConst.GRID_PADDING) / 2.0
		block.position = offset + padding
		
		add_child(block)
		visual_blocks.append(block)

# 弹出文字特效 (之前缺失的函数!)
func _pop_text(txt):
	label.text = txt
	var t = create_tween()
	t.tween_property(label, "position:y", -50.0, 0.1)
	t.tween_property(label, "position:y", -40.0, 0.1)
