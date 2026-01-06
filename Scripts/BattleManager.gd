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
@export var manpower_label: Label
@export var enemy_manpower_label: Label
@export var synergy_label: Label
@export var units_container: Node2D  # <--- 确保这一行存在，且名字一字不差
@export var initial_roster: Array[Resource] = [] # 初始自带的卡牌 (在编辑器里填 UnitData)
@export var player_library: CardLibrary # 玩家拥有的卡牌库（用于持久化存储）
@export var level_database: LevelDatabase
@export var level_index: int = 0

# --- 布局配置 (可在编辑器调整) ---
@export_group("Layout Settings")
@export var layout_scale: float = 1.2      ## 战场整体缩放比例 (1080p建议 1.3~1.4)
@export var battlefield_position: Vector2 = Vector2(200, 100) ## 战场的起始位置（屏幕坐标，大致对应左上角）
@export var friendly_field_base: Vector2 = Vector2(0, 0) ## 我方战场基准点 (左上角，相对于 Battlefield 容器)
@export var enemy_field_base: Vector2 = Vector2(1400, 0) ## 敌方战场基准点 (右上角，相对于 Battlefield 容器)
@export var bench_offset: Vector2 = Vector2(-20, 600) ## 备战区相对于我方战场左上角的固定位置
@export var bench_columns: int = 8         ## 备战区每行显示的卡牌数列数

# --- 内部引用 ---
var unit_scene = preload("res://Scenes/Unit.tscn")

# --- 战斗参数 ---
static var is_battle_started: bool = false
var current_manpower: float = 10.0
var max_manpower: float = 50.0

# 敌方民力 (新增)
var enemy_current_manpower: float = 10.0
var enemy_max_manpower: float = 50.0

@onready var battlefield = $Battlefield
@onready var friendly_field = $Battlefield/FriendlyField
@onready var enemy_field = $Battlefield/EnemyField
@onready var battle_line = $Battlefield/FriendlyField/BattleLine
@onready var enemy_battle_line = $Battlefield/EnemyField/BattleLine

@onready var friendly_grid_vis = $Battlefield/FriendlyField/GridVisualizer
@onready var enemy_grid_vis = $Battlefield/EnemyField/GridVisualizer

@onready var result_overlay = $CanvasLayer/ResultOverlay
@onready var result_title_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/TitleLabel
@onready var result_detail_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/DetailLabel
@onready var next_level_button = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/HBoxContainer/NextLevelButton
@onready var retry_button = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/HBoxContainer/RetryButton

var _tooltip_instance: Control

@onready var reward_container = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/RewardContainer

var _synergy_update_timer: float = 0.0

var battle_ended: bool = false
var _has_level_enemies: bool = false
var _enemy_occupied: Dictionary = {}

var _adjacency_lines_node: Node2D # 用于绘制连线

# 存储当前的敌人网格尺寸，供 _apply_layout 使用
var current_enemy_cols: int = GameConst.MAP_COLUMNS
var current_enemy_rows: int = GameConst.MAP_ROWS

# 当前关卡配置引用
var current_level_config: LevelConfig

