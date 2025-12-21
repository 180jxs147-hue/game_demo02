extends Node2D

## 战斗单位节点。
## 同一套 Unit 同时用于我方与敌方，通过 faction 区分行为：
## - FRIENDLY：消耗/产出民力，攻击敌方 boss（右侧血条）
## - ENEMY：不消耗民力，直接攻击我方阵线（左侧血条）
## 交互约定：
## - 拖拽部署仅允许 FRIENDLY 且战斗未开始
## - 部署后才允许进入战斗状态机（start_battle 会做锁定）

@export var data: UnitData
enum Faction { FRIENDLY, ENEMY }
@export var faction: Faction = Faction.FRIENDLY

var battle_manager: BattleManager
# 引用状态机节点
@onready var state_chart = $StateChart
@onready var timer = $Timer

# 动态属性
var current_cooldown: float
var current_hp: float
var visual_blocks: Array[ColorRect] = []
var _processed_death_ids: Dictionary = {}
var _last_stand_triggered: bool = false

# --- 拖拽相关变量 ---
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var drag_preview: Node2D = null # 拖拽时的指示器

# 引用新的 Label 节点
@onready var status_label = $StatusLabel # 记得在场景里改名
@onready var name_label = $NameLabel     # 新加的 Label
# var hp_bar: ColorRect # 血条 (已移除，改用 shader 表现)
var cooldown_bar: ColorRect # 冷却条

# --- 新增状态变量 ---
var is_deployed: bool = false      # 是否在军阵中
var bench_position: Vector2        # 备战区的坐标（老家）
var stored_grid_pos: Vector2i      # 上一次合法的格子坐标（用于手滑弹回）

# --- 生成控制 ---
var spawned_via_script: bool = false # 如果是代码生成的，默认不去尝试部署

var _is_hovered: bool = false # 内部状态：是否被鼠标悬停

func _ready():
	var node = self
	while node:
		if node is BattleManager:
			battle_manager = node
			break
		node = node.get_parent()
		
	if not data: return
	
	current_cooldown = data.cooldown
	current_hp = data.max_hp
	# 1. 记录初始位置作为"老家" (假设你在编辑器里把它们放在了格子外面)
	bench_position = position
	
	_build_visuals()
	
	# 2. 根据视觉包围盒调整 UI 位置
	var bounds = _calculate_visual_bounds()
	
	if name_label:
		name_label.text = data.name
		# 居中显示在包围盒内部上方
		var center_x = bounds.position.x + bounds.size.x / 2.0
		# 名字放在顶部内侧 (假设 GridSize 足够大)
		name_label.position = Vector2(center_x, bounds.position.y + 2)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 确保文字在最上层
		name_label.z_index = 20 
	
	if status_label:
		# 状态文字放在名字下方
		status_label.position = name_label.position + Vector2(0, 20)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.z_index = 20
	
	_create_cooldown_bar(bounds)
	# 初始化血量显示
	_update_health_visuals()
	
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
 
func _create_cooldown_bar(bounds: Rect2):
	# 创建一个简易冷却条 (位于底部)
	var bar_width = GameConst.GRID_SIZE - 10
	
	# 放在包围盒内部底部，水平居中
	var bottom_y = bounds.position.y + bounds.size.y
	var center_x = bounds.position.x + bounds.size.x / 2.0
	var start_x = center_x - bar_width / 2.0
	
	# 创建冷却条背景
	var cd_bg = ColorRect.new()
	cd_bg.size = Vector2(bar_width, 4.0)
	cd_bg.position = Vector2(start_x, bottom_y - 6) # 底部留2px
	cd_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	cd_bg.z_index = 20 # 提高层级
	add_child(cd_bg)
	
	cooldown_bar = ColorRect.new()
	cooldown_bar.size = cd_bg.size
	cooldown_bar.size.x = 0 # 初始为空
	cooldown_bar.color = Color(1, 1, 0, 1) # 黄色
	cd_bg.add_child(cooldown_bar)
	
	cooldown_bar.set_meta("max_width", bar_width)

