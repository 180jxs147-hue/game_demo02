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
static var instance: BattleManager
var unit_scene = preload("res://Scenes/Unit.tscn")
var battle_log_ui_scene = preload("res://Scenes/BattleLogUI.tscn")
var battle_log_ui_instance = null

# --- 战斗参数 ---
static var is_battle_started: bool = false
var current_manpower: float = 10.0
var max_manpower: float = 50.0

# 敌方民力 (新增)
var enemy_current_manpower: float = 10.0
var enemy_max_manpower: float = 50.0

# --- Visual Effects ---
var _shake_strength: float = 0.0
var _shake_decay: float = 10.0
@onready var _camera: Camera2D = get_viewport().get_camera_2d()
# ----------------------

@onready var battlefield = $Battlefield
@onready var friendly_field = $Battlefield/FriendlyField
@onready var enemy_field = $Battlefield/EnemyField

@onready var friendly_grid_vis = $Battlefield/FriendlyField/GridVisualizer
@onready var enemy_grid_vis = $Battlefield/EnemyField/GridVisualizer

@onready var result_overlay = $CanvasLayer/ResultOverlay
@onready var result_title_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/TitleLabel
@onready var result_progress_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/ProgressLabel
@onready var result_detail_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/DetailLabel
@onready var reward_hint_label = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/RewardHint
@onready var next_level_button = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/HBoxContainer/NextLevelButton
@onready var retry_button = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/HBoxContainer/RetryButton

var _tooltip_instance: Control
var _tooltip_target: Node = null
var _camp_intro_pending: bool = false
var _intro_dialogue_started: bool = false
var _active_tutorial: Node

@onready var reward_container = $CanvasLayer/ResultOverlay/Panel/VBoxContainer/RewardContainer

@onready var bench_panel = $CanvasLayer/HUD/BenchPanel
@onready var bench_grid = $CanvasLayer/HUD/BenchPanel/VBox/Scroll/Grid

var _synergy_update_timer: float = 0.0

var battle_ended: bool = false
var _has_level_enemies: bool = false
var _enemy_occupied: Dictionary = {}

var _adjacency_lines_node: Node2D # 用于绘制连线

var _card_slot_scene = preload("res://Scenes/CardSlot.tscn")
var _battle_presentation: Node
const _BENCH_CARD_SIZE := Vector2(126, 180) ## 备战区卡牌的显示尺寸（CardSlot 原始 280x400 等比缩小，适配底栏高度）
var _reward_primary_button_texture: Texture2D = preload("res://Assets/UI/Battle/reward_button_primary_v2.png")
var _reward_secondary_button_texture: Texture2D = preload("res://Assets/UI/Battle/reward_button_secondary_v2.png")
var _reward_resolved: bool = false
var _reward_action_buttons: Array = []

# 存储当前的敌人网格尺寸，供 _apply_layout 使用
var current_enemy_cols: int = GameConst.MAP_COLUMNS
var current_enemy_rows: int = GameConst.MAP_ROWS

# 当前关卡配置引用
var current_level_config: LevelConfig

func _exit_tree():
	if instance == self:
		instance = null

func log_message(msg: String, color: Color = Color.WHITE):
	if battle_log_ui_instance and battle_log_ui_instance.has_method("add_log"):
		battle_log_ui_instance.add_log(msg, color)

func enter_camp_before_level(level_id: String):
	if GameState and GameState.has_method("enter_camp_then_level"):
		GameState.enter_camp_then_level(level_id)

func set_shop_pool_for_next_camp(pool_id: String):
	if GameState and GameState.has_method("set_next_shop_pool"):
		GameState.set_next_shop_pool(pool_id)

func _ready():
	print("BattleManager: _ready started")
	if instance == null:
		instance = self
	
	# 初始化战斗日志UI
	if battle_log_ui_scene:
		battle_log_ui_instance = battle_log_ui_scene.instantiate()
		# 添加到HUD层，确保在最上层显示
		var hud_node = get_node_or_null("CanvasLayer/HUD")
		if hud_node:
			hud_node.add_child(battle_log_ui_instance)
			
			# 创建打开日志的按钮
			var open_log_btn = Button.new()
			open_log_btn.text = "战斗日志"
			open_log_btn.name = "BattleLogButton"
			
			# 使用锚点定位到右上角
			open_log_btn.layout_mode = 1 # Anchors
			open_log_btn.anchor_left = 1.0
			open_log_btn.anchor_top = 0.0
			open_log_btn.anchor_right = 1.0
			open_log_btn.anchor_bottom = 0.0
			
			open_log_btn.offset_left = -120
			open_log_btn.offset_top = 70
			open_log_btn.offset_right = -20
			open_log_btn.offset_bottom = 100
			open_log_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			
			if GameState:
				GameState.apply_button_style(open_log_btn)
			
			open_log_btn.pressed.connect(func(): 
				if battle_log_ui_instance: 
					battle_log_ui_instance.toggle()
			)
			hud_node.add_child(open_log_btn)
			
			# --- [New Feature] 战斗倍速按钮 ---
			var speed_btn = Button.new()
			speed_btn.text = "1x"
			speed_btn.name = "BattleSpeedButton"
			speed_btn.layout_mode = 1
			speed_btn.anchor_left = 1.0
			speed_btn.anchor_top = 0.0
			speed_btn.anchor_right = 1.0
			speed_btn.anchor_bottom = 0.0
			
			speed_btn.offset_left = -120
			speed_btn.offset_top = 110
			speed_btn.offset_right = -20
			speed_btn.offset_bottom = 140
			speed_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			
			if GameState:
				GameState.apply_button_style(speed_btn)
				
			speed_btn.pressed.connect(func():
				var current = Engine.time_scale
				var next = 1.0
				if is_equal_approx(current, 1.0): next = 2.0
				elif is_equal_approx(current, 2.0): next = 3.0
				else: next = 1.0
				
				Engine.time_scale = next
				speed_btn.text = "%.0fx" % next
			)
			hud_node.add_child(speed_btn)

	
	_apply_theme()
	if get_viewport() and not get_viewport().size_changed.is_connected(_fit_result_overlay):
		get_viewport().size_changed.connect(_fit_result_overlay)
	call_deferred("_fit_result_overlay")
	_setup_bench_ui()
	
	# --- 强制修复交互遮挡 ---
	var hud = get_node_or_null("CanvasLayer/HUD")
	if hud:
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		print("[BattleManager] HUD mouse_filter set to IGNORE")
	else:
		push_error("[BattleManager] HUD node not found!")

	var res_overlay = get_node_or_null("CanvasLayer/ResultOverlay")
	if res_overlay:
		res_overlay.visible = false
		res_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		print("[BattleManager] ResultOverlay forced hidden and IGNORE")
	
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
	if not level_database or level_database.levels.is_empty():
		push_error("[BattleManager] Level database is missing or empty.")
		return
	if level_index < 0 or level_index >= level_database.levels.size():
		var fallback_index := level_database.get_index_by_id("1_0_1")
		if fallback_index < 0: fallback_index = 0
		push_warning("[BattleManager] Saved level index %d is invalid; using database fallback %d." % [level_index, fallback_index])
		level_index = fallback_index
		if GameState: GameState.selected_level_index = level_index
	level = level_database.get_level(level_index)
	current_level_config = level
	if not current_level_config:
		push_error("[BattleManager] No level config at index %d." % level_index)
		return
	print("[BattleManager] Loading selected campaign level %s (index %d): %s" % [level.level_id, level_index, level.level_name])
	
	# --- 设置背景图片 ---
	_update_background()
	
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
			GameState.set_current_library(loaded)

	# --- 1. 动态调整战场格子数量 ---
	# 逻辑：取玩家解锁的尺寸与关卡要求尺寸的较大值
	# 修正：玩家战场尺寸只应该由 GameState 决定，不应该受关卡敌军规模影响
	# 敌军规模（grid_width/grid_height）只影响敌军战场的生成
	
	var final_cols = GameConst.MAP_COLUMNS
	var final_rows = GameConst.MAP_ROWS
	
	# 检查是否需要自动播放关卡剧情（从营地返回时）
	if GameState and "next_level_id_from_camp" in GameState and GameState.next_level_id_from_camp != "":
		var id = GameState.next_level_id_from_camp
		print("BattleManager: Found next_level_id_from_camp: ", id)
		# 清除标记防止重复
		GameState.next_level_id_from_camp = ""
		# 如果需要跳过（例如上一段剧情已经作为该关的引子），则不再播放
		if not GameState.skip_intro:
			_camp_intro_pending = true
			print("[BattleManager] Auto-playing intro for level: ", id)
			# 延迟一帧调用以确保 _ready 完成
			get_tree().create_timer(0.1).timeout.connect(func():
				play_level_intro(id)
			)
		else:
			print("BattleManager: skip_intro is true. Skipping intro for: ", id)
			GameState.skip_intro = false
	else:
		# The selected level was already initialized from GameState above.
		# Never replace it with the tutorial opening level on normal loads.
		print("[BattleManager] No pending camp level; keeping selected level %s." % level.level_id)

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


	if level:
		if units_container:
			for spawn in level.enemy_units:
				_spawn_enemy(spawn, current_enemy_cols, current_enemy_rows)
			_has_level_enemies = level.enemy_units.size() > 0

	# --- Apply Relic & Progression Bonuses to Manpower ---
	if GameState:
		var bonus_max = 0.0
		var start_mp = GameState.get_relic_effect_value("start_manpower")
		var relic_max_mp = GameState.get_relic_effect_value("global_max_manpower")
		
		if "run_manpower_bonus" in GameState:
			bonus_max += GameState.run_manpower_bonus
			
		max_manpower = 50.0 + bonus_max + relic_max_mp
		# Apply start_manpower as an increase to initial current_manpower
		# Assuming current_manpower starts at 10.0
		current_manpower = 10.0 + start_mp + bonus_max
		current_manpower = min(current_manpower, max_manpower)

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
	call_deferred("_start_intro_or_tutorial")
	
	print("[BattleManager] _ready completed successfully")

	# 初始化提示框
	var tooltip_scene = load("res://Scenes/Tooltip.tscn")
	if tooltip_scene:
		_tooltip_instance = tooltip_scene.instantiate()
		_tooltip_instance.visible = false
		_tooltip_instance.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		$CanvasLayer/HUD.add_child(_tooltip_instance)

	if player_library:
		# 只有在游戏开始时，才把库里的卡加进战斗
		for card_data in player_library.collected_cards:
			spawn_unit(card_data)
	_refresh_bench_ui()
	
	# [New Feature] Trigger Autosave at Level Start
	if GameState and GameState.has_method("trigger_autosave"):
		GameState.trigger_autosave()

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("[BattleManager] Click at ", event.position)
		# 尝试检测鼠标下的节点（仅供调试）
		# 注意：这只对 Control 节点有效，Node2D 需要物理查询
		var viewport = get_viewport()
		if viewport:
			# 简单的 UI 拾取检查
			pass