func _ready():
	get_tree().paused = false
	is_battle_started = false
	battle_ended = false
	
	# 创建用于绘制连线的节点，层级设高一点
	_adjacency_lines_node = Node2D.new()
	_adjacency_lines_node.z_index = 100 
	add_child(_adjacency_lines_node)
	
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
	
	# --- 1. 动态调整战场格子数量 (已移至下方合并处理) ---
	# 从存档读取
	# if GridManager and GameState:
	# 	GridManager.playable_columns = GameState.current_cols
	# 	GridManager.playable_rows = GameState.current_rows
		
	if not level_database and GameState and GameState.has_method("get_level_database"):
		level_database = GameState.get_level_database()
	if level_database:
		level = level_database.get_level(level_index)
		current_level_config = level
	
	# --- 设定敌方网格尺寸 ---
	var enemy_cols = GameConst.MAP_COLUMNS
	var enemy_rows = GameConst.MAP_ROWS
	
	if level:
		if "grid_width" in level and level.grid_width > enemy_cols:
			enemy_cols = level.grid_width
		if "grid_height" in level and level.grid_height > enemy_rows:
			enemy_rows = level.grid_height
	
	current_enemy_cols = enemy_cols
	current_enemy_rows = enemy_rows
	
	if enemy_grid_vis:
		enemy_grid_vis.override_cols = enemy_cols
		enemy_grid_vis.override_rows = enemy_rows
		enemy_grid_vis.queue_redraw()
	
	# 1. 先加载玩家存档
	if GameState and GameState.has_method("load_player_library"):
		var loaded = GameState.load_player_library()
		if loaded:
			player_library = loaded

	# --- 1. 动态调整战场格子数量 ---
	# 逻辑：取玩家解锁的尺寸与关卡要求尺寸的较大值
	# 修正：玩家战场尺寸只应该由 GameState 决定，不应该受关卡敌军规模影响
	# 敌军规模（grid_width/grid_height）只影响敌军战场的生成
	
	var final_cols = GameConst.MAP_COLUMNS
	var final_rows = GameConst.MAP_ROWS
	
	if GameState:
		final_cols = GameState.current_cols
		final_rows = GameState.current_rows
		
	# 注意：GridManager 的 playable_area 实际上是定义了“可以拖拽放置的区域”
	# 如果我们把 playable_area 设大了，玩家就可以把兵拖到更远的地方
	# 但现在的需求是“我方军阵格子数量是重要资源，为什么每关数量不一样”
	# 这意味着 final_cols/rows 必须严格等于 GameState 的值，不能因为关卡大就变大
	
	# 下面的代码曾经尝试把关卡尺寸合并进来，这导致了如果关卡很大，玩家的可操作区域也变大了
	# 我们现在移除这部分逻辑
	
	# if level:
	# 	# 如果关卡有特殊尺寸要求（例如敌阵很大），则临时扩大战场
	# 	# 这样 GridManager 才知道这片区域是合法的
	# 	if "grid_width" in level and level.grid_width > final_cols:
	# 		final_cols = level.grid_width
	# 	if "grid_height" in level and level.grid_height > final_rows:
	# 		final_rows = level.grid_height

	if GridManager:
		GridManager.playable_columns = final_cols
		GridManager.playable_rows = final_rows
	if GameState and player_library:
		var has_caesar = false
		for card in player_library.collected_cards:
			if card and card.resource_path.ends_with("caesar.tres"):
				has_caesar = true
				break
		
		# 如果没有凯撒，添加凯撒
		if not has_caesar:
			var caesar = load("res://Resources/DataFiles/caesar.tres")
			if caesar:
				player_library.collected_cards.append(caesar)
				GameState.save_player_library(player_library)
				
		# 3. 紧急修复：如果因为之前的 Bug 导致存档只剩凯撒，重新发放初始包
		if player_library.collected_cards.size() <= 1 and has_caesar:
			# 看起来被误清空了，补发初始包
			var starters = [
				"res://Resources/DataFiles/soldier.tres",
				"res://Resources/DataFiles/soldier.tres",
				"res://Resources/DataFiles/archer.tres",
				"res://Resources/DataFiles/spear.tres",
				"res://Resources/DataFiles/camp.tres",
				"res://Resources/DataFiles/camp.tres"
			]
			for path in starters:
				var unit = load(path)
				if unit:
					player_library.collected_cards.append(unit)
			GameState.save_player_library(player_library)

	if level:
		if units_container:
			for spawn in level.enemy_units:
				_spawn_enemy(spawn, current_enemy_cols, current_enemy_rows)
			_has_level_enemies = level.enemy_units.size() > 0

	_update_ui()

	# --- 清理残留的 Grid 占用 (防止重开游戏时格子被锁) ---
	GridManager.clear_all()

	# --- 动态生成初始阵容 ---
	if units_container and initial_roster.size() > 0:
		# 如果配置了初始阵容，先清空场景里摆烂的（可选，这里我选择追加，或者你可以 uncomment 下面这行）
		# for child in units_container.get_children(): child.queue_free()
		
		for data in initial_roster:
			spawn_unit(data)
	
	# 确保 _arrange_bench 在节点就绪后安全调用
	call_deferred("_arrange_bench")
	call_deferred("_apply_layout")
	call_deferred("start_intro_dialogue")
	
	# 初始化提示框
	var tooltip_scene = load("res://Scenes/Tooltip.tscn")
	if tooltip_scene:
		_tooltip_instance = tooltip_scene.instantiate()
		_tooltip_instance.visible = false
		$CanvasLayer/HUD.add_child(_tooltip_instance)

	if player_library:
		# 只有在游戏开始时，才把库里的卡加进战斗
		for card_data in player_library.collected_cards:
			spawn_unit(card_data)

func start_level(index: int):
	print("Switching to level: ", index)
	
	if GameState:
		GameState.selected_level_index = index
	level_index = index
	
	var level = null
	if level_database:
		level = level_database.get_level(level_index)
	
	if not level:
		push_error("Level not found: " + str(index))
		return

	# 1. 清理现有敌人
	if enemy_field:
		var enemy_units_container = $Battlefield/EnemyField/UnitsContainer
		if enemy_units_container:
			for child in enemy_units_container.get_children():
				child.queue_free()
	
	_enemy_occupied.clear()
	
	# 2. 设置数值
	
	# 3. 调整格子大小 (分别设置)
	# 玩家格子大小：只受 GameState 影响
	var player_cols = GameState.current_cols if GameState else GameConst.MAP_COLUMNS
	var player_rows = GameState.current_rows if GameState else GameConst.MAP_ROWS
	
	# 敌人格子大小：受关卡配置影响
	var enemy_cols = GameConst.MAP_COLUMNS
	var enemy_rows = GameConst.MAP_ROWS
	
	if "grid_width" in level and level.grid_width > enemy_cols:
		enemy_cols = level.grid_width
	if "grid_height" in level and level.grid_height > enemy_rows:
		enemy_rows = level.grid_height

	# 更新成员变量
	current_enemy_cols = enemy_cols
	current_enemy_rows = enemy_rows

	if GridManager:
		# GridManager 主要服务于玩家操作（拖拽、放置），所以使用玩家的尺寸
		GridManager.playable_columns = player_cols
		GridManager.playable_rows = player_rows
		GridManager.clear_all()
		if units_container:
			for unit in units_container.get_children():
				if unit.is_deployed and "stored_grid_pos" in unit:
					GridManager.mark_occupied(unit.stored_grid_pos, unit)
	
	# 刷新网格显示并应用尺寸
	if friendly_grid_vis:
		friendly_grid_vis.override_cols = player_cols
		friendly_grid_vis.override_rows = player_rows
		friendly_grid_vis.queue_redraw()
		
	if enemy_grid_vis:
		enemy_grid_vis.override_cols = enemy_cols
		enemy_grid_vis.override_rows = enemy_rows
		enemy_grid_vis.queue_redraw()
	
	# 4. 生成新敌人
	_has_level_enemies = false
	if units_container:
		for spawn in level.enemy_units:
			# 使用 enemy_cols 进行边界检查
			_spawn_enemy(spawn, enemy_cols, enemy_rows)
		_has_level_enemies = level.enemy_units.size() > 0
	
	# 5. 更新 UI
	_update_ui()
	
	# 6. 重置战斗状态
	is_battle_started = false
	battle_ended = false
	if result_overlay: result_overlay.visible = false

	call_deferred("_arrange_bench")
	call_deferred("_apply_layout")

func start_level_id(id: String):
	var idx = level_index
	if level_database:
		var found = level_database.get_index_by_id(id)
		if found >= 0:
			idx = found
	start_level(idx)

