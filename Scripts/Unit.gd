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
var buffer_hp: float # 缓冲血量 (用于表现扣血延迟)
var _buffer_decay_timer: float = 0.0 # 缓冲条停留计时器

var current_attack_damage: float # 实际攻击力 (含加成)
var bonus_max_hp: float = 0.0
var bonus_attack_damage: float = 0.0
var bonus_cooldown_speed: float = 0.0
var bonus_cooldown_flat: float = 0.0

var visual_blocks: Array[ColorRect] = []
var _processed_death_ids: Dictionary = {}
var _last_stand_triggered: bool = false
var current_charge_stacks: int = 0 # 剩余冲锋次数
var active_status_effects: Dictionary = {} # type -> {duration, value, tick_timer}

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

var in_hand: bool = false

var _cached_tag_defs: Array[TagDefinition] = []

func _update_tag_defs():
	_cached_tag_defs.clear()
	if not data: return
	if not TagManager: return
	
	# 1. Load explicit tags
	if data.tags:
		for t in data.tags:
			var def = TagManager.get_tag_info(t)
			if def:
				_cached_tag_defs.append(def)

	# 2. Auto-inject charge tag if needed (for backward compatibility)
	if "charge_count" in data and data.charge_count > 0:
		var has_charge = false
		for t in data.tags:
			if t == "charge":
				has_charge = true
				break
		
		if not has_charge:
			var def = TagManager.get_tag_info("charge")
			if def:
				_cached_tag_defs.append(def)
				
	# 3. 蛾贼游骑的 "charge" 标签在 tags 里，但 data 也有 charge_count
	# 上面的逻辑是如果 tag 有 charge 就加载了，如果没有但 count > 0 才补救
	# 蛾贼游骑 tags=["sniper", "charge"], charge_count=1
	# 所以 TagCharge 会被加载一次。
	# 问题在于 TagCharge 需要 unit.current_charge_stacks 被初始化
	# 这需要在 battle_started 时调用 on_battle_start

func set_bench_hidden(hidden: bool):
	for block in visual_blocks:
		block.visible = not hidden
	if name_label:
		name_label.visible = not hidden
	if status_label:
		status_label.visible = not hidden
	if cooldown_bar:
		cooldown_bar.get_parent().visible = not hidden
	set_process_unhandled_input(not hidden)

func begin_drag_from_ui():
	if BattleManager.is_battle_started:
		return
	if faction != Faction.FRIENDLY:
		return
	if is_deployed:
		return
	if is_dragging:
		return
	set_bench_hidden(false)
	in_hand = true
	var center_offset = Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE) / 2.0
	global_position = get_global_mouse_position() - center_offset
	drag_offset = center_offset
	is_dragging = true
	z_index = 100
	_create_drag_preview()

func get_max_hp() -> float:
	return data.max_hp + bonus_max_hp

func _recalculate_stats():
	if not data: return
	current_attack_damage = data.attack_damage + bonus_attack_damage
	# 冷却计算: (基础 - 固定减免) / (1 + 速度加成)
	var base_cd = maxf(0.1, data.cooldown - bonus_cooldown_flat)
	current_cooldown = base_cd / (1.0 + bonus_cooldown_speed)

func apply_synergy_bonus(type: String, value: float):
	match type:
		"max_hp":
			bonus_max_hp += value
			# 如果战斗还没开始，顺便把血回满
			if not BattleManager.is_battle_started:
				current_hp += value
		"attack_damage":
			bonus_attack_damage += value
		"cooldown_speed":
			bonus_cooldown_speed += value
		"cooldown_flat":
			bonus_cooldown_flat += value
	_recalculate_stats()

func reset_stats():
	bonus_max_hp = 0.0
	bonus_attack_damage = 0.0
	bonus_cooldown_speed = 0.0
	bonus_cooldown_flat = 0.0
	_recalculate_stats()
	if not BattleManager.is_battle_started:
		current_hp = get_max_hp()
		buffer_hp = current_hp
		
		# Tag init
		for tag in _cached_tag_defs:
			tag.on_battle_start(self)
			
		# Fallback/Default for charge if tag is missing but data has it?
		# But we are unifying, so assume tag exists if "charge" is in tags.
		# If charge is NOT in tags but charge_count > 0, we might have an issue.
		# The previous code checked `if data and "charge_count" in data`.
		# We should ensure "charge" tag is added to unit if charge_count > 0? 
		# Or just rely on the "charge" tag being present in data.tags.
		# User said "冲锋也应该被放在类似牺牲一类的标签中".
		# So we assume units with charge_count also have "charge" tag.
		# If not, we should probably add it in UnitData or ensure it's there.
		
		# For now, let's keep the hardcoded fallback IF the tag is missing?
		# No, the goal is to unify. If the tag is missing, the effect is missing.
		# But wait, I added "charge" tag definition, but did I add "charge" string to the unit's tags list?
		# I haven't modified the UnitData resources to add "charge" to `tags` array yet!
		# I need to do that.
		
		# Let's keep the hardcoded logic ONLY if tag logic fails?
		# No, let's rely on tags. I will update UnitData files later.
		pass

