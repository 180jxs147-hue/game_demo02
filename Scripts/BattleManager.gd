class_name BattleManager extends Node2D

# --- UI 引用 (请在编辑器里拖拽赋值) ---
@export var left_hp_bar: ProgressBar
@export var right_hp_bar: ProgressBar
@export var manpower_label: Label
@export var units_container: Node2D  # <--- 确保这一行存在，且名字一字不差
@export var initial_roster: Array[Resource] = [] # 初始自带的卡牌 (在编辑器里填 UnitData)
@export var player_library: CardLibrary # 玩家拥有的卡牌库（用于持久化存储）

# --- 内部引用 ---
var unit_scene = preload("res://Scenes/Unit.tscn")

# --- 战斗参数 ---
static var is_battle_started: bool = false
var current_manpower: float = 10.0
var max_manpower: float = 50.0

# 我方阵线 (Left HP)
var army_hp: float = 1000.0 
var max_army_hp: float = 1000.0

# 敌方 Boss (Right HP) <--- 新增
var enemy_hp: float = 1000.0 
var max_enemy_hp: float = 1000.0

@onready var battle_line = $Battlefield/BattleLine

func _ready():
	is_battle_started = false
	battle_line.position.x = GameConst.BATTLE_FIELD_WIDTH
	
	# 初始化血条最大值
	if left_hp_bar: left_hp_bar.max_value = max_army_hp
	if right_hp_bar: right_hp_bar.max_value = max_enemy_hp
	_update_ui()

	# --- 动态生成初始阵容 ---
	if not units_container:
		units_container = $Battlefield/UnitsContainer
		
	if units_container and initial_roster.size() > 0:
		# 如果配置了初始阵容，先清空场景里摆烂的（可选，这里我选择追加，或者你可以 uncomment 下面这行）
		# for child in units_container.get_children(): child.queue_free()
		
		for data in initial_roster:
			spawn_unit(data)
	
	# 确保 _arrange_bench 在节点就绪后安全调用
	call_deferred("_arrange_bench")

	# 自动加载库中的卡牌到初始阵容（如果配置了）
	if player_library:
		print("Loaded player library with ", player_library.collected_cards.size(), " cards.")
		# 只有在游戏开始时，才把库里的卡加进战斗
		for card_data in player_library.collected_cards:
			spawn_unit(card_data)

func _input(event):
	# --- 调试功能：按 D 键随机增加一个兵 ---
	if event is InputEventKey and event.pressed and event.keycode == KEY_D:
		_debug_add_random_unit()
		
	# --- 调试功能：按 A 键增加一张卡到库里并保存 ---
	if event is InputEventKey and event.pressed and event.keycode == KEY_A:
		_debug_add_card_to_library()

func _debug_add_random_unit() -> UnitData:
	var random_datas = [
		preload("res://Resources/DataFiles/soldier.tres"),
		preload("res://Resources/DataFiles/Pyrrhus.tres"),
		preload("res://Resources/DataFiles/quarter.tres")
	]
	var data = random_datas.pick_random()
	spawn_unit(data)
	print("Debug: Added unit ", data.name)
	return data

func _debug_add_card_to_library():
	if not player_library:
		print("Error: No PlayerLibrary assigned to BattleManager!")
		return
		
	# 随机生成一个（这里复用生成逻辑，但不一定非要生成实体）
	var random_datas = [
		preload("res://Resources/DataFiles/soldier.tres"),
		preload("res://Resources/DataFiles/Pyrrhus.tres"),
		preload("res://Resources/DataFiles/quarter.tres")
	]
	var data = random_datas.pick_random()
	
	# 添加到库
	player_library.collected_cards.append(data)
	
	# 保存到磁盘
	var save_path = player_library.resource_path
	if save_path.is_empty():
		save_path = "res://Resources/PlayerLibrary.tres"
		
	var error = ResourceSaver.save(player_library, save_path)
	if error == OK:
		print("Debug: Added ", data.name, " to library and saved to ", save_path)
		print("Current library size: ", player_library.collected_cards.size())
		
		# 顺便也在战场上生成一个，让你看到效果
		spawn_unit(data)
	else:
		print("Error saving library: ", error)