func _apply_layout():
	# 根据屏幕宽度摆放战场
	# 修改：不再动态居中，而是使用固定基准点
	if not battlefield:
		return
	
	# --- 适配 1080p: 整体缩放 ---
	battlefield.scale = Vector2(layout_scale, layout_scale)
	
	# 获取当前的实际行数和列数
	var current_cols = GameConst.MAP_COLUMNS
	var current_rows = GameConst.MAP_ROWS
	
	if GridManager:
		if GridManager.playable_columns > 0:
			current_cols = GridManager.playable_columns
		if GridManager.playable_rows > 0:
			current_rows = GridManager.playable_rows
	
	var battle_field_width_actual = current_cols * GameConst.GRID_SIZE
	
	# --- 1. 设置 Battlefield 容器位置 (绝对位置) ---
	# 直接使用 battlefield_position，不再根据内容宽度自动居中
	# 这样当网格扩大时，基准点不会移动
	battlefield.position = battlefield_position
	
	# --- 2. 设置 我方战场 (左上角基准) ---
	if friendly_field:
		# 锚点：Top-Left (Base Point)
		# 随着网格扩充，向右下延伸，左上角不动
		friendly_field.position = friendly_field_base

	# --- 3. 设置 敌方战场 (右上角基准) ---
	if enemy_field:
		# 锚点：Top-Right (Base Point)
		# 随着网格扩充，向左下延伸，右上角不动
		# Position (Top-Left) = Base (Top-Right) - Width
		
		# 使用敌人自己的列数计算宽度
		var enemy_width_actual = current_enemy_cols * GameConst.GRID_SIZE
		
		# 修正：用户反馈第三四关敌方阵线到了屏幕右侧（超出画面）。
		# 原因是之前的逻辑 pos_x = enemy_field_base.x - enemy_width_actual 是正确的“定右算左”逻辑，
		# 但是 enemy_field_base.x 的值（比如 1000）是相对于 Battlefield 容器的。
		# Battlefield 容器本身在屏幕上有偏移（battlefield_position = 280）且有缩放（1.35）。
		# 屏幕 X = 280 + (BaseX - Width) * 1.35
		# 右边界屏幕 X = 280 + BaseX * 1.35
		
		# 如果 BaseX = 1000，Scale = 1.35 -> 右边界 = 280 + 1350 = 1630 (在 1920 屏幕内)
		# 如果 BaseX = 800，Scale = 1.35 -> 右边界 = 280 + 1080 = 1360 (在 1920 屏幕内)
		
		# 那为什么用户说“第三四关会到屏幕右侧”？
		# 第三四关通常 enemy_width_actual 很大（比如 9列 = 990）。
		# 如果 BaseX = 1000，Width = 990 -> PosX = 10.
		# 左边界屏幕 X = 280 + 10 * 1.35 = 293.5
		# 右边界屏幕 X = 1630.
		# 这看起来完全正常。
		
		# 但是！如果用户之前的体验是 BaseX 比较小（比如为了让小地图居中），
		# 此时突然变大，他可能会觉得“偏右了”。
		# 或者，用户所谓的“屏幕右侧”是指**超出了**屏幕右侧？
		# 用户原话：“为什么第三四关会到屏幕右侧。”
		# 结合之前的“右侧已经超出画面”，可能是指虽然理论计算在内，但视觉上太靠右了，或者甚至出去了。
		
		# 让我们回退到用户认可的逻辑：
		# “敌方阵线是以右上角为基准点，基准点位置固定，不与任何其他要素相关”
		# 这意味着 BaseX 必须是一个常数，不能变。
		# 我们现在的代码 BaseX 就是常数 (enemy_field_base)。
		
		# 唯一的变量是 current_enemy_cols。
		# 如果 cols 变大，width 变大，pos_x 变小（向左延伸）。
		# 右边界始终是 BaseX。
		
		var base_pos = enemy_field_base
		
		# 如果有关卡特定的偏移配置，应用它
		if current_level_config and "position_offset" in current_level_config:
			base_pos += current_level_config.position_offset
		
		var pos_x = base_pos.x - enemy_width_actual
		var pos_y = base_pos.y
		
		enemy_field.position = Vector2(pos_x, pos_y)

		# 调整 Enemy Battle Line (红线)
		if enemy_battle_line:
			var line_height: float = current_enemy_rows * GameConst.GRID_SIZE
			enemy_battle_line.visible = false
			enemy_battle_line.custom_minimum_size = Vector2(2.0, line_height)
			# 敌方红线在敌方战场的左侧 (x=0) = 前线
			enemy_battle_line.position = Vector2(0.0, 0.0)
			enemy_battle_line.size = Vector2(2.0, line_height)
	
	# 调整 Friendly Battle Line
	if battle_line:
		var line_height: float = current_rows * GameConst.GRID_SIZE
		battle_line.visible = false
		battle_line.custom_minimum_size = Vector2(2.0, line_height)
		# 我方战线在右侧边缘
		battle_line.position = Vector2(battle_field_width_actual, 0.0)
		battle_line.size = Vector2(2.0, line_height)

	# --- 调试：按 F2 测试对话 ---
	print("按 F2 测试对话功能")

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			start_intro_dialogue()

func start_intro_dialogue():
	# 只有在第一关（index 0）时才播放开场剧情
	if level_index != 0:
		return

	var resource = load("res://Dialogues/level1.dialogue")
	var balloon_scene = load("res://Scenes/Dialogue/CustomBalloon.tscn")
	if resource and balloon_scene:
		# 传入 [self] 以便在对话中调用 start_level
		DialogueManager.show_dialogue_balloon_scene(balloon_scene, resource, "start", [self])
	else:
		push_error("Dialogue resource or Balloon scene not found!")

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

