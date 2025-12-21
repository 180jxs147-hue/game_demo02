class_name BattleManager extends Node2D

## 战斗主控脚本。
## 职责：
## - 初始化关卡（读取 LevelDatabase，生成敌军）
## - 管理双方 HP 与“战线红线”推进
## - 生成玩家单位到备战区，并在开始战斗时通知单位进入状态机循环
## 约定：
## - 玩家单位永远挂在 `$Battlefield/FriendlyField/UnitsContainer`
## - 敌方单位永远挂在 `$Battlefield/EnemyField/UnitsContainer`

# --- UI 引用 (请在编辑器里拖拽赋值) ---
@export var left_hp_bar: ProgressBar
@export var right_hp_bar: ProgressBar
@export var manpower_label: Label
@export var units_container: Node2D  # <--- 确保这一行存在，且名字一字不差
@export var initial_roster: Array[Resource] = [] # 初始自带的卡牌 (在编辑器里填 UnitData)
@export var player_library: CardLibrary # 玩家拥有的卡牌库（用于持久化存储）
@export var level_database: LevelDatabase
@export var level_index: int = 0

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

@onready var battlefield = $Battlefield
@onready var friendly_field = $Battlefield/FriendlyField
@onready var enemy_field = $Battlefield/EnemyField
@onready var battle_line = $Battlefield/FriendlyField/BattleLine
@onready var enemy_battle_line = $Battlefield/EnemyField/BattleLine
@onready var result_overlay = $CanvasLayer/ResultOverlay
@onready var result_title_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/TitleLabel
@onready var result_detail_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/DetailLabel
@onready var next_level_button = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/HBoxContainer/NextLevelButton
@onready var retry_button = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/HBoxContainer/RetryButton

var _tooltip_instance: Control

@onready var reward_container = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/RewardContainer

var battle_ended: bool = false
var _has_level_enemies: bool = false
var _enemy_occupied: Dictionary = {}

func _ready():
	get_tree().paused = false
	is_battle_started = false
	battle_ended = false
	_apply_layout()
	if result_overlay:
		result_overlay.visible = false
	if reward_container:
		reward_container.visible = false
	
	if not units_container:
		units_container = $Battlefield/FriendlyField/UnitsContainer
	
	var level: LevelConfig = null
	if GameState:
		level_index = GameState.selected_level_index
	
	# --- 1. 动态调整战场格子数量 ---
	# 初始 4 列，每过 1 关增加 1 列，上限为 GameConst.MAP_COLUMNS
	# 例如: Lvl 0 -> 4, Lvl 1 -> 5, Lvl 2 -> 6...
	if GridManager:
		var extra = level_index 
		GridManager.playable_columns = min(GameConst.MAP_COLUMNS, 4 + extra)
		
	if not level_database and GameState and GameState.has_method("get_level_database"):
		level_database = GameState.get_level_database()
	if level_database:
		level = level_database.get_level(level_index)
	
	if level:
		max_army_hp = level.army_hp
		army_hp = max_army_hp
		max_enemy_hp = level.enemy_hp
		enemy_hp = max_enemy_hp
		
		if units_container:
			for spawn in level.enemy_units:
				_spawn_enemy(spawn)
			_has_level_enemies = level.enemy_units.size() > 0

	# 初始化血条最大值
	if left_hp_bar: left_hp_bar.max_value = max_army_hp
	if right_hp_bar: right_hp_bar.max_value = max_enemy_hp
	_update_ui()

	# --- 动态生成初始阵容 ---
	if units_container and initial_roster.size() > 0:
		# 如果配置了初始阵容，先清空场景里摆烂的（可选，这里我选择追加，或者你可以 uncomment 下面这行）
		# for child in units_container.get_children(): child.queue_free()
		
		for data in initial_roster:
			spawn_unit(data)
	
	# 确保 _arrange_bench 在节点就绪后安全调用
	call_deferred("_arrange_bench")
	call_deferred("_apply_layout")
	
	# 初始化提示框
	var tooltip_scene = load("res://Scenes/Tooltip.tscn")
	if tooltip_scene:
		_tooltip_instance = tooltip_scene.instantiate()
		_tooltip_instance.visible = false
		$CanvasLayer/HUD.add_child(_tooltip_instance)

	# 自动加载库中的卡牌到初始阵容（如果配置了）
	if GameState and GameState.has_method("load_player_library"):
		var loaded = GameState.load_player_library()
		if loaded:
			player_library = loaded
	if player_library:
		# 只有在游戏开始时，才把库里的卡加进战斗
		for card_data in player_library.collected_cards:
			spawn_unit(card_data)

