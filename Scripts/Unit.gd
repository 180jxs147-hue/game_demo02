extends Node2D

@export var data: UnitData
enum Faction { FRIENDLY, ENEMY }
@export var faction: Faction = Faction.FRIENDLY

var battle_manager: BattleManager
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

# 引用新的 Label 节点
@onready var status_label = $StatusLabel # 记得在场景里改名
@onready var name_label = $NameLabel     # 新加的 Label

# --- 新增状态变量 ---
var is_deployed: bool = false      # 是否在军阵中
var bench_position: Vector2        # 备战区的坐标（老家）
var stored_grid_pos: Vector2i      # 上一次合法的格子坐标（用于手滑弹回）

# --- 生成控制 ---
var spawned_via_script: bool = false # 如果是代码生成的，默认不去尝试部署

func _ready():
	var node = self
	while node:
		if node is BattleManager:
			battle_manager = node
			break
		node = node.get_parent()
		
	if not data: return
	# 1. 显示名字
	if name_label:
		name_label.text = data.name
		# 将名字居中显示在形状上方
		name_label.position = Vector2(0, -20) 
	
	current_cooldown = data.cooldown
	# 1. 记录初始位置作为"老家" (假设你在编辑器里把它们放在了格子外面)
	bench_position = position
	
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
	
	# 5. 尝试在当前位置自动部署 (仅限非脚本生成的单位)
	if not spawned_via_script:
		var start_grid_pos = GridManager.world_to_grid(position)
		# 检查是否在地图内且不重叠
		if GridManager.can_place_unit(data, start_grid_pos):
			_deploy_to_grid(start_grid_pos)
		else:
			# 无法部署则进入备战状态
			is_deployed = false
			modulate = Color(0.7, 0.7, 0.7, 1)
	else:
		if not is_deployed:
			is_deployed = false
			modulate = Color(0.7, 0.7, 0.7, 1)
 
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
	if faction == Faction.ENEMY:
		state_chart.send_event("act")
		return
	
	# A. 产出类单位
	if data.manpower_cost < 0:
		state_chart.send_event("act")
		return

	# B. 消耗类单位
	var manager = battle_manager
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
	if faction == Faction.ENEMY:
		return
	var manager = battle_manager
	var amount = absf(data.manpower_cost)
	manager.modify_manpower(amount)
	_pop_text("+%.1f" % amount)

func _attack():
	var manager = battle_manager
	var dmg = data.attack_damage if "attack_damage" in data else 10.0
	if faction == Faction.ENEMY:
		manager.deal_damage_to_army(dmg)
	else:
		manager.modify_manpower(-data.manpower_cost)
		manager.deal_damage_to_enemy(dmg)
	_pop_text("ATK!")

# --- 外部调用与辅助函数 (之前缺失的部分) ---

# --- 修改 1: 战斗相关函数加锁 ---
# 只有部署了的单位才准打架、挨打

func start_battle():
	if not is_deployed: return # <--- 加锁
	state_chart.send_event("battle_started")

# 战线判定 (由 BattleManager 调用)
func check_burn(line_x: float, burn_from_right: bool = true):
	if not is_deployed: return # <--- 加锁，备战区不会被烧死
	for i in range(visual_blocks.size()):
		var block = visual_blocks[i]
		var relative_pos = data.grid_shape[i]
		var block_world_x = global_position.x + (relative_pos.x * GameConst.GRID_SIZE)
		
		if burn_from_right:
			if block_world_x > line_x:
				block.color = Color(0.2, 0.2, 0.2)
		else:
			if block_world_x < line_x:
				block.color = Color(0.2, 0.2, 0.2)
	
	# 死亡判定 (发送事件给状态机)
	if burn_from_right:
		if global_position.x > line_x:
			state_chart.send_event("die")
	else:
		if global_position.x < line_x:
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
	if faction != Faction.FRIENDLY: return
	
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
	modulate = Color(1.2, 1.2, 1.2, 1)
	var mouse_pos = get_global_mouse_position()
	
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
		drag_offset = mouse_pos - global_position
		z_index = 100 # 拖拽时显示在最上层
		
		# 拖起时，如果在格子里，要清除占用
		if is_deployed:
			GridManager.clear_unit(self)

func _end_drag():
	is_dragging = false
	z_index = 0
	
	# --- 核心修改开始 ---
	
	# 1. 获取鼠标当前的世界坐标
	# (global_position 是单位当前的绝对位置)
	var mouse_world_pos = global_position
	
	# 2. 将世界坐标转换为 "UnitsContainer" 内部的本地坐标
	# UnitsContainer 是 Unit 的父节点
	var local_pos = get_parent().to_local(mouse_world_pos)
	
	# 3. 使用本地坐标去计算它在第几个格子
	# GridManager 只需要知道 "相对于战场原点" 的位置
	var drop_grid_pos = GridManager.world_to_grid(local_pos)
	
	# --- 核心修改结束 ---
	
	# 2. 核心判断逻辑
	if GridManager.is_inside_map(drop_grid_pos):
		# Case A: 鼠标在地图范围内
		if GridManager.can_place_unit(data, drop_grid_pos):
			# A1: 位置合法 -> 部署成功！
			_deploy_to_grid(drop_grid_pos)
		else:
			# A2: 位置重叠/非法 -> 弹回上一次的位置
			_revert_position()
	else:
		# Case B: 鼠标在地图范围外 -> 撤回备战区
		_return_to_bench()
	
# 辅助：部署到格子
func _deploy_to_grid(grid_pos: Vector2i):
	GridManager.place_unit(self, grid_pos)
	position = GridManager.grid_to_world(grid_pos)
	is_deployed = true
	stored_grid_pos = grid_pos # 记住这个新位置，下次手滑可以弹回来
	
	# 视觉反馈：恢复正常亮度
	modulate = Color(1, 1, 1, 1)

# 辅助：回备战区
func _return_to_bench():
	var tween = create_tween()
	tween.tween_property(self, "position", bench_position, 0.2)
	is_deployed = false
	
	# 视觉反馈：变暗一点，表示未激活
	modulate = Color(0.7, 0.7, 0.7, 1)

# 辅助：弹回上一次状态
func _revert_position():
	if is_deployed:
		# 如果本来就在格子里，只是挪窝失败了 -> 回原来的格子
		_deploy_to_grid(stored_grid_pos)
	else:
		# 如果本来在备战区，想上阵失败了 -> 回备战区
		_return_to_bench()
		
func update_bench_pos(new_pos: Vector2):
	# 1. 更新内部记录的“老家”坐标
	bench_position = new_pos
	# 2. 实际移动到新位置
	position = new_pos
	# 3. 既然回到了备战区，肯定就是未部署状态
	is_deployed = false
	# 4. 视觉反馈：变暗
	modulate = Color(0.7, 0.7, 0.7, 1)