func _process(_delta):
	# 战斗循环：推进战线、检测胜负、让超出战线的单位进入死亡状态。
	if not is_battle_started:
		_synergy_update_timer += _delta
		if _synergy_update_timer > 0.2:
			_synergy_update_timer = 0.0
			_check_and_apply_synergies()
		return
	if battle_ended: return
	
	# 改为检测双方存活单位数量
	var friendly_alive = _count_alive_units(true)
	var enemy_alive = _count_alive_units(false)
	
	# 如果双方同时死光，优先判负
	if friendly_alive == 0:
		_end_battle(false)
		return
	
	if enemy_alive == 0:
		_end_battle(true)
		return

	
	_update_ui() # 每帧更新血条有点浪费，实际可优化，原型先这样

func _count_alive_units(is_friendly: bool) -> int:
	var container = null
	if is_friendly:
		container = $Battlefield/FriendlyField/UnitsContainer
	else:
		container = $Battlefield/EnemyField/UnitsContainer
		
	if not container: return 0
	
	var count = 0
	for unit in container.get_children():
		if is_instance_valid(unit) and not unit.is_queued_for_deletion():
			# 必须是存活的 (假设 Unit 有 current_hp)
			if "current_hp" in unit and unit.current_hp > 0:
				# 修正：只计算已部署的单位 (is_deployed == true)
				# 备战区的单位不计入存活数
				if unit.get("is_deployed") == true:
					count += 1
	return count

# --- 供 Unit 调用的接口 ---

func find_target_for(attacker: Node2D) -> Node2D:
	if not attacker or not is_instance_valid(attacker): return null
	
	# 确定敌对阵营容器
	var target_container = null
	if attacker.faction == 0: # FRIENDLY
		target_container = $Battlefield/EnemyField/UnitsContainer
	else:
		target_container = $Battlefield/FriendlyField/UnitsContainer
		
	if not target_container: return null
	
	var my_rows = _get_unit_occupied_rows(attacker)
	var best_target = null
	var min_dist = INF
	
	# 策略1: 优先寻找本行最近的
	for enemy in target_container.get_children():
		if not _is_valid_target(enemy): continue
		
		var enemy_rows = _get_unit_occupied_rows(enemy)
		var has_overlap = false
		for r in my_rows:
			if r in enemy_rows:
				has_overlap = true
				break
		
		if has_overlap:
			var dist = abs(attacker.global_position.x - enemy.global_position.x)
			if dist < min_dist:
				min_dist = dist
				best_target = enemy
	
	# 策略2: 如果本行没找到，寻找全局最近的 (跨行支援)
	if not best_target:
		min_dist = INF # 重置
		for enemy in target_container.get_children():
			if not _is_valid_target(enemy): continue
			
			# 计算欧几里得距离 (不仅仅是 x 轴)
			var dist = attacker.global_position.distance_to(enemy.global_position)
			if dist < min_dist:
				min_dist = dist
				best_target = enemy
				
	return best_target

# --- 新增辅助战术函数 ---

func heal_lowest_hp_ally(amount: float, is_friendly: bool):
	var container = null
	if is_friendly:
		if has_node("Battlefield/FriendlyField/UnitsContainer"):
			container = $Battlefield/FriendlyField/UnitsContainer
	else:
		if has_node("Battlefield/EnemyField/UnitsContainer"):
			container = $Battlefield/EnemyField/UnitsContainer
	
	if not container: return
	
	var target = null
	var min_hp_ratio = 1.0
	var found = false
	
	for unit in container.get_children():
		if is_instance_valid(unit) and not unit.is_queued_for_deletion():
			if "current_hp" in unit and unit.current_hp > 0 and "data" in unit and unit.data:
				# 必须是已受伤的
				if unit.current_hp < unit.data.max_hp:
					var ratio = unit.current_hp / unit.data.max_hp
					if ratio <= min_hp_ratio:
						min_hp_ratio = ratio
						target = unit
						found = true
	
	if found and target:
		if target.has_method("heal"):
			target.heal(amount)
		else:
			target.current_hp = min(target.current_hp + amount, target.data.max_hp)
			if target.has_method("_update_health_visuals"):
				target._update_health_visuals()

func deal_damage_to_random_enemy(amount: float, is_friendly_attacker: bool):
	var target_container = null
	if is_friendly_attacker:
		if has_node("Battlefield/EnemyField/UnitsContainer"):
			target_container = $Battlefield/EnemyField/UnitsContainer
	else:
		if has_node("Battlefield/FriendlyField/UnitsContainer"):
			target_container = $Battlefield/FriendlyField/UnitsContainer
		
	if not target_container: return
	
	var valid_targets = []
	for unit in target_container.get_children():
		if _is_valid_target(unit):
			valid_targets.append(unit)
			
	if valid_targets.size() > 0:
		var target = valid_targets.pick_random()
		if target.has_method("take_damage"):
			target.take_damage(amount)

func _is_valid_target(unit: Node2D) -> bool:
	if not is_instance_valid(unit): return false
	if unit.is_queued_for_deletion(): return false
	if "is_deployed" in unit and not unit.is_deployed: return false
	if "current_hp" in unit and unit.current_hp <= 0: return false
	return true

func _get_unit_occupied_rows(unit: Node2D) -> Array:
	var rows = []
	# 假设 unit.position 是相对于 Container 的，可以直接换算成 Grid
	# 注意：这里需要确保 GridManager 的 grid_size 正确
	# 更好的是用 stored_grid_pos，如果 Unit 存了这个
	if "stored_grid_pos" in unit:
		var anchor = unit.stored_grid_pos
		if "data" in unit and unit.data and unit.data.grid_shape:
			for offset in unit.data.grid_shape:
				rows.append(anchor.y + offset.y)
		else:
			rows.append(anchor.y)
	else:
		# fallback
		var grid_pos = GridManager.world_to_grid(unit.position)
		rows.append(grid_pos.y)
	return rows

# 对敌人造成伤害 (新增)
func deal_damage_to_enemy(_amount: float):
	pass