func start_level(index: int):
	print("Switching to level: ", index)
	get_tree().paused = false
	
	if GameState:
		GameState.selected_level_index = index
	level_index = index
	
	var level = null
	if level_database:
		level = level_database.get_level(level_index)
	
	current_level_config = level
	_camp_intro_pending = false
	_update_background()
	
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
	max_manpower = 50.0 # 默认值
	if GameState:
		max_manpower += GameState.get_run_manpower_bonus()
	
	current_manpower = max_manpower
	
	enemy_max_manpower = 50.0
	if "enemy_power" in level:
		enemy_max_manpower = float(level.enemy_power)
		print("[BattleManager] Loaded enemy_power: ", level.enemy_power, " -> enemy_max_manpower: ", enemy_max_manpower)
	else:
		print("[BattleManager] enemy_power not found in level config, using default 50.0")
	enemy_current_manpower = enemy_max_manpower
	
	# 3. 调整格子大小 (分别设置)
	# 玩家格子大小：只受 GameState 影响 (除非关卡特别指定)
	var player_cols = GameState.current_cols if GameState else GameConst.MAP_COLUMNS
	var player_rows = GameState.current_rows if GameState else GameConst.MAP_ROWS
	
	if "formation_cols" in level and level.formation_cols > 0:
		player_cols = level.formation_cols
	if "formation_rows" in level and level.formation_rows > 0:
		player_rows = level.formation_rows
	
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
		
		# Reset player units state
		if units_container:
			for unit in units_container.get_children():
				if unit.is_queued_for_deletion(): continue
				
				# 重置状态机和数值
				if unit.has_method("reset_state"):
					unit.reset_state()
				
				# 确保重新注册到 GridManager
				if unit.is_deployed and "stored_grid_pos" in unit:
					GridManager.place_unit(unit, unit.stored_grid_pos)
	
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
	
	# 应用局外成长加成
	if GameState:
		max_manpower += GameState.get_max_manpower_bonus()
		bench_columns += GameState.get_bench_columns_bonus()
		# 应用宝物加成
		max_manpower += GameState.get_relic_effect_value("start_manpower")
	
	# Ensure Start Button is visible
	if has_node("CanvasLayer/HUD/StartButton"):
		var start_btn = $CanvasLayer/HUD/StartButton
		start_btn.visible = true
		start_btn.disabled = false

	call_deferred("_arrange_bench")
	call_deferred("_apply_layout")
	call_deferred("_check_tutorial")
	if GameState:
		GameState.trigger_autosave()

func _apply_layout():
	if not _battle_presentation:
		_battle_presentation = preload("res://Scripts/BattlePresentation.gd").new()
		_battle_presentation.name = "BattlePresentation"
		add_child(_battle_presentation)
	else:
		_battle_presentation.layout()


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			start_intro_dialogue()

func start_intro_dialogue():
	if _intro_dialogue_started:
		return true
	# 只有在第一关（index 0）时才播放开场剧情
	if level_index != 0:
		return false

	# 使用 1_0_1.dialogue 而不是 level1.dialogue，以便统一管理
	var dialogue_path = BattleManager.get_dialogue_path_by_id("1_0_1")
	var resource = load(dialogue_path)
	var balloon_scene = load("res://Scenes/Dialogue/CustomBalloon.tscn")
	if resource and balloon_scene:
		_intro_dialogue_started = true
		# 传入 [self] 以便在对话中调用 start_level
		DialogueManager.show_dialogue_balloon_scene(balloon_scene, resource, "start", [self])
		return true
	else:
		push_error("Dialogue resource or Balloon scene not found!")
		return false

func _start_intro_or_tutorial():
	# LevelSelect may already have played this level's dialogue before entering
	# Battle. Consume that handoff and start its tutorial once, without replaying
	# the dialogue over the tutorial callouts.
	if _camp_intro_pending:
		return
	if GameState and GameState.skip_intro:
		GameState.skip_intro = false
		_check_tutorial()
		return
	if level_index == 0 and start_intro_dialogue():
		return
	_check_tutorial()