func take_damage(amount: float):
	if not is_deployed: return # 备战区无敌
	if current_hp <= 0: return
	
	current_hp -= amount
	_update_health_visuals()
	
	# 受击闪烁
	modulate = Color(1, 0.5, 0.5)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	
	if current_hp <= 0:
		current_hp = 0
		_on_death()

func _update_health_visuals():
	if not data: return
	var bounds = _calculate_visual_bounds()
	var hp_percent = current_hp / data.max_hp
	
	# 计算全局截断点 (相对于 Unit 节点)
	# 假设从右向左扣血，即显示部分为 [min_x, min_x + width * percent]
	var total_width = bounds.size.x
	var visible_width = total_width * hp_percent
	var global_cutoff_x = bounds.position.x + visible_width
	
	for block in visual_blocks:
		# 计算该 Block 内部的 progress (0.0 - 1.0)
		# block.position 是相对于 Unit 的
		var block_start = block.position.x
		var block_end = block.position.x + block.size.x
		var progress = 0.0
		
		if global_cutoff_x >= block_end:
			progress = 1.0 # 完全显示
		elif global_cutoff_x <= block_start:
			progress = 0.0 # 完全淡出
		else:
			# 部分显示
			progress = (global_cutoff_x - block_start) / block.size.x
			
		# 更新 Shader 参数
		if block.material:
			block.material.set_shader_parameter("progress", progress)

func _on_death():
	# 触发死亡状态机
	$StateChart.send_event("die")

func _process(delta):
	if is_dragging or BattleManager.is_battle_started:
		# 更新冷却条
		if cooldown_bar and current_cooldown > 0:
			var max_w = cooldown_bar.get_meta("max_width", GameConst.GRID_SIZE - 10)
			if not timer.is_stopped():
				# 正在冷却中：显示进度 (0 -> 1)
				var progress = 1.0 - (timer.time_left / current_cooldown)
				cooldown_bar.size.x = max_w * progress
			else:
				# 冷却完毕/未开始：满条
				cooldown_bar.size.x = max_w
				
		# 拖拽中或战斗中，不检测悬停（或者你可以选择战斗中也显示）
		if _is_hovered:
			_is_hovered = false
			if battle_manager and battle_manager.has_method("hide_tooltip"):
				battle_manager.hide_tooltip()
		return

	# 检测鼠标悬停
	# 简单的检测逻辑：鼠标位置是否在任一 grid_shape 的矩形内
	var mouse_pos = get_global_mouse_position()
	var hovered = false
	
	if faction == Faction.FRIENDLY: # 只对我方单位生效
		for grid_pos in data.grid_shape:
			var part_pos = global_position + Vector2(grid_pos) * GameConst.GRID_SIZE
			# 注意：ColorRect 在 _build_visuals 里有 padding，但检测可以粗略一点
			var part_rect = Rect2(part_pos, Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE))
			if part_rect.has_point(mouse_pos):
				hovered = true
				break
	
	if hovered != _is_hovered:
		_is_hovered = hovered
		if battle_manager:
			if _is_hovered:
				if battle_manager.has_method("show_tooltip"):
					battle_manager.show_tooltip(data)
			else:
				if battle_manager.has_method("hide_tooltip"):
					battle_manager.hide_tooltip()

# --- 状态机逻辑 ---

# 状态 1: 进入冷却
func _on_cooldown_entered():
	# status_label.text = "CD..." # 移除文字
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
	
	# 释放格子占用
	GridManager.clear_unit(self)
	
	EventBus.unit_died.emit(self, global_position.x)

# --- 业务逻辑 ---

func _produce():
	if faction == Faction.ENEMY:
		return
	var manager = battle_manager
	if not manager:
		return
	var amount = absf(data.manpower_cost)
	manager.modify_manpower(amount)
	_pop_text("+%.1f" % amount)