func deal_damage_to_army(_amount: float):
	pass

# 修改民力
func modify_manpower(amount: float):
	current_manpower += amount
	current_manpower = clampf(current_manpower, 0.0, max_manpower)
	_update_ui()

# 修改敌方民力
func modify_enemy_manpower(amount: float):
	enemy_current_manpower += amount
	enemy_current_manpower = clampf(enemy_current_manpower, 0.0, enemy_max_manpower)
	_update_ui()

# 统一更新 UI
func _update_ui():
	if manpower_label: manpower_label.text = "民力: %.1f" % current_manpower
	if enemy_manpower_label: enemy_manpower_label.text = "敌方民力: %.1f" % enemy_current_manpower
	
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
	
	if victory:
		# 胜利：先播放剧情，剧情结束后由对话调用 show_victory_screen
		show_victory_dialogue()
	else:
		# 失败：直接显示结算
		get_tree().paused = true
		_show_defeat_screen()

func show_victory_dialogue():
	var dialogue_path = ""
	# Level 0 -> 1_1.dialogue
	if level_index == 0:
		dialogue_path = "res://Dialogues/1_1.dialogue"
	# Level 1 -> 2_1.dialogue
	elif level_index == 1:
		dialogue_path = "res://Dialogues/2_1.dialogue"
	# Level 2 -> 3_1.dialogue
	elif level_index == 2:
		dialogue_path = "res://Dialogues/3_1.dialogue"
	
	# 如果没有对应的剧情文件，直接显示结算
	if dialogue_path == "":
		show_victory_screen()
		return

	var resource = load(dialogue_path)
	var balloon_scene = load("res://Scenes/Dialogue/CustomBalloon.tscn")
	
	if resource and balloon_scene:
		# 传入 [self] 以便在对话中调用 show_victory_screen
		# 既然是独立文件，默认从 ~ start 开始
		DialogueManager.show_dialogue_balloon_scene(balloon_scene, resource, "start", [self])
	else:
		# 如果加载失败，直接显示结算
		show_victory_screen()

# 供对话调用的接口
func show_victory_screen():
	get_tree().paused = true
	if result_overlay:
		result_overlay.visible = true
	if result_title_label:
		result_title_label.text = "胜利"
	
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
		var detail := "我方存活: %d\n敌方存活: %d\n民力: %.1f%s" % [_count_alive_units(true), _count_alive_units(false), current_manpower, reward_text]
		result_detail_label.text = detail

func _show_defeat_screen():
	# 确保胜利窗口不会同时出现
	if result_title_label and result_title_label.text == "胜利" and result_overlay.visible:
		return
		
	if result_overlay:
		result_overlay.visible = true
	if result_title_label:
		result_title_label.text = "失败"
		
	if next_level_button: next_level_button.visible = false
	if retry_button: retry_button.visible = true
	if reward_container: reward_container.visible = false
	if result_detail_label:
		var detail := "我方存活: %d\n敌方存活: %d\n民力: %.1f" % [_count_alive_units(true), _count_alive_units(false), current_manpower]
		result_detail_label.text = detail

# --- 羁绊系统 ---
func _check_and_apply_synergies():
	if not units_container: return
	
	var civ_counts = {}
	var class_counts = {}
	
	var civ_unique_types = {} # { "han": { "soldier_name": true, ... } }
	var class_unique_types = {} # { "infantry": { "soldier_name": true, ... } }
	
	var deployed_units = []
	
	# 1. 统计场上单位
	for unit in units_container.get_children():
		# 重置属性 (防止多次点击叠加，虽然目前只点一次)
		if unit.has_method("reset_stats"):
			unit.reset_stats() 
		
		# 检查是否已部署
		if unit.get("is_deployed") == true:
			deployed_units.append(unit)
			if unit.data:
				var civ = unit.data.civilization
				var cls = unit.data.unit_class
				var u_name = unit.data.name
				
				# 初始化字典
				if not civ_unique_types.has(civ): civ_unique_types[civ] = {}
				if not class_unique_types.has(cls): class_unique_types[cls] = {}
				
				# 记录唯一类型
				civ_unique_types[civ][u_name] = true
				class_unique_types[cls][u_name] = true

	# 计算数量
	for civ in civ_unique_types:
		civ_counts[civ] = civ_unique_types[civ].size()
	for cls in class_unique_types:
		class_counts[cls] = class_unique_types[cls].size()
	
	# 2. 定义加成规则 (这里硬编码，也可以配表)
	
	# -- 文明羁绊 --
	# 汉 (Han): 2人 -> +2 ATK; 4人 -> +5 ATK
	var han_bonus_atk = 0.0
	if civ_counts.get("han", 0) >= 4: han_bonus_atk = 5.0
	elif civ_counts.get("han", 0) >= 2: han_bonus_atk = 2.0
	
	# 罗马 (Roman): 2人 -> +20 Max HP
	var roman_bonus_hp = 0.0
	if civ_counts.get("roman", 0) >= 2: roman_bonus_hp = 20.0
	
	# 希腊 (Greek): 2人 -> +10% 冷却缩减 (简单实现为减CD时间)
	var greek_bonus_cdr = 0.0
	if civ_counts.get("greek", 0) >= 2: greek_bonus_cdr = 0.2 # 减少0.2秒冷却

	# -- 兵种羁绊 --
	# 步兵 (Infantry): 2人 -> +10 HP; 4人 -> +30 HP
	var inf_bonus_hp = 0.0
	if class_counts.get("infantry", 0) >= 4: inf_bonus_hp = 30.0
	elif class_counts.get("infantry", 0) >= 2: inf_bonus_hp = 10.0
	
	# 弓手 (Archer): 2人 -> +2 ATK
	var archer_bonus_atk = 0.0
	if class_counts.get("archer", 0) >= 2: archer_bonus_atk = 2.0
	
	# 盾兵 (Shield): 2人 -> +20 HP
	var shield_bonus_hp = 0.0
	if class_counts.get("shield", 0) >= 2: shield_bonus_hp = 20.0
	
	# 骑兵 (Cavalry): 2人 -> +2 ATK, +5 HP
	var cav_bonus_atk = 0.0
	var cav_bonus_hp = 0.0
	if class_counts.get("cavalry", 0) >= 2:
		cav_bonus_atk = 2.0
		cav_bonus_hp = 5.0
		
	# 辅助 (Support): 2人 -> +10 HP
	var sup_bonus_hp = 0.0
	if class_counts.get("support", 0) >= 2: sup_bonus_hp = 10.0

	# 3. 应用加成
	for unit in deployed_units:
		if not unit.data: continue
		
		var civ = unit.data.civilization
		var cls = unit.data.unit_class
		
		# 应用文明加成
		if civ == "han" and han_bonus_atk > 0:
			unit.apply_synergy_bonus("attack_damage", han_bonus_atk)
			
		if civ == "roman" and roman_bonus_hp > 0:
			unit.apply_synergy_bonus("max_hp", roman_bonus_hp)
			
		if civ == "greek" and greek_bonus_cdr > 0:
			unit.apply_synergy_bonus("cooldown_flat", greek_bonus_cdr)
			
		# 应用兵种加成
		if cls == "infantry" and inf_bonus_hp > 0:
			unit.apply_synergy_bonus("max_hp", inf_bonus_hp)
			
		if cls == "archer" and archer_bonus_atk > 0:
			unit.apply_synergy_bonus("attack_damage", archer_bonus_atk)
			
		if cls == "shield" and shield_bonus_hp > 0:
			unit.apply_synergy_bonus("max_hp", shield_bonus_hp)
			
		if cls == "cavalry":
			if cav_bonus_atk > 0: unit.apply_synergy_bonus("attack_damage", cav_bonus_atk)
			if cav_bonus_hp > 0: unit.apply_synergy_bonus("max_hp", cav_bonus_hp)
			
		if cls == "support" and sup_bonus_hp > 0:
			unit.apply_synergy_bonus("max_hp", sup_bonus_hp)
			
	# 4. 应用相邻加成 (Adjacency Bonuses)
	_apply_adjacency_bonuses(deployed_units)
	
	# 更新相邻连线视觉
	_update_adjacency_visuals(deployed_units)

	# (可选) 在UI上显示触发的羁绊
	_update_synergy_ui(civ_counts, class_counts)