func _debug_add_random_unit() -> UnitData:
	var random_datas = [
		preload("res://Resources/DataFiles/soldier.tres"),
		preload("res://Resources/DataFiles/Pyrrhus.tres"),
		preload("res://Resources/DataFiles/quarter.tres"),
		preload("res://Resources/DataFiles/archer.tres"),
		preload("res://Resources/DataFiles/han_caiguan.tres"),
		preload("res://Resources/DataFiles/cavalry.tres"),
		preload("res://Resources/DataFiles/catapult.tres"),
		preload("res://Resources/DataFiles/shield.tres"),
		preload("res://Resources/DataFiles/farmer.tres"),
		preload("res://Resources/DataFiles/war_drum.tres"),
		preload("res://Resources/DataFiles/supply_cart.tres"),
		preload("res://Resources/DataFiles/scout_tower.tres")
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
		preload("res://Resources/DataFiles/han_caiguan.tres"),
		preload("res://Resources/DataFiles/cavalry.tres"),
		preload("res://Resources/DataFiles/catapult.tres"),
		preload("res://Resources/DataFiles/shield.tres"),
		preload("res://Resources/DataFiles/farmer.tres"),
		preload("res://Resources/DataFiles/war_drum.tres"),
		preload("res://Resources/DataFiles/supply_cart.tres"),
		preload("res://Resources/DataFiles/scout_tower.tres")
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

func _check_tutorial():
	if not current_level_config:
		return
	if is_instance_valid(_active_tutorial) and _active_tutorial.is_queued_for_deletion():
		_active_tutorial = null
	if is_instance_valid(_active_tutorial):
		return
		
	var level_id = current_level_config.level_id
	var tutorial_script_path = "res://Scripts/Tutorials/Tutorial_%s.gd" % level_id
	
	if ResourceLoader.exists(tutorial_script_path):
		var tutorial_script = load(tutorial_script_path)
		if tutorial_script:
			var tutorial = tutorial_script.new()
			tutorial.name = "ActiveLevelTutorial"
			_active_tutorial = tutorial
			add_child(tutorial)
			tutorial.tree_exited.connect(func():
				if _active_tutorial == tutorial:
					_active_tutorial = null
			)
			if tutorial.has_method("start"):
				tutorial.start(self)



func _update_background():
	# 移除旧背景
	var old_bg = get_node_or_null("BackgroundLayer")
	if old_bg:
		old_bg.queue_free()

	var texture = null
	if current_level_config and current_level_config.background_texture:
		texture = current_level_config.background_texture
	
	# 如果没有配置背景，强制使用默认背景
	if not texture or texture.resource_path == "res://Resources/ImageFiles/Backgrounds/battleground.png":
		texture = load("res://Assets/UI/Battle/dusk.png")
	
	if texture:
		print("[BattleManager] Loading background: ", texture.resource_path)
		var bg_layer = CanvasLayer.new()
		bg_layer.layer = -100 # 最底层
		bg_layer.name = "BackgroundLayer"
		add_child(bg_layer)
		
		var bg_rect = TextureRect.new()
		bg_rect.texture = texture
		# 确保全屏填充
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		# 调暗背景，提高特效和网格的对比度
		bg_rect.modulate = Color(0.86, 0.86, 0.86, 1.0)
		
		# 确保不遮挡
		bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		bg_layer.add_child(bg_rect)
		print("[BattleManager] Background created with size: ", bg_rect.size)
	else:
		print("[BattleManager] No background texture available (Config: ", current_level_config, ")")
		# --- 调试：如果没有图片，显示一个深色背景 ---
		var bg_layer = CanvasLayer.new()
		bg_layer.layer = -100
		bg_layer.name = "BackgroundLayer"
		add_child(bg_layer)
		var color_rect = ColorRect.new()
		color_rect.color = Color(0.1, 0.1, 0.15)
		color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# 强制大小
		var vp_size = get_viewport_rect().size
		color_rect.size = vp_size
		
		bg_layer.add_child(color_rect)
		print("[BattleManager] Created fallback ColorRect background")

func _process(_delta):
	# 始终更新 Tooltip 位置
	_update_tooltip_position()
	
	# --- Screen Shake Update ---
	if _shake_strength > 0:
		_shake_strength = lerpf(_shake_strength, 0, _shake_decay * _delta)
		var offset = Vector2(randf_range(-_shake_strength, _shake_strength), randf_range(-_shake_strength, _shake_strength))
		
		# 优先震动相机，如果没有相机则震动 Battlefield
		if _camera:
			_camera.offset = offset
		elif has_node("Battlefield"):
			$Battlefield.position = battlefield_position + offset
	elif has_node("Battlefield"):
		# 恢复原始位置
		if $Battlefield.position != battlefield_position:
			$Battlefield.position = battlefield_position
	# ---------------------------

	# 战斗循环：推进战线、检测胜负、让超出战线的单位进入死亡状态。
	if not is_battle_started:
		_synergy_update_timer += _delta
		if _synergy_update_timer > 0.2:
			_synergy_update_timer = 0.0
			_check_and_apply_synergies()
		return
	if battle_ended: return
	
	# Apply Manpower Regen Relic
	if GameState:
		var regen = GameState.get_relic_effect_value("manpower_regen")
		if regen > 0:
			modify_manpower(regen * _delta)
	
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

# --- Visual Effects Interface ---

func trigger_shake(strength: float = 5.0):
	_shake_strength = max(_shake_strength, strength)

func spawn_floating_text(pos: Vector2, text: String, color: Color):
	var label = Label.new()
	label.text = text
	label.modulate = color
	label.z_index = 100 # Ensure on top
	
	# Style settings
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 24)
	
	# Add random offset to prevent perfect overlap
	var offset = Vector2(randf_range(-16, 16), randf_range(-8, 8))
	
	# Add to scene
	if has_node("Battlefield"):
		$Battlefield.add_child(label)
	else:
		add_child(label)
		
	label.global_position = pos + Vector2(0, -30) + offset
	label.scale = Vector2(0.5, 0.5) # Start small
	
	# Animation: Float up and fade out
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position:y", label.global_position.y - 60, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	
	# Scale Pop Effect
	var tw_scale = create_tween()
	tw_scale.tween_property(label, "scale", Vector2(1.2, 1.2), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_scale.tween_property(label, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	tw.chain().tween_callback(label.queue_free)

func spawn_hit_effect(pos: Vector2, color: Color = Color.WHITE):
	var p = CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.lifetime = 0.4
	p.explosiveness = 0.9
	p.amount = 8
	p.direction = Vector2(0, -1)
	p.spread = 180
	p.gravity = Vector2(0, 600)
	p.initial_velocity_min = 150
	p.initial_velocity_max = 250
	p.scale_amount_min = 4.0
	p.scale_amount_max = 6.0
	p.color = color
	p.z_index = 105
	
	# Create a simple 2x2 pixel texture
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	p.texture = ImageTexture.create_from_image(img)
	
	if has_node("Battlefield"):
		$Battlefield.add_child(p)
	else:
		add_child(p)
		
	p.global_position = pos
	p.emitting = true
	
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)

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
	
	# 策略2: 如果本行没找到，寻找“距离最近的有存活敌人的行”里面，“血量最少”的人
	if not best_target:
		# 1. 收集所有有效敌人及其相关信息
		var candidates = [] # Array of { unit, v_dist, hp, dist_sq }
		
		for enemy in target_container.get_children():
			if not _is_valid_target(enemy): continue
			
			# 计算垂直距离 (Vertical Distance)
			# 即：攻击者所在行与敌人所在行的最小行距
			var enemy_rows = _get_unit_occupied_rows(enemy)
			var min_v_dist = 9999
			
			for my_r in my_rows:
				for enemy_r in enemy_rows:
					var diff = abs(my_r - enemy_r)
					if diff < min_v_dist:
						min_v_dist = diff
			
			# 收集信息
			candidates.append({
				"unit": enemy,
				"v_dist": min_v_dist,
				"hp": enemy.current_hp,
				"dist_sq": attacker.global_position.distance_squared_to(enemy.global_position)
			})
			
		# 2. 排序筛选
		# 优先级: 
		# 1. 行距最小 (v_dist) -> 也就是“最近的行”
		# 2. 血量最少 (hp)
		# 3. 物理距离最近 (dist_sq) ->作为同血量同行的兜底
		
		if candidates.size() > 0:
			candidates.sort_custom(func(a, b):
				if a.v_dist != b.v_dist:
					return a.v_dist < b.v_dist
				if not is_equal_approx(a.hp, b.hp):
					return a.hp < b.hp
				return a.dist_sq < b.dist_sq
			)
			best_target = candidates[0].unit

	return best_target

# --- 新增辅助战术函数 ---

# 检查攻击射程限制 (返回 true 表示可以攻击)
func can_unit_attack(attacker: Node2D) -> bool:
	if not "data" in attacker or not attacker.data:
		return true # 没数据默认可以攻击
		
	var range_limit = attacker.data.attack_range
	# 射程 1: 前方无队友; 2: 前方<1队友; N: 前方<N-1队友
	# 即：allow if friends_in_front < range_limit
	
	# 确定我方阵营容器
	var my_container = null
	if attacker.faction == 0: # FRIENDLY
		my_container = $Battlefield/FriendlyField/UnitsContainer
	else:
		my_container = $Battlefield/EnemyField/UnitsContainer
		
	if not my_container: return true
	
	var my_rows = _get_unit_occupied_rows(attacker)
	var max_friends_in_front = 0
	
	# 遍历每一行，计算该行前方的友军数量
	for r in my_rows:
		var friends_in_this_row = 0
		for friend in my_container.get_children():
			if friend == attacker: continue
			if not _is_valid_target(friend): continue # 只计算存活且已部署的
			
			var friend_rows = _get_unit_occupied_rows(friend)
			if r in friend_rows:
				# 检查是否在“前方”
				# Friendly(0) 向右打(x变大)，Enemy(1) 向左打(x变小)
				var is_in_front = false
				if attacker.faction == 0:
					if friend.global_position.x > attacker.global_position.x:
						is_in_front = true
				else:
					if friend.global_position.x < attacker.global_position.x:
						is_in_front = true
				
				if is_in_front:
					friends_in_this_row += 1
		
		if friends_in_this_row > max_friends_in_front:
			max_friends_in_front = friends_in_this_row
			
	# 如果前方阻挡数量 >= 射程，则无法攻击
	if max_friends_in_front >= range_limit:
		return false
		
	return true

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
			# Skip equipment
			if "data" in unit and unit.data and unit.data.unit_class == "equipment":
				continue
				
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
			var u_name = target.data.name if ("data" in target and target.data) else target.name
			log_message("%s 恢复了 %.1f 生命" % [u_name, amount], Color.GREEN)
			
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
	# 装备无法被选为目标
	if "data" in unit and unit.data and unit.data.unit_class == "equipment": return false
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
	log_message("敌方基地受到 %.1f 伤害" % _amount, Color.GREEN)
	modify_enemy_manpower(-_amount)

func deal_damage_to_army(_amount: float):
	log_message("我方阵线受到 %.1f 伤害" % _amount, Color.RED)
	modify_manpower(-_amount)

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

func _update_tooltip_position():
	# 更新 Tooltip 位置
	if _tooltip_instance and _tooltip_instance.visible:
		var target_pos = Vector2.ZERO
		
		if is_instance_valid(_tooltip_target):
			var rect = Rect2()
			if _tooltip_target is Control:
				rect = _tooltip_target.get_global_rect()
			elif _tooltip_target is Node2D:
				var screen_pos = _tooltip_target.get_global_transform_with_canvas().origin
				# 估算大小，默认为 GridSize
				var size = Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE)
				# 如果是多格单位，尝试读取 data
				if "data" in _tooltip_target and _tooltip_target.data and _tooltip_target.data.grid_shape:
					# 简单估算：找出最大 x 和 y
					var max_x = 0
					var max_y = 0
					for p in _tooltip_target.data.grid_shape:
						if p.x > max_x: max_x = p.x
						if p.y > max_y: max_y = p.y
					size = Vector2((max_x + 1) * GameConst.GRID_SIZE, (max_y + 1) * GameConst.GRID_SIZE)
				
				rect = Rect2(screen_pos, size)
			
			# 默认显示在右侧
			target_pos = rect.position + Vector2(rect.size.x + 10, 0)
			
			# 屏幕边界检查
			var vp_size = get_viewport().get_visible_rect().size
			var tooltip_size = _tooltip_instance.size
			
			# 1. 右边界检查：如果超出右边，改到左边
			if target_pos.x + tooltip_size.x > vp_size.x:
				target_pos.x = rect.position.x - tooltip_size.x - 10
			
			# 2. 下边界检查：如果超出下边，向上顶
			if target_pos.y + tooltip_size.y > vp_size.y:
				target_pos.y = vp_size.y - tooltip_size.y
			
			# 3. 上/左边界硬限制
			if target_pos.x < 0: target_pos.x = 0
			if target_pos.y < 0: target_pos.y = 0
			
		else:
			# Fallback: 跟随鼠标
			var viewport_mouse = get_viewport().get_mouse_position()
			target_pos = viewport_mouse + Vector2(15, 15)
		
		_tooltip_instance.position = target_pos

