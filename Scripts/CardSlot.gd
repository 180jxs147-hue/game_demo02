extends Panel

## 单张卡牌 UI（用于图鉴与卡牌列表）。
## 交互约定：
## - ClickButton 覆盖整个卡面，统一发射 pressed(UnitData)
## - setup_stacked 用于显示“xN”堆叠数量

@onready var name_label = $VBoxContainer/NameLabel
@onready var stats_label = $VBoxContainer/StatsLabel
@onready var icon_texture = $IconTexture # <--- 新增
@onready var count_label = $CountLabel
@onready var click_button = $ClickButton
@onready var synergy_info_label = $SynergyInfoLabel

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
	# 已移除对 ColorRect 的依赖
	
	if icon_texture:
		icon_texture.texture = data.icon
		
	count_label.visible = false
	
	# 显示羁绊信息
	if synergy_info_label:
		# 简单的翻译映射 (也可以用 TranslationServer)
		var civ_map = {
			"han": "汉", "roman": "罗马", "greek": "希腊", "neutral": "中立", "french": "法兰西"
		}
		var cls_map = {
			"infantry": "步兵", "archer": "弓兵", "cavalry": "骑兵", "shield": "盾兵", "support": "辅助", "building": "建筑", "spear": "枪兵", "civilian": "平民", "siege": "攻城"
		}
		
		var civ_str = civ_map.get(data.civilization, data.civilization)
		var cls_str = cls_map.get(data.unit_class, data.unit_class)
		synergy_info_label.text = "%s\n%s" % [civ_str, cls_str]

func setup_stacked(data: UnitData, count: int):
	setup(data)
	if count > 1:
		count_label.visible = true
		count_label.text = "x%d" % count