func _attack():
	var manager = battle_manager
	if not manager:
		return
		
	# 特性: 医者 (medic) - 治疗我方
	if faction == Faction.FRIENDLY and "medic" in data.tags:
		# 治疗量 = 攻击力
		var heal = data.attack_damage
		manager.army_hp = min(manager.army_hp + heal, manager.max_army_hp)
		manager._update_ui() 
		_pop_text("Heal!")
		# 消耗民力
		manager.modify_manpower(-data.manpower_cost)
		return

	var dmg = data.attack_damage
	var target = manager.find_target_for(self)
	
	# --- 攻击表现优化 ---
	
	# 1. 冲撞动画
	var original_pos = position # 注意这里用的是局部 position (相对于 Container)
	# 为了防止 Tween 冲突，最好操作 visual_blocks 的父级或整体偏移
	# 这里简单起见，我们做一个 visual_blocks 的整体震动
	var punch_dir = Vector2.RIGHT if faction == Faction.FRIENDLY else Vector2.LEFT
	
	# 遍历移动所有方块
	for block in visual_blocks:
		var tw = create_tween()
		var start_p = block.position
		tw.tween_property(block, "position", start_p + punch_dir * 10, 0.05)
		tw.tween_property(block, "position", start_p, 0.1)
	
	# 2. 弹道连线 (如果距离较远)
	if target and is_instance_valid(target):
		_draw_attack_line(target.global_position)
	
	# --------------------
	
	# 特性: 神射手 (sniper) - 距离目标越远伤害越高
	if faction == Faction.FRIENDLY and "sniper" in data.tags:
		var dist = 0.0
		if target:
			dist = abs(global_position.x - target.global_position.x)
		else:
			# 如果打基地，假设距离是到屏幕边缘
			dist = abs(global_position.x - GameConst.BATTLE_FIELD_WIDTH)
			
		# 每 100 像素增加 10% 伤害
		var bonus = (dist / 100.0) * 0.1
		dmg *= (1.0 + bonus)

	if faction == Faction.FRIENDLY:
		manager.modify_manpower(-data.manpower_cost)
		
	if target:
		if target.has_method("take_damage"):
			target.take_damage(dmg)
			# _pop_text("ATK!") # 移除旧的飘字
	else:
		# 没有单位目标，攻击基地
		if faction == Faction.ENEMY:
			manager.deal_damage_to_army(dmg)
		else:
			manager.deal_damage_to_enemy(dmg)
		# _pop_text("Base!") # 移除旧的飘字

# 绘制简单的攻击连线
func _draw_attack_line(target_global_pos: Vector2):
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = Color(1, 1, 0, 0.8) # 黄色激光
	# 坐标需要转换到自己的局部坐标系下
	line.add_point(Vector2(GameConst.GRID_SIZE/2, GameConst.GRID_SIZE/2)) # 从自己中心
	line.add_point(to_local(target_global_pos) + Vector2(GameConst.GRID_SIZE/2, GameConst.GRID_SIZE/2))
	line.z_index = 20
	add_child(line)
	
	var tw = create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.1) # 0.1秒消失
	tw.tween_callback(line.queue_free)

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
			_trigger_last_stand()
			state_chart.send_event("die")
	else:
		if global_position.x < line_x:
			_trigger_last_stand()
			state_chart.send_event("die")

func _trigger_last_stand():
	if _last_stand_triggered: return
	_last_stand_triggered = true
	
	if "last_stand" in data.tags and faction == Faction.FRIENDLY:
		if battle_manager:
			# 造成 300% 攻击力的伤害
			var dmg = data.attack_damage * 3.0
			battle_manager.deal_damage_to_enemy(dmg)
			_pop_text("BOOM!")

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

# 辅助：构建视觉方块
func _build_visuals():
	# 定义 Shader 代码
	var shader_code = """
	shader_type canvas_item;
	uniform float progress : hint_range(0.0, 1.0) = 1.0;
	
	void fragment() {
		// UV.x (0..1)
		// 如果 UV.x > progress，则视为受伤部分
		// 假设从右向左扣血，即 progress 左边是血，右边是空的
		if (UV.x > progress) {
			COLOR.a *= 0.3; // 变透明
			COLOR.rgb *= 0.5; // 变暗
		}
	}
	"""
	var shader = Shader.new()
	shader.code = shader_code
	
	for grid_pos in data.grid_shape:
		var block = ColorRect.new()
		var size_val = GameConst.GRID_SIZE - GameConst.GRID_PADDING
		
		block.size = Vector2(size_val, size_val)
		block.color = data.color
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var offset = Vector2(grid_pos) * GameConst.GRID_SIZE
		var padding = Vector2(GameConst.GRID_PADDING, GameConst.GRID_PADDING) / 2.0
		block.position = offset + padding
		
		# 创建独立的 ShaderMaterial 实例
		var mat = ShaderMaterial.new()
		mat.shader = shader
		block.material = mat
		
		add_child(block)
		visual_blocks.append(block)