func show_tooltip(data: UnitData, target: Node = null):
	if _battle_presentation:
		_battle_presentation.inspect(data)
		return
	if _tooltip_instance:
		_tooltip_target = target
		_tooltip_instance.update_info(data)
		_tooltip_instance.visible = true
		_tooltip_instance.z_index = 100 # 保证在最上层

func hide_tooltip():
	if _tooltip_instance:
		_tooltip_instance.visible = false
		_tooltip_target = null

func _end_battle(victory: bool):
	if battle_ended:
		return
	battle_ended = true
	is_battle_started = false
	
	if victory:
		# 不直接显示结算界面，而是显示“完成战斗”按钮
		# show_victory_screen()
		_show_finish_battle_button()
	else:
		# 失败：不保存进度（允许重试），直接显示结算
		get_tree().paused = true
		_show_defeat_screen()

func _show_finish_battle_button():
	# 弹出飘字提示
	log_message("战斗胜利！请点击完成战斗进行结算。", Color("gold"))
	
	# 创建或显示“结算”按钮
	# 复用 HUD，类似于 battle_log_ui_instance
	var hud = $CanvasLayer/HUD
	if not hud: return
	
	var btn_name = "FinishBattleButton"
	var btn = hud.get_node_or_null(btn_name)
	
	if not btn:
		btn = Button.new()
		btn.name = btn_name
		btn.text = "完成战斗"
		
		# 居中显示
		btn.layout_mode = 1 # Anchors
		btn.anchor_left = 0.5
		btn.anchor_top = 0.5
		btn.anchor_right = 0.5
		btn.anchor_bottom = 0.5
		
		btn.offset_left = -60
		btn.offset_top = -15 
		btn.offset_right = 60
		btn.offset_bottom = 15
		btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		
		if GameState:
			GameState.apply_button_style(btn)
			# 覆盖颜色以突显
			btn.modulate = Color(1.2, 1.2, 0.8) 
			
		btn.pressed.connect(func():
			btn.visible = false
			show_victory_screen()
		)
		hud.add_child(btn)
	
	btn.visible = true
	$CanvasLayer/HUD/StartButton.hide()
	_apply_layout()

static func get_dialogue_path_by_id(id: String) -> String:
	var dialogue_id := "1_1_3_side_start" if id == "1_1_3_side" else id
	var dialogue_path := "res://Dialogues/%s.dialogue" % dialogue_id
	return dialogue_path if ResourceLoader.exists(dialogue_path) else ""

func get_next_level_id() -> String:
	if level_database and current_level_config:
		if current_level_config.level_id == "1_1_10" or current_level_config.level_id == "1_2_8":
			return "1_3_1"
		if current_level_config.level_id == "1_3_1" or current_level_config.level_id == "1_1_3_side":
			return ""
		var current_idx = level_database.get_index_by_id(current_level_config.level_id)
		if current_idx != -1 and current_idx + 1 < level_database.levels.size():
			return level_database.levels[current_idx + 1].level_id
	return ""