func _update_adjacency_visuals(units: Array):
	if not _adjacency_lines_node: return
	if not GridManager: return
	
	# 1. 收集当前所有有效的边
	var active_edges = {} # Key: String "x1,y1|x2,y2", Value: { "c1": v2, "c2": v2, "color": Color }
	
	for unit in units:
		if not unit.data or unit.data.adjacency_rules.is_empty():
			continue
		# 必须是活着的
		if "current_hp" in unit and unit.current_hp <= 0:
			continue
			
		var neighbors = GridManager.get_neighbors(unit)
		for rule in unit.data.adjacency_rules:
			var mode = rule.get("type", "give")
			var req_type = rule.get("req_type", "all")
			var req_val = rule.get("req_value", "")
			
			for neighbor in neighbors:
				if not neighbor.data: continue
				if "current_hp" in neighbor and neighbor.current_hp <= 0: continue
				
				var match_req = false
				if req_type == "all":
					match_req = true
				elif req_type == "tag":
					if neighbor.data.tags.has(req_val): match_req = true
				elif req_type == "class":
					if neighbor.data.unit_class == req_val: match_req = true
				elif req_type == "civ":
					if neighbor.data.civilization == req_val: match_req = true
				
				if match_req:
					# 确定颜色
					var color = Color(0.3, 1.0, 0.3, 1.0) # Green
					if mode == "receive":
						color = Color(0.3, 0.7, 1.0, 1.0) # Blue
						
					# 计算具体的边线段
					var cells1 = _get_unit_cells(unit)
					var cells2 = _get_unit_cells(neighbor)
					
					for c1 in cells1:
						for c2 in cells2:
							var diff = c2 - c1
							if diff.length_squared() == 1:
								var key = _get_edge_key(c1, c2)
								# 如果同一条边有多个加成，保留一个即可（或者混合颜色？）
								# 这里简单覆盖
								active_edges[key] = {
									"c1": c1, 
									"direction": diff,
									"color": color
								}

	# 2. 清理不再存在的边
	var current_children = _adjacency_lines_node.get_children()
	for child in current_children:
		if child.name not in active_edges:
			child.queue_free()
		else:
			# 如果存在，从 active_edges 移除，避免重复创建
			# 但我们需要更新颜色吗？如果颜色变了...
			# 简单起见，如果存在就不动，假设颜色不变。
			active_edges.erase(child.name)
	
	# 3. 创建新增的边
	for key in active_edges:
		var data = active_edges[key]
		_draw_edge_segment(data.c1, data.direction, data.color, key)

func _get_edge_key(c1: Vector2i, c2: Vector2i) -> String:
	# 保证 Key 唯一且与顺序无关
	if c1.x < c2.x or (c1.x == c2.x and c1.y < c2.y):
		return "%d,%d|%d,%d" % [c1.x, c1.y, c2.x, c2.y]
	else:
		return "%d,%d|%d,%d" % [c2.x, c2.y, c1.x, c1.y]

func _draw_adjacency_edge(from_unit, to_unit, mode):
	#此函数已被 _update_adjacency_visuals 的批量逻辑取代，保留为空或删除
	pass

