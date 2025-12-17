class_name BattleManager extends Node2D

# --- UI 引用 (请在编辑器里拖拽赋值) ---
@export var left_hp_bar: ProgressBar
@export var right_hp_bar: ProgressBar
@export var manpower_label: Label

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

func _on_button_pressed() -> void:
	pass # Replace with function body.