func start_level_id(id: String):
	if level_database:
		var idx = level_database.get_index_by_id(id)
		if idx != -1:
			# 如果已经在战斗场景中，直接开始新关卡
			start_level(idx)
		else:
			push_error("Level ID not found: " + id)

# 供对话调用的接口：播放指定关卡的开场剧情，如果没有则直接开始战斗
func play_level_intro(id: String):
	print("[BattleManager] play_level_intro: ", id)
	var dialogue_path = BattleManager.get_dialogue_path_by_id(id)
	
	if dialogue_path != "":
		if ResourceLoader.exists(dialogue_path):
			var resource = load(dialogue_path)
			var balloon_scene = load("res://Scenes/Dialogue/CustomBalloon.tscn")
			if resource and balloon_scene:
				print("[BattleManager] Showing dialogue balloon...")
				var balloon = balloon_scene.instantiate()
				get_tree().root.add_child(balloon)
				balloon.start(resource, "start", [self])
				return
			else:
				push_error("[BattleManager] Failed to load resource or balloon scene.")
		else:
			push_warning("[BattleManager] Dialogue file not found: " + dialogue_path)
	else:
		print("[BattleManager] No dialogue path configured for: ", id)
	
	# 如果没有剧情，直接开始关卡
	print("[BattleManager] Starting level directly: ", id)
	start_level_id(id)

func show_victory_dialogue():
	var dialogue_path = ""
	
	if current_level_config:
		var current_id = current_level_config.level_id
		
		if current_id == "1_1_3_side":
			dialogue_path = "res://Dialogues/1_1_3_side_victory.dialogue"
		# 汉军线、黄巾线最后一关结束后进入终章。
		elif current_id == "1_1_10" or current_id == "1_2_8":
			dialogue_path = BattleManager.get_dialogue_path_by_id("1_3_1")
		else:
			# 其他关卡：获取下一关的 ID，播放下一关的开场剧情
			var next_id = get_next_level_id()
			if next_id != "":
				dialogue_path = BattleManager.get_dialogue_path_by_id(next_id)
			
	# 如果没有对应的剧情文件，直接进入下一关
	if dialogue_path == "":
		_proceed_to_next_level_direct()
		return

	var resource = load(dialogue_path)
	var balloon_scene = load("res://Scenes/Dialogue/CustomBalloon.tscn")
	
	if resource and balloon_scene:
		# 传入 [self] 以便在对话中调用 show_victory_screen
		# 既然是独立文件，默认从 ~ start 开始
		DialogueManager.show_dialogue_balloon_scene(balloon_scene, resource, "start", [self])
	else:
		# 如果加载失败，直接进入下一关
		_proceed_to_next_level_direct()

func _proceed_to_next_level_direct():
	if level_database and current_level_config:
		var current_idx = level_database.get_index_by_id(current_level_config.level_id)
		if current_idx != -1 and current_idx + 1 < level_database.levels.size():
			start_level(current_idx + 1)
		else:
			# 没有下一关，回到主菜单 (Demo 结束)
			get_tree().paused = false
			get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

# 供对话调用的接口：直接发放单位
func grant_unit(unit_identifier: String):
	print("[BattleManager] Granting unit: ", unit_identifier)
	var unit_data: UnitData = null
	
	# 1. 尝试作为路径加载
	if unit_identifier.begins_with("res://"):
		if ResourceLoader.exists(unit_identifier):
			unit_data = load(unit_identifier)
	
	# 2. 尝试从数据库按名称查找
	if not unit_data and GameState:
		var db = GameState.get_unit_database()
		if db:
			# 这是一个低效查找，但对于少量奖励是可以接受的
			for u in db.units:
				if u.name == unit_identifier:
					unit_data = u
					break
	
	if unit_data:
		var new_unit = unit_data.duplicate()
		new_unit.is_injured = false
		
		if player_library:
			player_library.collected_cards.append(new_unit)
			if GameState:
				GameState.set_current_library(player_library)
				GameState.trigger_autosave()
		
		# 立即显示在备战区（如果有空位）
		spawn_unit(new_unit)
		
		# 提示
		var tip_msg = "获得单位：\n%s" % new_unit.name
		if $CanvasLayer:
			var label = Label.new()
			label.text = tip_msg
			label.position = Vector2(300, 100)
			label.set("theme_override_colors/font_color", Color.GOLD)
			label.set("theme_override_font_sizes/font_size", 32)
			$CanvasLayer.add_child(label)
			var tween = create_tween()
			tween.tween_property(label, "position:y", 50.0, 2.0)
			tween.parallel().tween_property(label, "modulate:a", 0.0, 2.0)
			tween.tween_callback(label.queue_free)
	else:
		push_error("[BattleManager] Could not find unit to grant: " + unit_identifier)

# 供对话调用的接口
func show_victory_screen():
	print("DEBUG: show_victory_screen called")
	if result_overlay and result_overlay.visible and result_title_label and result_title_label.text.begins_with("战斗胜利"):
		return
	_reward_resolved = false
	_reward_action_buttons.clear()
	get_tree().paused = true
	if result_overlay:
		result_overlay.visible = true
		result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if result_title_label:
		result_title_label.text = "战斗胜利"
	if reward_hint_label:
		reward_hint_label.visible = true
		reward_hint_label.text = "选择一项战利品，或将其折现为军资"
	
	# 胜利逻辑
	var reward_text = ""
	
	# 发放局外成长货币
	if GameState and GameState.has_method("add_meta_currency"):
		GameState.add_meta_currency(1)
		reward_text += "\n获得威望：+1"
	
	# 1. 弹出三选一奖励
	_show_rewards()
		
	# 2. 检查是否有下一关
	var has_next = false
	
	# 如果 level_database 在运行时丢失（例如编辑器直接运行导致未从 GameState 获取），尝试重新获取
	if not level_database and GameState:
		level_database = GameState.get_level_database()
	
	var current_idx = -1
	if level_database and current_level_config:
		current_idx = level_database.get_index_by_id(current_level_config.level_id)
		print("DEBUG: current_level_id=", current_level_config.level_id, " index=", current_idx)
	else:
		print("DEBUG: Missing level_database or current_level_config")
		if not level_database: print("DEBUG: level_database is null")
		if not current_level_config: print("DEBUG: current_level_config is null")
		
	if get_next_level_id() != "" or (current_level_config and current_level_config.level_id == "1_1_3_side"):
		has_next = true
		print("DEBUG: has_next=true. Next level=", get_next_level_id())
	else:
		print("DEBUG: has_next=false. levels.size=", level_database.levels.size() if level_database else "null")
		reward_text += "\n\n恭喜通关！(Demo结束)"
		
	if next_level_button: 
		next_level_button.visible = false # 等待选择奖励后再显示
	if retry_button: 
		retry_button.visible = false
	
	if result_detail_label:
		var detail := "我方存活: %d\n敌方存活: %d\n民力: %.1f%s" % [_count_alive_units(true), _count_alive_units(false), current_manpower, reward_text]
		result_detail_label.text = detail
	_update_result_progress()

func _show_defeat_screen():
	# 确保胜利窗口不会同时出现
	if result_title_label and result_title_label.text.begins_with("战斗胜利") and result_overlay.visible:
		return
		
	if result_overlay:
		result_overlay.visible = true
		result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if result_title_label:
		result_title_label.text = "失败"
	if reward_hint_label:
		reward_hint_label.visible = false
		
	if next_level_button: next_level_button.visible = false
	if retry_button: retry_button.visible = true
	if reward_container: reward_container.visible = false
	if result_detail_label:
		var detail := "我方存活: %d\n敌方存活: %d\n民力: %.1f" % [_count_alive_units(true), _count_alive_units(false), current_manpower]
		result_detail_label.text = detail
	_update_result_progress()