func _draw_edge_segment(cell_grid_pos: Vector2i, direction: Vector2i, color: Color, key_name: String = ""):
	var size = GameConst.GRID_SIZE
	var cell_world_pos = GridManager.grid_to_world(cell_grid_pos)
	
	var start_pos = Vector2.ZERO
	var end_pos = Vector2.ZERO
	
	# 根据方向确定边线位置
	if direction == Vector2i.RIGHT:
		start_pos = cell_world_pos + Vector2(size, 0)
		end_pos = cell_world_pos + Vector2(size, size)
	elif direction == Vector2i.LEFT:
		start_pos = cell_world_pos
		end_pos = cell_world_pos + Vector2(0, size)
	elif direction == Vector2i.DOWN:
		start_pos = cell_world_pos + Vector2(0, size)
		end_pos = cell_world_pos + Vector2(size, size)
	elif direction == Vector2i.UP:
		start_pos = cell_world_pos
		end_pos = cell_world_pos + Vector2(size, 0)
	
	# 稍微内缩一点点，防止完全重叠
	var shrink = 2.0
	if direction.x != 0: # 竖线
		start_pos.y += shrink
		end_pos.y -= shrink
	else: # 横线
		start_pos.x += shrink
		end_pos.x -= shrink
		
	# 关键修复：先转 Global，再转 Local
	# 因为 start_pos 是相对于 units_container 的
	if not units_container: return

	var p1 = _adjacency_lines_node.to_local(units_container.to_global(start_pos))
	var p2 = _adjacency_lines_node.to_local(units_container.to_global(end_pos))
	
	var line = Line2D.new()
	if key_name != "":
		line.name = key_name
	
	line.width = 4.0
	line.default_color = color
	line.add_point(p1)
	line.add_point(p2)
	_adjacency_lines_node.add_child(line)
	
	# 呼吸动画
	var tw = create_tween().set_loops()
	tw.tween_property(line, "width", 2.0, 1.0).from(4.0)
	tw.tween_property(line, "width", 4.0, 1.0)
	
	var tw_alpha = create_tween().set_loops()
	tw_alpha.tween_property(line, "modulate:a", 0.5, 1.5)
	tw_alpha.tween_property(line, "modulate:a", 1.0, 1.5)

func _get_unit_cells(unit) -> Array:
	var cells = []
	var anchor = Vector2i.ZERO
	
	if "stored_grid_pos" in unit:
		anchor = unit.stored_grid_pos
	else:
		anchor = GridManager.world_to_grid(unit.position)
		
	if unit.data and unit.data.grid_shape:
		for offset in unit.data.grid_shape:
			cells.append(anchor + offset)
	else:
		cells.append(anchor)
	return cells

func _get_unit_center_offset(unit) -> Vector2:
	# 简单取第一个格子的中心，或者计算整个形状的中心
	# 这里取 GridSize/2 比较稳妥 (锚点格中心)
	return Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE) / 2.0

func _apply_adjacency_bonuses(units: Array):
	if not GridManager: return
	
	for unit in units:
		if not unit.data or unit.data.adjacency_rules.is_empty():
			continue
			
		var neighbors = GridManager.get_neighbors(unit)
		for rule in unit.data.adjacency_rules:
			var mode = rule.get("type", "give")
			var req_type = rule.get("req_type", "all")
			var req_val = rule.get("req_value", "")
			var stat = rule.get("effect_stat", "attack_damage")
			var val = rule.get("effect_value", 0.0)
			
			for neighbor in neighbors:
				if not neighbor.data: continue
				
				# Check requirement against the NEIGHBOR
				var match_req = false
				if req_type == "all":
					match_req = true
				elif req_type == "tag":
					if neighbor.data.tags.has(req_val): match_req = true
				elif req_type == "class":
					if neighbor.data.unit_class == req_val: match_req = true
				elif req_type == "civ":
					if neighbor.data.civilization == req_val: match_req = true
				
				if match_req:
					if mode == "give":
						neighbor.apply_synergy_bonus(stat, val)
					elif mode == "receive":
						unit.apply_synergy_bonus(stat, val)

func _update_synergy_ui(civ_counts, class_counts):
	if not synergy_label: return
	
	var text = "当前羁绊:\n"
	
	# 文明
	if civ_counts.get("han", 0) >= 4: text += "[汉] 4: 全体+5攻\n"
	elif civ_counts.get("han", 0) >= 2: text += "[汉] 2: 全体+2攻\n"
	
	if civ_counts.get("roman", 0) >= 2: text += "[罗马] 2: 全体+20血\n"
	if civ_counts.get("greek", 0) >= 2: text += "[希腊] 2: 全体-0.2s CD\n"
	
	# 兵种
	if class_counts.get("infantry", 0) >= 4: text += "[步兵] 4: 步兵+30血\n"
	elif class_counts.get("infantry", 0) >= 2: text += "[步兵] 2: 步兵+10血\n"
	
	if class_counts.get("archer", 0) >= 2: text += "[弓兵] 2: 弓兵+2攻\n"
	if class_counts.get("shield", 0) >= 2: text += "[盾兵] 2: 盾兵+20血\n"
	if class_counts.get("cavalry", 0) >= 2: text += "[骑兵] 2: 骑兵+2攻+5血\n"
	if class_counts.get("support", 0) >= 2: text += "[辅助] 2: 辅助+10血\n"
	
	synergy_label.text = text

# 按钮点击回调
func _on_start_button_pressed():
	if is_battle_started: return
	
	# 计算羁绊加成
	_check_and_apply_synergies()
	
	is_battle_started = true
	$CanvasLayer/HUD/StartButton.visible = false # 隐藏按钮
	
	# 激活所有单位
	# 告诉所有 Unit 开始 Timer
	get_tree().call_group("units", "start_battle")