# 辅助：计算视觉包围盒
func _calculate_visual_bounds() -> Rect2:
	if not data or data.grid_shape.is_empty():
		return Rect2(0, 0, GameConst.GRID_SIZE, GameConst.GRID_SIZE)
		
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for grid_pos in data.grid_shape:
		if grid_pos.x < min_x: min_x = grid_pos.x
		if grid_pos.y < min_y: min_y = grid_pos.y
		if grid_pos.x > max_x: max_x = grid_pos.x
		if grid_pos.y > max_y: max_y = grid_pos.y
		
	var width_grids = max_x - min_x + 1
	var height_grids = max_y - min_y + 1
	
	var bounds = Rect2()
	bounds.position = Vector2(min_x, min_y) * GameConst.GRID_SIZE
	bounds.size = Vector2(width_grids, height_grids) * GameConst.GRID_SIZE
	
	return bounds

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
		# 更新指示器位置
		_update_drag_preview()

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
		
		# 创建拖拽指示器
		_create_drag_preview()
		
		# 拖起时，如果在格子里，要清除占用
		if is_deployed:
			GridManager.clear_unit(self)

func _end_drag():
	is_dragging = false
	z_index = 0
	
	# 清除指示器
	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null
	
	# --- 核心修改开始 ---
	
	# 优化判定：使用“锚点格子的中心”来判定落点，而不是左上角
	# 这样用户只要把卡牌的主体部分拖到格子里，就能吸附成功，不再需要精准对齐左上角
	var center_offset = Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE) / 2.0
	var mouse_world_pos = global_position + center_offset
	
	# 2. 将世界坐标转换为 "UnitsContainer" 内部的本地坐标
	var local_pos = get_parent().to_local(mouse_world_pos)
	
	# 3. 使用本地坐标去计算它在第几个格子
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

# --- 拖拽指示器逻辑 ---

func _create_drag_preview():
	if drag_preview:
		drag_preview.queue_free()
	
	drag_preview = Node2D.new()
	drag_preview.z_index = 90 # 比拖拽单位(100)低，比其他单位高
	# 添加到 UnitsContainer (父节点)
	get_parent().add_child(drag_preview)
	
	# 根据形状生成预览块
	for grid_pos in data.grid_shape:
		var rect = ColorRect.new()
		# 稍微缩小一点，产生间隔感
		var size_val = GameConst.GRID_SIZE - 4
		rect.size = Vector2(size_val, size_val)
		# 初始位置是相对于 drag_preview 的
		rect.position = Vector2(grid_pos) * GameConst.GRID_SIZE + Vector2(2, 2)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_preview.add_child(rect)
		
	_update_drag_preview()

func _update_drag_preview():
	if not drag_preview: return
	
	# 1. 计算目标格子 (逻辑与 _end_drag 保持一致)
	var center_offset = Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE) / 2.0
	var mouse_world_pos = global_position + center_offset
	var local_pos = get_parent().to_local(mouse_world_pos)
	var target_grid_pos = GridManager.world_to_grid(local_pos)
	
	# 2. 移动指示器到吸附位置
	# 注意：preview 是 UnitsContainer 的子节点，所以可以直接用 GridManager.grid_to_world 的结果(如果是基于Container的)
	# GridManager.grid_to_world 返回的是 local 坐标 (相对于 Container)
	drag_preview.position = GridManager.grid_to_world(target_grid_pos)
	
	# 3. 检查合法性并变色
	var is_valid = false
	if GridManager.is_inside_map(target_grid_pos):
		# 传入 data 和 anchor，检查所有格子是否空闲
		if GridManager.can_place_unit(data, target_grid_pos):
			is_valid = true
			
	var color = Color(0, 1, 0, 0.5) if is_valid else Color(1, 0, 0, 0.5)
	
	for child in drag_preview.get_children():
		if child is ColorRect:
			child.color = color