# --- 羁绊系统 ---
func _check_and_apply_synergies():
	if not units_container: return
	
	var civ_counts = {}
	var class_counts = {}
	
	var civ_unique_types = {} # { "dynasty": { "soldier_name": true, ... } }
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
	# 王朝 (Dynasty): 2人 -> +2 ATK; 4人 -> +5 ATK
	var dynasty_bonus_atk = 0.0
	if civ_counts.get("dynasty", 0) >= 4: dynasty_bonus_atk = 5.0
	elif civ_counts.get("dynasty", 0) >= 2: dynasty_bonus_atk = 2.0
	
	# 诸侯 (Warlord): 2人 -> +20 Max HP; 4人 -> +50 Max HP
	var warlord_bonus_hp = 0.0
	if civ_counts.get("warlord", 0) >= 4: warlord_bonus_hp = 50.0
	elif civ_counts.get("warlord", 0) >= 2: warlord_bonus_hp = 20.0
	
	# 义军 (Rebel): 2人 -> +10% 冷却缩减; 4人 -> +25% 冷却缩减
	var rebel_bonus_cdr = 0.0
	if civ_counts.get("rebel", 0) >= 4: rebel_bonus_cdr = 0.5
	elif civ_counts.get("rebel", 0) >= 2: rebel_bonus_cdr = 0.2
	
	# 虎狼 (Predator): 2人 -> +3 ATK; 4人 -> +8 ATK
	var predator_bonus_atk = 0.0
	if civ_counts.get("predator", 0) >= 4: predator_bonus_atk = 8.0
	elif civ_counts.get("predator", 0) >= 2: predator_bonus_atk = 3.0

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
		if civ == "dynasty" and dynasty_bonus_atk > 0:
			unit.apply_synergy_bonus("attack_damage", dynasty_bonus_atk)
			
		if civ == "warlord" and warlord_bonus_hp > 0:
			unit.apply_synergy_bonus("max_hp", warlord_bonus_hp)
			
		if civ == "rebel" and rebel_bonus_cdr > 0:
			unit.apply_synergy_bonus("cooldown_flat", rebel_bonus_cdr)
			
		if civ == "predator" and predator_bonus_atk > 0:
			unit.apply_synergy_bonus("attack_damage", predator_bonus_atk)
			
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

func find_closest_unit(from_pos: Vector2, target_faction: int, exclude_list: Array = []) -> Node2D:
	if not units_container: return null
	var best_unit = null
	var min_dist_sq = INF
	
	for unit in units_container.get_children():
		if not is_instance_valid(unit): continue
		if "current_hp" in unit and unit.current_hp <= 0: continue
		if "faction" in unit and unit.faction != target_faction: continue
		if unit in exclude_list: continue
		
		# Check if unit is actually deployed/active
		if "is_deployed" in unit and not unit.is_deployed: continue
		
		var dist_sq = from_pos.distance_squared_to(unit.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_unit = unit
			
	return best_unit

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
	var tw = line.create_tween().set_loops()
	tw.tween_property(line, "width", 2.0, 1.0).from(4.0)
	tw.tween_property(line, "width", 4.0, 1.0)
	
	var tw_alpha = line.create_tween().set_loops()
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
	if civ_counts.get("dynasty", 0) >= 4: text += "[王朝] 4: 全体+5攻\n"
	elif civ_counts.get("dynasty", 0) >= 2: text += "[王朝] 2: 全体+2攻\n"
	
	if civ_counts.get("warlord", 0) >= 4: text += "[诸侯] 4: 全体+50血\n"
	elif civ_counts.get("warlord", 0) >= 2: text += "[诸侯] 2: 全体+20血\n"
	
	if civ_counts.get("rebel", 0) >= 4: text += "[义军] 4: 全体-0.5s CD\n"
	elif civ_counts.get("rebel", 0) >= 2: text += "[义军] 2: 全体-0.2s CD\n"
	
	if civ_counts.get("predator", 0) >= 4: text += "[虎狼] 4: 全体+8攻\n"
	elif civ_counts.get("predator", 0) >= 2: text += "[虎狼] 2: 全体+3攻\n"
	
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
	if current_level_config and current_level_config.level_id == "1_1_3_side":
		show_victory_dialogue()
		return
	var next_id = get_next_level_id()
	if next_id != "":
		play_level_intro(next_id)
	else:
		_proceed_to_next_level_direct()

func _on_retry_button_pressed():
	# 重试时恢复本关开始时的自动检查点，保留此前关卡获得的卡牌。
	if GameState:
		var checkpoint = GameState.load_player_library(true, true)
		if checkpoint:
			GameState.set_current_library(checkpoint)
		
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _on_menu_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_save_button_pressed():
	var save_scene = preload("res://Scenes/SaveSlots.tscn").instantiate()
	save_scene.is_popup = true
	save_scene.mode = "save"
	# Add to CanvasLayer to ensure it's on top of everything
	if has_node("CanvasLayer"):
		$CanvasLayer.add_child(save_scene)
	else:
		add_child(save_scene)

# --- 奖励相关 ---

func _show_rewards():
	if not reward_container: return
	
	print("DEBUG: _show_rewards called")
	_reward_resolved = false
	_reward_action_buttons.clear()
	
	# 清空旧的
	for child in reward_container.get_children():
		child.queue_free()
		
	reward_container.visible = true
	
	# --- 根据关卡配置与 RewardPool 抽取奖励 ---
	var candidates: Array = []
	var used_pool := false
	
	# 1. 优先尝试使用 RewardPoolDatabase + 当前关卡的 reward_pool_id
	var pool_id := ""
	if current_level_config and "reward_pool_id" in current_level_config:
		pool_id = current_level_config.reward_pool_id
	
	if pool_id != "":
		var reward_db: RewardPoolDatabase = load("res://Resources/RewardPoolDatabase.tres")
		if reward_db:
			var reward_pool := reward_db.get_pool_by_id(pool_id)
			if reward_pool and not reward_pool.entries.is_empty():
				used_pool = true
				for entry in reward_pool.entries:
					var prob: float = float(entry.get("prob", 0.0))
					if prob <= 0.0: continue
					
					var type = entry.get("type", "unit")
					# 兼容旧配置：如果没有 type 且有 unit，认为是 unit
					if not entry.has("type") and entry.has("unit"):
						type = "unit"
						
					if type == "unit":
						var unit: UnitData = entry.get("unit", null)
						if unit:
							var item = { "type": "unit", "data": unit }
							candidates.append({ "item": item, "weight": prob })

					elif type == "upgrade_row":
						if GameState and GameState.current_rows < GameConst.MAP_ROWS:
							candidates.append({ "item": { "type": "upgrade_row", "data": null }, "weight": prob })
							
					elif type == "upgrade_col":
						if GameState and GameState.current_cols < GameConst.MAP_COLUMNS:
							candidates.append({ "item": { "type": "upgrade_col", "data": null }, "weight": prob })
	
	# 2. 如果没配置池或池为空，退回到 UnitDatabase 均匀分布
	if not used_pool:
		var db = load("res://Resources/UnitDatabase.tres")
		if not db:
			print("DEBUG: Failed to load UnitDatabase")
			return
		
		if db.units.is_empty():
			print("DEBUG: UnitDatabase is empty")
			return
		
		for unit in db.units:
			if unit:
				var item = { "type": "unit", "data": unit }
				candidates.append({ "item": item, "weight": 1.0 })
			else:
				print("DEBUG: Found null unit in database")
	
	# 3. 加入战线扩充选项 (已移至 RewardPool 配置中控制)
	# if GameState:
	# 	if GameState.current_rows < GameConst.MAP_ROWS:
	# 		candidates.append({ "item": { "type": "upgrade_row", "data": null }, "weight": 1.0 })
	# 	if GameState.current_cols < GameConst.MAP_COLUMNS:
	# 		candidates.append({ "item": { "type": "upgrade_col", "data": null }, "weight": 1.0 })
	
	# 4. 按权重抽取最多 3 个不同奖励
	var selections: Array = []
	
	while candidates.size() > 0 and selections.size() < 3:
		var total_weight := 0.0
		for c in candidates:
			total_weight += float(c.get("weight", 0.0))
		
		if total_weight <= 0.0:
			break
		
		var r := randf() * total_weight
		var chosen_idx := -1
		var acc := 0.0
		
		for i in range(candidates.size()):
			acc += float(candidates[i].get("weight", 0.0))
			if r <= acc:
				chosen_idx = i
				break
		
		if chosen_idx == -1:
			chosen_idx = candidates.size() - 1
		
		var chosen = candidates[chosen_idx]
		candidates.remove_at(chosen_idx)
		
		var chosen_item: Dictionary = chosen.get("item", {})
		if not chosen_item.is_empty():
			selections.append(chosen_item)
	
	for item in selections:
		_create_reward_card_ui(item)

func _create_reward_card_ui(item: Dictionary):
	var type = item.get("type", "unit")
	# 每张奖励卡都使用统一的宽度和暗金样式，保证三选一能完整落在面板内。
	const CARD_WIDTH := 220.0
	const CARD_HEIGHT := 292.0
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(CARD_WIDTH, 370)
	wrapper.add_theme_constant_override("separation", 8)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	if type == "unit":
		var data := item.get("data") as UnitData
		if not data or not _card_slot_scene:
			return

		var slot_host := Control.new()
		slot_host.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		slot_host.pivot_offset = Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5)
		slot_host.mouse_filter = Control.MOUSE_FILTER_PASS
		slot_host.mouse_entered.connect(func(): _set_reward_hover(slot_host, true))
		slot_host.mouse_exited.connect(func(): _set_reward_hover(slot_host, false))
		var slot = _card_slot_scene.instantiate()
		if slot.has_method("setup"):
			slot.setup(data)
		# CardSlot 原始尺寸 280x400，缩放后约 202x288，居中放入统一卡框。
		slot.scale = Vector2(0.72, 0.72)
		slot.position = Vector2(9, 0)
		if slot.has_signal("pressed"):
			slot.pressed.connect(func(_d): _on_reward_selected(item))
		slot_host.add_child(slot)
		wrapper.add_child(slot_host)

		var take_button := Button.new()
		take_button.text = "领取"
		take_button.custom_minimum_size = Vector2(0, 40)
		if GameState:
			GameState.apply_button_style(take_button)
		_apply_reward_button_art(take_button, _reward_primary_button_texture)
		take_button.pressed.connect(func(): _on_reward_selected(item))
		_reward_action_buttons.append(take_button)
		wrapper.add_child(take_button)

		var sell_price := 1
		if GameState:
			sell_price = GameState.get_card_sell_price(data.rarity)
		var sell_button := Button.new()
		sell_button.text = "折现  +%d 军资" % sell_price
		sell_button.custom_minimum_size = Vector2(0, 34)
		if GameState:
			GameState.apply_button_style(sell_button)
			sell_button.modulate = Color(1.0, 0.84, 0.5)
		_apply_reward_button_art(sell_button, _reward_secondary_button_texture, Color(0.92, 0.84, 0.66, 1))
		sell_button.pressed.connect(func(): _on_reward_sold(item))
		_reward_action_buttons.append(sell_button)
		wrapper.add_child(sell_button)
		reward_container.add_child(wrapper)
		return

	if type == "upgrade_row" or type == "upgrade_col":
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		card.pivot_offset = Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5)
		card.mouse_entered.connect(func(): _set_reward_hover(card, true))
		card.mouse_exited.connect(func(): _set_reward_hover(card, false))
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.075, 0.055, 0.04, 0.96)
		card_style.border_width_left = 2
		card_style.border_width_top = 2
		card_style.border_width_right = 2
		card_style.border_width_bottom = 2
		card_style.border_color = Color(0.68, 0.48, 0.22, 0.95)
		card_style.set_corner_radius_all(10)
		card_style.shadow_color = Color(0, 0, 0, 0.4)
		card_style.shadow_size = 8
		card.add_theme_stylebox_override("panel", card_style)

		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 10)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 18)
		margin.add_theme_constant_override("margin_right", 18)
		margin.add_theme_constant_override("margin_top", 18)
		margin.add_theme_constant_override("margin_bottom", 18)
		margin.add_child(inner)
		card.add_child(margin)

		var emblem := Label.new()
		emblem.text = "＋"
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.add_theme_color_override("font_color", Color(0.95, 0.72, 0.3, 1))
		emblem.add_theme_font_size_override("font_size", 54)
		inner.add_child(emblem)

		var title := Label.new()
		title.text = "扩充前线（行）" if type == "upgrade_row" else "扩充前线（列）"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.52, 1))
		title.add_theme_font_size_override("font_size", 22)
		inner.add_child(title)

		var desc := Label.new()
		desc.text = "战场容量 +1 行\n前后排空间增加" if type == "upgrade_row" else "战场容量 +1 列\n可部署更多单位"
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.82, 0.77, 0.67, 1))
		desc.add_theme_font_size_override("font_size", 16)
		inner.add_child(desc)
		wrapper.add_child(card)

		var take_button := Button.new()
		take_button.text = "领取扩充"
		take_button.custom_minimum_size = Vector2(0, 40)
		if GameState:
			GameState.apply_button_style(take_button)
		_apply_reward_button_art(take_button, _reward_primary_button_texture)
		take_button.pressed.connect(func(): _on_reward_selected(item))
		_reward_action_buttons.append(take_button)
		wrapper.add_child(take_button)
		reward_container.add_child(wrapper)