func _process(delta):
	if not is_battle_started: return
	if army_hp <= 0 or enemy_hp <= 0: return # 游戏结束
	
	# 1. 敌人对我方持续造成伤害 (模拟)
	var enemy_dps = 80.0
	army_hp -= enemy_dps * delta
	
	# 2. 计算战线红线位置
	var hp_percent = army_hp / max_army_hp
	var target_x = hp_percent * GameConst.BATTLE_FIELD_WIDTH
	battle_line.position.x = target_x
	
	# 3. 检查单位被吞没
	for unit in $Battlefield/UnitsContainer.get_children():
		if unit.has_method("check_burn"):
			unit.check_burn(target_x)
			
	_update_ui() # 每帧更新血条有点浪费，实际可优化，原型先这样

# --- 供 Unit 调用的接口 ---

# 对敌人造成伤害 (新增)
func deal_damage_to_enemy(amount: float):
	enemy_hp -= amount
	if enemy_hp < 0: enemy_hp = 0
	# 这里可以加个飘字特效或者受击闪烁
	_update_ui()

# 修改民力
func modify_manpower(amount: float):
	current_manpower += amount
	current_manpower = clampf(current_manpower, 0.0, max_manpower)
	_update_ui()

# 统一更新 UI
func _update_ui():
	if left_hp_bar: left_hp_bar.value = army_hp
	if right_hp_bar: right_hp_bar.value = enemy_hp
	if manpower_label: manpower_label.text = "民力: %.1f" % current_manpower
	
	# 简单的输赢判断打印
	if army_hp <= 0: print("失败！阵线崩溃")
	if enemy_hp <= 0: print("胜利！敌人被消灭")

# 按钮点击回调
func _on_start_button_pressed():
	if is_battle_started: return
	
	is_battle_started = true
	$CanvasLayer/HUD/StartButton.visible = false # 隐藏按钮
	
	# 激活所有单位
	# 告诉所有 Unit 开始 Timer
	get_tree().call_group("units", "start_battle")

# 动态生成单位
func spawn_unit(data: Resource):
	if not unit_scene:
		return
		
	var new_unit = unit_scene.instantiate()
	new_unit.data = data
	# 默认设为未部署
	new_unit.is_deployed = false
	new_unit.spawned_via_script = true # 标记为脚本生成
	
	if not units_container:
		units_container = $Battlefield/UnitsContainer
		
	units_container.add_child(new_unit)
	
	# 重新排列备战区
	# 注意：如果是批量生成，建议生成完再调一次，而不是每生成一个调一次
	# 这里为了简单，每次都调，但在 _ready 里我们只最后调一次
	if is_inside_tree(): # 确保我们在树里
		# 使用 call_deferred 避免在同一帧多次重排造成性能浪费（虽然这里很简单）
		call_deferred("_arrange_bench")

func _on_button_pressed() -> void:
	pass # Replace with function body.

func _arrange_bench():
	# 如果 units_container 没赋值，尝试自己找一下
	if not units_container:
		units_container = $Battlefield/UnitsContainer
		
	if not units_container:
		print("Error: units_container not found in BattleManager")
		return

	# 定义备战区的起始位置 (相对于 Battlefield 节点)
	var bench_rect = $Battlefield/ColorRect
	if bench_rect:
		# 让备战区背景框也自动适配位置
		bench_rect.position.y = GameConst.MAP_ROWS * GameConst.GRID_SIZE + 20
		bench_rect.size.x = GameConst.BATTLE_FIELD_WIDTH + 40
		bench_rect.position.x = -20 # 稍微往左一点，居中好看

	var start_x = 20.0
	var start_y = GameConst.MAP_ROWS * GameConst.GRID_SIZE + 40.0 # 地图下方 40 像素
	var gap = 100.0 # 每个兵种之间的间隔
	var index = 0
	for unit in units_container.get_children():
		# 只有那些没有部署在格子里的单位，才需要排队
		# 我们先假设所有单位都要排队，然后 Unit 脚本自己决定要不要听
		# 或者更智能一点：先检查 unit.is_deployed (如果能访问到)
		if unit.get("is_deployed") == true:
			continue
			
		# 计算该单位应该在哪
		var target_pos = Vector2(start_x + index * gap, start_y)
		# --- 核心操作 ---
		# 检查这个单位脚本里有没有 update_bench_pos 这个函数
		if unit.has_method("update_bench_pos"):
			# 有的话，就调用它，把目标坐标传过去
			unit.update_bench_pos(target_pos)        
		index += 1