func _on_next_level_button_pressed():
	if GameState:
		# 先保存当前进度（例如已通关的关卡索引）
		# 这里的逻辑是：如果我通关了第 0 关，现在应该去第 1 关
		# GameState.selected_level_index 是在进入场景时读取的
		# 所以我们在这里增加它
		GameState.selected_level_index = level_index + 1
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
		
	# 构建奖励池
	var pool = []
	
	# 1. 加入兵种卡牌
	for unit in db.units:
		pool.append({ "type": "unit", "data": unit })
		
	# 2. 加入扩充选项 (如果有空间)
	# 增加出现权重? 简单起见，作为普通项加入，但为了保证出现率，可以加多次，或者保证必出？
	# 用户说 "包括增加一行或一列"，意味着作为选项之一。
	
	if GameState:
		if GameState.current_rows < GameConst.MAP_ROWS:
			pool.append({ "type": "upgrade_row", "data": null })
			# 为了增加抽取几率，可以多加几个，或者不加
			
		if GameState.current_cols < GameConst.MAP_COLUMNS:
			pool.append({ "type": "upgrade_col", "data": null })

	pool.shuffle()
	var choices = pool.slice(0, 3)
	
	for item in choices:
		_create_reward_card_ui(item)

func _create_reward_card_ui(item: Dictionary):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(120, 160)
	
	var desc = ""
	var type = item.get("type", "unit")
	
	if type == "unit":
		var data = item["data"] as UnitData
		desc = data.name + "\n\n"
		desc += "ATK: %.0f\nCD: %.1f" % [data.attack_damage, data.cooldown]
		if not data.tags.is_empty():
			desc += "\n" + str(data.tags)
	elif type == "upgrade_row":
		desc = "【扩充战线】\n\n增加一行\n(横向)"
	elif type == "upgrade_col":
		desc = "【扩充战线】\n\n增加一列\n(纵向)"
		
	btn.text = desc
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(func(): _on_reward_selected(item))
	
	reward_container.add_child(btn)

func _on_reward_selected(item: Dictionary):
	var type = item.get("type", "unit")
	var reward_name = ""
	
	if type == "unit":
		var data = item["data"] as UnitData
		reward_name = data.name
		# 添加到玩家库
		if player_library:
			player_library.collected_cards.append(data)
			if GameState:
				GameState.save_player_library(player_library)
				
	elif type == "upgrade_row":
		reward_name = "战线扩充(行)"
		if GameState:
			GameState.current_rows = min(GameState.current_rows + 1, GameConst.MAP_ROWS)
			GameState.save_progress()
			
	elif type == "upgrade_col":
		reward_name = "战线扩充(列)"
		if GameState:
			GameState.current_cols = min(GameState.current_cols + 1, GameConst.MAP_COLUMNS)
			GameState.save_progress()

	# 隐藏奖励界面
	reward_container.visible = false
	
	# 更新文本提示
	if result_detail_label:
		result_detail_label.text += "\n\n已选择: %s" % reward_name
		
	# 显示下一关按钮 (如果有关卡)
	var has_next = false
	if level_database and level_index + 1 < level_database.levels.size():
		has_next = true
	
	if next_level_button:
		next_level_button.visible = has_next

func _grant_random_reward() -> UnitData:
	# 保留此函数以防万一，但逻辑已转移
	return null

func _spawn_enemy(spawn: UnitSpawn, map_cols: int = -1, map_rows: int = -1):
	# 生成敌方单位并直接部署到敌军网格。
	if not spawn:
		return
	if not spawn.unit_data:
		return
	if not enemy_field:
		return
	var enemy_units_container = $Battlefield/EnemyField/UnitsContainer
	if enemy_units_container:
		if not enemy_units_container:
			return
		
		var new_unit = unit_scene.instantiate()
		new_unit.data = spawn.unit_data
		new_unit.spawned_via_script = true
		new_unit.faction = new_unit.Faction.ENEMY
		enemy_units_container.add_child(new_unit)
		
		# 使用传入的尺寸或默认尺寸
		var check_cols = map_cols if map_cols > 0 else GameConst.MAP_COLUMNS
		var check_rows = map_rows if map_rows > 0 else GameConst.MAP_ROWS
		
		if _enemy_can_place(spawn.unit_data, spawn.grid_pos, check_cols, check_rows):
			_enemy_mark_occupied(spawn.unit_data, spawn.grid_pos)
			new_unit.position = GridManager.grid_to_world(spawn.grid_pos)
			new_unit.is_deployed = true
			new_unit.stored_grid_pos = spawn.grid_pos
			# 确保单位状态正常
			new_unit.modulate = Color.WHITE
		else:
			push_error("Failed to place enemy unit at " + str(spawn.grid_pos))
			# 放置失败也设为 deployed 只是为了测试，或者应该删除？
			# 暂时强制设为 deployed 以免无敌
			new_unit.is_deployed = true
			new_unit.position = GridManager.grid_to_world(spawn.grid_pos) # 强行放置
			new_unit.stored_grid_pos = spawn.grid_pos
			new_unit.modulate = Color.WHITE

func _enemy_can_place(data: UnitData, grid_pos: Vector2i, max_cols: int, max_rows: int) -> bool:
	for part in data.grid_shape:
		var cell = grid_pos + part
		if cell.x < 0 or cell.x >= max_cols:
			return false
		if cell.y < 0 or cell.y >= max_rows:
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
	# 修改：备战区位置改为固定值，不随战场大小变化
	
	# 注意：bench_offset 现在是相对于 friendly_field 左上角的绝对坐标
	var start_y = bench_offset.y
	var gap_x = 85.0 
	var gap_y = 90.0
	var cols = bench_columns
	
	# 起始 X 坐标也改为固定
	var start_x = bench_offset.x

	# 调整背景框
	# 已移除对 ColorRect 的依赖

	# 开始排布
	for i in range(visible_cards.size()):
		var unit = visible_cards[i]
		var row = int(i / cols)
		var col = i % cols
		
		var x = start_x + (col * gap_x)
		var y = start_y + (row * gap_y)
		
		var target_pos = Vector2(x, y)
		
		# 检查这个单位脚本里有没有 update_bench_pos 这个函数
		if unit.has_method("update_bench_pos"):
			# 有的话，就调用它，把目标坐标传过去
			unit.update_bench_pos(target_pos)