func _set_reward_hover(control: Control, hovered: bool):
	if not control or _reward_resolved:
		return
	control.scale = Vector2(1.04, 1.04) if hovered else Vector2.ONE
	control.modulate = Color(1.08, 1.03, 0.92, 1) if hovered else Color.WHITE

func _apply_reward_button_art(button: Button, texture: Texture2D, tint: Color = Color.WHITE):
	if not button or not texture:
		return
	var old_art := button.get_node_or_null("RewardButtonArt")
	if old_art:
		old_art.queue_free()

	# 让生成的按钮图负责边框与底纹，Button 只负责文字和输入状态。
	var clear_style := StyleBoxFlat.new()
	clear_style.bg_color = Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, clear_style)
	button.add_theme_color_override("font_color", Color(0.98, 0.88, 0.66, 1))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.82, 0.42, 1))

	var art := TextureRect.new()
	art.name = "RewardButtonArt"
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = texture
	art.expand_mode = 1
	art.stretch_mode = 6
	art.modulate = tint
	art.z_index = -1
	button.add_child(art)

func _on_reward_sold(item: Dictionary):
	if _reward_resolved:
		return
	_reward_resolved = true
	_disable_reward_actions()
	# 折现逻辑
	var reward_name = "军资"
	var sell_value = 1
	
	var type = item.get("type", "unit")
	if type == "unit":
		var data = item.get("data")
		if data and data is UnitData:
			if GameState:
				sell_value = GameState.get_card_sell_price(data.rarity)
			reward_name = "军资 x%d" % sell_value
	
	if GameState:
		GameState.add_run_gold(sell_value)
		# 触发自动存档
		GameState.trigger_autosave()
		
	# 隐藏奖励界面
	reward_container.visible = false
	
	# 更新文本提示
	if result_detail_label:
		result_detail_label.text += "\n\n已选择: %s" % reward_name
	if reward_hint_label:
		reward_hint_label.text = "战利品已入库，整备后继续远征"
		
	# 无论是否有下一关，都先进入营地
	# 如果是最后一关，可能也允许进营地看看？或者直接结束？
	# 逻辑：Battle -> Camp -> Next Level
	# 我们需要在这里修改流程，不直接显示 Next Level Button，而是显示 "前往营地"
	
	_show_camp_button()

