extends Node2D

# --- 资源参数 (Float) ---
var current_manpower: float = 10.0
var max_manpower: float = 50.0

# --- 战线参数 ---
var army_hp: float = 1000.0 
var max_army_hp: float = 1000.0
# 敌人每秒造成的伤害 (红线推进速度)
var enemy_dps: float = 50.0 

# --- 节点引用 (必须与你的场景结构一致) ---
@onready var battle_line = $BattleLine
@onready var units_root = $UnitsContainer
# 注意：这里假设你的 Label 在 CanvasLayer 下面，名为 ManpowerLabel
# 如果你的结构不同，请修改这里
@onready var ui_label = $CanvasLayer/ManpowerLabel

func _ready():
	# 初始状态：战线在最右边 (根据 GameConst 定义的宽度)
	battle_line.position.x = GameConst.BATTLE_FIELD_WIDTH
	_update_ui()

func _process(delta):
	# 如果血量归零，就不再处理
	if army_hp <= 0: return 
	
	# 1. 模拟阵线受损 (掉血)
	army_hp -= enemy_dps * delta
	
	# 2. 计算红线位置 (从右向左推进)
	# 逻辑：血量 100% -> 红线在 900 (最右)
	#       血量 0%   -> 红线在 0   (最左)
	var hp_percent = army_hp / max_army_hp
	var current_line_x = hp_percent * GameConst.BATTLE_FIELD_WIDTH
	
	battle_line.position.x = current_line_x
	
	# 3. 检查单位是否被红线越过 (传入当前红线 X 坐标)
	_check_culling(current_line_x)

# 遍历检查所有单位
func _check_culling(line_x: float):
	for unit in units_root.get_children():
		# 安全检查：确保单位有 check_burn 方法
		if unit.has_method("check_burn"):
			unit.check_burn(line_x)

# 供 Unit 调用的接口：修改民力
func modify_manpower(val: float):
	# 增加或减少，并限制在 0 到 最大值之间
	current_manpower = clampf(current_manpower + val, 0.0, max_manpower)
	_update_ui()

# 更新界面文字
func _update_ui():
	ui_label.text = "民力: %.1f / %.1f" % [current_manpower, max_manpower]
