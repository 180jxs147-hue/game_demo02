extends Panel

## 单张卡牌 UI（用于图鉴与卡牌列表）。
## 交互约定：
## - ClickButton 覆盖整个卡面，统一发射 pressed(UnitData)
## - setup_stacked 用于显示“xN”堆叠数量

@onready var name_label = $VBoxContainer/NameLabel
@onready var stats_label = $VBoxContainer/StatsLabel
@onready var color_rect = $ColorRect
@onready var count_label = $CountLabel
@onready var click_button = $ClickButton

signal pressed(data: UnitData)

var _unit_data: UnitData
var _connected_click: bool = false

func _ready():
	if click_button and not _connected_click:
		_connected_click = true
		click_button.pressed.connect(func():
			if _unit_data:
				pressed.emit(_unit_data)
		)

func setup(data: UnitData):
	if not data: return
	_unit_data = data
	
	name_label.text = data.name
	var manpower_txt: String = ""
	if data.manpower_cost < 0:
		manpower_txt = "产: %.1f" % absf(data.manpower_cost)
	else:
		manpower_txt = "耗: %.1f" % data.manpower_cost
	stats_label.text = "%s\n攻: %.0f\nCD: %.1fs" % [manpower_txt, data.attack_damage, data.cooldown]
	color_rect.color = data.color
	count_label.visible = false

func setup_stacked(data: UnitData, count: int):
	setup(data)
	if count > 1:
		count_label.visible = true
		count_label.text = "x%d" % count