func _on_reward_selected(item: Dictionary):
	if _reward_resolved:
		return
	_reward_resolved = true
	_disable_reward_actions()
	var type = item.get("type", "unit")
	var reward_name = ""
	
	if type == "unit":
		var data = item["data"] as UnitData
		# 必须复制一份，防止引用到已受伤的实例
		var new_data = data.duplicate()
		new_data.is_injured = false # 确保新获得的卡牌是健康的
		
		reward_name = new_data.name
		# 添加到玩家库
		if player_library:
			player_library.collected_cards.append(new_data)
			if GameState:
				GameState.set_current_library(player_library)
		# 立即添加到备战区显示
		spawn_unit(new_data)
				
	elif type == "upgrade_row":
		reward_name = "战线扩充(行)"
		if GameState:
			GameState.current_rows = min(GameState.current_rows + 1, GameConst.MAP_ROWS)
			
	elif type == "upgrade_col":
		reward_name = "战线扩充(列)"
		if GameState:
			GameState.current_cols = min(GameState.current_cols + 1, GameConst.MAP_COLUMNS)

	if GameState:
		GameState.trigger_autosave()

	# 隐藏奖励界面
	reward_container.visible = false
	
	# 更新文本提示
	if result_detail_label:
		result_detail_label.text += "\n\n已选择: %s" % reward_name
	if reward_hint_label:
		reward_hint_label.text = "战利品已入库，整备后继续远征"
		
	_show_camp_button()

func _disable_reward_actions():
	for button in _reward_action_buttons:
		if is_instance_valid(button):
			button.disabled = true

func _show_camp_button():
	# 检查是否还有下一关，决定是去营地还是直接结束
	var has_next = false
	var current_idx = -1
	if level_database and current_level_config:
		current_idx = level_database.get_index_by_id(current_level_config.level_id)
		
	if get_next_level_id() != "" or (current_level_config and current_level_config.level_id == "1_1_3_side"):
		has_next = true
	
	if next_level_button:
		if has_next:
			# 断开旧连接
			var conns = next_level_button.pressed.get_connections()
			for c in conns:
				next_level_button.pressed.disconnect(c.callable)
			
			# 奖励确认后再进入下一关，避免玩家误以为奖励尚未结算。
			next_level_button.text = "前往下一关"
			next_level_button.pressed.connect(_on_next_level_button_pressed)
				
			next_level_button.visible = true
		else:
			# 通关了
			next_level_button.visible = false

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

	for unit in units_container.get_children():
		if unit.get("is_deployed") == true:
			if unit.has_method("set_bench_hidden"):
				unit.set_bench_hidden(false)
			continue
		if unit.get("in_hand") == true:
			continue
		if unit.has_method("update_bench_pos"):
			unit.update_bench_pos(Vector2(-99999, -99999))
		if unit.has_method("set_bench_hidden"):
			unit.set_bench_hidden(true)
	_refresh_bench_ui()

func _setup_bench_ui():
	if bench_panel and bench_panel is PanelContainer:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55)
		sb.border_color = Color(1, 1, 1, 0.08)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.set_corner_radius_all(12)
		bench_panel.add_theme_stylebox_override("panel", sb)
	if EventBus and EventBus.has_signal("unit_deploy_state_changed"):
		EventBus.unit_deploy_state_changed.connect(func(_u):
			call_deferred("_refresh_bench_ui")
		)
	if bench_grid and bench_grid is GridContainer:
		bench_grid.columns = bench_columns

func _refresh_bench_ui():
	if not bench_grid:
		return
	for child in bench_grid.get_children():
		child.queue_free()
	if not units_container:
		return
	var groups: Dictionary = {}
	for unit in units_container.get_children():
		if unit.get("is_deployed") == true:
			continue
		if unit.get("in_hand") == true:
			continue
		if not ("data" in unit):
			continue
		var data_obj = unit.get("data")
		if not (data_obj is UnitData):
			continue
		var data: UnitData = data_obj
		var key = data.resource_path if data.resource_path != "" else data.name
		if not groups.has(key):
			groups[key] = { "data": data, "units": [] }
		groups[key]["units"].append(unit)

	for key in groups.keys():
		var entry = groups[key]
		var data = entry["data"] as UnitData
		var units = entry["units"]
		var slot = _card_slot_scene.instantiate()
		slot.set("drag_on_press", true)
		# CardSlot 原始尺寸 280x400，用等比缩放的包装 Control 适配备战区格子
		var wrapper := Control.new()
		wrapper.custom_minimum_size = _BENCH_CARD_SIZE
		wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
		wrapper.add_child(slot)
		slot.position = Vector2.ZERO
		slot.scale = _BENCH_CARD_SIZE / Vector2(280, 400)
		bench_grid.add_child(wrapper)
		if slot.has_method("setup_stacked"):
			slot.setup_stacked(data, units.size())
		else:
			slot.setup(data)
		if slot.has_signal("drag_requested"):
			slot.drag_requested.connect(func(_d):
				if units.size() <= 0:
					return
				var u = units.pop_back()
				if u and u.has_method("begin_drag_from_ui"):
					u.begin_drag_from_ui()
				_refresh_bench_ui()
			)
	# 补齐空槽位，让备战区呈现完整卡位（对齐图二示意）
	for i in range(maxi(0, bench_columns - groups.size())):
		var slot_panel := Panel.new()
		slot_panel.custom_minimum_size = _BENCH_CARD_SIZE
		slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.28)
		sb.border_color = Color(Color("c5a369").r, Color("c5a369").g, Color("c5a369").b, 0.35)
		sb.set_border_width_all(1)
		slot_panel.add_theme_stylebox_override("panel", sb)
		var plus := Label.new()
		plus.text = "+"
		plus.add_theme_font_size_override("font_size", 28)
		plus.add_theme_color_override("font_color", Color(1, 1, 1, 0.18))
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.set_anchors_preset(Control.PRESET_FULL_RECT)
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(plus)
		bench_grid.add_child(slot_panel)

func _update_result_progress():
	if not result_progress_label:
		return
	if level_database and current_level_config:
		var idx := level_database.get_index_by_id(current_level_config.level_id)
		if idx >= 0:
			result_progress_label.text = "战役进度  ·  第 %d / %d 关" % [idx + 1, level_database.levels.size()]
			return
	result_progress_label.text = "战役进度"

func _fit_result_overlay():
	if not result_overlay:
		return
	var panel = result_overlay.get_node_or_null("Panel")
	if not panel:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# 保留奖励卡的横向空间，同时给低分辨率留下安全边距。
	var panel_width := clampf(viewport_size.x - 48.0, 760.0, 1120.0)
	var panel_height := clampf(viewport_size.y - 48.0, 620.0, 700.0)
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5

func _apply_theme():
	if not GameState: return
	
	# 应用样式到现有按钮
	for node in find_children("", "Button", true, false):
		if node is Button:
			GameState.apply_button_style(node)
	_apply_reward_button_art(next_level_button, _reward_primary_button_texture)
	_apply_reward_button_art(retry_button, _reward_secondary_button_texture)
	_apply_reward_button_art($CanvasLayer/ResultOverlay/Panel/VBoxContainer/HBoxContainer/MenuButton, _reward_secondary_button_texture)
	
	# 胜利/失败面板背景
	if result_overlay:
		var panel = result_overlay.get_node_or_null("Panel")
		if panel and panel is Panel:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.055, 0.038, 0.026, 0.97)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.68, 0.48, 0.22, 0.96)
			style.set_corner_radius_all(14)
			style.shadow_color = Color(0, 0, 0, 0.6)
			style.shadow_size = 18
			panel.add_theme_stylebox_override("panel", style)
			panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var title = result_title_label
		if title:
			title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.42, 1))
		var detail = result_detail_label
		if detail:
			detail.add_theme_color_override("font_color", Color(0.86, 0.82, 0.73, 1))
