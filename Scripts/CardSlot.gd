extends Panel

@onready var name_label = $VBoxContainer/NameLabel
@onready var stats_label = $VBoxContainer/StatsLabel
@onready var color_rect = $ColorRect

func setup(data: UnitData):
	if not data: return
	
	name_label.text = data.name
	# 显示简单的属性
	stats_label.text = "攻: %.0f\nCD: %.1fs" % [data.attack_damage, data.cooldown]
	color_rect.color = data.color