func _ready():
	var node = self
	while node:
		if node is BattleManager:
			battle_manager = node
			break
		node = node.get_parent()
		
	if not data: return
	
	_update_tag_defs() # Load tags
	
	_recalculate_stats()
	current_hp = get_max_hp()
	buffer_hp = current_hp # 初始化缓冲血量
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

func take_damage_visual():
	# 1. Flash (Shader + Modulate)
	# Modulate for overall brightness (HDR)
	modulate = Color(2.0, 2.0, 2.0)
	var tw_mod = create_tween()
	tw_mod.tween_property(self, "modulate", Color.WHITE, 0.1).set_ease(Tween.EASE_OUT)
	
	# Shader flash for blocks
	for block in visual_blocks:
		if block.material is ShaderMaterial:
			var tw_s = block.create_tween()
			block.material.set_shader_parameter("flash_intensity", 0.8)
			tw_s.tween_method(func(v): if is_instance_valid(block): block.material.set_shader_parameter("flash_intensity", v), 0.8, 0.0, 0.15)
			
	# 2. Shake (Visual Blocks)
	# If Faction.FRIENDLY (me, left side) gets hit -> push Left (negative x)
	# If Faction.ENEMY (enemy, right side) gets hit -> push Right (positive x)
	var knockback_dir = Vector2.LEFT if faction == Faction.FRIENDLY else Vector2.RIGHT
	
	for block in visual_blocks:
		var start_p = block.position
		var tw_shake = block.create_tween()
		# Knockback slightly
		tw_shake.tween_property(block, "position", start_p + knockback_dir * 5.0, 0.05).set_trans(Tween.TRANS_QUART)
		# Return
		tw_shake.tween_property(block, "position", start_p, 0.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func take_damage(amount: float):
	if data and data.unit_class == "equipment": return
	if not BattleManager.is_battle_started: return # 战斗未开始或已结束，无敌
	if not is_deployed: return # 备战区无敌
	if current_hp <= 0: return
	
	# 应用防御减免
	var def = 0.0
	if data:
		def = data.defense
	
	var final_damage = max(1.0, amount - def)
	
	if BattleManager.instance:
		var u_name = data.name if data else name
		var msg = "%s 受到 %.1f 伤害" % [u_name, final_damage]
		if def > 0:
			msg += " (防御减免 %.1f)" % def
		# 我方受伤显示橙色，敌方受伤显示白色
		var log_color = Color.ORANGE if faction == Faction.FRIENDLY else Color.WHITE
		BattleManager.instance.log_message(msg, log_color)
	
	current_hp -= final_damage
	_update_health_visuals()
	
	# 视觉反馈：Unit 自身震动与闪白
	take_damage_visual()
	
	# 视觉反馈：屏幕震动与飘字
	if battle_manager:
		if battle_manager.has_method("trigger_shake"):
			# 根据伤害比例或阈值决定震动
			# 阈值：伤害 >= 5.0 触发震动
			if final_damage >= 5.0:
				var shake_intensity = clamp(final_damage / get_max_hp() * 20.0, 5.0, 15.0)
				battle_manager.trigger_shake(shake_intensity)
		
		if battle_manager.has_method("spawn_floating_text"):
			var txt = "-%.0f" % final_damage
			if def > 0:
				txt = "-%.0f (%s)" % [final_damage, "抵抗"]
			battle_manager.spawn_floating_text(global_position, txt, Color(1, 0.2, 0.2)) # 鲜红
			
			# Spawn hit particles (using unit's main color or blood color)
			var particle_color = Color(0.8, 0.1, 0.1) # Blood red
			if data and data.unit_class == "mechanism":
				particle_color = Color(0.6, 0.6, 0.6) # Metal sparks
			battle_manager.spawn_hit_effect(global_position, particle_color)

	if current_hp <= 0:
		current_hp = 0
		_on_death()

func _update_health_visuals():
	if not data: return
	var bounds = _calculate_visual_bounds()
	var hp_percent = current_hp / get_max_hp()
	var buffer_percent = buffer_hp / get_max_hp()
	
	# 计算全局截断点 (相对于 Unit 节点)
	# 假设从右向左扣血，即显示部分为 [min_x, min_x + width * percent]
	var total_width = bounds.size.x
	var visible_width = total_width * hp_percent
	var buffer_width = total_width * buffer_percent
	
	var global_cutoff_x = bounds.position.x + visible_width
	var buffer_cutoff_x = bounds.position.x + buffer_width
	
	for block in visual_blocks:
		# 计算该 Block 内部的 progress (0.0 - 1.0)
		# block.position 是相对于 Unit 的
		var block_start = block.position.x
		var block_end = block.position.x + block.size.x
		var progress = 0.0
		var buffer_prog = 0.0
		
		# 计算实际血量 progress
		if global_cutoff_x >= block_end:
			progress = 1.0 # 完全显示
		elif global_cutoff_x <= block_start:
			progress = 0.0 # 完全淡出
		else:
			# 部分显示
			progress = (global_cutoff_x - block_start) / block.size.x
		
		# 计算缓冲血量 buffer_prog
		if buffer_cutoff_x >= block_end:
			buffer_prog = 1.0
		elif buffer_cutoff_x <= block_start:
			buffer_prog = 0.0
		else:
			buffer_prog = (buffer_cutoff_x - block_start) / block.size.x
			
		# 更新 Shader 参数
		if block.material:
			block.material.set_shader_parameter("progress", progress)
			block.material.set_shader_parameter("buffer_progress", buffer_prog)

func _on_death():
	# 触发死亡状态机
	current_hp = 0 # 确保数值为0
	
	if BattleManager.instance:
		var u_name = data.name if data else name
		BattleManager.instance.log_message("%s 阵亡" % u_name, Color.GRAY)
	
	# 受伤逻辑：被击败的单位进入受伤状态
	if faction == Faction.FRIENDLY and data:
		data.is_injured = true
		
	$StateChart.send_event("die")

func _process(_delta):
	if is_dragging and in_hand:
		global_position = get_global_mouse_position() - drag_offset
		_update_drag_preview()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_end_drag()
		return
	
	# --- 血条缓冲逻辑 ---
	if buffer_hp > current_hp:
		if _buffer_decay_timer > 0:
			_buffer_decay_timer -= _delta
		else:
			# 动态调整下降速度：血量差越大降得越快，或者固定速度
			var decay_speed = max((buffer_hp - current_hp) * 2.0, get_max_hp() * 0.2)
			buffer_hp = move_toward(buffer_hp, current_hp, decay_speed * _delta)
			_update_health_visuals()
	elif buffer_hp < current_hp:
		# 如果因为治疗导致血量超过缓冲，瞬间跟上
		buffer_hp = current_hp
		_update_health_visuals()
	# --------------------
	
	_process_status_effects(_delta)

	if BattleManager.is_battle_started:
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
				
	if is_dragging:
		# 拖拽中，不检测悬停
		if _is_hovered:
			_is_hovered = false
			if battle_manager and battle_manager.has_method("hide_tooltip"):
				battle_manager.hide_tooltip()
		return

	# 检测鼠标悬停
	# 简单的检测逻辑：鼠标位置是否在任一 grid_shape 的矩形内
	var mouse_pos = get_global_mouse_position()
	var hovered = false
	
	if data and data.grid_shape:
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
					battle_manager.show_tooltip(data, self)
			else:
				if battle_manager.has_method("hide_tooltip"):
					battle_manager.hide_tooltip()

# --- 状态机逻辑 ---

func apply_status_effect(type: String, duration: float, value: float = 0.0):
	if active_status_effects.has(type):
		# 刷新持续时间
		active_status_effects[type].duration = max(active_status_effects[type].duration, duration)
		active_status_effects[type].value = max(active_status_effects[type].value, value)
	else:
		active_status_effects[type] = {
			"duration": duration,
			"value": value,
			"tick_timer": 0.0
		}
	_update_status_visuals()

func _process_status_effects(delta: float):
	if not BattleManager.is_battle_started: return
	if active_status_effects.is_empty(): return
	
	var keys_to_remove = []
	for type in active_status_effects:
		var effect = active_status_effects[type]
		effect.duration -= delta
		
		# DoT 逻辑
		if type == "poison" or type == "burn":
			effect.tick_timer += delta
			if effect.tick_timer >= 1.0:
				effect.tick_timer -= 1.0
				# 造成伤害，且无视防御 (DoT通常穿透防御)
				take_damage(effect.value)
				var txt = "中毒" if type == "poison" else "灼烧"
				var col = Color.PURPLE if type == "poison" else Color.ORANGE_RED
				_pop_text(txt, col)
		
		if effect.duration <= 0:
			keys_to_remove.append(type)
			
	for k in keys_to_remove:
		active_status_effects.erase(k)
		_update_status_visuals()
		
		# 如果眩晕结束，立即检查状态
		if k == "stun" and state_chart:
			# 如果当前在 Ready 状态，尝试触发 check
			# 但无法直接判断当前状态，只能发信号或依靠 Ready 的重试机制
			# 上面的 _check_condition 已经有重试机制了，所以这里不用做特殊处理
			pass

func _update_status_visuals():
	if active_status_effects.has("stun"):
		modulate = Color(0.5, 0.5, 0.5) # 灰色
	elif active_status_effects.has("poison"):
		modulate = Color(0.5, 1.0, 0.5) # 绿色
	elif active_status_effects.has("burn"):
		modulate = Color(1.0, 0.5, 0.5) # 红色
	else:
		# 恢复正常颜色
		if not is_deployed:
			modulate = Color(0.7, 0.7, 0.7, 1)
		else:
			modulate = Color.WHITE

# 状态 1: 进入冷却
func _on_cooldown_entered():
	if not BattleManager.is_battle_started:
		return
		
	# status_label.text = "CD..." # 移除文字
	timer.start(current_cooldown)

# Timer 跑完了 -> 告诉状态机 "CD结束了"
func _on_timer_timeout():
	if not BattleManager.is_battle_started:
		return
	state_chart.send_event("cd_finished")

# 状态 2: 准备就绪 (判定民力)
func _on_ready_entered():
	if not BattleManager.is_battle_started:
		return
	_check_condition()

func _check_condition():
	if not BattleManager.is_battle_started:
		return
	
	if active_status_effects.has("stun"):
		status_label.text = "眩晕"
		# 眩晕时不行动，且不重试（等待眩晕结束，或者让眩晕结束时手动触发？）
		# 简单做法：这里 return，依靠 update loop 或者 timer 再次触发？
		# 状态机在 Ready 状态如果不 act 也不 transition，就会卡住。
		# 我们可以每 0.5s check 一次
		get_tree().create_tree_timer(0.5).timeout.connect(_check_condition)
		return

	if not is_deployed:
		return
		
	# A. 产出类单位
	if data.manpower_cost < 0:
		state_chart.send_event("act")
		return

	# B. 消耗类单位
	var manager = battle_manager
	var can_act = false
	
	if faction == Faction.FRIENDLY:
		if manager.current_manpower >= data.manpower_cost:
			can_act = true
	else:
		# 敌人也受民力限制
		if manager.has_method("modify_enemy_manpower"):
			if manager.enemy_current_manpower >= data.manpower_cost:
				can_act = true
		else:
			can_act = true # Fallback
			
	if can_act:
		if BattleManager.is_battle_started:
			state_chart.send_event("act")
	else:
		# 缺气，等待 0.5s 后重试 (停留在 Ready 状态)
		status_label.text = "缺气"
		if BattleManager.is_battle_started:
			get_tree().create_timer(0.5).timeout.connect(_check_condition)

# 状态 3: 执行动作
func _on_action_entered():
	if not BattleManager.is_battle_started:
		# 如果动作还没开始就结束了，尝试回到冷却或直接停止
		return
		
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
	var manager = battle_manager
	if not manager:
		return
	var amount = absf(data.manpower_cost)
	
	if faction == Faction.FRIENDLY:
		manager.modify_manpower(amount)
	else:
		if manager.has_method("modify_enemy_manpower"):
			manager.modify_enemy_manpower(amount)
			
	_pop_text("+%.1f" % amount)

func _attack():
	if data and data.unit_class == "equipment": return
	var manager = battle_manager
	if not manager: return
	
	# 0. 检查射程/攻击条件
	if manager.has_method("can_unit_attack"):
		if not manager.can_unit_attack(self):
			return # 无法攻击（被阻挡），跳过本次攻击
		
	# 1. 攻击前置钩子 (如医者治疗)
	for tag in _cached_tag_defs:
		if tag.on_attack_start(self, manager):
			return # 已接管攻击行为
	
	var dmg = current_attack_damage
	var target = manager.find_target_for(self)
	
	# 2. 伤害修正钩子 (如狙击、冲锋)
	for tag in _cached_tag_defs:
		dmg = tag.modify_damage(self, target, dmg)

	if faction == Faction.FRIENDLY:
		manager.modify_manpower(-data.manpower_cost)
	else:
		if manager.has_method("modify_enemy_manpower"):
			manager.modify_enemy_manpower(-data.manpower_cost)
	
	# --- 攻击表现优化 ---
	var punch_dir = Vector2.RIGHT if faction == Faction.FRIENDLY else Vector2.LEFT
	var is_ranged = false
	if data:
		if data.unit_class in ["archer", "support", "siege", "mage"]:
			is_ranged = true
		elif data.attack_range > 1:
			is_ranged = true
	
	# 1. 蓄力提示 (Pre-attack Cue)
	# 让单位稍微后退一点
	for block in visual_blocks:
		var start_p = block.position
		var tw = block.create_tween()
		tw.tween_property(block, "position", start_p - punch_dir * 5.0, 0.15).set_trans(Tween.TRANS_SINE)
	
	# 等待蓄力完成
	await get_tree().create_timer(0.15).timeout
	if not is_instance_valid(self): return

	# 2. 执行攻击动画与逻辑
	if is_ranged:
		_perform_ranged_attack(target, dmg, manager, punch_dir)
	else:
		_perform_melee_attack(target, dmg, manager, punch_dir)

func _perform_melee_attack(target, dmg, manager, punch_dir):
	# 强化冲锋 (Lunge)
	var lunge_dist = GameConst.GRID_SIZE * 0.5 # 约 30-40 像素
	
	if visual_blocks.is_empty():
		_apply_damage_logic(target, dmg, manager)
		return

	# --- 刀光特效 (Infantry) ---
	if data and data.unit_class == "infantry":
		# 在冲锋顶点或稍微提前播放特效
		# 目标位置：如果有 target，则是 target 位置；否则是前方
		var effect_pos = global_position + punch_dir * GameConst.GRID_SIZE
		if target and is_instance_valid(target):
			effect_pos = target.global_position + Vector2(GameConst.GRID_SIZE/2, GameConst.GRID_SIZE/2)
		
		# 稍微延迟一点播放，配合冲锋动作
		get_tree().create_timer(0.1).timeout.connect(func():
			if is_instance_valid(self):
				_play_slash_effect(effect_pos)
		)
	# -------------------------

	for i in range(visual_blocks.size()):
		var block = visual_blocks[i]
		var start_p = block.position # 当前是蓄力后的位置
		# 恢复原位并冲锋：原位是 start_p + 5.0
		# 目标位是 (start_p + 5.0) + punch_dir * lunge_dist
		var original_pos = start_p + punch_dir * 5.0
		var target_pos = original_pos + punch_dir * lunge_dist
		
		var tw = block.create_tween()
		# 快出 (Fast Out)
		tw.tween_property(block, "position", target_pos, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		# 在冲锋顶点造成伤害
		if i == 0:
			tw.tween_callback(func(): _apply_damage_logic(target, dmg, manager))
			
		# 慢回 (Slow Return)
		tw.tween_property(block, "position", original_pos, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _perform_ranged_attack(target, dmg, manager, punch_dir):
	# 先让身体恢复原位
	for block in visual_blocks:
		var start_p = block.position
		var original_pos = start_p + punch_dir * 5.0
		var tw = block.create_tween()
		tw.tween_property(block, "position", original_pos, 0.1)
		
	# 某些特殊兵种使用连线 (如 Support / Mage 激光)
	# 这里暂时统一用投射物，如果是 Support 且需要连线可自行判断
	
	# 创建投射物 (Projectile)
	var proj = null
	
	if data and data.unit_class == "archer":
		proj = _create_arrow_visual()
	else:
		proj = ColorRect.new()
		proj.size = Vector2(12, 4)
		proj.color = Color(1, 1, 0.5) # 淡黄色
		proj.pivot_offset = Vector2(6, 2)
	
	proj.z_index = 20 # 确保在最上层
	
	# 添加到世界节点 (避免随单位移动，且不能添加到 UnitsContainer 以免干扰索敌)
	if manager:
		manager.add_child(proj)
	else:
		get_parent().add_sibling(proj) # 备用方案
	
	proj.global_position = global_position + Vector2(GameConst.GRID_SIZE/2, GameConst.GRID_SIZE/2)
	
	var target_pos = Vector2.ZERO
	if target and is_instance_valid(target):
		target_pos = target.global_position + Vector2(GameConst.GRID_SIZE/2, GameConst.GRID_SIZE/2)
	else:
		# 攻击基地/无目标：朝前方飞一段距离
		target_pos = proj.global_position + punch_dir * 300.0
	
	proj.rotation = (target_pos - proj.global_position).angle()
	
	var dist = proj.global_position.distance_to(target_pos)
	var speed = 900.0
	var duration = clamp(dist / speed, 0.2, 0.6)
	
	var tw_p = proj.create_tween()
	tw_p.tween_property(proj, "global_position", target_pos, duration).set_trans(Tween.TRANS_LINEAR)
	tw_p.tween_callback(func():
		if is_instance_valid(proj): proj.queue_free()
		# 击中回调：伤害延迟 (Impact Delay)
		_apply_damage_logic(target, dmg, manager)
	)

func _create_arrow_visual() -> Node2D:
	var arrow = Node2D.new()
	
	# 绘制箭头
	var poly = Polygon2D.new()
	# 简单的箭头形状 ->
	poly.polygon = PackedVector2Array([
		Vector2(-10, 0), Vector2(-2, -4), Vector2(10, 0), Vector2(-2, 4)
	])
	poly.color = Color(0.9, 0.9, 0.9) # 银白色箭头
	arrow.add_child(poly)
	
	# 箭杆
	var line = Line2D.new()
	line.points = PackedVector2Array([Vector2(-15, 0), Vector2(5, 0)])
	line.width = 2.0
	line.default_color = Color(0.4, 0.25, 0.1) # 木色
	arrow.add_child(line)
	
	# 箭羽
	var fletch = Line2D.new()
	fletch.points = PackedVector2Array([Vector2(-15, -3), Vector2(-12, 0), Vector2(-15, 3)])
	fletch.width = 1.5
	fletch.default_color = Color(0.8, 0.2, 0.2) # 红色箭羽
	arrow.add_child(fletch)
	
	return arrow

func _play_slash_effect(pos: Vector2):
	if not BattleManager.instance: return
	var parent = BattleManager.instance.get_node_or_null("Battlefield")
	if not parent: parent = self
	
	var slash = Line2D.new()
	slash.width = 0
	# 创建一个简单的“月牙”形状
	var points = []
	for i in range(10):
		var t = i / 9.0
		var angle = deg_to_rad(-60 + 120 * t) # -60 to +60
		var radius = 35.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	slash.points = PackedVector2Array(points)
	
	# 渐变宽度
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.5, 5.0))
	curve.add_point(Vector2(1, 0))
	slash.width_curve = curve
	
	slash.default_color = Color(1.2, 1.2, 1.5, 1.0) # 亮蓝白 (HDR)
	slash.z_index = 25
	
	parent.add_child(slash)
	slash.global_position = pos
	slash.rotation = randf_range(0, PI*2) # 随机角度
	
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(slash, "scale", Vector2(1.5, 1.5), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(slash, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(slash.queue_free)

func _apply_damage_logic(target, dmg, manager):
	if target and is_instance_valid(target):
		if BattleManager.instance:
			var u_name = data.name if data else name
			var t_name = target.data.name if (target.get("data") and target.data) else target.name
			BattleManager.instance.log_message("%s 攻击 %s" % [u_name, t_name], Color.LIGHT_BLUE)

		if target.has_method("take_damage"):
			target.take_damage(dmg)
	else:
		# 没有单位目标，攻击基地
		var u_name = data.name if data else name
		if faction == Faction.ENEMY:
			if BattleManager.instance:
				# 敌人攻击我方 -> 攻击我方基地
				BattleManager.instance.log_message("%s 攻击我方基地" % u_name, Color.RED)
			manager.deal_damage_to_army(dmg)
		else:
			if BattleManager.instance:
				# 我方攻击敌人 -> 攻击敌方基地
				BattleManager.instance.log_message("%s 攻击敌方基地" % u_name, Color.GREEN)
			manager.deal_damage_to_enemy(dmg)
			
	# 3. 攻击后置钩子 (如扣除冲锋层数)
	for tag in _cached_tag_defs:
		tag.on_post_attack(self, target)

# 绘制更明显的攻击连线 (Better Tracers)
func _draw_attack_line(target_global_pos: Vector2):
	var line = Line2D.new()
	line.width = 4.0 # 增加宽度
	line.default_color = Color(1, 0.8, 0.2, 0.9) # 亮金色
	# 坐标需要转换到自己的局部坐标系下
	line.add_point(Vector2(GameConst.GRID_SIZE/2, GameConst.GRID_SIZE/2)) # 从自己中心
	line.add_point(to_local(target_global_pos) + Vector2(GameConst.GRID_SIZE/2, GameConst.GRID_SIZE/2))
	line.z_index = 20
	add_child(line)
	
	var tw = create_tween()
	# 延长持续时间并添加淡出
	tw.tween_property(line, "width", 0.0, 0.4).set_trans(Tween.TRANS_SINE) # 慢慢变细
	tw.parallel().tween_property(line, "modulate:a", 0.0, 0.4) # 慢慢消失
	tw.tween_callback(line.queue_free)

# --- 外部调用与辅助函数 (之前缺失的部分) ---

# --- 修改 1: 战斗相关函数加锁 ---
# 只有部署了的单位才准打架、挨打

func start_battle():
	if not is_deployed: return # <--- 加锁
	
	# 初始化 Tag 状态
	for tag in _cached_tag_defs:
		if tag.has_method("on_battle_start"):
			tag.on_battle_start(self)
			
	state_chart.send_event("battle_started")

func reset_state():
	state_chart.send_event("reset")
	timer.stop()
	reset_stats()
	current_hp = get_max_hp()
	modulate = Color.WHITE
	_update_health_visuals()
	if cooldown_bar:
		var max_w = cooldown_bar.get_meta("max_width", GameConst.GRID_SIZE - 10)
		cooldown_bar.size.x = max_w


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
			current_hp = 0 # 确保数值为0
			state_chart.send_event("die")
	else:
		if global_position.x < line_x:
			_trigger_last_stand()
			current_hp = 0 # 确保数值为0
			state_chart.send_event("die")

func _trigger_last_stand():
	if _last_stand_triggered: return
	_last_stand_triggered = true
	
	# Tag Hooks
	for tag in _cached_tag_defs:
		tag.on_death(self, battle_manager)

func heal(amount: float):
	if current_hp <= 0: return
	
	if BattleManager.instance:
		var u_name = data.name if data else name
		BattleManager.instance.log_message("%s 恢复了 %.1f 生命" % [u_name, amount], Color.GREEN)
	
	current_hp = min(current_hp + amount, get_max_hp())
	_update_health_visuals()
	
	# 治疗特效与飘字
	if battle_manager and battle_manager.has_method("spawn_floating_text"):
		battle_manager.spawn_floating_text(global_position, "+%.0f" % amount, Color.GREEN)

	var old_mod = modulate
	modulate = Color(0.5, 2.0, 0.5) # HDR 绿
	var t = create_tween()
	t.tween_property(self, "modulate", old_mod, 0.2)

# 皮洛士机制
func _on_ally_died(unit, _pos):
	if unit == self:
		return
	var id = unit.get_instance_id()
	if _processed_death_ids.has(id):
		return
	_processed_death_ids[id] = true
	
	# Tag Hooks
	for tag in _cached_tag_defs:
		tag.on_ally_died(self, unit)

# 辅助：构建视觉方块
func _build_visuals():
	# 先计算包围盒，用于纹理映射
	var bounds = _calculate_visual_bounds()
	var min_x := 0
	var min_y := 0
	var width_grids := 1
	var height_grids := 1
	if data and not data.grid_shape.is_empty():
		min_x = int(data.grid_shape[0].x)
		min_y = int(data.grid_shape[0].y)
		var max_x := min_x
		var max_y := min_y
		for p in data.grid_shape:
			min_x = min(min_x, int(p.x))
			min_y = min(min_y, int(p.y))
			max_x = max(max_x, int(p.x))
			max_y = max(max_y, int(p.y))
		width_grids = max_x - min_x + 1
		height_grids = max_y - min_y + 1
	var base_color := data.color
	if data and "civilization" in data:
		base_color = _get_civ_color(String(data.civilization).to_lower(), data.color)
	var crop_uv_pos := Vector2(0.0, 0.0)
	var crop_uv_size := Vector2(1.0, 1.0)
	if data and data.icon:
		var tw := float(data.icon.get_width())
		var th := float(data.icon.get_height())
		if tw > 0.0 and th > 0.0:
			var icon_aspect: float = tw / th
			var target_aspect: float = 1.0 # Target is always a single square block
			if icon_aspect > target_aspect:
				var sub_w := target_aspect / icon_aspect
				crop_uv_pos.x = (1.0 - sub_w) * 0.5
				crop_uv_size.x = sub_w
			elif icon_aspect < target_aspect:
				var sub_h := icon_aspect / target_aspect
				crop_uv_pos.y = (1.0 - sub_h) * 0.5
				crop_uv_size.y = sub_h

	# 定义 Shader 代码
	var shader_code = """
	shader_type canvas_item;
	uniform float progress : hint_range(0.0, 1.0) = 1.0;
	uniform float buffer_progress : hint_range(0.0, 1.0) = 1.0;
	uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
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
			
			// 如果图片有透明度，混合一下背景色? 
			// 暂时直接使用图片颜色，但保留 alpha 混合
			// 如果希望未填充区域显示底色：
			// c = mix(main_color, c, c.a); 
		}

		// UV.x (0..1)
		// progress: 当前实际血量 (绿色)
		// buffer_progress: 缓冲血量 (白色/黄色)
		// 假设从右向左扣血
		
		if (UV.x > buffer_progress) {
			// 超过缓冲部分：完全变暗/透明
			c.a *= 0.3; 
			c.rgb *= 0.5; 
		} else if (UV.x > progress) {
			// 在缓冲部分与实际血量之间：显示白色缓冲条
			// 这里我们使用白色叠加，或者直接设置为亮黄色
			c.rgb = mix(c.rgb, vec3(1.0, 1.0, 1.0), 0.7);
		}
		
		// 受击闪白
		c.rgb = mix(c.rgb, vec3(1.0, 1.0, 1.0), flash_intensity);
		
		COLOR = c;
	}
	"""
	var shader = Shader.new()
	shader.code = shader_code
	
	for grid_pos in data.grid_shape:
		var block = ColorRect.new()
		var size_val = GameConst.GRID_SIZE - GameConst.GRID_PADDING
		
		block.size = Vector2(size_val, size_val)
		block.color = base_color
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var offset = Vector2(grid_pos) * GameConst.GRID_SIZE
		var padding = Vector2(GameConst.GRID_PADDING, GameConst.GRID_PADDING) / 2.0
		block.position = offset + padding
		
		# 创建独立的 ShaderMaterial 实例
		var mat = ShaderMaterial.new()
		mat.shader = shader
		block.material = mat
		
		# 设置 Shader 参数
		mat.set_shader_parameter("main_color", base_color)
		
		if data.icon:
			mat.set_shader_parameter("use_icon", true)
			mat.set_shader_parameter("icon_tex", data.icon)
			
			mat.set_shader_parameter("uv_offset", crop_uv_pos)
			mat.set_shader_parameter("uv_scale", crop_uv_size)
		else:
			mat.set_shader_parameter("use_icon", false)
		
		add_child(block)
		visual_blocks.append(block)

func _get_civ_color(civ_key: String, fallback: Color) -> Color:
	match civ_key:
		"dynasty":
			return Color("c83f2b")
		"warlord":
			return Color("3b1b5a")
		"predator":
			return Color("1b5ea8")
		"french":
			return Color("234aa5")
		"rebel":
			return Color("d1a322")
		_:
			return fallback

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

func _pop_text(txt, color: Color = Color.WHITE):
	status_label.text = txt
	status_label.modulate = color
	var t = create_tween()
	# 让状态文字跳动，不要遮挡名字
	t.tween_property(status_label, "position:y", -50.0, 0.1)
	t.tween_property(status_label, "position:y", -40.0, 0.1)
	# 动画结束后恢复颜色 (可选，防止影响下一次显示)
	t.tween_callback(func(): status_label.modulate = Color.WHITE)


	
#  --- 输入处理 (实现拖拽) ---
func _set_highlight(active: bool):
	var color = Color(1.5, 1.5, 1.5) if active else Color.WHITE
	# 如果是拖拽中，可以更亮一点，或者加边框
	if active:
		# 简单实现：变亮
		modulate = color
	else:
		# 恢复
		if not is_deployed:
			modulate = Color(0.7, 0.7, 0.7, 1) # 备战区变暗
		else:
			modulate = Color.WHITE

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
	# modulate = Color(1.2, 1.2, 1.2, 1) # 移除旧的高亮
	
	# 新的高亮：给所有 block 加 outline shader
	_set_highlight(true)
	
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
	in_hand = false
	
	_set_highlight(false) # 取消高亮
	
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
	set_bench_hidden(false)
	stored_grid_pos = grid_pos # 记住这个新位置，下次手滑可以弹回来
	if EventBus and EventBus.has_signal("unit_deploy_state_changed"):
		EventBus.unit_deploy_state_changed.emit(self)
	
	# 视觉反馈：恢复正常亮度
	modulate = Color(1, 1, 1, 1)

# 辅助：回备战区
func _return_to_bench():
	var tween = create_tween()
	tween.tween_property(self, "position", bench_position, 0.2)
	is_deployed = false
	set_bench_hidden(true)
	if EventBus and EventBus.has_signal("unit_deploy_state_changed"):
		EventBus.unit_deploy_state_changed.emit(self)
	
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
	set_bench_hidden(true)
	if EventBus and EventBus.has_signal("unit_deploy_state_changed"):
		EventBus.unit_deploy_state_changed.emit(self)
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