func _apply_layout():
	# 根据屏幕宽度自动居中摆放左右战场，并更新两条红线的长度。
	if not battlefield:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var gap: float = 160.0
	var total_width: float = GameConst.BATTLE_FIELD_WIDTH * 2.0 + gap
	var origin_x: float = (viewport_size.x - total_width) * 0.5
	var origin_y: float = 90.0
	battlefield.position = Vector2(origin_x, origin_y)
	
	if friendly_field:
		friendly_field.position = Vector2.ZERO
	if enemy_field:
		enemy_field.position = Vector2(GameConst.BATTLE_FIELD_WIDTH + gap, 0.0)
	
	var line_height: float = GameConst.MAP_ROWS * GameConst.GRID_SIZE
	if battle_line:
		battle_line.custom_minimum_size = Vector2(2.0, line_height)
		battle_line.position = Vector2(GameConst.BATTLE_FIELD_WIDTH, 0.0)
		battle_line.size = Vector2(2.0, line_height)
	if enemy_battle_line:
		enemy_battle_line.custom_minimum_size = Vector2(2.0, line_height)
		enemy_battle_line.position = Vector2(0.0, 0.0)
		enemy_battle_line.size = Vector2(2.0, line_height)

func _input(event):
	# 调试功能已移除，依靠游戏循环获取单位。
	pass

func _debug_add_random_unit() -> UnitData:
	var random_datas = [
		preload("res://Resources/DataFiles/soldier.tres"),
		preload("res://Resources/DataFiles/Pyrrhus.tres"),
		preload("res://Resources/DataFiles/quarter.tres"),
		preload("res://Resources/DataFiles/archer.tres"),
		preload("res://Resources/DataFiles/spear.tres"),
		preload("res://Resources/DataFiles/cavalry.tres"),
		preload("res://Resources/DataFiles/catapult.tres"),
		preload("res://Resources/DataFiles/shield.tres"),
		preload("res://Resources/DataFiles/farmer.tres")
	]
	var data = random_datas.pick_random()
	spawn_unit(data)
	return data

func _debug_add_card_to_library():
	if not player_library:
		push_error("No PlayerLibrary assigned to BattleManager.")
		return
		
	# 随机生成一个（这里复用生成逻辑，但不一定非要生成实体）
	var random_datas = [
		preload("res://Resources/DataFiles/soldier.tres"),
		preload("res://Resources/DataFiles/Pyrrhus.tres"),
		preload("res://Resources/DataFiles/quarter.tres"),
		preload("res://Resources/DataFiles/archer.tres"),
		preload("res://Resources/DataFiles/spear.tres"),
		preload("res://Resources/DataFiles/cavalry.tres"),
		preload("res://Resources/DataFiles/catapult.tres"),
		preload("res://Resources/DataFiles/shield.tres"),
		preload("res://Resources/DataFiles/farmer.tres")
	]
	var data = random_datas.pick_random()
	
	# 添加到库
	player_library.collected_cards.append(data)
	
	# 保存到磁盘
	var save_path = player_library.resource_path
	if save_path.is_empty() or save_path.begins_with("res://"):
		save_path = "user://PlayerLibrary.tres"
		
	var error = ResourceSaver.save(player_library, save_path)
	if error == OK:
		# 顺便也在战场上生成一个，让你看到效果
		spawn_unit(data)
	else:
		push_error("Error saving player library: " + str(error))

