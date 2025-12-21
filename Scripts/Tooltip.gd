extends PanelContainer

func update_info(data: UnitData):
	%NameLabel.text = data.name
	var cost_val = data.manpower_cost
	if cost_val < 0:
		%CostLabel.text = "产出: %.1f" % abs(cost_val)
		%CostLabel.modulate = Color(0.4, 1.0, 0.4) # Green
	else:
		%CostLabel.text = "消耗: %.1f" % cost_val
		%CostLabel.modulate = Color(1, 0.8, 0.2) # Yellow
		 
	%StatsLabel.text = "生命: %.0f  攻击: %.0f  冷却: %.1fs" % [data.max_hp, data.attack_damage, data.cooldown]
	
	var desc = data.story
	if desc.is_empty():
		# 如果没有故事，尝试生成一些基于标签的描述
		if not data.tags.is_empty():
			desc = "特性: " + ", ".join(data.tags)
		else:
			desc = "暂无简介"
			
	%DescLabel.text = desc
