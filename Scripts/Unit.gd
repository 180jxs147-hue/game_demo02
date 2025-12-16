extends Node2D

@export var data: UnitData # 记得拖入数据文件

var is_dead: bool = false
var current_cooldown: float
var visual_blocks: Array[ColorRect] = [] # 存储生成的方块

@onready var timer = $Timer
@onready var label = $Label

func _ready():
	if not data: return
	current_cooldown = data.cooldown
	
	# 1. 根据数据“画”出形状
	_build_visuals()
	
	timer.timeout.connect(_on_timer_timeout)
	# 2. 启动循环
	timer.wait_time = current_cooldown
	timer.start()
	
	# 3. 监听队友死亡 (皮洛士机制)
	EventBus.unit_died.connect(_on_ally_died)

func _build_visuals():
	for grid_pos in data.grid_shape:
		var block = ColorRect.new()
		var size_val = GameConst.GRID_SIZE - GameConst.GRID_PADDING
		
		block.size = Vector2(size_val, size_val)
		block.color = data.color
		
		# 计算偏移坐标
		var offset = Vector2(grid_pos) * GameConst.GRID_SIZE
		var padding = Vector2(GameConst.GRID_PADDING, GameConst.GRID_PADDING) / 2.0
		block.position = offset + padding
		
		add_child(block)
		visual_blocks.append(block)

# --- 核心：战线判定 (从右向左推进) ---
# line_x 是当前红线的 X 坐标
func check_burn(line_x: float):
	if is_dead: return
	
	# 1. 视觉变灰 (方块如果在红线右侧，说明被烧过了)
	for i in range(visual_blocks.size()):
		var block = visual_blocks[i]
		var relative_pos = data.grid_shape[i]
		var block_world_x = global_position.x + (relative_pos.x * GameConst.GRID_SIZE)
		
		# 因为红线从右往左走，所以如果 方块X > 红线X，说明方块在红线右边(已被吞没)
		if block_world_x > line_x:
			var b = visual_blocks[i]
			if b.color != Color(0.2, 0.2, 0.2):
				b.color = Color(0.2, 0.2, 0.2) # 变灰
	
	# 2. 死亡判定：锚点 (Head) 被红线越过
	if global_position.x > line_x:
		_die()

# --- 循环逻辑 ---
func _on_timer_timeout():
	if is_dead: return
	if data.manpower_cost < 0:
		_produce()
	else:
		_try_attack()

func _produce():
	var manager = get_parent().get_parent() # 获取 BattleManager
	if manager.has_method("modify_manpower"):
		var amount = absf(data.manpower_cost)
		manager.modify_manpower(amount)
		_pop_text("+%.1f" % amount)

func _try_attack():
	var manager = get_parent().get_parent()
	if manager.current_manpower >= data.manpower_cost:
		manager.modify_manpower(-data.manpower_cost)
		_pop_text("ATK!")
		timer.start(current_cooldown)
	else:
		label.text = "..." # 缺气发呆
		timer.start(0.5)

# --- 队友祭天机制 ---
func _on_ally_died(unit, _pos):
	if is_dead or unit == self: return
	if "sacrifice" in data.tags:
		current_cooldown *= 0.7 # 攻速提升 30%
		timer.wait_time = current_cooldown
		label.modulate = Color.RED

func _die():
	is_dead = true
	timer.stop()
	label.text = "X"
	EventBus.unit_died.emit(self, global_position.x)

func _pop_text(txt):
	label.text = txt
	var t = create_tween()
	t.tween_property(label, "position:y", -50.0, 0.1)
	t.tween_property(label, "position:y", -40.0, 0.1)