func _process(delta):
	# 战斗循环：推进战线、检测胜负、让超出战线的单位进入死亡状态。
	if not is_battle_started: return
	if battle_ended: return
	if army_hp <= 0:
		_end_battle(false)
		return
	if enemy_hp <= 0:
		_end_battle(true)
		return
	
	if not _has_level_enemies:
		var enemy_dps = 80.0
		army_hp -= enemy_dps * delta
	
	# 2. 计算战线红线位置
	var hp_percent = army_hp / max_army_hp
	var friendly_target_x = hp_percent * GameConst.BATTLE_FIELD_WIDTH
	if battle_line:
		battle_line.position.x = friendly_target_x
	
	var enemy_hp_percent = enemy_hp / max_enemy_hp
	var enemy_target_x = (1.0 - enemy_hp_percent) * GameConst.BATTLE_FIELD_WIDTH
	if enemy_battle_line:
		enemy_battle_line.position.x = enemy_target_x
	
	# 3. 检查单位被吞没
	var friendly_line_global_x = battle_line.global_position.x if battle_line else 0.0
	for unit in $Battlefield/FriendlyField/UnitsContainer.get_children():
		if unit.has_method("check_burn"):
			unit.check_burn(friendly_line_global_x, true)
	
	var enemy_line_global_x = enemy_battle_line.global_position.x if enemy_battle_line else 0.0
	for unit in $Battlefield/EnemyField/UnitsContainer.get_children():
		if unit.has_method("check_burn"):
			unit.check_burn(enemy_line_global_x, false)
			
	_update_ui() # 每帧更新血条有点浪费，实际可优化，原型先这样

# --- 供 Unit 调用的接口 ---

# 对敌人造成伤害 (新增)
func deal_damage_to_enemy(amount: float):
	enemy_hp -= amount
	if enemy_hp < 0: enemy_hp = 0
	# 这里可以加个飘字特效或者受击闪烁
	_update_ui()

func deal_damage_to_army(amount: float):
	army_hp -= amount
	if army_hp < 0: army_hp = 0
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
	
	# 更新 Tooltip 位置
	if _tooltip_instance and _tooltip_instance.visible:
		var mouse_pos = get_global_mouse_position()
		# HUD 是 CanvasLayer 下的，需要 Viewport 坐标
		var viewport_mouse = get_viewport().get_mouse_position()
		
		# 偏移一点，避免遮挡鼠标
		var target_pos = viewport_mouse + Vector2(15, 15)
		
		# 简单的边界检查 (假设屏幕足够大，先不做复杂的反转)
		_tooltip_instance.position = target_pos

func show_tooltip(data: UnitData):
	if _tooltip_instance:
		_tooltip_instance.update_info(data)
		_tooltip_instance.visible = true
		_tooltip_instance.z_index = 100 # 保证在最上层

func hide_tooltip():
	if _tooltip_instance:
		_tooltip_instance.visible = false

func _end_battle(victory: bool):
	if battle_ended:
		return
	battle_ended = true
	is_battle_started = false
	get_tree().paused = true
	if result_overlay:
		result_overlay.visible = true
	if result_title_label:
		result_title_label.text = "胜利" if victory else "失败"
	
	if victory:
		# 胜利逻辑
		var reward_text = ""
		
		# 1. 弹出三选一奖励
		_show_rewards()
			
		# 2. 检查是否有下一关
		var has_next = false
		if level_database and level_index + 1 < level_database.levels.size():
			has_next = true
		else:
			reward_text += "\n\n恭喜通关！(Demo结束)"
			
		if next_level_button: 
			next_level_button.visible = false # 等待选择奖励后再显示
		if retry_button: 
			retry_button.visible = false
		
		if result_detail_label:
			var detail := "我方 HP: %.0f / %.0f\n敌方 HP: %.0f / %.0f\n民力: %.1f%s" % [army_hp, max_army_hp, enemy_hp, max_enemy_hp, current_manpower, reward_text]
			result_detail_label.text = detail
	else:
		# 失败逻辑
		if next_level_button: next_level_button.visible = false
		if retry_button: retry_button.visible = true
		if reward_container: reward_container.visible = false
		if result_detail_label:
			var detail := "我方 HP: %.0f / %.0f\n敌方 HP: %.0f / %.0f\n民力: %.1f" % [army_hp, max_army_hp, enemy_hp, max_enemy_hp, current_manpower]
			result_detail_label.text = detail

# 按钮点击回调
func _on_start_button_pressed():
	if is_battle_started: return
	
	is_battle_started = true
	$CanvasLayer/HUD/StartButton.visible = false # 隐藏按钮
	
	# 激活所有单位
	# 告诉所有 Unit 开始 Timer
	get_tree().call_group("units", "start_battle")

func _on_next_level_button_pressed():
	if GameState:
		GameState.selected_level_index += 1
		GameState.save_progress()
	
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_retry_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _on_menu_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

# --- 奖励相关 ---

func _show_rewards():
	if not reward_container: return
	
	# 清空旧的
	for child in reward_container.get_children():
		child.queue_free()
		
	reward_container.visible = true
	
	# 读取数据库
	var db = load("res://Resources/UnitDatabase.tres")
	if not db or db.units.is_empty():
		return
		
	# 随机取3个
	var pool = db.units.duplicate()
	pool.shuffle()
	var choices = pool.slice(0, 3)
	
	for data in choices:
		_create_reward_card_ui(data)

func _create_reward_card_ui(data: UnitData):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(120, 160)
	
	# 简单的文本排版
	var desc = data.name + "\n\n"
	desc += "ATK: %.0f\nCD: %.1f" % [data.attack_damage, data.cooldown]
	if not data.tags.is_empty():
		desc += "\n" + str(data.tags)
		
	btn.text = desc
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(func(): _on_reward_selected(data))
	
	reward_container.add_child(btn)

func _on_reward_selected(data: UnitData):
	# 添加到玩家库
	if player_library:
		player_library.collected_cards.append(data)
		if GameState:
			GameState.save_player_library(player_library)
			
	# 隐藏奖励界面
	reward_container.visible = false
	
	# 更新文本提示
	if result_detail_label:
		result_detail_label.text += "\n\n已选择: %s" % data.name
		
	# 显示下一关按钮 (如果有关卡)
	var has_next = false
	if level_database and level_index + 1 < level_database.levels.size():
		has_next = true
	
	if next_level_button:
		next_level_button.visible = has_next

func _grant_random_reward() -> UnitData:
	# 保留此函数以防万一，但逻辑已转移
	return null
	if not GameState: return null
	var db = GameState.get_unit_database()
	if not db or db.units.is_empty(): return null
	
	var card = db.units.pick_random()
	if player_library:
		player_library.collected_cards.append(card)
	return card

func _spawn_enemy(spawn: UnitSpawn):
	# 生成敌方单位并直接部署到敌军网格。
	if not spawn:
		return
	if not spawn.unit_data:
		return
	if not enemy_field:
		return
	var enemy_units_container = $Battlefield/EnemyField/UnitsContainer
	if not enemy_units_container:
		return
	
	var new_unit = unit_scene.instantiate()
	new_unit.data = spawn.unit_data
	new_unit.spawned_via_script = true
	new_unit.faction = new_unit.Faction.ENEMY
	enemy_units_container.add_child(new_unit)
	
	if _enemy_can_place(spawn.unit_data, spawn.grid_pos):
		_enemy_mark_occupied(spawn.unit_data, spawn.grid_pos)
		new_unit.position = GridManager.grid_to_world(spawn.grid_pos)
		new_unit.is_deployed = true
		new_unit.stored_grid_pos = spawn.grid_pos

func _enemy_can_place(data: UnitData, grid_pos: Vector2i) -> bool:
	for part in data.grid_shape:
		var cell = grid_pos + part
		if cell.x < 0 or cell.x >= GameConst.MAP_COLUMNS:
			return false
		if cell.y < 0 or cell.y >= GameConst.MAP_ROWS:
			return false
		var key = str(cell.x) + "," + str(cell.y)
		if _enemy_occupied.has(key):
			return false
	return true

func _enemy_mark_occupied(data: UnitData, grid_pos: Vector2i):
	for part in data.grid_shape:
		var cell = grid_pos + part
		var key = str(cell.x) + "," + str(cell.y)
		_enemy_occupied[key] = true

# 动态生成单位（玩家备战区）
func spawn_unit(data: UnitData):
	if not unit_scene:
		return
		
	var new_unit = unit_scene.instantiate()
	new_unit.data = data
	# 默认设为未部署
	new_unit.is_deployed = false
	new_unit.spawned_via_script = true # 标记为脚本生成
	
	if not units_container:
		units_container = $Battlefield/FriendlyField/UnitsContainer
	if not units_container:
		if OS.is_debug_build():
			push_error("units_container not found in BattleManager.")
		return
		
	units_container.add_child(new_unit)
	
	# 重新排列备战区
	# 注意：如果是批量生成，建议生成完再调一次，而不是每生成一个调一次
	# 这里为了简单，每次都调，但在 _ready 里我们只最后调一次
	if is_inside_tree(): # 确保我们在树里
		# 使用 call_deferred 避免在同一帧多次重排造成性能浪费（虽然这里很简单）
		call_deferred("_arrange_bench")

func _arrange_bench():
	# 如果 units_container 没赋值，尝试自己找一下
	if not units_container:
		units_container = $Battlefield/FriendlyField/UnitsContainer
		
	if not units_container:
		if OS.is_debug_build():
			push_error("units_container not found in BattleManager.")
		return

	# 获取所有未部署的单位
	var visible_cards = []
	for unit in units_container.get_children():
		# 只有那些没有部署在格子里的单位，才需要排队
		if unit.get("is_deployed") == true:
			continue
		visible_cards.append(unit)

	# 布局配置
	var start_y = GameConst.MAP_ROWS * GameConst.GRID_SIZE + 40.0 # 地图下方 40 像素
	var gap_x = 85.0 
	var gap_y = 90.0
	var cols = 4 # 战场宽度 384，每行放4个比较合适
	
	# 计算起始 X 坐标以居中显示
	# 整个网格的宽度约为 cols * gap_x
	var grid_width = cols * gap_x
	var start_x = (GameConst.BATTLE_FIELD_WIDTH - grid_width) / 2.0 + 10.0 # 微调居中

	# 调整背景框
	var bench_rect = $Battlefield/FriendlyField/ColorRect
	if bench_rect:
		var rows = ceil(visible_cards.size() / float(cols))
		if rows < 1: rows = 1
		# 动态调整背景高度
		var total_h = rows * gap_y + 20
		bench_rect.position.y = start_y - 20
		bench_rect.size.x = GameConst.BATTLE_FIELD_WIDTH + 40
		bench_rect.position.x = -20 
		bench_rect.size.y = total_h

	# 开始排布
	for i in range(visible_cards.size()):
		var unit = visible_cards[i]
		var row = i / cols
		var col = i % cols
		
		var x = start_x + (col * gap_x)
		var y = start_y + (row * gap_y)
		
		var target_pos = Vector2(x, y)
		
		# 检查这个单位脚本里有没有 update_bench_pos 这个函数
		if unit.has_method("update_bench_pos"):
			# 有的话，就调用它，把目标坐标传过去
			unit.update_bench_pos(target_pos)
